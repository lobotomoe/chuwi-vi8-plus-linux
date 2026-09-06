#!/usr/bin/env bash
#
# What the touchscreen interrupt storm costs, measured by taking it away.
#
# Three windows of equal length: driver bound, driver unbound, driver bound
# again. The unbound window sits between two bound ones on purpose -- this
# tablet is usually running something (a browser, a kiosk) whose own load
# drifts, and bracketing lets that drift show up as a difference between the two
# bound windows rather than as a result. A real effect puts the middle window
# outside both brackets; drift puts it between them.
#
# The touchscreen is dead for the middle window only. The driver is rebound on
# every exit path, including Ctrl-C and a failure part-way through.
#
# Per-process CPU is tracked alongside the interrupt rates because the storm's
# cost is not where it looks. See docs/01-hardware.md, "The touchscreen holds its
# interrupt line asserted".

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

DRIVER=/sys/bus/i2c/drivers/chipone_icn8505
DEVICE=i2c-CHPN0001:00
CPUIDLE=/sys/devices/system/cpu/cpu0/cpuidle
WINDOW=${WINDOW:-120}
SETTLE=${SETTLE:-20}
SAMPLE=5

[ "$(id -u)" -eq 0 ] || die "needs root: sudo $0"
[ -d "$DRIVER" ] || die "chipone_icn8505 is not loaded"
[ -e "$DRIVER/$DEVICE" ] || die "$DEVICE is not bound; nothing to take away"

hz=$(getconf CLK_TCK)

rebind() {
  if [ -e "$DRIVER/$DEVICE" ]; then
    return 0
  fi
  if printf '%s' "$DEVICE" >"$DRIVER/bind" 2>/dev/null; then
    log "-- touchscreen rebound"
  else
    warn "could not rebind $DEVICE -- touch is dead until you reboot"
  fi
}
trap rebind EXIT INT TERM

# The IRQ numbers are not stable across boots; both lines are found by the name
# the kernel prints for them, not by a number written down once.
irq_number() {
  awk -v pat="$1" '$0 ~ pat { sub(":", "", $1); print $1; exit }' /proc/interrupts
}

# Total across all CPUs. Prints 0 when the line is gone, which is what the
# unbound window needs rather than an error.
irq_total() {
  awk -v n="$1:" '
    $1 == n { s = 0; for (i = 2; i <= NF; i++) if ($i ~ /^[0-9]+$/) s += $i; print s; found = 1 }
    END { if (!found) print 0 }
  ' /proc/interrupts
}

# utime + stime in clock ticks. A pid that has gone away reads as 0 rather than
# aborting the run: the IRQ thread legitimately disappears when the driver is
# unbound, and comes back with a different pid on rebind.
proc_ticks() {
  local pid=$1
  [ -n "$pid" ] && [ -r "/proc/$pid/stat" ] || {
    printf '0'
    return 0
  }
  awk '{ n = index($0, ") "); split(substr($0, n + 2), f, " "); print f[12] + f[13] }' \
    "/proc/$pid/stat" 2>/dev/null || printf '0'
}

# comm is truncated to 15 characters, so this matches a prefix, not the full
# "irq/156-CHPN0001:00".
irq_thread_pid() {
  ps -eo pid=,comm= | awk '$2 ~ /^irq\/.*CHPN/ { print $1; exit }'
}

cpu_jiffies() { # busy and total, from the aggregate line
  awk '/^cpu /{ t = 0; for (i = 2; i <= NF; i++) t += $i; print t - $5, t; exit }' /proc/stat
}

# The trailing newline is load-bearing: `read` returns non-zero at EOF without
# one, and errexit would take the run down between two halves of a measurement.
cstate() { # $1 = state index; prints "time usage"
  printf '%s %s\n' "$(cat "$CPUIDLE/state$1/time")" "$(cat "$CPUIDLE/state$1/usage")"
}

# PNIT is the hottest real zone on this tablet and the one 51-freezes.md tracks.
# Never address it as thermal_zone3: the numbering is not fixed across boots, and
# INT3400 reports a constant 20 C that would pass for a cool die without ever
# looking wrong.
pnit_millicelsius() {
  local zone
  for zone in /sys/class/thermal/thermal_zone*; do
    [ -r "$zone/type" ] && [ -r "$zone/temp" ] || continue
    [ "$(cat "$zone/type")" = PNIT ] || continue
    cat "$zone/temp"
    return 0
  done
  printf '0'
}

ts_irq=$(irq_number CHPN0001)
i2c_irq=$(irq_number 'i2c_designware.4|808622C1:04')
xorg_pid=$(pgrep -x Xorg | head -1 || true)
browser_pid=$(pgrep -x firefox | head -1 || true)

[ -n "$ts_irq" ] || die "no CHPN0001 line in /proc/interrupts"

measure() {
  local label=$1 irq_pid t0 t1 dt
  local a0 a1 b0 b1 busy0 busy1 tot0 tot1
  local c1t0 c1u0 c1t1 c1u1 c6t0 c6u0 c6t1 c6u1
  local x0 x1 f0 f1 k0 k1 pnit_sum=0 pnit_n=0 deadline

  irq_pid=$(irq_thread_pid)
  t0=$(awk '{print int($1)}' /proc/uptime)
  a0=$(irq_total "$ts_irq")
  b0=$(irq_total "$i2c_irq")
  read -r busy0 tot0 < <(cpu_jiffies)
  read -r c1t0 c1u0 < <(cstate 1)
  read -r c6t0 c6u0 < <(cstate 2)
  x0=$(proc_ticks "$xorg_pid")
  f0=$(proc_ticks "$browser_pid")
  k0=$(proc_ticks "$irq_pid")

  deadline=$(($(date +%s) + WINDOW))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    pnit_sum=$((pnit_sum + $(pnit_millicelsius)))
    pnit_n=$((pnit_n + 1))
    sleep "$SAMPLE"
  done

  t1=$(awk '{print int($1)}' /proc/uptime)
  a1=$(irq_total "$ts_irq")
  b1=$(irq_total "$i2c_irq")
  read -r busy1 tot1 < <(cpu_jiffies)
  read -r c1t1 c1u1 < <(cstate 1)
  read -r c6t1 c6u1 < <(cstate 2)
  x1=$(proc_ticks "$xorg_pid")
  f1=$(proc_ticks "$browser_pid")
  k1=$(proc_ticks "$irq_pid")
  dt=$((t1 - t0))

  awk -v l="$label" -v dt="$dt" -v hz="$hz" \
    -v a="$((a1 - a0))" -v b="$((b1 - b0))" \
    -v db="$((busy1 - busy0))" -v dtot="$((tot1 - tot0))" \
    -v c1t="$((c1t1 - c1t0))" -v c1u="$((c1u1 - c1u0))" \
    -v c6t="$((c6t1 - c6t0))" -v c6u="$((c6u1 - c6u0))" \
    -v dx="$((x1 - x0))" -v df="$((f1 - f0))" -v dk="$((k1 - k0))" \
    -v ps="$pnit_sum" -v pn="$pnit_n" '
  BEGIN {
    printf "%-16s  %ds\n", l, dt
    printf "    touchscreen irq  %9d  %8.1f/s\n", a, a / dt
    printf "    i2c ctrl irq     %9d  %8.1f/s\n", b, b / dt
    printf "    cpu busy          %7.1f%%  all cores\n", 100 * db / dtot
    printf "    irq thread        %7.1f%%  of one core\n", 100 * dk / (dt * hz)
    printf "    Xorg              %7.1f%%  of one core\n", 100 * dx / (dt * hz)
    printf "    browser           %7.1f%%  of one core\n", 100 * df / (dt * hz)
    printf "    C1   %6.1f%% of wall, %9d wakeups, mean %6.0f us\n", c1t / (dt * 10000), c1u, (c1u ? c1t / c1u : 0)
    printf "    C6N  %6.1f%% of wall, %9d wakeups, mean %6.0f us\n", c6t / (dt * 10000), c6u, (c6u ? c6t / c6u : 0)
    printf "    PNIT  %6.1f C mean over %d samples\n", (pn ? ps / pn / 1000 : 0), pn
  }'
  echo
}

log "window ${WINDOW}s per phase, three phases, plus ${SETTLE}s settling between."
log "the touchscreen is dead for phase 2 only."
log "tracking: touchscreen irq ${ts_irq}, i2c irq ${i2c_irq:-none}, Xorg ${xorg_pid:-none}, browser ${browser_pid:-none}"
echo

measure "1 bound"

printf '%s' "$DEVICE" >"$DRIVER/unbind" || die "unbind failed"
log "-- unbound, settling ${SETTLE}s"
sleep "$SETTLE"
measure "2 unbound"

rebind
log "-- rebound, settling ${SETTLE}s"
sleep "$SETTLE"
measure "3 bound again"

if grep -q CHPN0001 /proc/interrupts && [ -e "$DRIVER/$DEVICE" ]; then
  log "touchscreen is back: irq registered, driver bound"
else
  warn "touchscreen did not come back cleanly -- check it, or reboot"
fi
