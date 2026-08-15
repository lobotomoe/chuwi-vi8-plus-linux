#!/usr/bin/env bash
#
# Four settings that matter on a 2 GB / 32 GB eMMC tablet. Run on the installed
# system, not from the live session.
#
# Prints what it would do and changes nothing unless you pass --apply.

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

apply=no
failures=0

usage() {
  cat <<EOF
Usage: sudo ${0##*/} [--apply]

Without --apply this only reports. With --apply it will:

  1. zram swap           compressed swap in RAM, sized at half of physical
  2. fstrim.timer        weekly TRIM, so the eMMC does not slow to a crawl
  3. iio-sensor-proxy    the daemon desktops use for automatic screen rotation
  4. journald cap        50 MB of logs instead of unbounded eMMC writes

It deliberately does not touch /etc/fstab. Mount options are yours to change.
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
  --apply)
    apply=yes
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "unknown argument: $1 (try --help)" ;;
  esac
done

[ "$(host_os)" = linux ] || die "run this on the tablet"
if [ "$apply" = yes ] && [ "$(id -u)" -ne 0 ]; then die "--apply needs root"; fi

pm=
if command -v apt-get >/dev/null 2>&1; then
  pm=apt
elif command -v pacman >/dev/null 2>&1; then
  pm=pacman
fi
[ -n "$pm" ] || die "unrecognised distribution: no apt-get and no pacman"

step() { log ""; log "--- $1"; }
would() { log "    would run: $*"; }

# A failed step is recorded, not swallowed: the remaining steps are independent
# and still worth attempting, but the script must not exit 0 pretending it
# succeeded. The tally is reported and turned into a non-zero exit at the end.
run() {
  if [ "$apply" = yes ]; then
    log "    $*"
    if ! "$@"; then
      warn "failed: $*"
      failures=$((failures + 1))
    fi
  else
    would "$@"
  fi
}

install_pkg() {
  case $pm in
  apt) run apt-get install -y "$@" ;;
  pacman) run pacman -S --needed --noconfirm "$@" ;;
  esac
}

write_file() {
  local path=$1 content=$2
  if [ "$apply" = yes ]; then
    mkdir -p "$(dirname -- "$path")"
    printf '%s' "$content" >"$path"
    log "    wrote $path"
  else
    log "    would write $path:"
    printf '%s' "$content" | sed 's/^/        /' >&2
  fi
}

# ---------------------------------------------------------------------------

step "1. zram swap"
if [ -e /dev/zram0 ] || [ -f /etc/systemd/zram-generator.conf ]; then
  log "    already configured"
else
  mem_kb=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
  log "    physical RAM: $((mem_kb / 1024)) MiB -> zram device of half that"
  case $pm in
  apt) install_pkg systemd-zram-generator ;;
  pacman) install_pkg zram-generator ;;
  esac
  write_file /etc/systemd/zram-generator.conf \
    '[zram0]
zram-size = ram / 2
compression-algorithm = zstd
'
  run systemctl daemon-reload
  run systemctl start systemd-zram-setup@zram0.service
fi

step "2. Weekly TRIM"
if systemctl is-enabled fstrim.timer >/dev/null 2>&1; then
  log "    already enabled"
else
  run systemctl enable --now fstrim.timer
fi

step "3. Screen rotation daemon"
if command -v iio-sensor-proxy >/dev/null 2>&1 ||
  [ -x /usr/libexec/iio-sensor-proxy ] || [ -x /usr/lib/iio-sensor-proxy ]; then
  log "    already installed"
else
  install_pkg iio-sensor-proxy
fi
iio_devices=$(find /sys/bus/iio/devices -mindepth 1 -maxdepth 1 -printf '%f ' 2>/dev/null || true)
if [ -n "$iio_devices" ]; then
  log "    accelerometer visible: $iio_devices"
else
  warn "no iio devices - the accelerometer driver did not bind, rotation will not work"
fi

step "4. Cap the journal"
if [ -f /etc/systemd/journald.conf.d/50-vi8plus.conf ]; then
  log "    already configured"
else
  write_file /etc/systemd/journald.conf.d/50-vi8plus.conf \
    '[Journal]
SystemMaxUse=50M
SystemMaxFileSize=10M
'
  run systemctl restart systemd-journald
fi

# ---------------------------------------------------------------------------

log ""
log "Left alone on purpose, decide for yourself:"
log ""
log "  /etc/fstab mount options. 'noatime' on the root filesystem removes one"
log "  eMMC write per file read. Current root options:"
awk '$2 == "/" { print "    " $0 }' /proc/mounts >&2
log ""
log "  Kernel command line. The panel is 1280x800 and native landscape, so"
log "  nothing is needed for normal use. If early boot is garbled, add"
log "  video=1280x800@60 to GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub."
log ""
if [ "$apply" = no ]; then
  log "Nothing was changed. Re-run with --apply."
elif [ "$failures" -gt 0 ]; then
  die "$failures step(s) failed - see the 'warning:' lines above.
Whatever succeeded is in place; nothing was rolled back. Fix the cause and
re-run: every step checks whether it is already done before acting."
else
  log "All steps completed."
fi
