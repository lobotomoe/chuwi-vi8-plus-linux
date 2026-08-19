#!/usr/bin/env bash
#
# Controlled load test: try to provoke the freeze on demand instead of waiting
# hours for one.
#
# Waiting is what this replaces. Every freeze so far has cost a couple of hours
# of idling and a trip to the tablet, which is why eight theories have been
# argued and none settled. A reproducer turns that into a five-minute run.
#
# Two rules are built into the shape of this script, and both matter more than
# the load itself:
#
#   1. One subsystem at a time. An all-out CPU+GPU+RAM run that ends in a freeze
#      is consistent with every remaining hypothesis and separates none of them,
#      so --phase takes exactly one value and there is deliberately no --phase
#      all. Run them one after another instead, and note which one bites.
#
#   2. There is a ceiling and a control. Sustained load heats this SoC, and a
#      critical trip powers the machine off -- which looks nothing like a freeze
#      in the photograph but everything like one in a report written afterwards.
#      The run aborts before that. And --phase idle loads nothing at all: if the
#      tablet dies during that too, load was never the variable.
#
# It records nothing about the hardware itself. watch-freeze.sh already does
# that, better, from boot -- this only writes markers saying what was being
# asked of the machine and when, so the two logs line up by wall clock.
#
# Linux only.

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source-path=SCRIPTDIR source=lib-stress-phases.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib-stress-phases.sh"

LOG_DEFAULT=/var/log/chuwi-stress.log
DURATION_DEFAULT=600
SAMPLE_INTERVAL=5
SERVICE=chuwi-freeze-watch.service

# The passive trip on the skin sensor is 61 C and the critical one is 85 C. This
# sits below the point where the thermal core would act on its own, so an abort
# here means "the test stopped", never "the firmware stopped the machine".
MAX_TEMP_DEFAULT=80

# Below this the run is too short to mean anything: the longest gap between a
# boot finishing and a freeze was around 19 minutes, and a one-minute clean run
# would prove nothing while looking like a result.
DURATION_MIN=60

log_path=$LOG_DEFAULT
duration=$DURATION_DEFAULT
max_temp=$MAX_TEMP_DEFAULT
phase=
allow_no_recorder=no

usage() {
  cat <<EOF
Usage: ${0##*/} --phase <cpu|gpu|mem|wifi|wifi-reload|idle> [options]
       ${0##*/} --list

  --phase NAME         Which subsystem to load. One at a time, on purpose.
  --duration SECS      How long to hold it (default: $DURATION_DEFAULT, minimum: $DURATION_MIN)
  --max-temp C         Abort above this (default: $MAX_TEMP_DEFAULT)
  --log PATH           Marker log (default: $LOG_DEFAULT)
  --allow-no-recorder  Run even with watch-freeze.sh not recording. A freeze
                       caught without a record is a wasted freeze; this exists
                       for dry runs, not for real ones.
  --list               What each phase loads and what it needs installed.

Run one phase, then power-cycle if it froze and read both logs:

  sudo ./scripts/watch-freeze.sh --report
  sudo tail -20 $LOG_DEFAULT
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
  --phase)
    phase=${2:?--phase needs a name}
    shift 2
    ;;
  --duration)
    duration=${2:?--duration needs a number}
    shift 2
    ;;
  --max-temp)
    max_temp=${2:?--max-temp needs a number}
    shift 2
    ;;
  --log)
    log_path=${2:?--log needs a path}
    shift 2
    ;;
  --allow-no-recorder)
    allow_no_recorder=yes
    shift
    ;;
  --list)
    list_phases
    exit 0
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

[ -n "$phase" ] || {
  usage >&2
  die "--phase is required; see --list"
}

case $phase in
cpu | gpu | mem | wifi | wifi-reload | idle) ;;
all) die "there is no 'all' phase on purpose -- a combined run separates nothing" ;;
*) die "unknown phase: $phase (see --list)" ;;
esac

case $duration in
'' | *[!0-9]*) die "--duration must be a whole number of seconds, got '$duration'" ;;
esac
[ "$duration" -ge "$DURATION_MIN" ] ||
  die "--duration below ${DURATION_MIN}s proves nothing when it passes"

case $max_temp in
'' | *[!0-9]*) die "--max-temp must be a whole number of degrees, got '$max_temp'" ;;
esac

[ "$(host_os)" = linux ] || die "this loads Linux hardware; run it on the tablet"

# shellcheck source-path=SCRIPTDIR source=lib-freeze-sample.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib-freeze-sample.sh"

sync_cmd() {
  if sync --data "$log_path" 2>/dev/null; then return 0; fi
  sync
}

mark() {
  printf -- '--- %s\n' "$*" >>"$log_path"
  sync_cmd
}

finish() {
  stop_load
  restore_network "$phase"
  mark "stress end $phase $1 after ${2}s $(date '+%Y-%m-%d %H:%M:%S %z')"
  exit "${3:-0}"
}

require_phase_tools "$phase"

if ! systemctl is-active --quiet "$SERVICE"; then
  if [ "$allow_no_recorder" = no ]; then
    die "$SERVICE is not running, so a freeze here would leave no record" \
      "(sudo ./scripts/watch-freeze.sh --install, or pass --allow-no-recorder)"
  fi
  warn "$SERVICE is not running -- a freeze in this run will not be recorded"
fi

[ -d "$(dirname -- "$log_path")" ] || die "no such directory: $(dirname -- "$log_path")"
: >>"$log_path" || die "cannot write to $log_path (try sudo)"

{
  printf -- '--- stress start %s %ss ceiling %sC %s\n' \
    "$phase" "$duration" "$max_temp" "$(date '+%Y-%m-%d %H:%M:%S %z')"
  printf -- '--- boot %s\n' "$(read_or_empty /proc/sys/kernel/random/boot_id)"
  printf -- '--- thermal zones %s\n' "$(thermal_zone_names)"
} >>"$log_path"
sync_cmd

trap 'finish INTERRUPTED "$elapsed" 130' INT TERM HUP

elapsed=0
peak=0
peak_name=none
zones_seen=$(thermal_zone_names)
start_load "$phase" "$duration" "$log_path"
log "phase $phase for ${duration}s, aborting above ${max_temp}C; Ctrl-C to stop"

while [ "$elapsed" -lt "$duration" ]; do
  # A load that ended by itself means the phase stopped loading anything, and
  # every second after that is a clean run being manufactured out of nothing.
  if ! kill -0 "$LOAD_PID" 2>/dev/null; then
    log "the $phase load stopped on its own after ${elapsed}s -- this run proves nothing"
    LOAD_PID=
    finish "LOAD-DIED" "$elapsed" 1
  fi

  read -r hot_name hot <<<"$(hottest_zone)"

  # Zones register as their drivers probe, so the set is not fixed for the run.
  # Without this the temp= columns would silently shift under a reader who had
  # only the header to go by -- and a zone appearing mid-run is itself a lead,
  # since the first implausible reading here showed up during the radio phase.
  zones_now=$(thermal_zone_names)
  if [ "$zones_now" != "$zones_seen" ]; then
    mark "thermal zones $zones_now"
    zones_seen=$zones_now
  fi

  printf 't=%s elapsed=%ss phase=%s temp=%sC hottest=%s@%sC\n' \
    "$(date +%H:%M:%S)" "$elapsed" "$phase" "$(thermal_temps_c)" \
    "$hot_name" "$hot" >>"$log_path"
  sync_cmd

  if [ "$hot" -gt "$peak" ]; then
    peak=$hot
    peak_name=$hot_name
  fi

  if [ "$hot" -gt "$max_temp" ]; then
    log "aborting: $hot_name reads ${hot}C, above the ${max_temp}C ceiling"
    finish "ABORTED-HOT-$hot_name-${hot}C" "$elapsed" 0
  fi

  # Backgrounded and waited on for the same reason as the recorder: bash defers
  # a trap until the running command finishes, and a foreground sleep would swallow
  # Ctrl-C for up to one interval.
  sleep "$SAMPLE_INTERVAL" &
  wait $! || true
  elapsed=$((elapsed + SAMPLE_INTERVAL))
done

stop_load
restore_network "$phase"
mark "stress end $phase SURVIVED after ${elapsed}s peak $peak_name ${peak}C $(date '+%Y-%m-%d %H:%M:%S %z')"
log "survived ${elapsed}s of $phase, peak ${peak}C on $peak_name"
