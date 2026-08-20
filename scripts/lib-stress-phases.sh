#!/usr/bin/env bash
#
# What each phase of stress-freeze.sh actually does: which tools it needs, what
# it starts, and what it has to put back afterwards.
#
# Split out because the phases are where the domain knowledge lives -- what the
# tablet does at boot, what holds the radio module, what a failed load looks
# like -- while stress-freeze.sh itself is a CLI, a sampling loop and a report.
# They change for different reasons and at different times.
#
# Sourced, never run. Every function takes what it needs as an argument rather
# than reading the caller's variables -- the two files then have one direction
# of dependency instead of a shared namespace, and shellcheck can see it.

# Owned by this file, set by the functions below and read by the caller.
LOAD_PID=
GPU_CMD=

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
         the run. Two commands, and the first is not
         optional: a backgrounded sudo whose timestamp has
         expired reads the password from the tty, takes
         SIGTTIN and stops before exec -- no run, no log, no
         error anywhere.
           sudo -v
           sudo setsid ./scripts/stress-freeze.sh \
             --phase wifi-reload </dev/null &>/tmp/reload.log &
                                                              needs: modprobe
  idle   nothing. The control. If the tablet freezes during
         this, none of the phases above prove anything.       needs: nothing
EOF
}

# wifi-reload spends part of every cycle with the module out and NetworkManager
# stopped. Whatever ends the run -- the timer, Ctrl-C, the ceiling, the load
# dying mid-cycle -- must not leave the tablet in that state: it is in another
# city, and an unreachable machine costs somebody a trip rather than a reboot.
#
# Best-effort by design. This runs on the way out, so a failure here must be
# said out loud but must not replace the result the run was there to produce.
restore_network() {
  local phase=$1
  [ "$phase" = wifi-reload ] || return 0
  modprobe brcmfmac 2>/dev/null ||
    warn "could not reload brcmfmac -- the tablet may have no radio"
  systemctl start NetworkManager.service 2>/dev/null ||
    warn "could not start NetworkManager -- the tablet may be unreachable"
}

require_phase_tools() {
  local phase=$1
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
    GPU_CMD=$(first_cmd glmark2 glxgears) ||
      die "neither glmark2 nor glxgears found (sudo apt install glmark2)"
    [ -n "${DISPLAY:-}" ] ||
      die "no DISPLAY -- the GPU phase needs an X session (try DISPLAY=:0, or run it on the tablet)"
    ;;
  esac
}

# One cycle of the radio stack, repeated: the boot sequence on demand.
#
# Stopping NetworkManager alone was not enough on the reference tablet --
# brcmfmac was still "in use" a second later, and the run died in five seconds.
# So this tears down further (the supplicant that may outlive its unit, and the
# interface itself) and, when the removal still fails, records who is holding
# the module rather than leaving that to another round trip through a person in
# another city: holders/ names any module with a reference, refcnt counts the
# anonymous ones, and the process list catches a daemon nobody stopped.
#
# Exported and run under bash -c by name, so the body is real code shellcheck
# can lint instead of a quoted string it will not look inside.
wifi_reload_cycle() {
  local w iface
  while :; do
    systemctl stop NetworkManager.service || exit 1
    # Tolerated: NetworkManager may run the supplicant as a dbus-activated unit
    # that is legitimately not there to stop, and pkill finds nothing to kill.
    systemctl stop wpa_supplicant.service 2>/dev/null || true
    pkill -x wpa_supplicant 2>/dev/null || true
    for w in /sys/class/net/*/wireless; do
      [ -e "$w" ] || continue
      iface=$(dirname "$w")
      iface=${iface##*/}
      ip link set "$iface" down 2>/dev/null || true
    done
    sleep 1

    if ! modprobe -r brcmfmac; then
      local h holders=
      for h in /sys/module/brcmfmac/holders/*; do
        [ -e "$h" ] || continue
        holders="${holders:+$holders }${h##*/}"
      done
      {
        printf -- '--- wifi-reload: brcmfmac would not unload\n'
        printf -- '--- refcnt %s\n' "$(cat /sys/module/brcmfmac/refcnt 2>/dev/null)"
        printf -- '--- module holders [%s]\n' "$holders"
        lsmod | grep -E '^(brcmfmac|brcmutil|cfg80211|btsdio|hci_)' |
          sed 's/^/--- lsmod /'
        # No match is a real answer here, not a failure -- record the empty set.
        pgrep -a -f 'wpa_supplicant|NetworkManager|hostapd|connman|iwd' |
          sed 's/^/--- proc /' || true
      } >>"$MARKER" 2>&1
      sync
      exit 1
    fi

    sleep 2
    modprobe brcmfmac || exit 1
    systemctl start NetworkManager.service || exit 1
    sleep 15
  done
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
  local phase=$1 duration=$2 log_path=$3
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
    timeout "${deadman}s" bash -c "while $GPU_CMD >/dev/null 2>&1; do :; done; exit 1" &
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
    # A function rather than a quoted string, so shellcheck actually lints it.
    export MARKER=$log_path
    export -f wifi_reload_cycle
    timeout "${deadman}s" bash -c wifi_reload_cycle &
    ;;
  idle)
    # The control loads nothing. Deliberately still a process, so every phase
    # goes down the same path and a bug in the harness cannot hide here.
    timeout "${deadman}s" bash -c 'while :; do sleep 60; done' &
    ;;
  esac
  LOAD_PID=$!
}

# Ends the load started above, gently first. stress-ng reaps its own workers on
# SIGTERM; the grace period is so a phase that ends normally does not leave
# orphans, and the KILL is for the ones that ignore it.
stop_load() {
  [ -n "$LOAD_PID" ] || return 0
  kill "$LOAD_PID" 2>/dev/null || true
  local waited=0
  while kill -0 "$LOAD_PID" 2>/dev/null && [ "$waited" -lt 10 ]; do
    sleep 1
    waited=$((waited + 1))
  done
  kill -KILL "$LOAD_PID" 2>/dev/null || true
  wait "$LOAD_PID" 2>/dev/null || true
  LOAD_PID=
}
