#!/usr/bin/env bash
#
# Download the packages the tablet needs but cannot get by itself, so they can be
# carried on the USB stick.
#
# Only Ubuntu flavours need this: their ISOs do not carry grub-efi-ia32-bin, and
# the tablet has no wired network. Debian's netinst already has it in its pool.
#
# Run this on your computer before building the stick, then copy the resulting
# directory onto the stick (or a second one).

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

UBUNTU_MIRROR=${UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu}
release=resolute
outdir=$REPO_ROOT/payload
packages=(grub-efi-ia32-bin)

usage() {
  cat <<EOF
Usage: ${0##*/} [--release CODENAME] [--out DIR] [--package NAME]...

  --release CODENAME  Ubuntu series codename (default: $release, which is 26.04 LTS)
  --out DIR           Where to put the .deb files (default: payload/)
  --package NAME      Extra package to fetch; repeatable

Environment:
  UBUNTU_MIRROR       Archive base URL (default: $UBUNTU_MIRROR)

grub-efi-ia32-bin is the only package strictly required: it provides
/usr/lib/grub/i386-efi, which is what "grub-install --target=i386-efi" needs.
It is co-installable with grub-efi-amd64-bin, so installing it offline cannot
leave the tablet without a bootloader.
EOF
}

extra=()
while [ $# -gt 0 ]; do
  case $1 in
  --release)
    release=${2:?--release needs a codename}
    shift 2
    ;;
  --out)
    outdir=${2:?--out needs a directory}
    shift 2
    ;;
  --package)
    extra+=("${2:?--package needs a name}")
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "unknown argument: $1 (try --help)" ;;
  esac
done
packages+=("${extra[@]+"${extra[@]}"}")

require_cmd curl gzip awk
mkdir -p "$outdir"

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

# Order matters: the stanza picked below is the last one seen, so the pockets
# that carry newer builds are appended after the release pocket.
for pocket in "$release" "$release-security" "$release-updates"; do
  url="$UBUNTU_MIRROR/dists/$pocket/main/binary-amd64/Packages.gz"
  log "Fetching index: $url"
  if curl -fsSL --retry 3 -o "$workdir/$pocket.gz" "$url"; then
    gzip -dc "$workdir/$pocket.gz" >>"$workdir/Packages"
  else
    warn "no index for $pocket (that is normal for a brand-new series)"
  fi
done
[ -s "$workdir/Packages" ] || die "could not fetch any package index for $release"

for pkg in "${packages[@]}"; do
  # Later pockets were appended last, so take the final stanza for the package.
  awk -v p="$pkg" 'BEGIN { RS = "" } $0 ~ "(^|\n)Package: " p "(\n|$)" { last = $0 } END { print last }' \
    "$workdir/Packages" >"$workdir/stanza"
  [ -s "$workdir/stanza" ] || die "$pkg not found in $release"

  filename=$(awk '$1 == "Filename:" { print $2; exit }' "$workdir/stanza")
  expected=$(awk '$1 == "SHA256:" { print $2; exit }' "$workdir/stanza")
  version=$(awk '$1 == "Version:" { print $2; exit }' "$workdir/stanza")
  [ -n "$filename" ] && [ -n "$expected" ] || die "index stanza for $pkg is incomplete"

  dest=$outdir/$(basename -- "$filename")
  log "Downloading $pkg $version"
  curl -fsSL --retry 3 -o "$dest" "$UBUNTU_MIRROR/$filename" || die "download of $pkg failed"

  actual=$(sha256_of "$dest")
  [ "$actual" = "$expected" ] || die "checksum mismatch for $pkg: $actual != $expected"
  log "  $dest  (verified)"
done

log ""
log "Copy $outdir onto the USB stick, then on the tablet run:"
log "  sudo ./scripts/postinstall-grub-ia32.sh --root /mnt --offline-debs /path/to/payload"
