#!/usr/bin/env bash
#
# Dump everything about this tablet that matters for the rest of this repo, into
# one file. Run it from the live session before installing, and again afterwards.
#
# Read-only. Root is not required, but a few sections are richer with it.

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

[ "$(host_os)" = linux ] || die "run this on the tablet, from a Linux session"

outdir=$REPO_ROOT/reports
out=$outdir/hw-$(date +%Y%m%d-%H%M%S).txt

[ $# -eq 0 ] || {
  case $1 in
  -h | --help)
    printf 'Usage: %s\nWrites reports/hw-<timestamp>.txt\n' "${0##*/}"
    exit 0
    ;;
  *) die "unknown argument: $1" ;;
  esac
}

mkdir -p "$outdir"

section() { printf '\n===== %s =====\n' "$1"; }

# Runs a command if it exists, and says so plainly when it does not.
try() {
  if command -v "$1" >/dev/null 2>&1; then
    "$@" 2>&1 || true
  else
    printf '(%s not installed)\n' "$1"
  fi
}

{
  printf 'chuwi-vi8-plus-linux hardware report\n'
  printf 'generated: %s\n' "$(date -Is)"

  section "Identity (DMI)"
  for f in sys_vendor product_name product_version board_vendor board_name \
    bios_vendor bios_version bios_date; do
    printf '%-16s %s\n' "$f" "$(cat "/sys/class/dmi/id/$f" 2>/dev/null || echo '?')"
  done
  printf '\nExpected on a Chuwi Vi8 Plus: Hampoo / D2D3_Vi8A1 / Cherry Trail CR\n'

  section "Firmware"
  if [ -d /sys/firmware/efi ]; then
    printf 'booted via UEFI: yes\n'
    printf 'fw_platform_size: %s (32 = IA32 firmware, 64 = x64 firmware)\n' \
      "$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null || echo '?')"
    printf 'efivars writable: %s\n' \
      "$([ -d /sys/firmware/efi/efivars ] && echo yes || echo no)"
  else
    printf 'booted via UEFI: NO - this is a legacy/BIOS boot\n'
  fi
  printf '\nSecure Boot: '
  try mokutil --sb-state

  section "Kernel"
  uname -a
  printf '\nRelevant config options:\n'
  cfg=/boot/config-$(uname -r)
  if [ -r "$cfg" ]; then
    grep -E '^(# )?CONFIG_(EFI_MIXED|EFI_HANDOVER_PROTOCOL|EFI_EMBEDDED_FIRMWARE|TOUCHSCREEN_DMI|TOUCHSCREEN_CHIPONE_ICN8505|SND_SOC_INTEL_BYTCR_RT5651_MACH|BRCMFMAC)\b' \
      "$cfg" || printf '(none matched)\n'
  else
    printf '(%s not readable - live images often omit it)\n' "$cfg"
  fi

  section "Storage"
  try lsblk -o NAME,SIZE,TYPE,FSTYPE,PARTTYPENAME,MOUNTPOINT
  printf '\nPartition table of the eMMC:\n'
  for d in /dev/mmcblk0 /dev/mmcblk1; do
    [ -b "$d" ] && { try sudo -n sfdisk -l "$d" || true; }
  done

  section "PCI"
  try lspci -nnk

  section "USB"
  try lsusb

  section "Loaded modules of interest"
  lsmod | grep -E 'i915|brcmfmac|icn8505|rt5651|bytcr|snd_soc|axp288|bmc150|sdhci|hci_uart|btbcm' ||
    printf '(none loaded)\n'

  section "Input devices"
  cat /proc/bus/input/devices 2>/dev/null || printf '(unavailable)\n'

  section "Sound"
  try aplay -l
  printf '\n'
  cat /proc/asound/cards 2>/dev/null || true

  section "Power supply"
  for ps in /sys/class/power_supply/*; do
    [ -e "$ps" ] || continue
    printf -- '--- %s\n' "$(basename -- "$ps")"
    for k in type status capacity voltage_now current_now online; do
      [ -r "$ps/$k" ] && printf '%-12s %s\n' "$k" "$(cat "$ps/$k")"
    done
  done

  section "Backlight"
  for bl in /sys/class/backlight/*; do
    [ -e "$bl" ] || continue
    printf '%s: %s / %s\n' "$(basename -- "$bl")" \
      "$(cat "$bl/brightness" 2>/dev/null)" "$(cat "$bl/max_brightness" 2>/dev/null)"
  done

  section "Accelerometer / iio"
  ls -l /sys/bus/iio/devices/ 2>/dev/null || printf '(no iio devices)\n'
  try systemctl status iio-sensor-proxy --no-pager

  section "dmesg: boot, firmware, tablet drivers"
  dmesg 2>/dev/null |
    grep -iE 'efi|secure boot|icn8505|chipone|brcmfmac|rt5651|bytcr|axp288|bmc150|touchscreen|firmware' ||
    printf '(dmesg not readable without root)\n'
} >"$out" 2>&1

log "Wrote $out"
log ""
log "Quick read of the two lines that matter most:"
grep -E 'fw_platform_size|product_name' "$out" >&2 || true
