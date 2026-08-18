#!/usr/bin/env bash
#
# Black-box recorder for the freezes on this tablet.
#
# The freezes leave nothing behind: the journal simply stops mid-boot, because a
# hard hang gives the kernel no chance to flush anything. So this samples the
# handful of things that could plausibly explain one -- power, thermals, load,
# CPU idle states, GPU clock -- and forces each line to disk before taking the
# next sample. Whatever the last line says is the state the machine was in when
# it died.
#
# It exists because guessing from the tail of the journal produced three
# different theories in one evening, and none of them could be told apart
# without knowing what the hardware was doing at the moment it stopped.
#
# Linux only, and --install needs root.

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

LOG_DEFAULT=/var/log/chuwi-freeze-watch.log
INTERVAL_DEFAULT=5
SERVICE_PATH=/etc/systemd/system/chuwi-freeze-watch.service

# Anything below this is a sample the recorder itself would distort: the write
# and the fsync start to cost more than what is being measured, and on eMMC the
# wear stops being negligible.
INTERVAL_MIN=1

log_path=$LOG_DEFAULT
interval=$INTERVAL_DEFAULT
mode=run

usage() {
  cat <<EOF
Usage: ${0##*/} [--log PATH] [--interval SECONDS]
       ${0##*/} --install [--log PATH] [--interval SECONDS]
       ${0##*/} --report [--log PATH]

  (no mode)     Sample until interrupted, appending to the log.
  --install     Install and start a systemd service that does that from boot,
                early enough to catch the freezes that happen during one.
  --report      Show what the machine was doing at the end of every session, and
                which of those ends was a freeze rather than a restart or a stop.

  --log PATH        Where to write (default: $LOG_DEFAULT)
  --interval SECS   Seconds between samples (default: $INTERVAL_DEFAULT)

Every line is flushed to disk before the next sample, so the last line survives
a hard hang. That is the whole point; do not "optimise" it away.
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
  --log)
    log_path=${2:?--log needs a path}
    shift 2
    ;;
  --interval)
    interval=${2:?--interval needs a number}
    shift 2
    ;;
  --install)
    mode=install
    shift
    ;;
  --report)
    mode=report
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

case $interval in
'' | *[!0-9]*) die "--interval must be a whole number of seconds, got '$interval'" ;;
esac
[ "$interval" -ge "$INTERVAL_MIN" ] ||
  die "--interval below ${INTERVAL_MIN}s costs more than it measures"

# Argument checks first, so they can be exercised anywhere. Only the two modes
# that touch sysfs need to be on the tablet; --report just reads a file, and
# being able to read a log on a laptop is the point of copying it off.
case $mode in
run | install)
  [ "$(host_os)" = linux ] || die "this reads Linux sysfs; run it on the tablet"
  ;;
esac

# shellcheck source-path=SCRIPTDIR source=lib-freeze-sample.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib-freeze-sample.sh"

# Data-only fsync of the one file, where available -- a full sync every few
# seconds on eMMC is a cost with no benefit here.
sync_cmd() {
  if sync --data "$log_path" 2>/dev/null; then return 0; fi
  sync
}

# systemd sends SIGTERM on stop and on shutdown, so a session that ends without
# this marker ended without anyone asking it to. That is the whole distinction
# the report needs, and it cannot be recovered afterwards -- write it now.
finish() {
  printf -- '--- session end %s %s\n' "$1" "$(date '+%Y-%m-%d %H:%M:%S %z')" \
    >>"$log_path"
  sync_cmd
  exit 0
}

run_recorder() {
  local dir sleeper
  dir=$(dirname -- "$log_path")
  [ -d "$dir" ] || die "no such directory: $dir"
  : >>"$log_path" || die "cannot write to $log_path (try sudo)"

  trap 'finish TERM' TERM
  trap 'finish INT' INT
  trap 'finish HUP' HUP

  {
    printf -- '--- session start %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
    # Unique per boot, so the report can tell a recorder restart from a machine
    # that went away and came back.
    printf -- '--- boot %s\n' "$(read_or_empty /proc/sys/kernel/random/boot_id)"
    printf -- '--- kernel %s\n' "$(uname -r)"
    printf -- '--- cmdline %s\n' "$(read_or_empty /proc/cmdline)"
    printf -- '--- cpuidle driver %s, states %s\n' \
      "$(read_or_empty /sys/devices/system/cpu/cpuidle/current_driver)" \
      "$(idle_state_names)"
    printf -- '--- gpu freq from %s\n' "${gpu_freq_file:-not found}"
    printf -- '--- interval %ss, idle= fields are entries per interval,\n' "$interval"
    printf -- '--- temp= fields follow the thermal zones line below\n'
  } >>"$log_path"
  sync_cmd

  log "recording to $log_path every ${interval}s; Ctrl-C to stop"
  while :; do
    sample_line >>"$log_path"
    sync_cmd
    # Backgrounded and waited on rather than run in the foreground: bash defers
    # a trap until the current command finishes, so a foreground sleep would
    # swallow the shutdown signal for up to one interval and lose the marker.
    sleep "$interval" &
    sleeper=$!
    wait "$sleeper" || true
  done
}

install_service() {
  [ "$(id -u)" -eq 0 ] || die "--install needs root"
  local self
  self=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")

  cat >"$SERVICE_PATH" <<EOF
[Unit]
Description=Chuwi Vi8 Plus freeze recorder
DefaultDependencies=no
After=local-fs.target
Before=basic.target

[Service]
Type=simple
ExecStart=$self --log $log_path --interval $interval
Restart=always
Nice=-5

[Install]
WantedBy=sysinit.target
EOF

  systemctl daemon-reload
  systemctl enable --now chuwi-freeze-watch.service
  log "installed $SERVICE_PATH and started it"
  log ""
  log "it now starts before basic.target, so it is already sampling by the time"
  log "the boot-tail freezes happen. After the next freeze:"
  log "  sudo ./scripts/watch-freeze.sh --report"
  log ""
  log "to remove: sudo systemctl disable --now chuwi-freeze-watch.service &&"
  log "           sudo rm $SERVICE_PATH"
}

# A session that ended in a freeze has no clean end -- the next thing in the log
# is another "session start". So the interesting lines are the ones immediately
# before each of those, and the last line of the file if the machine is up now.
#
# Three things end a session and only one of them is a freeze, so the report has
# to say which: a restart of the recorder alone, an orderly stop or shutdown, and
# the machine going away underneath it. Calling all three "session ended here"
# invites reading a systemctl restart as a crash, which is exactly what happened
# the first time this log was read.
report() {
  [ -r "$log_path" ] || die "no log at $log_path (run --install first)"
  local tail_len=12
  awk -v tail_len="$tail_len" '
    function uptime_of(line) {
      if (match(line, /up=[0-9]+/))
        return substr(line, RSTART + 3, RLENGTH - 3) + 0
      return -1
    }
    function verdict(i,   k, next_first) {
      if (i == sessions)
        return clean[i] ? "stopped cleanly, nothing running since" : "current session"
      if (clean[i])
        return "stopped cleanly"

      # Same boot id means only the recorder went away. A different one means
      # the machine did, and nobody asked it to.
      if (boot[i] != "" && boot[i + 1] != "") {
        if (boot[i] == boot[i + 1])
          return "recorder restarted, machine kept running"
        return "DIED HERE -- no clean stop, and the machine rebooted"
      }

      # Logs written before boot ids were recorded. Uptime that keeps climbing
      # across the gap says the machine did not reboot; anything else says it
      # did, since a fresh boot restarts the count.
      next_first = -1
      for (k = i + 1; k <= sessions; k++)
        if (samples[k] > 0) { next_first = first_up[k]; break }
      if (next_first < 0 || last_up[i] < 0)
        return "ended, cause unknown (log predates boot ids)"
      if (next_first > last_up[i])
        return "recorder restarted, machine kept running"
      return "DIED HERE -- no clean stop, and uptime restarted"
    }
    /^--- session start/ {
      sessions++
      started[sessions] = substr($0, 19)
      samples[sessions] = 0
      next
    }
    /^--- boot / { if (sessions > 0) boot[sessions] = $3; next }
    /^--- session end/ { if (sessions > 0) clean[sessions] = 1; next }
    /^--- / { next }
    {
      if (sessions == 0) next
      buf[sessions "," (samples[sessions] % tail_len)] = $0
      if (samples[sessions] == 0) first_up[sessions] = uptime_of($0)
      last_up[sessions] = uptime_of($0)
      samples[sessions]++
    }
    END {
      for (i = 1; i <= sessions; i++) {
        printf "\n=== %s, started %s\n", verdict(i), started[i]
        if (samples[i] == 0) {
          print "  (no samples -- it did not survive to the first one)"
          continue
        }
        for (j = (samples[i] > tail_len ? samples[i] - tail_len : 0); j < samples[i]; j++)
          print "  " buf[i "," (j % tail_len)]
      }
    }
  ' "$log_path"

  printf '\n'
  log "Each block is the last ${tail_len} samples of a session. Only the blocks"
  log "marked DIED HERE are freezes -- read the final line of one as the state the"
  log "machine was in when it stopped."
}

case $mode in
run) run_recorder ;;
install) install_service ;;
report) report ;;
esac
