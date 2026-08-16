#!/usr/bin/env bash
#
# Read the tablet's SPI flash chip, prove the dump is trustworthy, and pull the
# touchscreen firmware out of it if it is in there.
#
# Read-only. This script never writes to the flash, and deliberately has no
# option to. Writing the BIOS is covered in docs/60-bios-firmware.md, which
# explains why you almost certainly should not.
#
# Two reasons to run it:
#   - It is the only copy of this unit's factory DMI strings and of whatever
#     touchscreen firmware its BIOS carries. Nobody else has your build.
#   - The ICN8505 firmware cannot be redistributed, so the only lawful way to
#     get it is out of your own tablet.

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

# The descriptor the kernel uses to find the touchscreen firmware in UEFI
# memory. From drivers/platform/x86/touchscreen_dmi.c, chuwi_vi8_plus_data.
TS_FW_NAME=icn8505-HAMP0002.fw
TS_FW_PREFIX_HEX=b0070000e4070000
TS_FW_LENGTH=35012
TS_FW_SHA256=93e549e0b6a2b4b3889634975ea81378729b8b829eb5ca7f125134f4307cfc7c

# Both search paths below derive their pattern from TS_FW_PREFIX_HEX, so the
# bytes are written down exactly once: \xb0\x07\x00\x00\xe4\x07\x00\x00
ts_prefix_escaped=$(printf '%s' "$TS_FW_PREFIX_HEX" | sed 's/../\\x&/g')

# 1.5.0 could issue an invalid opcode when erasing or writing on Braswell and
# earlier, leaving an incomplete flash. Reading is not affected, but a version
# that old should not be anywhere near this tablet.
FLASHROM_BAD_VERSION=1.5.0

dest_dir=$PWD

[ $# -eq 0 ] || {
  case $1 in
  -h | --help)
    cat <<EOF
Usage: sudo ${0##*/} [--dest DIR]

Reads the SPI flash twice, compares the two reads, and writes:

  bios-<host>-<stamp>.bin       the dump
  bios-<host>-<stamp>.sha256    its checksum
  chipone/$TS_FW_NAME  if the touchscreen firmware is present

Never writes to the flash. Run it on the tablet, from Linux.
EOF
    exit 0
    ;;
  --dest)
    dest_dir=${2:?--dest needs a directory}
    ;;
  *) die "unknown argument: $1" ;;
  esac
}

[ "$(host_os)" = linux ] || die "run this on the tablet, from a Linux session"
[ "$(id -u)" -eq 0 ] || die "run with sudo: the SPI controller needs root"
[ -d "$dest_dir" ] || die "no such directory: $dest_dir"
require_cmd flashrom dd cmp

# The dump must not land on the disk we may later want to restore, and writing
# it to a full filesystem wastes the one chance to catch a bad read.
free_kb=$(df -Pk "$dest_dir" | awk 'NR == 2 { print $4 }')
[ "${free_kb:-0}" -ge 65536 ] ||
  die "less than 64 MiB free in $dest_dir; two 8 MiB dumps will not fit comfortably"

version=$(flashrom --version 2>/dev/null | awk 'NR == 1 { print $2 }')
log "flashrom: ${version:-unknown}"
if [ "$version" = "$FLASHROM_BAD_VERSION" ]; then
  warn "flashrom $FLASHROM_BAD_VERSION mis-erases Braswell parts. Reading is safe,"
  warn "but do not write anything with this build. Upgrade to 1.5.1 or newer."
fi

stamp=$(date +%Y%m%d-%H%M%S)
base=$dest_dir/bios-$(hostname -s 2>/dev/null || echo tablet)-$stamp
probe_log=$base.probe.txt

log ""
log "Probing the flash chip..."
if ! flashrom -p internal --flash-name >"$probe_log" 2>&1; then
  cat "$probe_log" >&2
  die "flashrom could not identify the flash chip; the dump would be meaningless"
fi
grep -i 'vendor\|flash chip' "$probe_log" | head -3 >&2 || true

# Worth surfacing even on a read: these are the gates that decide whether the
# part could ever be written, and people always ask next.
log ""
log "Write-protection state (informational; this script only reads):"
grep -iE 'protected range|PR[0-4]|BIOS_CNTL|write protect|descriptor mode|locked' \
  "$probe_log" | sed 's/^/  /' >&2 || log "  (flashrom reported nothing about locks)"

# A single read can be quietly wrong: a marginal SPI clock or a flaky read gives
# a file that looks fine and hashes consistently with itself. Two independent
# reads that agree is the cheapest real check there is.
log ""
log "Reading the flash (1 of 2)..."
flashrom -p internal -r "$base.bin" >>"$probe_log" 2>&1 ||
  die "first read failed; see $probe_log"

log "Reading the flash (2 of 2)..."
if ! flashrom -p internal -r "$base.verify.bin" >>"$probe_log" 2>&1; then
  # The first read is still on disk and looks exactly like a good dump. Rename
  # it so it cannot later be mistaken for one that was checked.
  mv "$base.bin" "$base.unverified.bin" 2>/dev/null || true
  rm -f "$base.verify.bin"
  die "second read failed; see $probe_log
The single read that did succeed is at $base.unverified.bin. It has not been
checked against a second read, so do not trust it as a backup."
fi

if ! cmp -s "$base.bin" "$base.verify.bin"; then
  rm -f "$base.bin" "$base.verify.bin"
  die "the two reads differ. The dump is not trustworthy and has been deleted.
Retry; if it keeps happening the SPI read is unreliable and this unit needs an
external programmer instead."
fi
rm -f "$base.verify.bin"

sum=$(sha256_of "$base.bin")
printf '%s  %s\n' "$sum" "${base##*/}.bin" >"$base.sha256"
log "Two reads agree. $(wc -c <"$base.bin") bytes, sha256 $sum"

# Record what this dump belongs to. A BIOS image without its DMI is much less
# useful later, and this is the one moment both are in front of us.
{
  printf 'chuwi-vi8-plus-linux BIOS dump\n'
  printf 'taken:  %s\n' "$(date -Is)"
  printf 'sha256: %s\n\n' "$sum"
  for f in sys_vendor product_name board_vendor board_name product_sku \
    bios_vendor bios_version bios_date; do
    printf '%-14s %s\n' "$f:" "$(cat "/sys/class/dmi/id/$f" 2>/dev/null || echo '(unreadable)')"
  done
} >"$base.dmi.txt"
log "Identity recorded in ${base##*/}.dmi.txt"

# The touchscreen firmware, if this build carries it. The kernel finds it by
# scanning UEFI memory for these exact bytes, so the same search works on a
# flash image - provided the blob is stored uncompressed, which is not
# guaranteed. Not finding it here does not prove it is absent.
# Prints the byte offset of the prefix, empty if absent, and fails only if
# there is no way to search at all. Not every grep is built with PCRE, and a
# grep that cannot take -P must not be mistaken for a dump without firmware -
# both would otherwise print nothing.
find_prefix_offset() {
  local file=$1
  if printf '%b' "A$ts_prefix_escaped" |
    LC_ALL=C grep -qaP "$ts_prefix_escaped" 2>/dev/null; then
    LC_ALL=C grep -aboP "$ts_prefix_escaped" "$file" | head -1 | cut -d: -f1
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys
d = open(sys.argv[1], "rb").read()
o = d.find(bytes.fromhex(sys.argv[2]))
print(o if o >= 0 else "")' "$file" "$TS_FW_PREFIX_HEX"
    return 0
  fi
  return 1
}

log ""
log "Looking for the touchscreen firmware..."

if ! offset=$(find_prefix_offset "$base.bin"); then
  warn "cannot search the dump: this grep has no working -P and python3 is absent."
  warn "The dump is fine; install either and re-run, or search $base.bin by hand."
  offset=skipped
fi

if [ "$offset" = skipped ]; then
  : # already reported
elif [ -z "$offset" ]; then
  log "  Not found as a contiguous blob. It may be compressed inside a driver."
  log "  This is expected on some builds and is not an error."
else
  mkdir -p "$dest_dir/chipone"
  tail -c "+$((offset + 1))" "$base.bin" | head -c "$TS_FW_LENGTH" \
    >"$dest_dir/chipone/$TS_FW_NAME"
  got=$(sha256_of "$dest_dir/chipone/$TS_FW_NAME")
  if [ "$got" = "$TS_FW_SHA256" ]; then
    log "  Found at offset $offset, checksum matches the kernel's."
    log ""
    log "  Install it with:"
    log "    sudo cp -r $dest_dir/chipone /lib/firmware/"
    log "    sudo modprobe -r chipone_icn8505; sudo modprobe chipone_icn8505"
  else
    rm -f "$dest_dir/chipone/$TS_FW_NAME"
    rmdir "$dest_dir/chipone" 2>/dev/null || true
    warn "found the prefix at offset $offset but the checksum does not match:"
    warn "  got      $got"
    warn "  expected $TS_FW_SHA256"
    warn "This build carries a different firmware revision. The kernel pins that"
    warn "hash, so it would refuse this one; not installing it."
  fi
fi

log ""
log "Dump:  $base.bin"
log "Keep it. It is the only copy of this unit's factory firmware."
