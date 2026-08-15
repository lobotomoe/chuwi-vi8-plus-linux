#!/usr/bin/env bash
#
# Answer one question about an ISO: will it boot on 32-bit UEFI firmware as-is,
# and if not, what has to be added.
#
# Works on macOS and Linux, read-only, no root needed.

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} PATH_TO.iso

Reports whether the ISO already carries a 32-bit EFI bootloader
(EFI/BOOT/BOOTIA32.EFI) and whether a GRUB menu exists at /boot/grub/grub.cfg,
which is what artifacts/bootia32.efi expects to find.
EOF
}

[ $# -eq 1 ] || {
  usage
  exit 2
}
case $1 in -h | --help)
  usage
  exit 0
  ;;
esac

iso=$1
[ -f "$iso" ] || die "no such file: $iso"

lister=$(first_cmd 7z 7zz 7za bsdtar tar) || die "need 7z or bsdtar to read an ISO"

# On macOS "tar" is libarchive and reads ISO9660. On Linux it is usually GNU tar,
# which cannot - it would fail with an empty listing and the misleading "is this a
# valid image?" below. Say what to install instead of blaming the ISO.
if [ "$lister" = tar ] && ! tar --version 2>/dev/null | grep -qi 'bsdtar\|libarchive'; then
  die "the only 'tar' here is GNU tar, which cannot read ISO9660 images.
Install one of: p7zip (7z), libarchive-tools (bsdtar)."
fi

listing=$(mktemp)
trap 'rm -f "$listing"' EXIT

# A truncated download still lists most of its entries, so failures here are
# reported rather than fatal - but they are reported.
rc=0
case $lister in
7z | 7zz | 7za)
  # -slt prints one "Path = ..." per entry, which survives filenames with spaces
  # and entries whose size columns are blank; the columnar output does not.
  "$lister" l -slt "$iso" 2>/dev/null |
    awk '/^Path = / { print substr($0, 8) }' >"$listing" || rc=$?
  ;;
bsdtar | tar) "$lister" -tf "$iso" >"$listing" 2>/dev/null || rc=$? ;;
esac
[ -s "$listing" ] || die "could not read the ISO (is it a valid image?)"
[ "$rc" -eq 0 ] || warn "$lister reported errors reading the image - is the download complete?"

has() { grep -qiE "$1" "$listing"; }

log "ISO:  $iso"
log ""

ia32=no
grubcfg=no
has '(^|/)EFI/BOOT/BOOTIA32\.EFI$' && ia32=yes
has '(^|/)boot/grub/grub\.cfg$' && grubcfg=yes

if [ "$ia32" = yes ]; then
  log "  EFI/BOOT/BOOTIA32.EFI  present"
else
  log "  EFI/BOOT/BOOTIA32.EFI  MISSING"
fi
if [ "$grubcfg" = yes ]; then
  log "  /boot/grub/grub.cfg    present"
else
  log "  /boot/grub/grub.cfg    missing"
fi

# Hybrid ISOs keep their ESP as a FAT image inside the tree. Its free space is
# what decides whether bootia32.efi could ever be added to a dd-written stick.
case $lister in
7z | 7zz | 7za)
  esp=$(grep -iE '(^|/)(boot/grub/efi\.img|EFI/[^/]*\.img|isolinux/efiboot\.img|efiboot\.img)$' "$listing" | head -1 || true)
  if [ -n "$esp" ]; then
    log ""
    log "  Embedded ESP image: $esp"
    tmpdir=$(mktemp -d)
    # Registered here rather than at the top: the EXIT trap must keep removing
    # the listing too, and a die() between here and the rm would otherwise leak.
    trap 'rm -f "$listing"; rm -rf "$tmpdir"' EXIT
    if "$lister" e -y -o"$tmpdir" "$iso" "$esp" >/dev/null 2>&1; then
      img=$(find "$tmpdir" -type f -print -quit)
      free=$("$lister" l "$img" 2>/dev/null | awk -F'= *' '/^Free Space/ { print $2; exit }')
      [ -n "$free" ] && log "    free space: $free bytes"
      "$lister" l -ba "$img" 2>/dev/null | grep -iE '\.efi$' |
        awk '{ print "    " $NF }' >&2 || true
    fi
    rm -rf "$tmpdir"
  fi
  ;;
esac

log ""
if [ "$ia32" = yes ]; then
  log "Verdict: boots 32-bit UEFI as shipped. Write it to a stick however you like."
elif [ "$grubcfg" = yes ]; then
  log "Verdict: needs artifacts/bootia32.efi copied to EFI/BOOT/ on the stick."
  log "         Because the ISO is read-only once written with dd, build the stick"
  log "         with scripts/make-usb.sh (FAT32 + copied contents) instead."
else
  log "Verdict: no 32-bit bootloader and no GRUB menu at /boot/grub/grub.cfg."
  log "         artifacts/bootia32.efi would start and find nothing to load."
  log "         Use Ventoy, or write a grub.cfg for this image by hand."
fi
