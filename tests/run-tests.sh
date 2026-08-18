#!/usr/bin/env bash
#
# Test suite for the scripts in this repository.
#
#   ./tests/run-tests.sh          logic, argument handling and artifact checks
#   sudo ./tests/run-tests.sh     the above, plus an end-to-end make-media.sh run
#
# The end-to-end test builds a synthetic ISO, attaches a virtual disk (a disk
# image on macOS, a loop device on Linux) and runs make-media.sh against it, so it
# exercises the partition/format/copy path without needing a real USB stick and
# without any risk to a real device. It is skipped when not run as root.

set -o errexit
set -o nounset
set -o pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPTS=$REPO_ROOT/scripts

passed=0
failed=0
skipped=0

pass() {
  passed=$((passed + 1))
  printf '  ok    %s\n' "$1"
}
fail() {
  failed=$((failed + 1))
  printf '  FAIL  %s\n' "$1"
  [ $# -lt 2 ] || printf '        %s\n' "$2"
}
skip() {
  skipped=$((skipped + 1))
  printf '  skip  %s (%s)\n' "$1" "$2"
}
group() { printf '\n%s\n' "$1"; }

# Runs a command and compares its exit status and combined output.
#   expect_fail <name> <expected status> <substring of output> -- cmd...
expect_fail() {
  local name=$1 want_status=$2 want_text=$3 out status
  shift 4 # name, status, text, and the literal --
  set +o errexit
  out=$("$@" 2>&1)
  status=$?
  set -o errexit
  if [ "$status" -ne "$want_status" ]; then
    fail "$name" "exited $status, expected $want_status: $out"
    return
  fi
  case $out in
  *"$want_text"*) pass "$name" ;;
  *) fail "$name" "output did not contain '$want_text': $out" ;;
  esac
}

# Runs a command that must succeed and checks its output.
#   expect_ok <name> <substring of output> -- cmd...
expect_ok() {
  local name=$1 want_text=$2 out status
  shift 3 # name, text, and the literal --
  set +o errexit
  out=$("$@" 2>&1)
  status=$?
  set -o errexit
  if [ "$status" -ne 0 ]; then
    fail "$name" "exited $status: $out"
    return
  fi
  case $out in
  *"$want_text"*) pass "$name" ;;
  *) fail "$name" "output did not contain '$want_text': $out" ;;
  esac
}

# Checks that text already captured contains a substring.
#   expect_contains <name> <substring> <haystack>
expect_contains() {
  local name=$1 want=$2 haystack=$3
  case $haystack in
  *"$want"*) pass "$name" ;;
  *) fail "$name" "did not contain '$want' in: $haystack" ;;
  esac
}

# ---------------------------------------------------------------------------
group "Static analysis"

if command -v shellcheck >/dev/null 2>&1; then
  if out=$(shellcheck "$SCRIPTS"/*.sh "$REPO_ROOT"/tests/*.sh 2>&1); then
    pass "shellcheck is clean"
  else
    fail "shellcheck is clean" "$out"
  fi
else
  skip "shellcheck is clean" "shellcheck not installed"
fi

for f in "$SCRIPTS"/*.sh "$REPO_ROOT"/tests/*.sh; do
  if bash -n "$f" 2>/dev/null; then
    pass "parses: ${f#"$REPO_ROOT"/}"
  else
    fail "parses: ${f#"$REPO_ROOT"/}"
  fi
done

# The lib*.sh files are sourced, never executed; a +x bit invites running one
# directly, which for a library of function definitions does nothing at all.
for f in "$SCRIPTS"/lib*.sh; do
  name="${f#"$REPO_ROOT"/}"
  if [ -x "$f" ]; then
    fail "not executable: $name" "it is a sourced library, mode should be 644"
  else
    pass "not executable: $name"
  fi
done

# ---------------------------------------------------------------------------
group "Shipped artifact"

if (cd "$REPO_ROOT/artifacts" && shasum -a 256 -c SHA256SUMS >/dev/null 2>&1) ||
  (cd "$REPO_ROOT/artifacts" && sha256sum -c SHA256SUMS >/dev/null 2>&1); then
  pass "bootia32.efi matches artifacts/SHA256SUMS"
else
  fail "bootia32.efi matches artifacts/SHA256SUMS"
fi

# A PE executable, not an ELF or a stray text file. GRUB EFI images start "MZ".
if [ "$(head -c 2 "$REPO_ROOT/artifacts/bootia32.efi")" = "MZ" ]; then
  pass "bootia32.efi is a PE image"
else
  fail "bootia32.efi is a PE image" "does not start with the MZ magic"
fi

# ---------------------------------------------------------------------------
group "Usage and argument handling"

for s in make-media.sh backup-emmc.sh restore-emmc.sh postinstall-grub-ia32.sh \
  postinstall-tune.sh check-iso-ia32.sh fetch-bootia32.sh fetch-offline-payload.sh \
  collect-hw-report.sh watch-freeze.sh stress-freeze.sh; do
  set +o errexit
  out=$("$SCRIPTS/$s" --help 2>&1)
  status=$?
  set -o errexit
  if [ "$status" -eq 0 ] && [ -n "$out" ]; then
    pass "$s --help exits 0"
  else
    fail "$s --help exits 0" "exited $status"
  fi
done

# Missing required arguments must be exit 2 (usage), not a generic failure.
expect_fail "make-media.sh with no arguments prints usage" 2 "Usage:" -- \
  "$SCRIPTS/make-media.sh"
expect_fail "backup-emmc.sh with no arguments prints usage" 2 "Usage:" -- \
  "$SCRIPTS/backup-emmc.sh"
expect_fail "restore-emmc.sh with no arguments prints usage" 2 "Usage:" -- \
  "$SCRIPTS/restore-emmc.sh"

expect_fail "make-media.sh rejects an unknown argument" 1 "unknown argument" -- \
  "$SCRIPTS/make-media.sh" --wat

expect_fail "watch-freeze.sh rejects a non-numeric interval" 1 "whole number of seconds" -- \
  "$SCRIPTS/watch-freeze.sh" --interval abc
expect_fail "watch-freeze.sh rejects an interval below the floor" 1 "costs more than it measures" -- \
  "$SCRIPTS/watch-freeze.sh" --interval 0
expect_fail "watch-freeze.sh reports a missing log rather than an empty one" 1 "no log at" -- \
  "$SCRIPTS/watch-freeze.sh" --report --log /nonexistent/freeze.log
expect_fail "make-media.sh rejects a missing ISO" 1 "no such ISO" -- \
  "$SCRIPTS/make-media.sh" --iso /nonexistent.iso --device /dev/null

# The point of the load test is that one phase runs at a time; a combined run
# would end in a freeze consistent with every hypothesis and decide none. That
# is a design decision, so it gets a test rather than a comment alone.
expect_fail "stress-freeze.sh refuses a combined run" 1 "separates nothing" -- \
  "$SCRIPTS/stress-freeze.sh" --phase all
expect_fail "stress-freeze.sh rejects an unknown phase" 1 "unknown phase: disk" -- \
  "$SCRIPTS/stress-freeze.sh" --phase disk
expect_fail "stress-freeze.sh requires a phase" 1 "--phase is required" -- \
  "$SCRIPTS/stress-freeze.sh"
expect_fail "stress-freeze.sh rejects a non-numeric duration" 1 "whole number of seconds" -- \
  "$SCRIPTS/stress-freeze.sh" --phase cpu --duration abc
expect_fail "stress-freeze.sh rejects a run too short to mean anything" 1 "proves nothing when it passes" -- \
  "$SCRIPTS/stress-freeze.sh" --phase cpu --duration 30
expect_fail "stress-freeze.sh rejects a non-numeric ceiling" 1 "whole number of degrees" -- \
  "$SCRIPTS/stress-freeze.sh" --phase cpu --max-temp hot
expect_ok "stress-freeze.sh --list names the control phase" "idle   nothing. The control." -- \
  "$SCRIPTS/stress-freeze.sh" --list

# The GPU phase once looped `glmark2 || sleep 1` with glmark2 unable to reach the
# display, spun on the error for ten minutes and reported "survived". These two
# pin the assumptions the fix rests on, since a load test that passes without
# loading anything is worse than no load test at all.
loop_status=$(
  bash -c 'while false; do :; done; exit 1' >/dev/null 2>&1
  printf 'status=%s' $?
)
expect_contains "a load command that fails takes the phase down with it" \
  "status=1" "$loop_status"

liveness=$(bash -c 'bash -c "exit 3" & p=$!; sleep 1
  kill -0 "$p" 2>/dev/null && printf alive || printf gone' 2>/dev/null)
expect_contains "an exited load is detectable, not a zombie that reads as alive" \
  "gone" "$liveness"

# A whole SHA256SUMS line pasted into --sha256 must be named as such, not
# reported as a checksum mismatch.
expect_fail "make-media.sh rejects a pasted SHA256SUMS line" 1 "only the 64-character digest" -- \
  "$SCRIPTS/make-media.sh" --iso "$REPO_ROOT/artifacts/bootia32.efi" --device /dev/null \
  --sha256 "d21e473e4f81716aae013720024755cd5ff89c9674ee5326fd3c4c6f7a84f0e7  bootia32.efi"

expect_fail "make-media.sh rejects a truncated digest" 1 "64 hex characters" -- \
  "$SCRIPTS/make-media.sh" --iso "$REPO_ROOT/artifacts/bootia32.efi" --device /dev/null \
  --sha256 d21e473e

expect_fail "make-media.sh rejects an over-long FAT32 label" 1 "11 characters at most" -- \
  "$SCRIPTS/make-media.sh" --iso "$REPO_ROOT/artifacts/bootia32.efi" --device /dev/null \
  --label THIS_LABEL_IS_TOO_LONG

# ---------------------------------------------------------------------------
group "watch-freeze.sh sampling"

# Every sysfs root in lib-freeze-sample.sh is overridable so the sampler can be
# run against a tree shaped like the tablet, from a machine that is not it.
fake=$(mktemp -d)
mkdir -p "$fake"/thermal "$fake"/psy/axp288_fuel_gauge "$fake"/psy/axp288_charger \
  "$fake"/cpuidle/state0 "$fake"/cpuidle/state1 "$fake"/cpufreq "$fake"/drm

# The reference unit's zones and their real readings. INT3400 is a DPTF policy
# device with no sensor behind it and always reports 20 C, which is why the
# sampler records every zone instead of the maximum.
zones=(acpitz:43600 "INT3400 Thermal:20000" STR0:43650 PNIT:59000
  soc_dts0:53000 soc_dts1:50000)
zone_index=0
for z in "${zones[@]}"; do
  mkdir -p "$fake/thermal/thermal_zone$zone_index"
  printf '%s' "${z%:*}" >"$fake/thermal/thermal_zone$zone_index/type"
  printf '%s' "${z##*:}" >"$fake/thermal/thermal_zone$zone_index/temp"
  zone_index=$((zone_index + 1))
done

printf 'Charging' >"$fake/psy/axp288_fuel_gauge/status"
printf '99' >"$fake/psy/axp288_fuel_gauge/capacity"
printf '592000' >"$fake/psy/axp288_fuel_gauge/current_now"
printf '4224000' >"$fake/psy/axp288_fuel_gauge/voltage_now"
printf '1' >"$fake/psy/axp288_charger/online"
printf '2000000' >"$fake/psy/axp288_charger/input_current_limit"
printf 'C1' >"$fake/cpuidle/state0/name"
printf 'C7S' >"$fake/cpuidle/state1/name"
printf '10' >"$fake/cpuidle/state0/usage"
printf '100' >"$fake/cpuidle/state1/usage"
printf '1600000' >"$fake/cpufreq/scaling_cur_freq"
printf 'cpu 100 0 100 800 0 0 0 0 0 0\n' >"$fake/stat"

# Two samples: the first has nothing to subtract from, the second does. Between
# them the counters advance by 100 busy jiffies out of 200 total.
sample_out=$(
  PSY="$fake/psy" CPUIDLE="$fake/cpuidle" THERMAL="$fake/thermal" DRM="$fake/drm" \
    CPUFREQ="$fake/cpufreq" PROC_STAT="$fake/stat" \
    bash -c '
      source "$1"
      sample_line
      printf "cpu 150 0 150 900 0 0 0 0 0 0\n" >"$PROC_STAT"
      printf "200" >"$CPUIDLE/state1/usage"
      sample_line
    ' _ "$SCRIPTS/lib-freeze-sample.sh"
)

expect_contains "every thermal zone is recorded, not the maximum" \
  "temp=43/20/43/59/53/50C" "$sample_out"
expect_contains "the zone names are announced before the first sample" \
  "--- thermal zones acpitz,INT3400 Thermal,STR0,PNIT,soc_dts0,soc_dts1" "$sample_out"
expect_contains "the first sample has no deltas to report" "busy=first%" "$sample_out"
expect_contains "CPU utilisation comes from the jiffy counters" "busy=50%" "$sample_out"
expect_contains "idle entries are reported as per-interval deltas" "idle=0/100" "$sample_out"
expect_contains "the charger and gauge are read straight through" \
  "bat=99% bst=Charging bcur=592mA bv=4224mV chg=1 ilim=2000mA" "$sample_out"
expect_contains "a GPU with no frequency file reports unknown, not zero" \
  "gpu=?MHz" "$sample_out"

# The load test's ceiling names the zone it tripped on, because the first abort
# in the field read an implausible 100 C and the message did not say from where.
hot_out=$(
  THERMAL="$fake/thermal" bash -c 'source "$1"; hottest_zone' _ \
    "$SCRIPTS/lib-freeze-sample.sh"
)
expect_contains "the ceiling names the hottest zone, not just its reading" \
  "PNIT 59" "$hot_out"

# A zone reporting garbage must be attributable, which is the whole point of
# carrying the name: 100 C on acpitz and 100 C on the die mean different things.
mkdir -p "$fake/thermal/thermal_zone9"
printf 'bogus_zone' >"$fake/thermal/thermal_zone9/type"
printf '100000' >"$fake/thermal/thermal_zone9/temp"
hot_out=$(
  THERMAL="$fake/thermal" bash -c 'source "$1"; hottest_zone' _ \
    "$SCRIPTS/lib-freeze-sample.sh"
)
expect_contains "a zone appearing later can be named as the one that tripped" \
  "bogus_zone 100" "$hot_out"
rm -rf "$fake/thermal/thermal_zone9"

# The names line must not be repeated while the set of zones is unchanged --
# it is a marker for a set that grew, not decoration on every sample.
zone_lines=$(printf '%s\n' "$sample_out" | grep -c -- '--- thermal zones')
if [ "$zone_lines" -eq 1 ]; then
  pass "the zone names are announced once, not per sample"
else
  fail "the zone names are announced once, not per sample" \
    "found $zone_lines announcements, expected 1"
fi

# A zone that registers late must re-announce, or the columns silently shift
# under a header that no longer describes them. This is what boot looks like:
# only the policy device exists at first.
late_out=$(
  PSY="$fake/psy" CPUIDLE="$fake/cpuidle" THERMAL="$fake/thermal-late" DRM="$fake/drm" \
    CPUFREQ="$fake/cpufreq" PROC_STAT="$fake/stat" \
    bash -c '
      mkdir -p "$THERMAL/thermal_zone0"
      printf "INT3400 Thermal" >"$THERMAL/thermal_zone0/type"
      printf "20000" >"$THERMAL/thermal_zone0/temp"
      source "$1"
      sample_line
      mkdir -p "$THERMAL/thermal_zone1"
      printf "soc_dts0" >"$THERMAL/thermal_zone1/type"
      printf "53000" >"$THERMAL/thermal_zone1/temp"
      sample_line
    ' _ "$SCRIPTS/lib-freeze-sample.sh"
)
expect_contains "a zone that appears later is announced when it does" \
  "--- thermal zones INT3400 Thermal,soc_dts0" "$late_out"
expect_contains "and its reading joins the sample line" "temp=20/53C" "$late_out"

rm -rf "$fake"

# ---------------------------------------------------------------------------
group "watch-freeze.sh --report classification"

# Three different things end a session and only one of them is a freeze. Reading
# a systemctl restart as a crash sent an evening down the wrong hypothesis, so
# each verdict is pinned here.
freeze_log=$(mktemp)
cat >"$freeze_log" <<'EOF'
--- session start 2026-08-18 10:00:00 +0400
--- boot aaaa-1111
--- kernel 7.0.0-14-generic
t=10:00:01 up=16 temp=55C
--- session start 2026-08-18 10:00:30 +0400
--- boot aaaa-1111
t=10:00:31 up=46 temp=57C
--- session end TERM 2026-08-18 10:01:00 +0400
--- session start 2026-08-18 10:02:00 +0400
--- boot aaaa-1111
t=10:02:01 up=136 temp=70C
--- session start 2026-08-18 10:05:00 +0400
--- boot bbbb-2222
t=10:05:01 up=15 temp=52C
EOF

expect_ok "a restart within one boot is not a freeze" \
  "recorder restarted, machine kept running" -- \
  "$SCRIPTS/watch-freeze.sh" --report --log "$freeze_log"
expect_ok "a session ending on SIGTERM is not a freeze" "=== stopped cleanly," -- \
  "$SCRIPTS/watch-freeze.sh" --report --log "$freeze_log"
expect_ok "a session with no end marker and a new boot id is a freeze" \
  "DIED HERE -- no clean stop, and the machine rebooted" -- \
  "$SCRIPTS/watch-freeze.sh" --report --log "$freeze_log"

# Logs recorded before the boot id was written still have to be readable, and
# the only signal left in them is uptime restarting.
legacy_log=$(mktemp)
cat >"$legacy_log" <<'EOF'
--- session start 2026-08-18 16:20:13 +0400
t=16:24:07 up=346 temp=67C
--- session start 2026-08-18 16:24:13 +0400
t=16:29:02 up=642 temp=71C
--- session start 2026-08-18 16:29:03 +0400
t=16:29:48 up=688 temp=70C
--- session start 2026-08-18 16:36:49 +0400
t=16:36:55 up=23 temp=77C
EOF

expect_ok "a legacy log still separates a restart from a death" \
  "DIED HERE -- no clean stop, and uptime restarted" -- \
  "$SCRIPTS/watch-freeze.sh" --report --log "$legacy_log"

legacy_verdicts=$("$SCRIPTS/watch-freeze.sh" --report --log "$legacy_log" 2>/dev/null |
  grep -c 'DIED HERE')
if [ "$legacy_verdicts" -eq 1 ]; then
  pass "a legacy log calls exactly one of its three ends a death"
else
  fail "a legacy log calls exactly one of its three ends a death" \
    "found $legacy_verdicts DIED HERE verdicts, expected 1"
fi

rm -f "$freeze_log" "$legacy_log"

# ---------------------------------------------------------------------------
group "FAT32 size boundary"

# FAT32 stores files up to 4 GiB - 1. The check must accept exactly that and
# reject exactly one byte more; make-media.sh uses find -size +Nc, which is
# "strictly greater than", so the constant is the largest legal size.
sizedir=$(mktemp -d)
trap 'rm -rf "$sizedir"' EXIT
dd if=/dev/zero of="$sizedir/legal.bin" bs=1 count=0 seek=4294967295 2>/dev/null
dd if=/dev/zero of="$sizedir/toobig.bin" bs=1 count=0 seek=4294967296 2>/dev/null
FAT32_MAX_FILE_BYTES=$((4 * 1024 * 1024 * 1024 - 1))
flagged=$(find "$sizedir" -type f -size +"$FAT32_MAX_FILE_BYTES"c -exec basename {} \; | sort | tr '\n' ' ')
if [ "$flagged" = "toobig.bin " ]; then
  pass "4 GiB - 1 accepted, 4 GiB rejected"
else
  fail "4 GiB - 1 accepted, 4 GiB rejected" "flagged: '$flagged'"
fi

# ---------------------------------------------------------------------------
group "restore-emmc.sh sidecar naming"

# restore-emmc.sh derives the .sha256 and .size names from the image name. This
# repeats that derivation verbatim, against real files, so a change to the naming
# on either side shows up here rather than at restore time.
derive_sidecar() {
  local image=$1 sidecar
  sidecar=${image%.img.*}.sha256
  [ -f "$sidecar" ] || sidecar=${image%.img}.sha256
  printf '%s' "$sidecar"
}

sidecardir=$(mktemp -d)
check_sidecar() {
  local imagename=$1 sidecarname=$2 got
  : >"$sidecardir/$imagename"
  : >"$sidecardir/$sidecarname"
  got=$(derive_sidecar "$sidecardir/$imagename")
  if [ "$got" = "$sidecardir/$sidecarname" ]; then
    pass "$imagename -> $sidecarname"
  else
    fail "$imagename -> $sidecarname" "derived ${got#"$sidecardir"/}"
  fi
}
# Exactly the names backup-emmc.sh produces, for each compressor it may pick.
check_sidecar "emmc-tablet-20260815-120000.img.zst" "emmc-tablet-20260815-120000.sha256"
check_sidecar "emmc-tablet-20260815-120000.img.xz" "emmc-tablet-20260815-120000.sha256"
check_sidecar "emmc-tablet-20260815-120000.img.gz" "emmc-tablet-20260815-120000.sha256"
# A raw image, and a name with a dot in it, which the %.img.* expansion must not
# chew into.
check_sidecar "emmc-tablet.img" "emmc-tablet.sha256"
check_sidecar "emmc-v1.2-backup.img.zst" "emmc-v1.2-backup.sha256"
rm -rf "$sidecardir"

# ---------------------------------------------------------------------------
group "check-iso-ia32.sh"

if command -v hdiutil >/dev/null 2>&1 || command -v xorrisofs >/dev/null 2>&1 ||
  command -v genisoimage >/dev/null 2>&1 || command -v mkisofs >/dev/null 2>&1; then
  isodir=$(mktemp -d)
  mkdir -p "$isodir/tree/EFI/BOOT" "$isodir/tree/boot/grub"
  printf 'menuentry "test" {}\n' >"$isodir/tree/boot/grub/grub.cfg"
  printf 'MZfake\n' >"$isodir/tree/EFI/BOOT/bootx64.efi"

  made=no
  if command -v hdiutil >/dev/null 2>&1; then
    hdiutil makehybrid -iso -joliet -o "$isodir/t.iso" "$isodir/tree" -quiet && made=yes
  else
    for tool in xorrisofs genisoimage mkisofs; do
      command -v "$tool" >/dev/null 2>&1 || continue
      "$tool" -quiet -o "$isodir/t.iso" -J -R "$isodir/tree" 2>/dev/null && made=yes && break
    done
  fi

  if [ "$made" = yes ]; then
    set +o errexit
    out=$("$SCRIPTS/check-iso-ia32.sh" "$isodir/t.iso" 2>&1)
    set -o errexit
    case $out in
    *"BOOTIA32.EFI  MISSING"*) pass "reports a missing BOOTIA32.EFI" ;;
    *) fail "reports a missing BOOTIA32.EFI" "$out" ;;
    esac
    case $out in
    *"/boot/grub/grub.cfg    present"*) pass "finds /boot/grub/grub.cfg" ;;
    *) fail "finds /boot/grub/grub.cfg" "$out" ;;
    esac
    case $out in
    *"needs artifacts/bootia32.efi"*) pass "verdict is 'needs bootia32.efi'" ;;
    *) fail "verdict is 'needs bootia32.efi'" "$out" ;;
    esac
  else
    skip "check-iso-ia32.sh on a synthetic ISO" "could not build a test ISO"
  fi
  rm -rf "$isodir"
else
  skip "check-iso-ia32.sh on a synthetic ISO" "no ISO-building tool available"
fi

# ---------------------------------------------------------------------------
group "Documentation"

if command -v python3 >/dev/null 2>&1; then
  if output=$(python3 "$REPO_ROOT/tests/check-doc-links.py" 2>&1); then
    pass "internal links and anchors resolve"
  else
    fail "internal links and anchors resolve" "$output"
  fi
else
  skip "internal links and anchors resolve" "python3 not available"
fi

# ---------------------------------------------------------------------------
group "make-media.sh end to end (virtual disk)"

if [ "$(id -u)" -ne 0 ]; then
  skip "end-to-end build" "needs root; re-run with sudo"
else
  if "$REPO_ROOT/tests/e2e-make-media.sh"; then
    pass "end-to-end build"
  else
    fail "end-to-end build"
  fi
fi

# ---------------------------------------------------------------------------
printf '\n%d passed, %d failed, %d skipped\n' "$passed" "$failed" "$skipped"
[ "$failed" -eq 0 ]
