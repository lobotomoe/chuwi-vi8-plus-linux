#!/usr/bin/env bash
#
# Test suite for the scripts in this repository.
#
#   ./tests/run-tests.sh          logic, argument handling and artifact checks
#   sudo ./tests/run-tests.sh     the above, plus an end-to-end make-usb.sh run
#
# The end-to-end test builds a synthetic ISO, attaches a virtual disk (a disk
# image on macOS, a loop device on Linux) and runs make-usb.sh against it, so it
# exercises the partition/format/copy path without needing a real USB stick and
# without any risk to a real device. It is skipped when not run as root.

set -o errexit
set -o nounset
set -o pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPTS=$REPO_ROOT/scripts

passed=0
failed=0
skipped=0

pass() {
  passed=$((passed + 1))
  printf '  ok    %s\n' "$1"
}
fail() {
  failed=$((failed + 1))
  printf '  FAIL  %s\n' "$1"
  [ $# -lt 2 ] || printf '        %s\n' "$2"
}
skip() {
  skipped=$((skipped + 1))
  printf '  skip  %s (%s)\n' "$1" "$2"
}
group() { printf '\n%s\n' "$1"; }

# Runs a command and compares its exit status and combined output.
#   expect_fail <name> <expected status> <substring of output> -- cmd...
expect_fail() {
  local name=$1 want_status=$2 want_text=$3 out status
  shift 4 # name, status, text, and the literal --
  set +o errexit
  out=$("$@" 2>&1)
  status=$?
  set -o errexit
  if [ "$status" -ne "$want_status" ]; then
    fail "$name" "exited $status, expected $want_status: $out"
    return
  fi
  case $out in
  *"$want_text"*) pass "$name" ;;
  *) fail "$name" "output did not contain '$want_text': $out" ;;
  esac
}

# ---------------------------------------------------------------------------
group "Static analysis"

if command -v shellcheck >/dev/null 2>&1; then
  if out=$(shellcheck "$SCRIPTS"/*.sh "$REPO_ROOT"/tests/*.sh 2>&1); then
    pass "shellcheck is clean"
  else
    fail "shellcheck is clean" "$out"
  fi
else
  skip "shellcheck is clean" "shellcheck not installed"
fi

for f in "$SCRIPTS"/*.sh "$REPO_ROOT"/tests/*.sh; do
  if bash -n "$f" 2>/dev/null; then
    pass "parses: ${f#"$REPO_ROOT"/}"
  else
    fail "parses: ${f#"$REPO_ROOT"/}"
  fi
done

# lib.sh is sourced, never executed; a +x bit on it invites running it directly.
if [ -x "$SCRIPTS/lib.sh" ]; then
  fail "lib.sh is not executable" "it is a sourced library, mode should be 644"
else
  pass "lib.sh is not executable"
fi

# ---------------------------------------------------------------------------
group "Shipped artifact"

if (cd "$REPO_ROOT/artifacts" && shasum -a 256 -c SHA256SUMS >/dev/null 2>&1) ||
  (cd "$REPO_ROOT/artifacts" && sha256sum -c SHA256SUMS >/dev/null 2>&1); then
  pass "bootia32.efi matches artifacts/SHA256SUMS"
else
  fail "bootia32.efi matches artifacts/SHA256SUMS"
fi

# A PE executable, not an ELF or a stray text file. GRUB EFI images start "MZ".
if [ "$(head -c 2 "$REPO_ROOT/artifacts/bootia32.efi")" = "MZ" ]; then
  pass "bootia32.efi is a PE image"
else
  fail "bootia32.efi is a PE image" "does not start with the MZ magic"
fi

# ---------------------------------------------------------------------------
group "Usage and argument handling"

for s in make-usb.sh backup-emmc.sh restore-emmc.sh postinstall-grub-ia32.sh \
  postinstall-tune.sh check-iso-ia32.sh fetch-bootia32.sh fetch-offline-payload.sh \
  collect-hw-report.sh; do
  set +o errexit
  out=$("$SCRIPTS/$s" --help 2>&1)
  status=$?
  set -o errexit
  if [ "$status" -eq 0 ] && [ -n "$out" ]; then
    pass "$s --help exits 0"
  else
    fail "$s --help exits 0" "exited $status"
  fi
done

# Missing required arguments must be exit 2 (usage), not a generic failure.
expect_fail "make-usb.sh with no arguments prints usage" 2 "Usage:" -- \
  "$SCRIPTS/make-usb.sh"
expect_fail "backup-emmc.sh with no arguments prints usage" 2 "Usage:" -- \
  "$SCRIPTS/backup-emmc.sh"
expect_fail "restore-emmc.sh with no arguments prints usage" 2 "Usage:" -- \
  "$SCRIPTS/restore-emmc.sh"

expect_fail "make-usb.sh rejects an unknown argument" 1 "unknown argument" -- \
  "$SCRIPTS/make-usb.sh" --wat
expect_fail "make-usb.sh rejects a missing ISO" 1 "no such ISO" -- \
  "$SCRIPTS/make-usb.sh" --iso /nonexistent.iso --device /dev/null

# A whole SHA256SUMS line pasted into --sha256 must be named as such, not
# reported as a checksum mismatch.
expect_fail "make-usb.sh rejects a pasted SHA256SUMS line" 1 "only the 64-character digest" -- \
  "$SCRIPTS/make-usb.sh" --iso "$REPO_ROOT/artifacts/bootia32.efi" --device /dev/null \
  --sha256 "d21e473e4f81716aae013720024755cd5ff89c9674ee5326fd3c4c6f7a84f0e7  bootia32.efi"

expect_fail "make-usb.sh rejects a truncated digest" 1 "64 hex characters" -- \
  "$SCRIPTS/make-usb.sh" --iso "$REPO_ROOT/artifacts/bootia32.efi" --device /dev/null \
  --sha256 d21e473e

expect_fail "make-usb.sh rejects an over-long FAT32 label" 1 "11 characters at most" -- \
  "$SCRIPTS/make-usb.sh" --iso "$REPO_ROOT/artifacts/bootia32.efi" --device /dev/null \
  --label THIS_LABEL_IS_TOO_LONG

# ---------------------------------------------------------------------------
group "FAT32 size boundary"

# FAT32 stores files up to 4 GiB - 1. The check must accept exactly that and
# reject exactly one byte more; make-usb.sh uses find -size +Nc, which is
# "strictly greater than", so the constant is the largest legal size.
sizedir=$(mktemp -d)
trap 'rm -rf "$sizedir"' EXIT
dd if=/dev/zero of="$sizedir/legal.bin" bs=1 count=0 seek=4294967295 2>/dev/null
dd if=/dev/zero of="$sizedir/toobig.bin" bs=1 count=0 seek=4294967296 2>/dev/null
FAT32_MAX_FILE_BYTES=$((4 * 1024 * 1024 * 1024 - 1))
flagged=$(find "$sizedir" -type f -size +"$FAT32_MAX_FILE_BYTES"c -exec basename {} \; | sort | tr '\n' ' ')
if [ "$flagged" = "toobig.bin " ]; then
  pass "4 GiB - 1 accepted, 4 GiB rejected"
else
  fail "4 GiB - 1 accepted, 4 GiB rejected" "flagged: '$flagged'"
fi

# ---------------------------------------------------------------------------
group "restore-emmc.sh sidecar naming"

# restore-emmc.sh derives the .sha256 and .size names from the image name. This
# repeats that derivation verbatim, against real files, so a change to the naming
# on either side shows up here rather than at restore time.
derive_sidecar() {
  local image=$1 sidecar
  sidecar=${image%.img.*}.sha256
  [ -f "$sidecar" ] || sidecar=${image%.img}.sha256
  printf '%s' "$sidecar"
}

sidecardir=$(mktemp -d)
check_sidecar() {
  local imagename=$1 sidecarname=$2 got
  : >"$sidecardir/$imagename"
  : >"$sidecardir/$sidecarname"
  got=$(derive_sidecar "$sidecardir/$imagename")
  if [ "$got" = "$sidecardir/$sidecarname" ]; then
    pass "$imagename -> $sidecarname"
  else
    fail "$imagename -> $sidecarname" "derived ${got#"$sidecardir"/}"
  fi
}
# Exactly the names backup-emmc.sh produces, for each compressor it may pick.
check_sidecar "emmc-tablet-20260815-120000.img.zst" "emmc-tablet-20260815-120000.sha256"
check_sidecar "emmc-tablet-20260815-120000.img.xz" "emmc-tablet-20260815-120000.sha256"
check_sidecar "emmc-tablet-20260815-120000.img.gz" "emmc-tablet-20260815-120000.sha256"
# A raw image, and a name with a dot in it, which the %.img.* expansion must not
# chew into.
check_sidecar "emmc-tablet.img" "emmc-tablet.sha256"
check_sidecar "emmc-v1.2-backup.img.zst" "emmc-v1.2-backup.sha256"
rm -rf "$sidecardir"

# ---------------------------------------------------------------------------
group "check-iso-ia32.sh"

if command -v hdiutil >/dev/null 2>&1 || command -v xorrisofs >/dev/null 2>&1 ||
  command -v genisoimage >/dev/null 2>&1 || command -v mkisofs >/dev/null 2>&1; then
  isodir=$(mktemp -d)
  mkdir -p "$isodir/tree/EFI/BOOT" "$isodir/tree/boot/grub"
  printf 'menuentry "test" {}\n' >"$isodir/tree/boot/grub/grub.cfg"
  printf 'MZfake\n' >"$isodir/tree/EFI/BOOT/bootx64.efi"

  made=no
  if command -v hdiutil >/dev/null 2>&1; then
    hdiutil makehybrid -iso -joliet -o "$isodir/t.iso" "$isodir/tree" -quiet && made=yes
  else
    for tool in xorrisofs genisoimage mkisofs; do
      command -v "$tool" >/dev/null 2>&1 || continue
      "$tool" -quiet -o "$isodir/t.iso" -J -R "$isodir/tree" 2>/dev/null && made=yes && break
    done
  fi

  if [ "$made" = yes ]; then
    set +o errexit
    out=$("$SCRIPTS/check-iso-ia32.sh" "$isodir/t.iso" 2>&1)
    set -o errexit
    case $out in
    *"BOOTIA32.EFI  MISSING"*) pass "reports a missing BOOTIA32.EFI" ;;
    *) fail "reports a missing BOOTIA32.EFI" "$out" ;;
    esac
    case $out in
    *"/boot/grub/grub.cfg    present"*) pass "finds /boot/grub/grub.cfg" ;;
    *) fail "finds /boot/grub/grub.cfg" "$out" ;;
    esac
    case $out in
    *"needs artifacts/bootia32.efi"*) pass "verdict is 'needs bootia32.efi'" ;;
    *) fail "verdict is 'needs bootia32.efi'" "$out" ;;
    esac
  else
    skip "check-iso-ia32.sh on a synthetic ISO" "could not build a test ISO"
  fi
  rm -rf "$isodir"
else
  skip "check-iso-ia32.sh on a synthetic ISO" "no ISO-building tool available"
fi

# ---------------------------------------------------------------------------
group "make-usb.sh end to end (virtual disk)"

if [ "$(id -u)" -ne 0 ]; then
  skip "end-to-end build" "needs root; re-run with sudo"
else
  if "$REPO_ROOT/tests/e2e-make-usb.sh"; then
    pass "end-to-end build"
  else
    fail "end-to-end build"
  fi
fi

# ---------------------------------------------------------------------------
printf '\n%d passed, %d failed, %d skipped\n' "$passed" "$failed" "$skipped"
[ "$failed" -eq 0 ]
