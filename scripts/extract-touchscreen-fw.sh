#!/usr/bin/env bash
#
# Extract the Chipone ICN8505 touchscreen firmware from Chuwi's own Windows
# driver package.
#
# On a unit with unfilled DMI the kernel's touchscreen quirk never matches, so
# the firmware is never pulled out of UEFI and the driver's probe fails on a
# missing file. The filename comes from the ACPI _SUB object rather than from
# DMI, so supplying the file by hand fixes the touchscreen on a stock kernel.
#
# Chuwi ships that firmware inside the INF of its touch driver: seven blobs as
# hex, keyed by the same HAMP000x names the ACPI _SUB reports. This reads them
# back out.
#
# Works on macOS and Linux. --install is Linux-only and needs root.

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

# Chuwi's driver package, offered on its own forum for both the Vi8 Plus and
# the Hi8 Pro. The two tablets share the C806 platform code.
VENDOR_ZIP_PAGE=${VENDOR_ZIP_PAGE:-https://www.mediafire.com/file/180vqqbk3rus2s1/Hi8_Pro_drivers_C806_X64.zip/file}
VENDOR_ZIP_SHA256=92a4163ec7d0388888a31666ef8340d2056e3ec866639d9cdd7275dac817561f
INF_MEMBER='drivers_C806_X64/TP_X64/chpntsc.inf'
FW_SECTION='[Chpntsc_Device_Firmware.AddReg]'

# SHA-256 of each blob as carried by the 2016-04-21 driver (DriverVer
# 04/21/2016, catalog Chpntsc.cat). A different package version will not match;
# that is a signal, not a bug — see --allow-unknown.
known_sha() {
  case $1 in
  HAMP0001) printf '3e0f9cd21ddfc91eb4f66e3419392115a69bebfe07c49b2e78d9b93499ff7c58' ;;
  HAMP0002) printf 'e895933dbd19c510a464e4f78d5387aeabea2c07948be2eaf85da9e893ba092b' ;;
  HAMP0003) printf '5a08fb4248c97e17ce02ac957e4cd4972d745fbf46e890385e75d2f3038f6c47' ;;
  HAMP0004) printf '25c059c435013bffdb46dcb02917f53bf4b55909e166832f95fcc089dd2e124b' ;;
  HAMP0005) printf '4f1deaf35d1a47a99fa87c17160f78b4f6053934c7816ba179447230f4c897ba' ;;
  HAMP0006) printf '921c04b4335f58603f4d4adfa673259f9f17aee2445a0b6ce4821d8e859b88ff' ;;
  HAMP0007) printf '7cb400fe4ac2aee553c1d19b190bb80c03b6607c1cfd399d3d1b294b892fffc5' ;;
  *) return 1 ;;
  esac
}

zip_path=
inf_path=
do_download=0
do_install=0
allow_unknown=0
fw_name=
output=

usage() {
  cat <<EOF
Usage: ${0##*/} [--zip PATH | --inf PATH | --download] [--name HAMP000N]
                [--output PATH] [--install] [--allow-unknown]

Source of the driver package, pick one:
  --zip PATH        Hi8_Pro_drivers_C806_X64.zip you already have
  --inf PATH        chpntsc.inf already extracted from it
  --download        Fetch the package from Chuwi's forum mirror (~217 MiB)

  --name HAMP000N   Which blob to extract. Default: read it off this machine
                    from what the driver asked for, else HAMP0002.
  --output PATH     Where to write it (default: artifacts/icn8505-NAME.fw)
  --install         Also copy to /lib/firmware/chipone/ (Linux, root)
  --allow-unknown   Continue when the blob's SHA-256 is not one this script
                    knows. Only sensible with a newer driver package.

Nothing here writes to the tablet's flash and nothing needs the tablet, except
--install and the default --name detection.
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
  --zip)
    zip_path=${2:?--zip needs a path}
    shift 2
    ;;
  --inf)
    inf_path=${2:?--inf needs a path}
    shift 2
    ;;
  --download)
    do_download=1
    shift
    ;;
  --name)
    fw_name=${2:?--name needs a value}
    shift 2
    ;;
  --output)
    output=${2:?--output needs a path}
    shift 2
    ;;
  --install)
    do_install=1
    shift
    ;;
  --allow-unknown)
    allow_unknown=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    die "unknown argument: $1"
    ;;
  esac
done

case "${zip_path:+z}${inf_path:+i}$([ "$do_download" = 1 ] && printf d)" in
'') die "pick a source: --zip, --inf or --download (see --help)" ;;
z | i | d) ;;
*) die "--zip, --inf and --download are mutually exclusive" ;;
esac

require_cmd awk

# Which blob does this machine actually want? The driver logs the name it built
# out of ACPI _SUB, which is the only authoritative answer.
#
# Match on the basename only, never on the directory. The name the kernel builds
# is "chipone/icn8505-<SUB>.fw", but anchoring the search to that prefix makes
# the detection fail silently -- and fall back to the default -- if the log wraps
# the line, the directory is ever renamed, or the message is read through
# something lossy. The part that carries the answer is icn8505-<SUB>.fw.
detect_fw_name() {
  local seen
  [ -r /dev/kmsg ] || command -v dmesg >/dev/null 2>&1 || return 1
  seen=$(dmesg 2>/dev/null |
    grep -o 'icn8505-[A-Za-z0-9]*\.fw' |
    head -1 |
    sed 's|icn8505-||; s|\.fw$||') || return 1
  [ -n "$seen" ] || return 1
  printf '%s' "$seen"
}

if [ -z "$fw_name" ]; then
  if fw_name=$(detect_fw_name); then
    log "this machine asked for: $fw_name"
  else
    fw_name=HAMP0002
    log "could not read a firmware name from dmesg; defaulting to $fw_name"
    log "  (that is the Vi8 Plus value upstream records; pass --name to override)"
  fi
fi

case $fw_name in
HAMP[0-9][0-9][0-9][0-9]) ;;
*) die "firmware name looks wrong: '$fw_name' (expected e.g. HAMP0002)" ;;
esac

workdir=$(mktemp -d) || die "could not create a temporary directory"
trap 'rm -rf "$workdir"' EXIT

if [ "$do_download" = 1 ]; then
  require_cmd curl
  log "resolving the download link..."
  page=$workdir/page.html
  curl -fsS -m 60 -L -A 'Mozilla/5.0' -o "$page" "$VENDOR_ZIP_PAGE" ||
    die "could not fetch $VENDOR_ZIP_PAGE"
  direct=$(grep -oE 'https://download[0-9]*\.mediafire\.com[^"'"'"']*' "$page" | head -1) ||
    true
  [ -n "$direct" ] ||
    die "no direct link on that page; the host's layout changed — download it by hand and use --zip"
  zip_path=$workdir/drivers.zip
  log "downloading ~217 MiB..."
  curl -fsS -m 1800 -L -A 'Mozilla/5.0' -o "$zip_path" "$direct" ||
    die "download failed"
  got=$(sha256_of "$zip_path")
  if [ "$got" != "$VENDOR_ZIP_SHA256" ]; then
    warn "package SHA-256 is $got"
    warn "expected                $VENDOR_ZIP_SHA256"
    [ "$allow_unknown" = 1 ] ||
      die "the package is not the one this script was written against; re-run with --allow-unknown to continue anyway"
  fi
fi

if [ -n "$zip_path" ]; then
  [ -f "$zip_path" ] || die "no such file: $zip_path"
  require_cmd unzip
  unzip -q -o -j "$zip_path" "$INF_MEMBER" -d "$workdir" ||
    die "could not extract $INF_MEMBER from $zip_path"
  inf_path=$workdir/$(basename "$INF_MEMBER")
fi

[ -f "$inf_path" ] || die "no such file: $inf_path"

# The INF is CRLF with one very long line per blob:
#   HKR,,"HAMP0002",0x00000001,b0,07,00,00,...
hex=$(awk -v want="$fw_name" -v section="$FW_SECTION" '
  { sub(/\r$/, "") }
  $0 == section { in_section = 1; next }
  /^\[/ { in_section = 0 }
  in_section && index($0, "\"" want "\"") {
    n = index($0, "0x00000001,")
    if (n == 0) next
    print substr($0, n + length("0x00000001,"))
    found = 1
    exit
  }
  END { if (!found) exit 1 }
' "$inf_path") || die "$fw_name is not in $inf_path"

blob=$workdir/$fw_name.fw
printf '%s' "$hex" | tr -d ' ,\r\n' >"$workdir/hex.txt"

bytes=$(wc -c <"$workdir/hex.txt" | tr -d ' ')
[ $((bytes % 2)) -eq 0 ] || die "odd number of hex digits ($bytes) — the INF did not parse cleanly"

if command -v xxd >/dev/null 2>&1; then
  xxd -r -p "$workdir/hex.txt" >"$blob"
elif command -v python3 >/dev/null 2>&1; then
  python3 -c 'import sys; sys.stdout.buffer.write(bytes.fromhex(open(sys.argv[1]).read()))' \
    "$workdir/hex.txt" >"$blob"
else
  die "need xxd or python3 to turn the hex back into bytes"
fi

size=$(wc -c <"$blob" | tr -d ' ')
[ "$size" -gt 0 ] || die "extracted an empty blob"
got=$(sha256_of "$blob")

log ""
log "$fw_name: $size bytes, SHA-256 $got"

if expected=$(known_sha "$fw_name"); then
  if [ "$got" = "$expected" ]; then
    log "matches the 2016-04-21 driver package"
  else
    warn "does NOT match the 2016-04-21 driver package ($expected)"
    warn "this is a different build of the same firmware"
    [ "$allow_unknown" = 1 ] ||
      die "refusing to continue; re-run with --allow-unknown if that is expected"
  fi
else
  warn "$fw_name is not in this script's table — nothing to compare against"
  [ "$allow_unknown" = 1 ] ||
    die "refusing to continue; re-run with --allow-unknown to accept it unverified"
fi

: "${output:=$REPO_ROOT/artifacts/icn8505-$fw_name.fw}"
mkdir -p "$(dirname -- "$output")"
cp "$blob" "$output"
log "wrote $output"

if [ "$do_install" = 1 ]; then
  [ "$(host_os)" = linux ] || die "--install only makes sense on the tablet (Linux)"
  [ "$(id -u)" -eq 0 ] || die "--install needs root"
  install -d /lib/firmware/chipone
  install -m 0644 "$blob" "/lib/firmware/chipone/icn8505-$fw_name.fw"
  log "installed /lib/firmware/chipone/icn8505-$fw_name.fw"
  log ""
  log "now reload the driver and check:"
  log "  modprobe -r chipone_icn8505 && modprobe chipone_icn8505"
  log "  dmesg | grep -i icn8505"
fi
