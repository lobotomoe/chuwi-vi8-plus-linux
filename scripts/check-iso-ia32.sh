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

lister=$(first_cmd 7z bsdtar tar) || die "need 7z or bsdtar to read an ISO"

listing=$(mktemp)
trap 'rm -f "$listing"' EXIT

# A truncated download still lists most of its entries, so failures here are
# reported rather than fatal - but they are reported.
rc=0
case $lister in
7z) 7z l -ba "$iso" 2>/dev/null | awk '{ $1=$1; sub(/^([^ ]+ ){5}/, ""); print }' >"$listing" || rc=$? ;;
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
if [ "$lister" = 7z ]; then
  esp=$(grep -iE '(^|/)(boot/grub/efi\.img|EFI/[^/]*\.img|isolinux/efiboot\.img|efiboot\.img)$' "$listing" | head -1 || true)
  if [ -n "$esp" ]; then
    log ""
    log "  Embedded ESP image: $esp"
    tmpdir=$(mktemp -d)
    if 7z e -y -o"$tmpdir" "$iso" "$esp" >/dev/null 2>&1; then
      img=$(find "$tmpdir" -type f -print -quit)
      free=$(7z l "$img" 2>/dev/null | awk -F'= *' '/^Free Space/ { print $2; exit }')
      [ -n "$free" ] && log "    free space: $free bytes"
      7z l -ba "$img" 2>/dev/null | grep -iE '\.efi$' |
        awk '{ print "    " $NF }' >&2 || true
    fi
    rm -rf "$tmpdir"
  fi
fi

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
