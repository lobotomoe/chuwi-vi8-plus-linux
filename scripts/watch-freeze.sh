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

# Every read here is of a file that may not exist. axp288_charger vanished from
# sysfs on one boot of the reference unit while charging carried on regardless,
# so a missing file is normal operation, not an error -- and must never take the
# recorder down with it.
read_or_empty() {
  [ -r "$1" ] || return 0
  cat -- "$1" 2>/dev/null || true
}

# microamps/microvolts to milli, which is what the datasheets and everyone's
# mental model use. Keeps the log narrow enough to read on an 8" screen.
milli() {
  local raw=$1
  case $raw in
  '' | *[!0-9-]*) printf '?' ;;
  *) printf '%s' $((raw / 1000)) ;;
  esac
}

# Overridable so the sampler can be exercised against a fake tree, including the
# case where axp288_charger is simply not there -- which happened on the unit.
PSY=${PSY:-/sys/class/power_supply}
CPUIDLE=${CPUIDLE:-/sys/devices/system/cpu/cpu0/cpuidle}
THERMAL=${THERMAL:-/sys/class/thermal}
DRM=${DRM:-/sys/class/drm}
CPUFREQ=${CPUFREQ:-/sys/devices/system/cpu/cpu0/cpufreq}
PROC_STAT=${PROC_STAT:-/proc/stat}

# Highest reading across all thermal zones, in whole degrees. Which zone is
# hottest matters less than whether anything is climbing before a freeze.
max_temp_c() {
  local zone raw hottest=
  for zone in "$THERMAL"/thermal_zone*/temp; do
    [ -r "$zone" ] || continue
    raw=$(read_or_empty "$zone")
    case $raw in
    '' | *[!0-9-]*) continue ;;
    esac
    if [ -z "$hottest" ] || [ "$raw" -gt "$hottest" ]; then hottest=$raw; fi
  done
  [ -n "$hottest" ] || {
    printf '?'
    return 0
  }
  printf '%s' $((hottest / 1000))
}

# The GT frequency file has moved around and the card number is not fixed -- it
# is card1 on the reference unit, because card0 is taken. Resolve it once rather
# than hard-coding a path that silently reports "?" forever.
find_gpu_freq_file() {
  local candidate
  for candidate in \
    "$DRM"/card*/gt_cur_freq_mhz \
    "$DRM"/card*/gt/gt0/rps_cur_freq_mhz \
    "$DRM"/card*/device/tile0/gt0/freq0/cur_freq; do
    [ -r "$candidate" ] || continue
    printf '%s' "$candidate"
    return 0
  done
  return 0
}

gpu_freq_file=$(find_gpu_freq_file)

idle_state_names() {
  local state name names=
  for state in "$CPUIDLE"/state*; do
    [ -d "$state" ] || continue
    name=$(read_or_empty "$state/name")
    names="${names:+$names,}${name:-?}"
  done
  printf '%s' "${names:-none}"
}

# Cumulative entry counts, one per idle state. Sampled as deltas below: a jump
# in the deepest state on the last line before a hang is the evidence that would
# implicate C-states, and its absence is the evidence that would clear them.
idle_usage_now() {
  local state usage out=
  for state in "$CPUIDLE"/state*; do
    [ -d "$state" ] || continue
    usage=$(read_or_empty "$state/usage")
    out="${out:+$out }${usage:-0}"
  done
  printf '%s' "$out"
}

prev_usage=
prev_cpu_busy=
prev_cpu_total=

# Cumulative jiffy counters as "busy total".
#
# This exists because scaling_cur_freq cannot answer the question. Reading it
# requires running this script, which wakes the CPU, so it reports near-maximum
# whatever the machine was doing -- the instrument measuring its own footprint.
# Jiffy counters are cumulative and immune to that.
cpu_counters_now() {
  local tag user nice system idle iowait irq softirq steal
  # stderr first: redirections apply left to right, so a missing file would
  # otherwise be reported by the shell before 2>/dev/null takes effect.
  if ! read -r tag user nice system idle iowait irq softirq steal _ 2>/dev/null <"$PROC_STAT"; then
    return 0
  fi
  [ "$tag" = cpu ] || return 0
  printf '%s %s' \
    $((user + nice + system + irq + softirq + steal)) \
    $((user + nice + system + idle + iowait + irq + softirq + steal))
}

# Percentage of that time which was not idle since the previous sample. Split
# from the reader above because the caller runs it in a command substitution,
# and a subshell cannot carry the previous counters back -- the state has to
# live in sample_line, exactly as it does for the idle-state deltas.
cpu_busy_pct() {
  local now=$1 busy total dbusy dtotal
  read -r busy total <<<"$now"
  case ${busy:-}${total:-} in
  '' | *[!0-9]*)
    printf '?'
    return 0
    ;;
  esac
  if [ -z "$prev_cpu_total" ]; then
    printf 'first'
    return 0
  fi
  dtotal=$((total - prev_cpu_total))
  dbusy=$((busy - prev_cpu_busy))
  [ "$dtotal" -gt 0 ] || {
    printf '?'
    return 0
  }
  printf '%s' $((dbusy * 100 / dtotal))
}

idle_deltas() {
  local now=$1 a b out='' i=0
  local -a cur prev
  read -r -a cur <<<"$now"
  read -r -a prev <<<"$prev_usage"
  [ ${#cur[@]} -gt 0 ] || {
    printf '?'
    return 0
  }
  if [ ${#prev[@]} -ne ${#cur[@]} ]; then
    printf 'first'
    return 0
  fi
  while [ $i -lt ${#cur[@]} ]; do
    a=${cur[$i]}
    b=${prev[$i]}
    out="${out:+$out/}$((a - b))"
    i=$((i + 1))
  done
  printf '%s' "$out"
}

sample_line() {
  local now_usage status capacity current voltage online ilim gpu loadavg khz uptime busy now_cpu

  status=$(read_or_empty "$PSY/axp288_fuel_gauge/status")
  capacity=$(read_or_empty "$PSY/axp288_fuel_gauge/capacity")
  current=$(milli "$(read_or_empty "$PSY/axp288_fuel_gauge/current_now")")
  voltage=$(milli "$(read_or_empty "$PSY/axp288_fuel_gauge/voltage_now")")
  online=$(read_or_empty "$PSY/axp288_charger/online")
  ilim=$(milli "$(read_or_empty "$PSY/axp288_charger/input_current_limit")")
  gpu=$(read_or_empty "${gpu_freq_file:-/nonexistent}")
  khz=$(read_or_empty "$CPUFREQ/scaling_cur_freq")
  loadavg=$(read_or_empty /proc/loadavg)
  loadavg=${loadavg%% *}
  uptime=$(read_or_empty /proc/uptime)
  uptime=${uptime%%.*}
  now_cpu=$(cpu_counters_now)
  busy=$(cpu_busy_pct "$now_cpu")

  now_usage=$(idle_usage_now)

  printf 't=%s up=%s bat=%s%% bst=%s bcur=%smA bv=%smV chg=%s ilim=%smA temp=%sC load=%s busy=%s%% cpu=%sMHz gpu=%sMHz idle=%s\n' \
    "$(date +%H:%M:%S)" \
    "${uptime:-?}" \
    "${capacity:-?}" \
    "${status:-none}" \
    "$current" \
    "$voltage" \
    "${online:-none}" \
    "$ilim" \
    "$(max_temp_c)" \
    "${loadavg:-?}" \
    "$busy" \
    "$((${khz:-0} / 1000))" \
    "${gpu:-?}" \
    "$(idle_deltas "$now_usage")"

  prev_usage=$now_usage
  if [ -n "$now_cpu" ]; then
    prev_cpu_busy=${now_cpu%% *}
    prev_cpu_total=${now_cpu##* }
  fi
}

# cpu= is the instantaneous requested frequency and is distorted by this script
# waking the CPU to read it; busy= is the honest one. Kept because a frequency
# pinned low while busy= is high would mean thermal throttling, which no other
# column would show.

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
    printf -- '--- interval %ss, idle= fields are entries per interval\n' "$interval"
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
