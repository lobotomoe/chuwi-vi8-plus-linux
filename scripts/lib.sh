#!/usr/bin/env bash
# Shared helpers. Sourced by the other scripts; not executable on its own.

set -o errexit
set -o nounset
set -o pipefail

log() { printf '%s\n' "$*" >&2; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

# Debian/Ubuntu package providing a command, for the cases where the two names
# differ. Anything not listed ships in a package of the same name.
pkg_for_cmd() {
  case "$1" in
  mountpoint | lsblk | sfdisk | blockdev) printf 'util-linux' ;;
  dd | df) printf 'coreutils' ;;
  cmp) printf 'diffutils' ;;
  sgdisk) printf 'gdisk' ;;
  mkfs.vfat) printf 'dosfstools' ;;
  udevadm) printf 'udev' ;;
  xz) printf 'xz-utils' ;;
  *) printf '%s' "$1" ;;
  esac
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 && continue
    die "required command not found: $cmd" \
      "(Debian/Ubuntu: sudo apt install $(pkg_for_cmd "$cmd"))"
  done
}

# First available command from the list, or empty.
first_cmd() {
  local cmd
  for cmd in "$@"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      printf '%s' "$cmd"
      return 0
    fi
  done
  return 1
}

host_os() {
  case "$(uname -s)" in
  Darwin) printf 'macos' ;;
  Linux) printf 'linux' ;;
  *) printf 'unsupported' ;;
  esac
}

sha256_of() {
  local file=$1
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | cut -d' ' -f1
  else
    die "no sha256sum or shasum available"
  fi
}

# Refuses to continue unless the user types the exact expected string.
confirm_exact() {
  local expected=$1 prompt=$2 answer
  printf '%s\n' "$prompt" >&2
  printf 'Type %s to continue: ' "$expected" >&2
  IFS= read -r answer
  [ "$answer" = "$expected" ] || die "aborted (got '$answer')"
}

REPO_ROOT=${REPO_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}
export REPO_ROOT
