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

list_phases() {
  cat <<'EOF'
  cpu    every core, all stress-ng CPU methods in turn.       needs: stress-ng
  mem    75% of RAM written and read back with --verify.      needs: stress-ng
         Not a substitute for memtest86+, which tests the
         memory the kernel is sitting in and this cannot.
  gpu    glmark2 on a loop, or glxgears. Needs an X session,
         so run it from the tablet or export DISPLAY=:0.      needs: glmark2
  wifi   a scan every few seconds, which is what
         NetworkManager does in the background. Ten minutes
         of this did not freeze the reference tablet, which
         is what narrowed the lead to the phase below.        needs: nmcli
  wifi-reload
         NetworkManager stopped, brcmfmac unloaded and
         loaded, NetworkManager started again, on a loop --
         the radio coming up from cold with the stack on top
         of it. Every boot freeze on record lands inside that
         window and none on steady radio use, so this
         reproduces the suspect event rather than its
         aftermath. Needs root, and fails loudly rather than
         quietly cycling nothing.
         It drops the network every cycle, so over SSH on
         wireless run it detached or the lost session ends
         the run:
           sudo setsid ./scripts/stress-freeze.sh \
             --phase wifi-reload </dev/null &>/tmp/reload.log &
                                                              needs: modprobe
  idle   nothing. The control. If the tablet freezes during
         this, none of the phases above prove anything.       needs: nothing
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

load_pid=

stop_load() {
  [ -n "$load_pid" ] || return 0
  kill "$load_pid" 2>/dev/null || true
  # stress-ng reaps its own workers on SIGTERM; give it a moment before the
  # blunt instrument, so a phase that ends normally does not leave orphans.
  local waited=0
  while kill -0 "$load_pid" 2>/dev/null && [ "$waited" -lt 10 ]; do
    sleep 1
    waited=$((waited + 1))
  done
  kill -KILL "$load_pid" 2>/dev/null || true
  wait "$load_pid" 2>/dev/null || true
  load_pid=
}

finish() {
  stop_load
  mark "stress end $phase $1 after ${2}s $(date '+%Y-%m-%d %H:%M:%S %z')"
  exit "${3:-0}"
}

require_phase_tools() {
  require_cmd timeout
  case $phase in
  cpu | mem) require_cmd stress-ng ;;
  wifi) require_cmd nmcli ;;
  wifi-reload)
    require_cmd modprobe systemctl
    [ "$(id -u)" -eq 0 ] || die "--phase wifi-reload needs root to cycle the stack"
    # Worth saying out loud rather than discovering: this phase takes the
    # network down every cycle. Over SSH on the wireless interface that means
    # the session dies with it, and the SIGHUP would end the run early -- see
    # the --list note about running it detached.
    warn "this phase stops NetworkManager repeatedly; the network drops every cycle"
    ;;
  gpu)
    gpu_cmd=$(first_cmd glmark2 glxgears) ||
      die "neither glmark2 nor glxgears found (sudo apt install glmark2)"
    [ -n "${DISPLAY:-}" ] ||
      die "no DISPLAY -- the GPU phase needs an X session (try DISPLAY=:0, or run it on the tablet)"
    ;;
  esac
}

# No phase sets its own duration and no phase swallows a failure. Both rules are
# here because of one bad run: the GPU phase looped `glmark2 || sleep 1`, glmark2
# could not reach the display, and the loop spun on the error for ten minutes and
# reported "survived". The arithmetic gave it away afterwards -- the phase peaked
# 4 C above the idle control, on a machine where the screensaver alone costs 15 C
# -- but a load test that passes without loading anything is worse than no test.
#
# So: every load runs until this script kills it, and a load that stops on its
# own is an error the sampling loop reports. stress-ng's --timeout is gone for
# the same reason, since it would otherwise exit near the end and trip the check.
start_load() {
  # A dead man's switch, well past the run so it can never trip the liveness
  # check above. It exists for the case this script does not get to clean up --
  # SIGKILL, or the freeze we are hunting -- which would otherwise leave every
  # core pinned by an orphaned load until someone noticed.
  local deadman=$((duration + 300))

  case $phase in
  cpu)
    timeout "${deadman}s" stress-ng --cpu "$(nproc)" --cpu-method all \
      >/dev/null 2>&1 &
    ;;
  mem)
    timeout "${deadman}s" stress-ng --vm 2 --vm-bytes 75% --vm-method all \
      --verify >/dev/null 2>&1 &
    ;;
  gpu)
    # Restarts on a clean exit -- a benchmark run finishing is normal -- and
    # exits non-zero the moment one fails, which takes the whole phase down.
    timeout "${deadman}s" bash -c "while $gpu_cmd >/dev/null 2>&1; do :; done; exit 1" &
    ;;
  wifi)
    # A rescan every few seconds is what NetworkManager already does between
    # freezes; this only removes the waiting. A rescan can legitimately fail
    # while one is already in flight, so this one does tolerate a failure.
    timeout "${deadman}s" bash -c \
      'while :; do nmcli device wifi rescan >/dev/null 2>&1 || true; sleep 5; done' &
    ;;
  wifi-reload)
    # The event every boot freeze on record sits on, repeated on demand: the
    # radio coming up from cold, firmware and NVRAM and all. Ten minutes of
    # scanning on an already-associated radio changed nothing, which is what
    # pointed here.
    #
    # The whole stack, not just the module. A first attempt cycled brcmfmac
    # alone and died on "Module brcmfmac is in use" -- NetworkManager holds it.
    # Stopping NM first is what makes the removal possible, and it also makes
    # this a far closer copy of the boot sequence: cold module, then NM and
    # wpa_supplicant starting on top of it, then association. The photographed
    # boot freezes land inside exactly that window, not before it.
    #
    # exit 1 rather than || true on everything that must work: a cycle that
    # quietly does nothing would report a clean run, which is the same false
    # pass the GPU phase already produced once. The one tolerated failure is
    # stopping wpa_supplicant, which NetworkManager may run as a dbus-activated
    # unit that is legitimately not there to stop.
    timeout "${deadman}s" bash -c '
      while :; do
        systemctl stop NetworkManager.service || exit 1
        systemctl stop wpa_supplicant.service 2>/dev/null || true
        sleep 1
        modprobe -r brcmfmac || exit 1
        sleep 2
        modprobe brcmfmac || exit 1
        systemctl start NetworkManager.service || exit 1
        sleep 15
      done' &
    ;;
  idle)
    # The control loads nothing. Deliberately still a process, so every phase
    # goes down the same path and a bug in the harness cannot hide here.
    timeout "${deadman}s" bash -c 'while :; do sleep 60; done' &
    ;;
  esac
  load_pid=$!
}

gpu_cmd=
require_phase_tools

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
start_load
log "phase $phase for ${duration}s, aborting above ${max_temp}C; Ctrl-C to stop"

while [ "$elapsed" -lt "$duration" ]; do
  # A load that ended by itself means the phase stopped loading anything, and
  # every second after that is a clean run being manufactured out of nothing.
  if ! kill -0 "$load_pid" 2>/dev/null; then
    log "the $phase load stopped on its own after ${elapsed}s -- this run proves nothing"
    load_pid=
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
mark "stress end $phase SURVIVED after ${elapsed}s peak $peak_name ${peak}C $(date '+%Y-%m-%d %H:%M:%S %z')"
log "survived ${elapsed}s of $phase, peak ${peak}C on $peak_name"
