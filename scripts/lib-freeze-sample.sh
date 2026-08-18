#!/usr/bin/env bash
#
# The sampling half of watch-freeze.sh: everything that reads the hardware and
# turns it into one line of log. Split out so it can be exercised against a fake
# sysfs tree without a tablet, and so the recorder itself stays about the loop,
# the service and the report.
#
# Sourced, never run. All sysfs roots are overridable for exactly that reason.

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

# Every zone, in whole degrees, in sysfs order -- the header says which name goes
# with which position.
#
# This used to report the maximum, and the maximum lies twice on this hardware.
# `INT3400 Thermal` is a DPTF policy device with no sensor behind it: it reports a
# constant 20 C, which is what the recorder called the machine's temperature in
# the first sample of every boot, before the real zones had registered. And the
# hottest real zone is `PNIT`, which runs about 6 C above `soc_dts0`/`soc_dts1`,
# the SoC's own sensors -- so a single number was reported as the die temperature
# while being neither the die nor a fixed offset from it.
thermal_zone_names() {
  local zone name names=
  for zone in "$THERMAL"/thermal_zone*; do
    [ -d "$zone" ] || continue
    name=$(read_or_empty "$zone/type")
    names="${names:+$names,}${name:-?}"
  done
  printf '%s' "${names:-none}"
}

thermal_temps_c() {
  local zone raw out=
  for zone in "$THERMAL"/thermal_zone*; do
    [ -d "$zone" ] || continue
    raw=$(read_or_empty "$zone/temp")
    case $raw in
    '' | *[!0-9-]*) out="${out:+$out/}?" ;;
    *) out="${out:+$out/}$((raw / 1000))" ;;
    esac
  done
  printf '%s' "${out:-?}"
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
prev_zone_names=

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
  local now_usage status capacity current voltage online ilim gpu loadavg khz uptime busy now_cpu zones

  # Zones register as their drivers probe, so the set at the first sample of a
  # boot is not the set a minute later. Re-announce it whenever it changes,
  # otherwise the header would mislabel every column below it.
  zones=$(thermal_zone_names)
  if [ "$zones" != "$prev_zone_names" ]; then
    printf -- '--- thermal zones %s\n' "$zones"
    prev_zone_names=$zones
  fi

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
    "$(thermal_temps_c)" \
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

