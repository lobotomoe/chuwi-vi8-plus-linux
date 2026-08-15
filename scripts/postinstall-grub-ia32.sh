#!/usr/bin/env bash
#
# Put a 32-bit GRUB into the installed system's ESP, so the tablet boots without
# the USB stick.
#
# Needed after any installer that assumed 64-bit firmware - Ubuntu's and
# Xubuntu's do. Lubuntu (Calamares) and debian-installer handle it themselves;
# running this afterwards is harmless.
#
# Two ways to run it:
#   on the installed system:  sudo ./postinstall-grub-ia32.sh
#   from the live session:    sudo ./postinstall-grub-ia32.sh --root /mnt
#                             (with the root filesystem mounted at /mnt and its
#                              ESP at /mnt/boot/efi)

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

root=/
esp=
bootloader_id=
offline_debs=
mounted=()

usage() {
  cat <<EOF
Usage: sudo ${0##*/} [--root DIR] [--esp DIR] [--id NAME] [--offline-debs DIR]

  --root DIR           Installed system's root (default: /)
  --esp DIR            ESP mountpoint inside that root (default: /boot/efi)
  --id NAME            GRUB bootloader-id (default: taken from /etc/os-release)
  --offline-debs DIR   Install grub-efi-ia32*.deb from here instead of the network
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
  --root)
    root=${2:?--root needs a directory}
    shift 2
    ;;
  --esp)
    esp=${2:?--esp needs a directory}
    shift 2
    ;;
  --id)
    bootloader_id=${2:?--id needs a name}
    shift 2
    ;;
  --offline-debs)
    offline_debs=${2:?--offline-debs needs a directory}
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "unknown argument: $1 (try --help)" ;;
  esac
done

[ "$(host_os)" = linux ] || die "run this on the tablet, from a Linux session"
[ "$(id -u)" -eq 0 ] || die "must run as root"
[ -d "$root" ] || die "no such directory: $root"
root=${root%/}
[ -n "$root" ] || root=/

# ---------------------------------------------------------------------------
# Sanity: is this firmware actually 32-bit, and did we boot via EFI at all?
# ---------------------------------------------------------------------------

[ -d /sys/firmware/efi ] ||
  die "this session did not boot via EFI, so grub-install cannot see the firmware.
Boot the live stick in UEFI mode and try again."

fw=$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null || echo '?')
case $fw in
32) log "Firmware is 32-bit (IA32). Installing a 32-bit GRUB." ;;
64) die "Firmware reports 64-bit. You do not need this script; install grub-efi-amd64 instead." ;;
*) warn "could not read fw_platform_size (got '$fw'). Continuing anyway." ;;
esac

# ---------------------------------------------------------------------------
# Prepare the target (chroot if --root was given)
# ---------------------------------------------------------------------------

cleanup() {
  local i
  for ((i = ${#mounted[@]} - 1; i >= 0; i--)); do
    umount -l "${mounted[i]}" 2>/dev/null || true
  done
}
trap cleanup EXIT

bind_into_root() {
  local what=$1 where=$root$2 type=${3:-}
  [ -d "$where" ] || return 0
  mountpoint -q "$where" && return 0
  if [ -n "$type" ]; then
    mount -t "$type" "$type" "$where" || return 0
  else
    mount --bind "$what" "$where" || return 0
  fi
  mounted+=("$where")
}

if [ "$root" != "" ] && [ "$root" != "/" ]; then
  require_cmd mountpoint
  [ -e "$root/etc/os-release" ] || die "$root does not look like an installed system"
  bind_into_root /dev /dev
  bind_into_root /dev/pts /dev/pts
  bind_into_root /proc /proc proc
  bind_into_root /sys /sys sysfs
  bind_into_root /run /run
  bind_into_root "" /sys/firmware/efi/efivars efivarfs
  run_in_target() { chroot "$root" "$@"; }
else
  run_in_target() { "$@"; }
fi

# ---------------------------------------------------------------------------
# Where is the ESP, and what should the entry be called?
# ---------------------------------------------------------------------------

if [ -z "$esp" ]; then
  esp=/boot/efi
  # Arch and some others mount the ESP at /efi instead.
  if ! grep -qE '[[:space:]]/boot/efi[[:space:]]' "$root/etc/fstab" 2>/dev/null &&
    grep -qE '[[:space:]]/efi[[:space:]]' "$root/etc/fstab" 2>/dev/null; then
    esp=/efi
  fi
fi
mountpoint -q "$root$esp" || mount "$root$esp" 2>/dev/null || true
[ -d "$root$esp/EFI" ] || die "$root$esp does not look like an ESP (no EFI directory).
Mount it first, or pass --esp."

if [ -z "$bootloader_id" ]; then
  # shellcheck disable=SC1091 # path is built at runtime from --root
  bootloader_id=$(. "$root/etc/os-release" >/dev/null 2>&1 && printf '%s' "${ID:-linux}")
fi
log "ESP: $esp    bootloader-id: $bootloader_id"

# ---------------------------------------------------------------------------
# Install the 32-bit GRUB package
# ---------------------------------------------------------------------------

if run_in_target sh -c 'command -v apt-get' >/dev/null 2>&1; then
  if [ -n "$offline_debs" ]; then
    [ -d "$offline_debs" ] || die "no such directory: $offline_debs"
    log "Installing .deb files from $offline_debs ..."
    cp "$offline_debs"/*.deb "$root/tmp/" || die "could not stage the .deb files"
    run_in_target sh -c 'dpkg -i /tmp/grub-efi-ia32*.deb' || die "dpkg failed"
    run_in_target sh -c 'rm -f /tmp/grub-efi-ia32*.deb'
  else
    log "Installing grub-efi-ia32-bin (needs network)..."
    run_in_target apt-get update ||
      warn "apt-get update failed; the install below may still work from cache"
    run_in_target apt-get install -y grub-efi-ia32-bin grub-efi-ia32 ||
      die "could not install grub-efi-ia32. No network? Use --offline-debs, see
scripts/fetch-offline-payload.sh"
  fi
elif run_in_target sh -c 'command -v pacman' >/dev/null 2>&1; then
  log "Installing grub (Arch ships every EFI target in one package)..."
  run_in_target pacman -S --needed --noconfirm grub efibootmgr || die "pacman failed"
else
  die "unrecognised distribution: no apt-get and no pacman in $root"
fi

run_in_target sh -c 'test -d /usr/lib/grub/i386-efi' ||
  die "/usr/lib/grub/i386-efi is missing - the 32-bit GRUB modules did not get installed"

# ---------------------------------------------------------------------------
# Install GRUB twice: an NVRAM entry, plus the removable-media fallback
# ---------------------------------------------------------------------------

log "Running grub-install (NVRAM entry)..."
run_in_target grub-install --target=i386-efi --efi-directory="$esp" \
  --bootloader-id="$bootloader_id" --recheck ||
  warn "the NVRAM entry could not be written; the fallback below is what will boot"

# \EFI\BOOT\bootia32.efi is what the firmware falls back to when no NVRAM entry
# matches. On these tablets it is frequently the only thing that works.
log "Running grub-install --removable (\\EFI\\BOOT\\bootia32.efi fallback)..."
run_in_target grub-install --target=i386-efi --efi-directory="$esp" \
  --removable --recheck || die "the removable fallback install failed"

log "Regenerating the GRUB menu..."
if run_in_target sh -c 'command -v update-grub' >/dev/null 2>&1; then
  run_in_target update-grub || die "update-grub failed"
else
  run_in_target grub-mkconfig -o /boot/grub/grub.cfg || die "grub-mkconfig failed"
fi

log ""
log "ESP now contains:"
find "$root$esp/EFI" -iname '*.efi' -printf '  %p (%s bytes)\n' 2>/dev/null ||
  find "$root$esp/EFI" -iname '*.efi' >&2

log ""
log "Done. Remove the USB stick and reboot."
log "If the tablet still boots into the firmware menu, pick the entry named"
log "'$bootloader_id' or the internal eMMC, then see docs/50-troubleshooting.md."
