#!/usr/bin/env bash
#
# End-to-end test for make-media.sh, against a virtual disk.
#
# Builds a synthetic ISO, attaches a throwaway block device (a disk image on
# macOS, a loop device on Linux), runs make-media.sh against it exactly as an
# operator would, and then checks the resulting stick really carries what makes
# the tablet boot: EFI/BOOT/bootia32.efi and the ISO's own tree.
#
# Needs root, because make-media.sh partitions and mounts. It never touches a real
# device: the target is created here and detached at the end.
#
# Called by run-tests.sh; can also be run on its own.

set -o errexit
set -o nounset
set -o pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

[ "$(id -u)" -eq 0 ] || {
  printf 'e2e: needs root\n' >&2
  exit 2
}

work=$(mktemp -d)
device=
loopdev=

cleanup() {
  set +o errexit
  if [ -n "$device" ] && [ "$(uname -s)" = Darwin ]; then
    hdiutil detach "$device" -force >/dev/null 2>&1
  fi
  if [ -n "$loopdev" ]; then
    umount "$loopdev"* >/dev/null 2>&1
    losetup -d "$loopdev" >/dev/null 2>&1
  fi
  rm -rf "$work"
}
trap cleanup EXIT

fail() {
  printf 'e2e: FAIL: %s\n' "$*" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# A synthetic ISO shaped like a distribution image: a GRUB menu where
# bootia32.efi expects one, an x64-only EFI directory, and a payload file.
# ---------------------------------------------------------------------------

tree=$work/tree
mkdir -p "$tree/EFI/BOOT" "$tree/boot/grub" "$tree/boot/grub/fonts" "$tree/casper"
cat >"$tree/boot/grub/grub.cfg" <<'CFG'
search --no-floppy --set=root --label E2ESOURCE
menuentry "Try or Install" {
    linux  /casper/vmlinuz  --- quiet splash
    initrd /casper/initrd
}
CFG
head -c 65536 /dev/urandom >"$tree/EFI/BOOT/bootx64.efi"
head -c 1048576 /dev/urandom >"$tree/casper/vmlinuz"
head -c 1048576 /dev/urandom >"$tree/casper/initrd"
head -c 4096 /dev/urandom >"$tree/boot/grub/fonts/unicode.pf2"
# Stands in for the live filesystem: the thing --boot-only must leave behind.
head -c 2097152 /dev/urandom >"$tree/casper/minimal.squashfs"

iso=$work/test.iso
if command -v hdiutil >/dev/null 2>&1; then
  hdiutil makehybrid -iso -joliet -o "$iso" "$tree" -quiet ||
    fail "could not build the test ISO"
else
  built=no
  for tool in xorrisofs genisoimage mkisofs; do
    command -v "$tool" >/dev/null 2>&1 || continue
    "$tool" -quiet -o "$iso" -J -R "$tree" 2>/dev/null && built=yes && break
  done
  [ "$built" = yes ] || fail "no ISO-building tool (install xorriso or genisoimage)"
fi

iso_sha=$(
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$iso" | cut -d' ' -f1
  else
    shasum -a 256 "$iso" | cut -d' ' -f1
  fi
)

# ---------------------------------------------------------------------------
# A throwaway 256 MB block device
# ---------------------------------------------------------------------------

if [ "$(uname -s)" = Darwin ]; then
  hdiutil create -size 256m -layout NONE -type UDIF -o "$work/disk" -quiet ||
    fail "could not create the disk image"
  device=$(hdiutil attach -nomount "$work/disk.dmg" | head -1 | awk '{ print $1 }')
  [ -n "$device" ] || fail "could not attach the disk image"
else
  dd if=/dev/zero of="$work/disk.img" bs=1M count=256 status=none
  loopdev=$(losetup --find --show --partscan "$work/disk.img") ||
    fail "could not set up a loop device"
  device=$loopdev
fi

printf 'e2e: target is %s\n' "$device"

# ---------------------------------------------------------------------------
# Run make-media.sh exactly as documented, answering the confirmation prompt
# ---------------------------------------------------------------------------

# A loop device is neither removable nor USB-attached, and a macOS disk image is
# not a physical stick, so the removable check has to be waived here. That check
# is what protects a real operator; it is tested separately, not bypassed there.
out=$work/make-media.log
if ! printf 'ERASE %s\n' "$device" |
  "$REPO_ROOT/scripts/make-media.sh" \
    --iso "$iso" --sha256 "$iso_sha" --device "$device" \
    --label E2ETEST --force --scratch "$work" >"$out" 2>&1; then
  printf '%s\n' "--- make-media.sh output ---" >&2
  cat "$out" >&2
  fail "make-media.sh exited non-zero"
fi

# ---------------------------------------------------------------------------
# Mount the result and check what actually landed on it
# ---------------------------------------------------------------------------

check=$work/check
mkdir -p "$check"

if [ "$(uname -s)" = Darwin ]; then
  # make-media.sh ejects on macOS, so re-attach to inspect the result.
  hdiutil detach "$device" -force >/dev/null 2>&1 || true
  device=$(hdiutil attach -nomount "$work/disk.dmg" | head -1 | awk '{ print $1 }')
  [ -n "$device" ] || fail "could not re-attach the image for inspection"
  diskutil mount -mountPoint "$check" "${device}s1" >/dev/null ||
    fail "could not mount the built stick"
else
  part=${device}p1
  [ -b "$part" ] || part=${device}1
  mount "$part" "$check" || fail "could not mount the built stick"
fi

status=0
expect_file() {
  if [ -f "$check/$1" ]; then
    printf 'e2e: ok    %s\n' "$1"
  else
    printf 'e2e: FAIL  %s is missing\n' "$1" >&2
    status=1
  fi
}

# The one file the whole repository exists to deliver.
expect_file "EFI/BOOT/bootia32.efi"
# The ISO's own tree has to be there too, or there is nothing for GRUB to boot.
expect_file "EFI/BOOT/bootx64.efi"
expect_file "boot/grub/grub.cfg"
expect_file "casper/vmlinuz"
# The prefix shim make-media.sh writes when the ISO carries a GRUB menu.
expect_file "boot/grub/i386-efi/grub.cfg"

# bootia32.efi must be the artifact, byte for byte, not a truncated copy.
if command -v sha256sum >/dev/null 2>&1; then
  a=$(sha256sum "$check/EFI/BOOT/bootia32.efi" | cut -d' ' -f1)
  b=$(sha256sum "$REPO_ROOT/artifacts/bootia32.efi" | cut -d' ' -f1)
else
  a=$(shasum -a 256 "$check/EFI/BOOT/bootia32.efi" | cut -d' ' -f1)
  b=$(shasum -a 256 "$REPO_ROOT/artifacts/bootia32.efi" | cut -d' ' -f1)
fi
if [ "$a" = "$b" ]; then
  printf 'e2e: ok    bootia32.efi on the stick matches the artifact\n'
else
  printf 'e2e: FAIL  bootia32.efi on the stick differs from the artifact\n' >&2
  status=1
fi

if [ "$(uname -s)" = Darwin ]; then
  diskutil unmount "$check" >/dev/null 2>&1 || true
else
  umount "$check" || true
fi

[ "$status" -eq 0 ] || fail "the built stick is missing something"
printf 'e2e: stick built and verified\n'

# ---------------------------------------------------------------------------
# An ISO too large for the stick must be refused before anything is erased
# ---------------------------------------------------------------------------

bigtree=$work/bigtree
mkdir -p "$bigtree/boot/grub"
printf 'menuentry "big" {}\n' >"$bigtree/boot/grub/grub.cfg"
# Comfortably over 95% of the 256 MB target, but still made of small files so it
# is the device-size check that trips and not the FAT32 4 GiB one.
dd if=/dev/zero of="$bigtree/payload.bin" bs=1M count=250 status=none

bigiso=$work/big.iso
if command -v hdiutil >/dev/null 2>&1; then
  hdiutil makehybrid -iso -joliet -o "$bigiso" "$bigtree" -quiet || fail "could not build the oversized ISO"
else
  for tool in xorrisofs genisoimage mkisofs; do
    command -v "$tool" >/dev/null 2>&1 || continue
    "$tool" -quiet -o "$bigiso" -J -R "$bigtree" 2>/dev/null && break
  done
fi

set +o errexit
bigout=$(printf 'ERASE %s\n' "$device" |
  "$REPO_ROOT/scripts/make-media.sh" \
    --iso "$bigiso" --device "$device" \
    --label E2ETEST --force --scratch "$work" 2>&1)
bigstatus=$?
set -o errexit

if [ "$bigstatus" -eq 0 ]; then
  fail "an ISO larger than the stick was accepted"
fi
case $bigout in
*"does not fit"*) printf 'e2e: ok    oversized ISO refused\n' ;;
*)
  printf '%s\n' "$bigout" >&2
  fail "oversized ISO was rejected, but not by the size check"
  ;;
esac
# The refusal has to come before the erase, or the check is worth nothing: the
# stick built above must still be intact and mountable.
case $bigout in
*"Nothing has been erased"*) printf 'e2e: ok    refusal happened before the erase\n' ;;
*) fail "the size check did not report that the stick was left alone" ;;
esac

if [ "$(uname -s)" = Darwin ]; then
  diskutil mount -mountPoint "$check" "${device}s1" >/dev/null ||
    fail "the stick was damaged by the refused run"
  [ -f "$check/EFI/BOOT/bootia32.efi" ] || fail "the refused run destroyed the stick contents"
  diskutil unmount "$check" >/dev/null 2>&1 || true
else
  part=${device}p1
  [ -b "$part" ] || part=${device}1
  mount "$part" "$check" || fail "the stick was damaged by the refused run"
  [ -f "$check/EFI/BOOT/bootia32.efi" ] || fail "the refused run destroyed the stick contents"
  umount "$check" || true
fi
printf 'e2e: ok    stick from the earlier run survived intact\n'

# ---------------------------------------------------------------------------
# --boot-only: the small half of a split-media pair
#
# This runs last because it erases the device built above.
# ---------------------------------------------------------------------------

bootout=$work/boot-only.log
if ! printf 'ERASE %s\n' "$device" |
  "$REPO_ROOT/scripts/make-media.sh" \
    --iso "$iso" --device "$device" --boot-only \
    --label E2EBOOT --force --scratch "$work" >"$bootout" 2>&1; then
  printf '%s\n' "--- make-media.sh --boot-only output ---" >&2
  cat "$bootout" >&2
  fail "make-media.sh --boot-only exited non-zero"
fi

if [ "$(uname -s)" = Darwin ]; then
  hdiutil detach "$device" -force >/dev/null 2>&1 || true
  device=$(hdiutil attach -nomount "$work/disk.dmg" | head -1 | awk '{ print $1 }')
  [ -n "$device" ] || fail "could not re-attach the image for inspection"
  diskutil mount -mountPoint "$check" "${device}s1" >/dev/null ||
    fail "could not mount the boot-only medium"
else
  part=${device}p1
  [ -b "$part" ] || part=${device}1
  mount "$part" "$check" || fail "could not mount the boot-only medium"
fi

status=0
expect_absent() {
  if [ -e "$check/$1" ]; then
    printf 'e2e: FAIL  %s should not be on a boot-only medium\n' "$1" >&2
    status=1
  else
    printf 'e2e: ok    %s absent\n' "$1"
  fi
}

expect_file "vmlinuz"
expect_file "initrd"
expect_file "boot/grub/grub.cfg"
expect_file "boot/grub/fonts/unicode.pf2"
expect_file "EFI/BOOT/bootia32.efi"

# The invariant the whole split-media arrangement rests on. A casper/ directory
# here would be a medium that looks live and is not, which is exactly what the
# live-boot scan must never be offered.
expect_absent "casper"
expect_absent "casper/minimal.squashfs"

cfg=$check/boot/grub/grub.cfg
if [ -f "$cfg" ]; then
  # Paths must point at the root of this volume, where the files actually are.
  if grep -q '^[[:space:]]*linux[[:space:]]\{1,\}/vmlinuz' "$cfg"; then
    printf 'e2e: ok    grub.cfg loads /vmlinuz\n'
  else
    printf 'e2e: FAIL  grub.cfg does not load /vmlinuz\n' >&2
    status=1
  fi
  if grep -q '^[[:space:]]*initrd[[:space:]]\{1,\}/initrd' "$cfg"; then
    printf 'e2e: ok    grub.cfg loads /initrd\n'
  else
    printf 'e2e: FAIL  grub.cfg does not load /initrd\n' >&2
    status=1
  fi
  # A stale /casper/ path would send GRUB looking for files that are not there.
  if grep -q '/casper/' "$cfg"; then
    printf 'e2e: FAIL  grub.cfg still references /casper/\n' >&2
    status=1
  else
    printf 'e2e: ok    grub.cfg has no /casper/ paths left\n'
  fi
  # search would set $root by hunting for the source ISO's label, which does not
  # exist on this medium - and $root is already correct without it.
  if grep -q '^[[:space:]]*search[[:space:]]' "$cfg"; then
    printf 'e2e: FAIL  grub.cfg still has a search line\n' >&2
    status=1
  else
    printf 'e2e: ok    search line dropped\n'
  fi
  # The distribution's own kernel arguments have to survive the rewrite.
  if grep -q -- '--- quiet splash' "$cfg"; then
    printf 'e2e: ok    kernel arguments preserved\n'
  else
    printf 'e2e: FAIL  kernel arguments were lost\n' >&2
    status=1
  fi
  # The added entry that shows the kernel log instead of the splash.
  if grep -q 'kernel log visible' "$cfg"; then
    printf 'e2e: ok    verbose menu entry added\n'
  else
    printf 'e2e: FAIL  no verbose menu entry\n' >&2
    status=1
  fi
  # It has to keep the distribution's own arguments while dropping only the two
  # that hide the log - an entry that boots differently is worse than none.
  if awk '/kernel log visible/, /^}/' "$cfg" |
    grep -q -- '^[[:space:]]*linux[[:space:]].*---[[:space:]]*$'; then
    printf 'e2e: ok    verbose entry keeps the distribution arguments\n'
  else
    printf 'e2e: FAIL  verbose entry lost or mangled the arguments\n' >&2
    awk '/kernel log visible/, /^}/' "$cfg" >&2
    status=1
  fi
  # Only the linux line: the entry's own title is free to say the words, and an
  # earlier version of this check failed on a title reading "(no splash)".
  if awk '/kernel log visible/, /^}/' "$cfg" |
    grep '^[[:space:]]*linux[[:space:]]' | grep -qE 'quiet|splash'; then
    printf 'e2e: FAIL  verbose entry still has quiet/splash\n' >&2
    status=1
  else
    printf 'e2e: ok    verbose entry has no quiet/splash\n'
  fi
fi

if [ "$(uname -s)" = Darwin ]; then
  diskutil unmount "$check" >/dev/null 2>&1 || true
else
  umount "$check" || true
fi

[ "$status" -eq 0 ] || fail "the boot-only medium is wrong"
printf 'e2e: boot-only medium built and verified\n'
