#!/usr/bin/env bash
#
# Build a USB stick that a 32-bit UEFI tablet will actually boot.
#
#   GPT -> one FAT32 partition typed "EFI System" -> contents of the ISO copied
#   onto it -> artifacts/bootia32.efi dropped into EFI/BOOT/
#
# The ISO is copied, not dd-ed, because a dd-written ISO9660 filesystem is
# read-only and bootia32.efi could never be added to it. See docs/02-boot-problem.md.
#
# Runs on macOS and Linux. Needs root. DESTROYS the target device.

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

LABEL=VI8PLUS
FAT32_MAX_FILE_BYTES=$((4 * 1024 * 1024 * 1024 - 1))

bootia32=$REPO_ROOT/artifacts/bootia32.efi
iso=
device=
force=no
scratch=${TMPDIR:-/tmp}

usage() {
  cat <<EOF
Usage: sudo ${0##*/} --iso PATH.iso --device DEVICE [options]

  --iso PATH        Distribution ISO to put on the stick
  --device DEVICE   Whole-disk device node: /dev/diskN (macOS), /dev/sdX (Linux)
  --bootia32 PATH   32-bit GRUB to install (default: artifacts/bootia32.efi)
  --label NAME      FAT32 volume label, 11 chars max (default: $LABEL)
  --scratch DIR     Where to unpack the ISO on macOS; needs as much free space
                    as the ISO is big (default: \$TMPDIR, currently $scratch)
  --force           Skip the removable-device safety check

Find the device first:
  macOS:  diskutil list external physical
  Linux:  lsblk -o NAME,SIZE,TRAN,RM,MODEL

Everything on DEVICE is destroyed.
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
  --iso)
    iso=${2:?--iso needs a path}
    shift 2
    ;;
  --device)
    device=${2:?--device needs a path}
    shift 2
    ;;
  --bootia32)
    bootia32=${2:?--bootia32 needs a path}
    shift 2
    ;;
  --label)
    LABEL=${2:?--label needs a value}
    shift 2
    ;;
  --scratch)
    scratch=${2:?--scratch needs a path}
    shift 2
    ;;
  --force)
    force=yes
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "unknown argument: $1 (try --help)" ;;
  esac
done

[ -n "$iso" ] && [ -n "$device" ] || {
  usage
  exit 2
}
[ -f "$iso" ] || die "no such ISO: $iso"
[ -f "$bootia32" ] || die "no such bootia32: $bootia32"
[ "$(id -u)" -eq 0 ] || die "must run as root (partitioning and mounting)"
[ ${#LABEL} -le 11 ] || die "FAT32 labels are 11 characters at most: $LABEL"

os=$(host_os)
[ "$os" != unsupported ] || die "only macOS and Linux are supported (Windows: use make-usb.ps1)"
require_cmd rsync find

mnt_iso=$(mktemp -d)
mnt_usb=$(mktemp -d)
workdir=
if [ "$os" = macos ]; then
  [ -d "$scratch" ] || die "no such scratch directory: $scratch"
  iso_kb=$(($(wc -c <"$iso") / 1024))
  free_kb=$(df -Pk "$scratch" | awk 'NR == 2 { print $4 }')
  [ "$free_kb" -gt "$iso_kb" ] ||
    die "$scratch has ${free_kb} KiB free, the ISO needs about ${iso_kb} KiB. Use --scratch."
  workdir=$(mktemp -d "$scratch/vi8-iso.XXXXXX")
fi

cleanup() {
  if [ "$os" = macos ]; then
    diskutil unmount "$mnt_usb" >/dev/null 2>&1 || true
  else
    umount "$mnt_iso" 2>/dev/null || true
    umount "$mnt_usb" 2>/dev/null || true
  fi
  if [ -n "$workdir" ] && [ -d "$workdir" ]; then
    # ISO9660 trees unpack read-only, which stops rm from unlinking them.
    chmod -R u+rwX "$workdir" 2>/dev/null || true
    rm -rf "$workdir"
  fi
  rmdir "$mnt_iso" "$mnt_usb" 2>/dev/null || true
}
trap cleanup EXIT

# --------------------------------------------------------------------------
# Safety: describe the target and make the operator type it back.
# --------------------------------------------------------------------------

describe_and_check_device() {
  if [ "$os" = macos ]; then
    [ -b "$device" ] || [ -c "$device" ] || die "not a device node: $device"
    diskutil info "$device" >&2 || die "diskutil could not read $device"
    local location
    location=$(diskutil info "$device" | awk -F': *' '/Device Location/ { print $2; exit }')
    if [ "$force" = no ] && [ "$location" = "Internal" ]; then
      die "$device is an internal disk. Refusing. Use --force only if you are certain."
    fi
  else
    [ -b "$device" ] || die "not a block device: $device"
    lsblk -o NAME,SIZE,TRAN,RM,MODEL "$device" >&2 || die "lsblk could not read $device"
    local name removable transport
    name=$(basename -- "$device")
    removable=$(cat "/sys/block/$name/removable" 2>/dev/null || echo 0)
    transport=$(lsblk -dno TRAN "$device" 2>/dev/null || true)
    if [ "$force" = no ] && [ "$removable" != 1 ] && [ "$transport" != usb ]; then
      die "$device is neither removable nor USB-attached. Refusing. Use --force if you are certain."
    fi
  fi
}

log "Target device:"
describe_and_check_device
log ""
confirm_exact "ERASE $device" \
  "Everything on $device will be destroyed."

# --------------------------------------------------------------------------
# Partition and format
# --------------------------------------------------------------------------

partition_macos() {
  # -noEFI suppresses diskutil's separate 200 MB helper partition, so the stick
  # ends up with exactly one FAT32 partition covering the whole device. macOS
  # types it "Microsoft Basic Data" rather than "EFI System"; firmware looking
  # for \EFI\BOOT\BOOTIA32.EFI on removable media scans FAT volumes either way.
  diskutil unmountDisk force "$device" >/dev/null 2>&1 || true
  diskutil eraseDisk -noEFI FAT32 "$LABEL" GPT "$device" >/dev/null ||
    die "diskutil eraseDisk failed on $device"
  diskutil unmountDisk force "$device" >/dev/null 2>&1 || true
  diskutil mount -mountPoint "$mnt_usb" "${device}s1" >/dev/null ||
    die "could not mount ${device}s1"
}

partition_linux() {
  require_cmd sgdisk mkfs.vfat udevadm
  umount "$device"?* 2>/dev/null || true
  sgdisk --zap-all "$device" >/dev/null || die "sgdisk --zap-all failed"
  sgdisk --new=1:2048:0 --typecode=1:ef00 --change-name=1:"$LABEL" "$device" >/dev/null ||
    die "sgdisk partitioning failed"
  udevadm settle
  local part="${device}1"
  [ -b "$part" ] || part="${device}p1"
  [ -b "$part" ] || die "partition node did not appear for $device"
  mkfs.vfat -F 32 -n "$LABEL" "$part" >/dev/null || die "mkfs.vfat failed on $part"
  mount "$part" "$mnt_usb" || die "could not mount $part"
}

log ""
log "Partitioning $device (GPT, one FAT32 EFI System partition, label $LABEL)..."
if [ "$os" = macos ]; then partition_macos; else partition_linux; fi

# --------------------------------------------------------------------------
# Copy the ISO contents
# --------------------------------------------------------------------------

if [ "$os" = macos ]; then
  # macOS cannot mount a hybrid Linux ISO ("no mountable file systems"), so the
  # tree is unpacked to scratch space first. libarchive reads ISO9660/Rock Ridge.
  require_cmd tar
  log "Unpacking the ISO to $workdir (macOS cannot mount hybrid ISOs)..."
  tar -xf "$iso" -C "$workdir" || die "could not unpack $iso"
  src=$workdir
else
  mount -o loop,ro "$iso" "$mnt_iso" || die "could not mount $iso"
  src=$mnt_iso
fi

oversized=$(find "$src" -type f -size +"$FAT32_MAX_FILE_BYTES"c 2>/dev/null | head -3 || true)
if [ -n "$oversized" ]; then
  log "$oversized"
  die "the image contains files larger than 4 GiB, which FAT32 cannot store.
Use Ventoy (docs/11-usb-linux.md, docs/12-usb-windows.md) or pick a smaller image."
fi

log "Copying to the stick (this is the slow part)..."
# -r without -l: symlinks are skipped, and hard links become independent copies.
# FAT32 supports neither, and no distribution needs them to boot or install.
rsync -rt "$src"/ "$mnt_usb"/ || die "copy failed"

# --------------------------------------------------------------------------
# Install the 32-bit bootloader
# --------------------------------------------------------------------------

# FAT is case-insensitive, but the ISO may have created EFI/boot or EFI/BOOT.
efi_boot=$(find "$mnt_usb" -maxdepth 2 -type d -iname boot -ipath '*/EFI/*' -print -quit)
[ -n "$efi_boot" ] || {
  efi_boot="$mnt_usb/EFI/BOOT"
  mkdir -p "$efi_boot"
}

existing=$(find "$efi_boot" -maxdepth 1 -iname 'bootia32.efi' -print -quit)
if [ -n "$existing" ]; then
  log ""
  log "The ISO already ships $(basename -- "$existing") - leaving it in place."
  log "This image boots 32-bit firmware on its own."
else
  cp "$bootia32" "$efi_boot/bootia32.efi" || die "could not install bootia32.efi"
  log ""
  log "Installed bootia32.efi into ${efi_boot#"$mnt_usb"}/"
fi

# artifacts/bootia32.efi looks for /boot/grub/grub.cfg. Some GRUB builds instead
# resolve $prefix/${grub_cpu}-efi/grub.cfg; this 1-line file satisfies both.
if [ -f "$mnt_usb/boot/grub/grub.cfg" ]; then
  mkdir -p "$mnt_usb/boot/grub/i386-efi"
  printf 'source /boot/grub/grub.cfg\n' >"$mnt_usb/boot/grub/i386-efi/grub.cfg"
fi

sync

log ""
log "Contents of EFI/BOOT:"
ls -l "$efi_boot" >&2

cleanup
trap - EXIT

if [ "$os" = macos ]; then
  diskutil eject "$device" >/dev/null 2>&1 || true
fi

log ""
log "Done. Stick is ready."
log "Next: docs/20-uefi-setup.md - disable Secure Boot, then boot it from the tablet."
