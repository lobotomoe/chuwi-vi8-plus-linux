#!/usr/bin/env bash
#
# Image the tablet's eMMC to an external disk before wiping it. Run from the
# live session, with a USB disk attached through the OTG hub.
#
# Reads the eMMC, writes to the target. It never writes to the eMMC.
#
# 32 GB compresses to roughly 8-14 GB depending on how full Windows is, and
# takes 25-60 minutes over USB 2.0. The tablet is on battery the whole time.

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

source_dev=
dest_dir=

usage() {
  cat <<EOF
Usage: sudo ${0##*/} --source /dev/mmcblkN --dest /path/on/external/disk

  --source DEV   The eMMC device (check with lsblk - it is the ~29 GiB one)
  --dest DIR     Directory on an external disk with enough free space

Produces in DIR:
  emmc-<host>-<date>.img.zst   full block image, zstd compressed
  emmc-<host>-<date>.sfdisk    partition table, for a quick table-only restore
  emmc-<host>-<date>.sha256    checksum of the image
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
  --source)
    source_dev=${2:?--source needs a device}
    shift 2
    ;;
  --dest)
    dest_dir=${2:?--dest needs a directory}
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "unknown argument: $1 (try --help)" ;;
  esac
done

[ -n "$source_dev" ] && [ -n "$dest_dir" ] || {
  usage
  exit 2
}
[ "$(host_os)" = linux ] || die "run this on the tablet, from a Linux session"
[ "$(id -u)" -eq 0 ] || die "must run as root (reading a raw block device)"
[ -b "$source_dev" ] || die "not a block device: $source_dev"
[ -d "$dest_dir" ] || die "no such directory: $dest_dir"

require_cmd lsblk dd sfdisk df awk blockdev
compressor=$(first_cmd zstd xz gzip) || die "need zstd, xz or gzip"

# The destination must not live on the disk being imaged.
dest_src=$(df -P "$dest_dir" | awk 'NR == 2 { print $1 }')
case $dest_src in
"$source_dev"*) die "$dest_dir is on $source_dev. Write the backup somewhere else." ;;
esac

size_bytes=$(blockdev --getsize64 "$source_dev")
free_kb=$(df -Pk "$dest_dir" | awk 'NR == 2 { print $4 }')
# Compressed images of a mostly-full 32 GB Windows install land around 40-50 %.
need_kb=$((size_bytes / 1024 / 2))

log "Source: $source_dev ($((size_bytes / 1024 / 1024 / 1024)) GiB)"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL "$source_dev" >&2
log ""
log "Destination: $dest_dir on $dest_src"
log "  free:      $((free_kb / 1024)) MiB"
log "  estimated: $((need_kb / 1024)) MiB (a full 32 GB eMMC usually lands near half)"
log ""
if [ "$free_kb" -le "$need_kb" ]; then
  # Imaging takes 25-60 minutes, on battery, on a tablet that cannot charge with
  # the OTG hub attached. Running out of space halfway wastes the whole charge,
  # so this needs a deliberate second answer rather than a warning nobody reads.
  warn "the destination is smaller than the image is likely to need"
  warn "this only works out if the eMMC is mostly empty (a mostly-full 32 GB"
  warn "Windows install lands near $((need_kb / 1024)) MiB compressed)"
  confirm_exact "SMALL" \
    "Continue only if you know this eMMC is largely empty."
fi

confirm_exact "BACKUP $source_dev" \
  "This reads $source_dev and writes a compressed image into $dest_dir."

stamp=$(date +%Y%m%d-%H%M%S)
base=$dest_dir/emmc-$(hostname -s 2>/dev/null || echo tablet)-$stamp

log ""
log "Saving the partition table..."
sfdisk --dump "$source_dev" >"$base.sfdisk" || die "sfdisk dump failed"

case $compressor in
zstd) ext=zst; cmd=(zstd -3 -T0 -c) ;;
xz) ext=xz; cmd=(xz -T0 -2 -c) ;;
gzip) ext=gz; cmd=(gzip -c) ;;
esac

log "Imaging with $compressor. This is the long part; do not unplug anything."
log "Progress is reported by dd every few seconds."

# conv=noerror would silently produce a corrupt image; a read error on the eMMC
# is something you want to know about, so let dd fail instead.
dd if="$source_dev" bs=4M status=progress | "${cmd[@]}" >"$base.img.$ext" ||
  die "imaging failed - the image at $base.img.$ext is incomplete, delete it"

sync

log ""
log "Checksumming..."
sha256_of "$base.img.$ext" >"$base.sha256"

log ""
log "Done:"
ls -lh "$base".* >&2
log ""
log "Keep the .sha256 next to the image - restore-emmc.sh verifies against it."
log ""
log "To restore later (this overwrites the eMMC completely):"
log "  sudo ./scripts/restore-emmc.sh --image $base.img.$ext --target $source_dev"
