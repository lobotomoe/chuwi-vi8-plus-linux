#!/usr/bin/env bash
#
# Re-derive bootia32.efi from the Debian archive instead of trusting the copy
# committed in artifacts/.
#
# Resolves the current version of grub-efi-ia32-unsigned from Debian's package
# index, verifies the downloaded .deb against the SHA-256 published there, and
# extracts usr/lib/grub/i386-efi/monolithic/gcdia32.efi.
#
# Works on macOS and Linux.

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

DEBIAN_MIRROR=${DEBIAN_MIRROR:-https://deb.debian.org/debian}
SUITE=${SUITE:-trixie}
PACKAGE=grub-efi-ia32-unsigned
MEMBER=usr/lib/grub/i386-efi/monolithic/gcdia32.efi

output=$REPO_ROOT/artifacts/bootia32.efi

usage() {
  cat <<EOF
Usage: ${0##*/} [--output PATH] [--suite SUITE]

  --output PATH   Where to write bootia32.efi (default: artifacts/bootia32.efi)
  --suite SUITE   Debian suite to pull from (default: $SUITE)

Environment:
  DEBIAN_MIRROR   Archive base URL (default: $DEBIAN_MIRROR)
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
  --output)
    output=${2:?--output needs a path}
    shift 2
    ;;
  --suite)
    SUITE=${2:?--suite needs a value}
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "unknown argument: $1 (try --help)" ;;
  esac
done

require_cmd curl gzip awk

# libarchive's bsdtar reads both .deb (ar) and the inner tar; on macOS the system
# tar is bsdtar. 7z is the fallback for hosts that have neither.
extractor=$(first_cmd bsdtar tar 7z) || die "need bsdtar, tar or 7z to unpack a .deb"

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

index_url="$DEBIAN_MIRROR/dists/$SUITE/main/binary-amd64/Packages.gz"
log "Fetching package index: $index_url"
curl -fsSL --retry 3 -o "$workdir/Packages.gz" "$index_url" ||
  die "could not download the package index"

# Decompress to a file first: awk exits at the first matching stanza, which would
# hand gzip a SIGPIPE and trip errexit/pipefail if this were a pipeline.
gzip -dc "$workdir/Packages.gz" >"$workdir/Packages"

# One stanza per package, separated by a blank line.
awk -v pkg="$PACKAGE" 'BEGIN { RS = "" } $0 ~ "(^|\n)Package: " pkg "(\n|$)" { print; exit }' \
  "$workdir/Packages" >"$workdir/stanza"
[ -s "$workdir/stanza" ] || die "$PACKAGE not found in $SUITE"

field() { awk -v k="$1:" '$1 == k { print $2; exit }' "$workdir/stanza"; }

version=$(field Version)
filename=$(field Filename)
expected_sha=$(field SHA256)
[ -n "$filename" ] && [ -n "$expected_sha" ] || die "index stanza is missing Filename or SHA256"

log "Package:  $PACKAGE $version"
log "Expected: $expected_sha"

deb=$workdir/package.deb
log "Downloading $DEBIAN_MIRROR/$filename"
curl -fsSL --retry 3 -o "$deb" "$DEBIAN_MIRROR/$filename" || die "download failed"

actual_sha=$(sha256_of "$deb")
[ "$actual_sha" = "$expected_sha" ] ||
  die "checksum mismatch: got $actual_sha, index says $expected_sha"
log "Checksum verified."

unpack=$workdir/unpack
mkdir -p "$unpack"
case $extractor in
bsdtar | tar)
  # bsdtar handles the ar container directly, then the inner data tarball.
  "$extractor" -xf "$deb" -C "$unpack" ||
    die "could not unpack the .deb with $extractor"
  data=$(find "$unpack" -maxdepth 1 -name 'data.tar*' -print -quit)
  [ -n "$data" ] || die "data.tar not found inside the .deb"
  "$extractor" -xf "$data" -C "$unpack" || die "could not unpack $data"
  ;;
7z)
  7z x -y -o"$unpack" "$deb" >/dev/null || die "7z failed on the .deb"
  data=$(find "$unpack" -maxdepth 1 -name 'data.tar*' -print -quit)
  [ -n "$data" ] || die "data.tar not found inside the .deb"
  7z x -y -o"$unpack" "$data" >/dev/null || die "7z failed on $data"
  # 7z leaves an intermediate data.tar when the payload is compressed.
  if [ ! -f "$unpack/$MEMBER" ] && [ -f "$unpack/data.tar" ]; then
    7z x -y -o"$unpack" "$unpack/data.tar" >/dev/null || die "7z failed on data.tar"
  fi
  ;;
esac

[ -f "$unpack/$MEMBER" ] || die "$MEMBER not found in the package"

mkdir -p "$(dirname -- "$output")"
cp "$unpack/$MEMBER" "$output"

log ""
log "Wrote $output"
log "  from   $PACKAGE $version ($SUITE)"
log "  sha256 $(sha256_of "$output")"
log ""
log "Compare against artifacts/SHA256SUMS. A difference means Debian shipped a new"
log "grub2 upload since that file was recorded, not that something is wrong."
