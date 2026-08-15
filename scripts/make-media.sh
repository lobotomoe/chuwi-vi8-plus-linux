#!/usr/bin/env bash
#
# Build a USB stick that a 32-bit UEFI tablet will actually boot.
#
#   GPT -> one FAT32 partition covering the device -> contents of the ISO copied
#   onto it -> artifacts/bootia32.efi dropped into EFI/BOOT/
#
# On Linux the partition is typed "EFI System" (ef00); on macOS diskutil types it
# "Microsoft Basic Data". Firmware scanning removable media for
# \EFI\BOOT\BOOTIA32.EFI looks at FAT volumes either way.
#
# The ISO is copied, not dd-ed, because a dd-written ISO9660 filesystem is
# read-only and bootia32.efi could never be added to it. See docs/02-boot-problem.md.
#
# --boot-only builds the small half of a split-media install: the bootloader, the
# kernel and the initrd, and nothing else. The live filesystem then comes from a
# second medium - on this tablet, the microSD card in its own slot, which the
# kernel reads over the SD controller instead of over USB. See
# docs/13-split-media.md for why that is worth doing.
#
# Runs on macOS and Linux. Needs root. DESTROYS the target device.

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

LABEL=VI8PLUS
FAT32_MAX_FILE_BYTES=$((4 * 1024 * 1024 * 1024 - 1))
# Covers the GRUB menu, the font and FAT32's own overhead. The kernel, the initrd
# and the bootloader are measured rather than guessed.
BOOT_ONLY_SLACK_BYTES=$((16 * 1024 * 1024))

bootia32=$REPO_ROOT/artifacts/bootia32.efi
iso=
iso_sha256=
device=
force=no
boot_only=no
boot_kernel=
boot_initrd=
label_given=no
scratch=${TMPDIR:-/tmp}

usage() {
  cat <<EOF
Usage: sudo ${0##*/} --iso PATH.iso --device DEVICE [options]

  --iso PATH        Distribution ISO to put on the stick
  --sha256 HEX      Expected SHA-256 of the ISO, from the distribution's
                    SHA256SUMS. Checked before the stick is touched.
  --device DEVICE   Whole-disk device node: /dev/diskN (macOS), /dev/sdX (Linux)
  --bootia32 PATH   32-bit GRUB to install (default: artifacts/bootia32.efi)
  --label NAME      FAT32 volume label, 11 chars max (default: $LABEL)
  --scratch DIR     Where to unpack the ISO on macOS; needs as much free space
                    as the ISO is big (default: \$TMPDIR, currently $scratch)
  --boot-only       Write only the bootloader, kernel and initrd - no live
                    filesystem. Pair it with a second medium built without this
                    flag. See docs/13-split-media.md
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
  --sha256)
    iso_sha256=${2:?--sha256 needs a hex digest}
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
    label_given=yes
    shift 2
    ;;
  --boot-only)
    boot_only=yes
    shift
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

# The two halves of a split-media pair end up plugged into the same machine while
# being built, and mixing them up wastes a rebuild. Give them different names
# unless the operator asked for something specific.
if [ "$boot_only" = yes ] && [ "$label_given" = no ]; then
  LABEL=VI8BOOT
fi
[ ${#LABEL} -le 11 ] || die "FAT32 labels are 11 characters at most: $LABEL"

# Argument shape is checked before privileges: someone who mistyped a digest
# should hear about it now, not after re-running the whole thing under sudo.
# Pasting a whole SHA256SUMS line is the common slip, and comparing it raises a
# tampering alarm over what is really a copy-paste mistake.
if [ -n "$iso_sha256" ]; then
  case $iso_sha256 in
  *[!0-9A-Fa-f]*) die "--sha256 takes only the 64-character digest, not the whole
SHA256SUMS line: $iso_sha256" ;;
  esac
  [ ${#iso_sha256} -eq 64 ] ||
    die "--sha256 must be 64 hex characters, got ${#iso_sha256}: $iso_sha256"
fi

[ "$(id -u)" -eq 0 ] || die "must run as root (partitioning and mounting)"

# The committed artifact has a recorded checksum, and a stick built from a damaged
# copy boots nothing at all. Only the repository's own file is checked: a
# --bootia32 the operator supplied is theirs to vouch for.
sha256sums=$REPO_ROOT/artifacts/SHA256SUMS
if [ "$bootia32" = "$REPO_ROOT/artifacts/bootia32.efi" ] && [ -f "$sha256sums" ]; then
  expected_bootia32=$(awk '$2 == "bootia32.efi" { print tolower($1); exit }' "$sha256sums")
  if [ -n "$expected_bootia32" ]; then
    actual_bootia32=$(sha256_of "$bootia32")
    [ "$actual_bootia32" = "$expected_bootia32" ] ||
      die "artifacts/bootia32.efi does not match artifacts/SHA256SUMS.
  expected: $expected_bootia32
  actual:   $actual_bootia32
Check the file out again, or re-derive it with scripts/fetch-bootia32.sh."
  fi
fi

# The ISO is the one thing here that ends up executing as root on the tablet, so
# check it before the stick is destroyed rather than after.
if [ -n "$iso_sha256" ]; then
  log "Verifying $iso against the digest you gave (reads the whole image)..."
  # Digests get pasted from SHA256SUMS (lowercase) and from Windows' Get-FileHash
  # or certutil (uppercase). Case is not a mismatch; treating it as one raises a
  # tampering alarm over a copy-paste.
  expected_sha256=$(printf '%s' "$iso_sha256" | tr 'A-F' 'a-f')
  actual_sha256=$(sha256_of "$iso")
  [ "$actual_sha256" = "$expected_sha256" ] || die "SHA-256 mismatch - do not use this image.
  expected: $expected_sha256
  actual:   $actual_sha256"
  log "ISO checksum OK."
else
  warn "no --sha256 given; the ISO is being used unverified"
fi

os=$(host_os)
[ "$os" != unsupported ] || die "only macOS and Linux are supported (Windows: use make-media.ps1)"
require_cmd rsync find

mnt_iso=$(mktemp -d)
mnt_usb=$(mktemp -d)
workdir=
progress_pid=
if [ "$os" = macos ]; then
  [ -d "$scratch" ] || die "no such scratch directory: $scratch"
  iso_kb=$(($(wc -c <"$iso") / 1024))
  free_kb=$(df -Pk "$scratch" | awk 'NR == 2 { print $4 }')
  [ "$free_kb" -gt "$iso_kb" ] ||
    die "$scratch has ${free_kb} KiB free, the ISO needs about ${iso_kb} KiB. Use --scratch."
  workdir=$(mktemp -d "$scratch/vi8-iso.XXXXXX")
fi

# Copying several gigabytes with no output looks indistinguishable from a hang,
# and this is the step people wait longest on. rsync's own --info=progress2 is
# not an option: macOS ships openrsync, which reports itself as 2.6.9 and has
# neither that flag nor --progress in a usable form. Polling how full the
# destination has become needs nothing from rsync at all and behaves the same on
# both platforms.
PROGRESS_INTERVAL_SECONDS=2

report_progress() {
  local dst=$1 total_kib=$2 used pct
  while :; do
    used=$(df -Pk "$dst" 2>/dev/null | awk 'NR == 2 { print $3 }')
    # The mount disappearing means the copy is over, one way or another.
    [ -n "$used" ] || break
    pct=$((used * 100 / total_kib))
    [ "$pct" -le 100 ] || pct=100
    printf '\r  %3d%%   %d of %d MiB' \
      "$pct" "$((used / 1024))" "$((total_kib / 1024))" >&2
    sleep "$PROGRESS_INTERVAL_SECONDS"
  done
}

start_progress() {
  local dst=$1 total_kib=$2
  # Only when someone is watching: carriage returns are noise in a log file, and
  # the test suite captures this output.
  [ -t 2 ] || return 0
  [ "${total_kib:-0}" -gt 0 ] || return 0
  report_progress "$dst" "$total_kib" &
  progress_pid=$!
}

stop_progress() {
  [ -n "$progress_pid" ] || return 0
  kill "$progress_pid" 2>/dev/null || true
  wait "$progress_pid" 2>/dev/null || true
  progress_pid=
  printf '\r%-40s\r' '' >&2
}

cleanup() {
  stop_progress
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
# Safety: check the target is a device we are willing to erase.
#
# This runs before the unpack so that a mistyped --device fails in a second
# rather than after ten minutes of work. The confirmation prompt is deliberately
# further down, immediately before the erase.
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

device_size_bytes() {
  if [ "$os" = macos ]; then
    # "Disk Size: 32.0 GB (32017047552 Bytes) (exactly 62533296 512-Byte-Units)"
    diskutil info "$device" |
      awk -F'[()]' '/(Disk|Total) Size/ { print $2; exit }' |
      awk '{ print $1 }'
  else
    blockdev --getsize64 "$device" 2>/dev/null || true
  fi
}

log "Target device:"
describe_and_check_device

# The payload also has to fit. Cheap to check, and checking it now means a stick
# that was never big enough does not get erased for nothing.
iso_bytes=$(wc -c <"$iso")
device_bytes=$(device_size_bytes)

check_fits() {
  local needed=$1 what=$2
  case $device_bytes in
  '' | *[!0-9]*)
    warn "could not read the size of $device; not checking that $what fits"
    return 0
    ;;
  esac
  # FAT32 metadata and per-file slack make the usable space meaningfully smaller
  # than the raw device, so ask for real headroom rather than a bare fit.
  if [ "$needed" -gt $((device_bytes * 95 / 100)) ]; then
    die "$what does not fit on $device.
  needed: $((needed / 1024 / 1024)) MiB
  device: $((device_bytes / 1024 / 1024)) MiB
Use a larger stick. Nothing has been erased."
  fi
}

# How much a boot-only medium needs cannot be known until the image is open, so
# that check happens further down - still before anything is erased.
if [ "$boot_only" = no ]; then
  check_fits "$iso_bytes" "the ISO"
fi

# --------------------------------------------------------------------------
# Open the ISO and check it can actually go onto FAT32.
#
# All of this happens before the stick is touched. An image with a >4 GiB file
# cannot be written this way at all, and finding that out after the erase leaves
# the operator with a wiped stick, no install medium and nothing to show for the
# unpack. Nothing below this point is destructive.
# --------------------------------------------------------------------------

if [ "$os" = macos ]; then
  # macOS cannot mount a hybrid Linux ISO ("no mountable file systems"), so the
  # tree is unpacked to scratch space first. libarchive reads ISO9660/Rock Ridge.
  require_cmd tar
  if [ "$boot_only" = yes ]; then
    # Unpacking the whole image to pick four files out of it costs several GiB of
    # scratch and the better part of ten minutes. Ask for the members instead.
    # Which of these exist depends on the distribution, so a pattern that matches
    # nothing is not an error - the kernel and initrd check below is the real guard.
    log "Unpacking the boot files from the ISO..."
    for member in 'boot/grub' 'EFI' \
      'casper/vmlinuz*' 'casper/initrd*' 'live/vmlinuz*' 'live/initrd*'; do
      tar -xf "$iso" -C "$workdir" "$member" 2>/dev/null || true
    done
  else
    log "Unpacking the ISO to $workdir (macOS cannot mount hybrid ISOs)..."
    tar -xf "$iso" -C "$workdir" || die "could not unpack $iso"
  fi
  src=$workdir
else
  mount -o loop,ro "$iso" "$mnt_iso" || die "could not mount $iso"
  src=$mnt_iso
fi

# Only matters when the whole image is being copied; a boot-only medium never
# carries the squashfs that trips this.
if [ "$boot_only" = no ]; then
  oversized=$(find "$src" -type f -size +"$FAT32_MAX_FILE_BYTES"c 2>/dev/null | head -3 || true)
  if [ -n "$oversized" ]; then
    log "$oversized"
    die "the image contains files larger than 4 GiB, which FAT32 cannot store.
Use Ventoy (docs/11-usb-linux.md, docs/12-usb-windows.md) or pick a smaller image.
The stick has not been touched."
  fi
fi

# Now that the image is open, a boot-only medium can be measured instead of
# guessed at - and an image with no kernel in it can be rejected while the target
# is still untouched.
if [ "$boot_only" = yes ]; then
  boot_kernel=$(find "$src" -maxdepth 2 -type f -name 'vmlinuz*' -print -quit)
  boot_initrd=$(find "$src" -maxdepth 2 -type f -name 'initrd*' -print -quit)
  [ -n "$boot_kernel" ] || die "no kernel (vmlinuz*) found in $iso"
  [ -n "$boot_initrd" ] || die "no initrd (initrd*) found in $iso"
  check_fits "$((
    $(wc -c <"$boot_kernel") + $(wc -c <"$boot_initrd") +
      $(wc -c <"$bootia32") + BOOT_ONLY_SLACK_BYTES
  ))" "the boot files"
fi

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
  #
  # That last sentence was an assumption for a long time. It is now confirmed: a
  # stick built here, typed Microsoft Basic Data, boots the Chuwi Vi8 Plus - it
  # appears as "UEFI: SanDisk, Partition 1" under Boot Override and hands over to
  # GRUB. No ESP type code needed.
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

# Everything the firmware and GRUB have to read before the kernel is running, and
# nothing else. The live filesystem is on the other medium.
#
# The kernel and initrd go to the ROOT of the volume, deliberately not under
# casper/ or live/. Those are the directory names the live-boot scripts scan for
# when they go looking for a root filesystem, and a directory that looks like a
# live medium but contains no squashfs is exactly the kind of thing that gets
# picked and then fails. Putting the kernel at the root makes choosing this medium
# by mistake impossible rather than merely unlikely - which matters, because the
# whole point of splitting the media is that this one is the unreliable half.
copy_boot_only() {
  local kernel=$boot_kernel initrd=$boot_initrd cfg font

  cp "$kernel" "$mnt_usb/${kernel##*/}" || die "could not copy ${kernel##*/}"
  cp "$initrd" "$mnt_usb/${initrd##*/}" || die "could not copy ${initrd##*/}"

  cfg=$(find "$src" -maxdepth 3 -type f -path '*/grub/grub.cfg' -print -quit)
  [ -n "$cfg" ] || die "no boot/grub/grub.cfg found in $iso"

  mkdir -p "$mnt_usb/boot/grub"
  font=$(find "$src" -type f -name 'unicode.pf2' -print -quit)
  if [ -n "$font" ]; then
    mkdir -p "$mnt_usb/boot/grub/fonts"
    cp "$font" "$mnt_usb/boot/grub/fonts/unicode.pf2"
  else
    # loadfont is not fatal in GRUB, but the menu comes out in a fallback face.
    warn "no unicode.pf2 in the image; the GRUB menu will look plain"
  fi

  # The distribution's own menu is kept, because it carries the kernel arguments
  # that distribution expects. Only two things change:
  #
  #   - the kernel and initrd paths lose their directory, matching the layout above
  #   - "search" lines are dropped: they set $root by hunting for the ISO's label,
  #     which does not exist here, whereas $root already IS this volume - GRUB just
  #     loaded this file from it
  {
    printf '# Generated by %s --boot-only from %s\n' "${0##*/}" "${iso##*/}"
    printf '# Kernel and initrd are at the root of this volume; the live\n'
    printf '# filesystem is on the other medium. See docs/13-split-media.md\n\n'
    sed -e '/^[[:space:]]*search[[:space:]]/d' \
      -e 's,/[A-Za-z0-9_.-]*/vmlinuz,/vmlinuz,g' \
      -e 's,/[A-Za-z0-9_.-]*/initrd,/initrd,g' \
      "$cfg"
  } >"$mnt_usb/boot/grub/grub.cfg" || die "could not write grub.cfg"

  log "Boot files: ${kernel##*/}, ${initrd##*/}, boot/grub/grub.cfg"
}

if [ "$boot_only" = yes ]; then
  log "Writing boot files only (the live filesystem goes on the other medium)..."
  copy_boot_only
else
  copy_kib=$(du -sk "$src" | awk '{ print $1 }')
  log "Copying $((copy_kib / 1024)) MiB to the stick (this is the slow part)..."
  start_progress "$mnt_usb" "$copy_kib"
  # -r without -l: symlinks are skipped, and hard links become independent copies.
  # FAT32 supports neither, and no distribution needs them to boot or install.
  rsync -rt "$src"/ "$mnt_usb"/ || die "copy failed"
  stop_progress
  log "Copied."
fi

# --------------------------------------------------------------------------
# Install the 32-bit bootloader
# --------------------------------------------------------------------------

# FAT is case-insensitive, but the ISO may have created EFI/boot or EFI/BOOT.
#
# The pruning is not cosmetic. macOS drops .Spotlight-V100 onto every volume it
# mounts and TCC then denies even root access to it, so find exits non-zero -
# which under errexit killed this script right here, after the multi-minute copy
# had already succeeded and before the bootloader was installed. The stick came
# out with 64-bit loaders only: the exact failure this repository exists to
# prevent. A non-zero exit is a warning now, because the emptiness test below is
# the real guard and nothing is worth discarding a finished copy for.
efi_boot=$(find "$mnt_usb" -maxdepth 2 \
  \( -name '.Spotlight-V100' -o -name '.fseventsd' -o -name '.Trashes' \) -prune -o \
  -type d -iname boot -ipath '*/EFI/*' -print -quit) ||
  warn "find reported errors under $mnt_usb; continuing"
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
if [ "$boot_only" = yes ]; then
  log "Done. Boot medium ($LABEL) is ready - it carries no live filesystem."
  log "It is half of a pair. Build the other half without --boot-only, put it in"
  log "the tablet's microSD slot, and boot this one. See docs/13-split-media.md."
else
  log "Done. Stick is ready."
  log "Next: docs/20-uefi-setup.md - disable Secure Boot, then boot it from the tablet."
fi
