# Random freezes

Two faults were found here wearing the same symptom — the tablet hanging at
idle, and the tablet hanging twenty seconds into boot — plus a third explanation
that had the most evidence behind it and was wrong. Whether the first two were
ever really separate is
[an open question](#open-question-were-these-ever-really-two-faults); both fixes
are kept, because neither costs anything.

**Which one is yours:**

| | boot hang | idle hang |
|---|---|---|
| when | 16-27 s of uptime, every time | ~19 minutes after being left alone |
| on screen | the boot log, backlight on | the screensaver, mid-animation |
| power data | none — `axp288` has not probed yet | `gpu=400MHz`, 70 °C at `busy=14%` |
| fix | [`intel_idle.states_off=56`](#erratum-cht45-the-processor-may-not-wake-from-c6-or-deeper) | [suppress the screensaver](#the-idle-hangs-were-the-screensaver) |

The reasoning is kept in full because on a machine that fails intermittently the
method is the part that transfers to your unit — the conclusions may not.

**Both are fixed on the reference unit.** The boot hangs stopped dead with
`intel_idle.states_off=56`: 10 hangs in 17 boots before, 0 in 15 after. The idle
hangs stopped when `xscreensaver` went away — from hanging within ~19 minutes of
being left alone to 3 days 8 hours unbroken, then back within the hour when the
screensaver returned on a reboot. The charger, which had the most evidence behind
it, was **not** the cause: the last sample before the final desktop freeze reads
`chg=1 ilim=2000mA bat=99% bst=Charging` — the full 2 A budget, battery full.
Every number here is derived below, with what it rests on.

## Erratum CHT45: the processor may not wake from C6 or deeper

This SoC has a documented, unfixed silicon bug whose symptom is exactly what this
tablet does. From Intel's own specification update for the Atom Z8000 series
(document **332067**), verbatim:

```
CHT45          Processor May Not Wake From C6 or Deeper Sleep State

Problem:       The processor may not wake after a sleep state entered with MWAIT Target C-state of
               C6 and Sub C-state of 2 or a target C-state deeper than C6 is requested.

Implication:   When this erratum occurs, the system may hang.

Workaround:    It is possible for the firmware to contain a workaround for this erratum.

Status:        For the steppings affected, see the Summary Tables of Changes.
```

The summary table marks CHT45 for every stepping listed and its status as
**No Fix**. The document covers the Z8300 as S-Spec `SR29Z`, stepping `C-0` — and
this tablet reports CPUID `0x6:4c:3`, which is `0x406C3`, Cherry Trail C0. Same
part, same stepping, erratum applies.

Read the symptom back against the photographs. A processor that entered a sleep
state and never woke leaves the display controller scanning out the last frame it
was given: a lit screen holding a still image, with nothing in the journal because
nothing ran to write it. That is the frozen boot log, and it is the frozen
screensaver.

**The erratum names two specific things, and both can be identified exactly.**
Intel's "workaround" line offers nothing to an operating system — it says the
*firmware* may contain one, which is not something a user can switch on. But the
text is precise enough to point at individual entries in this machine's idle
table rather than at C-states in general. An MWAIT hint encodes the target
C-state in bits [7:4] — where 0 means C1 — and the sub-state in bits [3:0], and
the kernel prints the hint for every state it offers:

```sh
for s in /sys/devices/system/cpu/cpu0/cpuidle/state*; do
  printf '%s %-5s %s\n' "${s##*/}" "$(cat $s/name)" "$(cat $s/desc)"
done
```

On the reference unit that gives six states, and the erratum lands on three of
them:

| state | name | MWAIT | decodes to | named by CHT45? |
|-------|------|-------|------------|-----------------|
| state0 | POLL | — | busy loop | no |
| state1 | C1 | `0x00` | C1, sub-state 0 | no |
| state2 | C6N | `0x58` | C6, sub-state **8** | no |
| state3 | C6S | `0x52` | C6, sub-state **2** | **yes, by name** |
| state4 | C7 | `0x60` | C7, sub-state 0 | yes, deeper than C6 |
| state5 | C7S | `0x64` | C7, sub-state 4 | yes, deeper than C6 |

"C6 and Sub C-state of 2" is not a family of states here. It is one row, `C6S`,
`MWAIT 0x52`. And "deeper than C6" is `C7` and `C7S`. `C6N` is C6 sub-state 8,
which is neither — and the latency column agrees that it is the shallower of the
two C6 entries: 80 µs against 200 µs, so the sub-state numbers are not ordered by
depth on this part and the erratum's "2" has to be read literally.

So the workaround is three states, not all of them. `intel_idle` takes a bitmask
of state indices to disable at init, and bits 3, 4 and 5 are 8 + 16 + 32:

```sh
printf 'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT intel_idle.states_off=56"\n' |
  sudo tee /etc/default/grub.d/99-cstate-cht45.cfg
sudo update-grub
```

A drop-in rather than an edit to `GRUB_CMDLINE_LINUX_DEFAULT` itself, so undoing it
is `rm` plus `update-grub` rather than a careful re-edit. Ubuntu's `grub-mkconfig`
sources `/etc/default/grub.d/*.cfg` after the main file.

**Verify which states it actually took away**, rather than trusting the bit
numbering — `states_off` counts `POLL` as index 0, so an off-by-one here silently
disables the wrong three:

```sh
cat /proc/cmdline
for s in /sys/devices/system/cpu/cpu0/cpuidle/state*; do
  printf '%s %-5s disable=%s usage=%s\n' "${s##*/}" "$(cat $s/name)" \
    "$(cat $s/disable)" "$(cat $s/usage)"
done
```

`C6S`, `C7` and `C7S` must read `disable=1` with `usage=0`, and `POLL`, `C1`,
`C6N` must be untouched. A `usage` that keeps climbing on a state marked disabled
means the parameter did not apply.

**Why not `max_cstate=1`, which is the advice you will find posted.** It leaves
only `POLL` and `C1`, and the cost of going that far is measurable here. During
one six-day session something in userspace held `/dev/cpu_dma_latency` at zero for
the last four days, which pins the CPU to `POLL` — a natural experiment. Median
idle temperature on `PNIT`, at `busy` under 8%, across 93 000 samples:

| idle behaviour | median PNIT | samples |
|---|---|---|
| C-states in use | **54 °C** | 29 711 |
| `POLL` only | **73 °C** | 63 613 |

Nineteen degrees, on a fanless aluminium 8" tablet. Keeping `C6N` is what buys
that back, and `C6N` is the one C6 entry the erratum does not name. Battery is a
separate question and on the reference unit a moot one: across the same session
it logged 73 118 samples at `Full` and 20 384 at `Charging` and never once
`Discharging`. It lives on a charger.

**If the hangs continue with C6N still enabled**, the next step is `states_off=60`
— bits 2 through 5 — which takes `C6N` as well and leaves `POLL` and `C1`. That
is the reading-of-the-text assumption failing, and it is worth knowing which way
it fell before paying the nineteen degrees.

**How this was confirmed, and how to confirm it on another unit.** One lucky boot
proves nothing here: the failure is probabilistic, and the rate has to be measured
on both sides of the change. Reboot the machine in a loop, let each boot live past
the window where the hangs land — two minutes is plenty for a fault that fires at
16-27 s — and count afterwards from `journalctl --list-boots`, where a boot that
ended twenty seconds after it started is a hang:

```sh
journalctl --list-boots --no-pager
```

On the reference unit that gave 10 hangs in 17 boots before, and 0 in 15 after.
Two things made the earlier estimate untrustworthy and are worth avoiding: the
"before" figure was originally taken from twelve boots spread over five weeks,
which is a confidence interval from 10% to 65% rather than a rate — and a batch of
consecutive hangs was briefly blamed on an unrelated change made that evening,
when the honest reading was that both numbers were too small to compare.

**What the freezes look like in the journal**, if you want to identify the fault
before fixing it. They stop at a *different* place every time — `dbus` on one
boot, `avahi` on another, `ModemManager`, `i915`, `wpa_supplicant` — always inside
the 21-27 s window where userspace brings everything up at once. A driver bug
stops at the same line every time; this does not. And the last recorder sample
before one of them reads

```
up=23 busy=90% idle=232/9329/170/51/109/31
             POLL  C1  C6N C6S C7  C7S
```

which is 140 entries into states deeper than C6 in the final five seconds, on a
machine that was 90% busy. That last part matters: "the boot is too busy for an
idle bug" sounds reasonable and is wrong. `busy` is a five-second average, and
CHT45 needs one bad entry, not a sustained sleep.

**A cheap prediction that would corroborate it on another unit.** If a hang is
CHT45, the processor is asleep and the kernel is not running, so the Caps Lock LED
test below should show a *dead* LED. A LED that still toggles would mean the kernel
is alive and something else is wedged — which would point away from this erratum.

### Open question: were these ever really two faults?

This page treats the idle hangs and the boot hangs as separate, because that is
how they were found and fixed — the screensaver first, months before CHT45 was
identified. But the tidier explanation has not been ruled out: **that both were
CHT45, and the screensaver was a way of provoking it rather than a cause.**

A screensaver animating on an otherwise unattended machine is not a busy
machine. It is a machine going idle and waking again, several times a second,
for hours — which is precisely the pattern an erratum about waking from a deep
C-state punishes, and it explains why the freezes came at idle rather than
under the deliberate CPU, memory and GPU load tests that the tablet survived
for three days.

Against that: the correlation with `xscreensaver` was three-legged and strong,
and it held before any C-state parameter existed.

**It is testable, and it has not been tested.** Put `xscreensaver` back with
`intel_idle.states_off=56` in place and leave the tablet alone for a few days.
If it survives, one fault explains everything and the screensaver was innocent.
If it hangs, they really are two. Until somebody runs that, this page keeps both
fixes, because keeping a fix that turns out to be unnecessary costs a screensaver
and dropping one that was necessary costs the machine.

## The hardware watchdog: real, usable, and only half a safety net

The firmware describes a watchdog in the ACPI `WDAT` table, and Linux can drive it
— which is worth knowing, because the alternative to a hang is holding the power
button. It is not enabled by default and nothing hints that it exists:

```sh
ls /sys/bus/platform/devices/ | grep wdat     # wdat_wdt
sudo modprobe wdat_wdt && sudo wdctl          # 30s timeout, SETTIMEOUT supported
```

Loading it from `/etc/modules-load.d/` is **not** enough. `systemd` opens
`/dev/watchdog` while PID 1 starts, which is before `systemd-modules-load.service`
runs, so the device does not exist yet, systemd gives up, and nothing ever arms it.
The module has to be in the initramfs. Note that this system uses **dracut**, not
initramfs-tools — `/etc/initramfs-tools/modules` does not exist here and writing to
it silently achieves nothing:

```sh
printf 'force_drivers+=" wdat_wdt "\n' | sudo tee /etc/dracut.conf.d/99-watchdog.conf
printf '[Manager]\nRuntimeWatchdogSec=30\n' | sudo tee /etc/systemd/system.conf.d/watchdog.conf
sudo dracut -f
```

Verify after a reboot — all three, because each can be true while the next is
false:

```sh
sudo lsinitrd /boot/initrd.img-$(uname -r) | grep wdat   # in the image
systemctl show -p RuntimeWatchdogUSec                    # RuntimeWatchdogUSec=30s
cat /sys/class/watchdog/watchdog0/state                  # active
```

**Do not count on it to recover a hang.** Tested twice by crashing the kernel
deliberately — `echo c > /proc/sysrq-trigger`, with `kernel.panic = 0` so the
kernel cannot reboot itself and any reset must be the watchdog. The first time the
machine reset itself 63 s later. The second time it stayed dark for six minutes
and needed the power button. One recovery out of two attempts is not a safety net,
and the dark screen on the failure — rather than a lit, frozen console — suggests
this firmware's watchdog action powers the tablet off rather than resetting it.
Leave it enabled if you like; do not build a test plan that assumes it works.

**Start by recording, not by guessing.** A hard hang gives the kernel no chance
to flush anything, so the journal simply stops and every theory below looks
equally plausible from the wreckage. One evening of reading journal tails
produced three incompatible explanations and no way to choose between them.

```sh
sudo ./scripts/watch-freeze.sh --install    # samples from boot, flushed to disk
# ... wait for a freeze, power-cycle, then:
sudo ./scripts/watch-freeze.sh --report
```

It writes power, thermals, load, CPU frequency, GPU clock and per-C-state entry
counts every few seconds and forces each line to disk before taking the next, so
the final line is the state the machine was in when it died. That single line
distinguishes most of what follows: a current spike, a thermal climb, and a jump
into a deep idle state look nothing alike.

**Then try to provoke one, rather than waiting.** Every freeze so far has cost a
couple of hours of idling, which is why several theories have been argued and none
settled. `stress-freeze.sh` loads one subsystem at a time while the recorder
watches:

```sh
sudo ./scripts/stress-freeze.sh --list
sudo ./scripts/stress-freeze.sh --phase idle     # the control, first
sudo ./scripts/stress-freeze.sh --phase cpu
sudo ./scripts/stress-freeze.sh --phase wifi
```

**One phase at a time is the whole design, not a limitation.** A combined run that
ends in a freeze is consistent with every hypothesis on this page and separates
none of them, so there is no `--phase all` and asking for one is an error. Two
other things are built in for the same reason: the run aborts above 80 °C, so a
thermal shutdown can never be written up afterwards as a freeze, and `--phase idle`
loads nothing at all — if the tablet dies during *that*, none of the other phases
prove anything.

**What the phases have returned so far**, ten minutes each on the reference
tablet, hottest zone in brackets:

| Phase | Result | Peak |
| --- | --- | --- |
| `idle` (control) | survived | 59 °C |
| `cpu` | survived | 67 °C |
| `mem` | survived | 67 °C |
| `wifi` (scan) | survived | — |
| `gpu` | void — the load never started, see below | — |

The control surviving is what makes the rest mean anything: load was a real
variable in those runs, not a label on a machine that happens to stay up. And
`cpu` and `mem` surviving retires a whole family of theories at once — a tablet
that holds 67 °C through every core at full load and 75 % of RAM under `--verify`
is not freezing because it is too weak, too hot, or short of memory.

That is why `wifi-reload` exists, and it is the phase to run if you only run one.
The `wifi` phase scans on an already-associated radio and changed nothing;
`wifi-reload` unloads `brcmfmac` and brings the whole stack back up on a loop,
which is the event every photographed boot freeze actually sits on. It needs root
and it drops the network every cycle, so over SSH on wireless it must be launched
detached — and the `sudo -v` first is not optional:

```sh
sudo -v
sudo setsid ./scripts/stress-freeze.sh \
  --phase wifi-reload </dev/null &>/tmp/reload.log &
```

A backgrounded `sudo` whose credential timestamp has expired reads the password
from the terminal, takes `SIGTTIN` and stops before it ever execs the script. The
symptom is nothing at all: no run, no marker in the stress log, and an empty
`/tmp/reload.log` — the shell truncated it with the redirect and no process ever
wrote to it. Easy to read as "the script is broken" when nothing has run yet.

**`modprobe -r brcmfmac` fails with "Module brcmfmac is in use", and
NetworkManager is not why.** That was the first guess on this tablet; stopping
NetworkManager, `wpa_supplicant` and the interface itself changed nothing. The
holder is `brcmfmac_wcc`:

```
--- refcnt 1
--- module holders [brcmfmac_wcc]
--- lsmod brcmfmac_wcc           12288  0
--- lsmod brcmfmac              544768  1 brcmfmac_wcc
```

Kernel 6.x split the per-vendor firmware and regulatory hooks out of `brcmfmac`
into their own module, which then registers back into it. `modprobe -r` does not
walk that edge — it removes what a module depends *on*, not what depends on it —
so the chain has to come apart from the top:

```sh
sudo modprobe -r brcmfmac_wcc   # takes brcmfmac and brcmutil with it
sudo modprobe brcmfmac          # asks the kernel for its vendor module again
```

`stress-freeze.sh` reads `/sys/module/brcmfmac/holders/` and removes whatever is
listed rather than naming `brcmfmac_wcc`, since the vendor module differs by chip.
Note the second command is enough to restore the radio: `brcmfmac` requests its
own vendor module when the chip probes, which is also what makes the phase a
faithful copy of the boot sequence rather than an approximation of it.

**A load test that passes without loading anything is worse than no test**, and
this one did it once. The `gpu` phase looped `glmark2 || sleep 1`, `glmark2` could
not reach the display, and the loop spun on the error for ten minutes and reported
"survived 600s". Nothing in the run said otherwise; the arithmetic did, afterwards.
The phase peaked 63 °C against 59 °C for the idle control, on a tablet where the
screensaver alone is worth 15 °C, and the recorder had `gpu=200MHz` — the idle
clock — on every line. Two things changed as a result: every load now runs until
the script kills it, and the sampling loop checks each interval that the load is
still alive and fails the run the moment it is not. That check has since caught a
second false pass, so treat any earlier `SURVIVED` line without a `hottest=` field
as unproven and run it again.

It refuses to run unless the recorder service is active, because a freeze caught
without a record is a wasted freeze and a wasted power cycle.

`--report` marks only the genuine freezes `DIED HERE`. It knows the difference
because each session records the boot id and writes an end marker when it is
asked to stop, so restarting the recorder, shutting the machine down and the
machine vanishing underneath it are three distinguishable endings rather than one
ambiguous gap. Worth insisting on: the first reading of this log counted two
`systemctl restart`s as crashes.

**They cluster at the tail of boot.** Five boots on that tablet ended without a
shutdown sequence, three of them after **21, 22 and 23 seconds** against a normal
17-second boot. Reading the tail of each shows a different last service every
time — `gpu-manager` and `logind`, `bluetoothd` starting its SDP server,
`iio-sensor-proxy`, and twice `wpa_supplicant` with `NetworkManager`. No service
is common to them. A sixth died 19 minutes in while idle, and the owner reports
it freezing on the screensaver. — **observed on the unit**

**Three of those five are the moment a radio powers up** — Bluetooth once, Wi-Fi
twice. That was read at the time as a current peak, and it is what kept the
charger theory alive. It is also, as it turned out, the heaviest SDIO DMA of the
boot, which fits CHT45 just as well and does not need the supply to be at fault.

Every search for this points at deep C-states and `intel_idle.max_cstate=1`, and
the erratum usually named alongside it is **VLP52, which is Bay Trail only**: the
patch written for it matches a single model, `case 0x37: /* BYT */`, and was never
merged. This tablet reports `family:model:stepping 0x6:4c:3`, and `0x4c` is
Airmont — the Cherry Trail core, a different generation.

**That is true and it was used here to reach a wrong conclusion.** Checking the
Bay Trail erratum, finding it did not apply, and writing C-states off was the
mistake: Cherry Trail has its own, [CHT45](#erratum-cht45-the-processor-may-not-wake-from-c6-or-deeper),
status **No Fix**, and it applies to this exact part and stepping. The popular
advice happens to be right here for a reason its sources never state. Worth
remembering as a method: an erratum not applying is not the same as the mechanism
not applying, and the second question has to be asked separately.

What the timing does rule out is screen blanking, which cannot explain a freeze
22 seconds in with the boot log still lit on the panel.

Worth knowing what it is *not*, since all of these were checked here: no OOM,
swap untouched with 1.1 GiB still available, and no I/O or eMMC error anywhere in
the journal. Memory pressure and failing storage both look plausible from the
outside and neither left a trace.

## What the recorder actually caught

Five session ends on the reference unit, two on the desktop and three during
boot. — **measured on the unit**

**The battery voltage never sags.** `bv=` sits between 4206 and 4259 mV in every
sample of every session, including the last one written before each desktop
freeze, with the charger negotiating 2 A and the pack at 99 %. A supply that
collapses under a current peak should show up here, and it does not. Two caveats
keep this from closing the question: the recorder samples every 5 s and a
brownout is a millisecond event, and at the boot freezes there is **no power data
at all** — `axp288_fuel_gauge` has not probed yet at 16-23 s, so those lines read
`bat=?% bst=none`.

**The panel stays lit with the last frame intact.** Every photographed freeze
shows the boot log or the screensaver still on screen, backlight on. A supply
collapse takes the backlight with it, and a thermal trip powers the machine down
rather than parking it on a frame. What that picture does fit is a lockup: the
display controller keeps scanning out the framebuffer it was given while nothing
else advances. — **observed**, and it argues against both the charger and the
thermal readings below being the whole story.

**The six thermal zones, and which of them lies.** — **read off the unit**

```
thermal_zone0  acpitz           43.6 C
thermal_zone1  INT3400 Thermal  20.0 C
thermal_zone2  STR0             43.6 C
thermal_zone3  PNIT             59.0 C
thermal_zone4  soc_dts0         53.0 C
thermal_zone5  soc_dts1         50.0 C
```

`INT3400` is the DPTF policy device. It has no sensor behind it and reports a
constant 20 °C. `soc_dts0` and `soc_dts1` are the SoC's own digital thermal
sensors — the closest thing here to a die temperature. `PNIT` reads about 6 °C
above them and is the hottest zone, which matters because the recorder used to
log the maximum: every `temp=` in the older logs is `PNIT`, and every `temp=20C`
in a first sample is `INT3400` being the only zone registered that early rather
than a cold machine. It now records all six, with a `--- thermal zones` line
naming them.

**And the trip points say the freezes are not thermal.** — **read off the unit**

```
acpitz    critical 100.0 C
STR0      passive 61.05 C   hot 82.05 C   critical 85.05 C
PNIT      passive 85.05 C
soc_dts0  passive 0 C, 0 C      (unprogrammed)
soc_dts1  passive 0 C, 0 C      (unprogrammed)
```

Two of `STR0`'s passive trips read `-274000`, which is below absolute zero and
means unset, as do the SoC sensors' zeroes. What is set is a throttling trip at
61 °C and a critical one at 85 °C on the skin sensor. The hottest reading ever
recorded here is 77 °C on `PNIT`, whose own trip is at 85 °C, so nothing has
come close to a critical trip.

That matters more than the margin, because of what a critical trip *does*: the
thermal core powers the machine off. A tablet that overheated past a trip would
be found switched off, not sitting on a lit frame of the boot log. Overheating
would have to hang the hardware silently *below* every configured trip to explain
what is actually seen, which is a much larger claim than "it runs warm".

**The screensaver costs 15-20 °C.** Idle with `xscreensaver` running: 67-71 °C,
`gpu=400MHz`, load ~1.3. The same machine idle with it gone: 51-57 °C, `busy=3%`.
The last desktop sample before a freeze was 70 °C with the GPU at 400 MHz and the
charge current fallen from 1024 to 592 mA — the system drawing more of the 2 A
budget, not the supply giving less. — **measured**

**Suppressing it is what ended the desktop freezes.** Before: repeated hangs
within ~19 minutes of the machine being left alone, the longest recorded session
11 minutes. After: `up=287263` — 3 days 8 hours, unbroken, with ten-minute `cpu`,
`mem` and `gpu` load runs deliberately thrown at it in the middle. One variable
changed. — **verified on the unit**

**Acceleration works, so a software-rendering theory does not hold.** Xorg says so
outright, and reading its log costs nothing — no `mesa-utils`, no network:

```
(II) modeset(0): glamor X acceleration enabled on Mesa Intel(R) HD Graphics (CHV)
(II) modeset(0): glamor: Using OpenGL 4.6 context.
(II) AIGLX: Loaded and initialized crocus
```

— **verified on the unit**. `CHV` is Cherryview, and `crocus` is the right driver
for it, not a fallback: Mesa lists the Cherryview PCI IDs `0x22b0`-`0x22b3` in
[`include/pci_ids/crocus_pci_ids.h`](https://gitlab.freedesktop.org/mesa/mesa/-/blob/main/include/pci_ids/crocus_pci_ids.h),
with the renderer string `Intel(R) HD Graphics` that the log prints back. The
newer `iris` covers later generations and is *not* the one to expect here.

Two numbers from the recorder said the same thing before the log was read, and
they are the cheap check if you have no X log to hand: `gpu=` sits at 200 MHz idle
and moves to 400 MHz exactly while the screensaver runs — `gt_cur_freq_mhz` exists
only under `i915`, and a GPU with nothing to do stays on its bottom step — while
`busy=` reads 14 % through the same window, where a full-screen GL animation at
800x1280 falling back to `llvmpipe` would cost multiples of that across four
Airmont cores.

So the reading that "the graphics are broken, and the CPU overheats doing their
work" fails on both halves.

**Boot freezes land at 16-23 s of uptime**, three of three. The one sample
captured at the edge read 77 °C and `busy=90%` at `up=23`, on a SoC that had been
running 70 °C six minutes earlier and never cooled.

These are still open, and the screensaver result says nothing about them: it was a
desktop-idle fault and this is not. The power columns cannot help either —
`bat=?`, `chg=?`, `ilim=?` on every one of those lines, because `axp288_charger`
has not probed yet at 16 seconds.

**A console photographed mid-hang says where it stops.** Booting without a splash
so the log is visible, the last lines on a frozen screen were:

```
[   19.756358] brcmfmac: brcmf_fw_alloc_request: using brcm/brcmfmac43430a0-sdio for chip BCM43430/0
[   20.426338] brcmfmac: brcmf_c_process_clm_blob: no clm_blob available (err=-2)
[   20.430110] brcmfmac: brcmf_c_process_txcap_blob: no txcap_blob available (err=-2)
[   20.435638] brcmfmac: brcmf_c_preinit_dcmds: Firmware: BCM43430/0 wl0: May 29 2017 ... FWID 01-130000
[  OK  ] Started bluetooth.service
         Starting NetworkManager.service - Network Manager...
         Starting wpa_supplicant.service - WPA supplicant...
[  OK  ] Started polkit.service
         Starting ModemManager.service - Modem Manager...
[  OK  ] Started iio-sensor-proxy.service
[  OK  ] Started wpa_supplicant.service - WPA supplicant.
```

— **photographed on the unit**. Nothing after that. The radio firmware finishes
loading at 20.4 s and the machine dies within about two seconds of the supplicant
coming up on top of it. That is the same window every earlier boot freeze landed
in, now with the kernel's own timestamps against it rather than a `up=` reading
from the sampler.

The `clm_blob` and `txcap_blob` lines are **not** the fault — they are normal for
this chip on Linux, which ships no regulatory blob for it, and they appear on
boots that succeed too. What matters is the sequence: cold module, firmware, then
`NetworkManager` and `wpa_supplicant` starting on it. That is precisely what
`stress-freeze.sh --phase wifi-reload` reproduces on demand.

**On a tablet you cannot reach, fix the recoverability before the fault.** A boot
hang needs a human to hold the power button, which on a machine in another city
is the expensive part — not the hang itself. The watchdog is the answer, with the
caveats recorded in
[its own section](#the-hardware-watchdog-real-usable-and-only-half-a-safety-net):
it recovered one hang out of two attempts here, so wire it up and do not build a
test plan that assumes it works.

## The idle hangs were the screensaver

The evidence is [above](#what-the-recorder-actually-caught): 15-20 °C and a
pinned 400 MHz GPU while it animates, repeated hangs within ~19 minutes of the
machine being left alone, then `up=287263` — 3 days 8 hours unbroken — with one
variable changed. Then it came back on the first reboot and hung the machine
within the hour, which is the leg that makes the correlation hard to argue with.

**Remove the package.** Nothing on a wall-mounted tablet needs an animated
OpenGL screen hack, and every softer measure here has a way of coming back:

```sh
sudo apt purge xscreensaver
```

Read what `apt` proposes to remove before agreeing. If it wants to take `lxqt` or
`lxqt-session` with it, decline and use the autostart override below instead.

`pkill -f xscreensaver` does **not** stick — the LXQt session respawns it, and
`ps` shows it back a minute later. `xscreensaver-command -exit` does stick for the
session, and that is the trap: it held for three days on the reference unit and
then came back on the first reboot, because nothing had rebooted in between to
test it.

**And the autostart override did not save it either.** The `Hidden=true` entry was
in place — timestamped 13 minutes before the clean three-day session began, and
still there when the screensaver came back and hung the machine at `up=707`. So
the quiet three days are explained by the runtime kill alone; the override has
never been observed to do anything on this system. Which is the whole argument for
purging instead. If the package has to stay, write the override, then **reboot and
confirm `pgrep xscreensaver` finds nothing** — an untested suppression is
indistinguishable from a working one until the machine restarts:

```sh
xscreensaver-command -exit
mkdir -p ~/.config/autostart
printf '[Desktop Entry]\nType=Application\nName=xscreensaver\nHidden=true\n' \
  > ~/.config/autostart/xscreensaver.desktop
```

**The one test worth doing during a freeze** costs nothing and splits the
remaining hypotheses: press Caps Lock on the USB keyboard and watch its LED. The
LED is driven by the kernel's HID layer, so if it still toggles the kernel is
alive and only userspace is wedged; if it is dead, so is the kernel, and no
amount of userspace tuning will help.

## Things to try, in order

The two fixes this page established come first, because a reader who scrolled
straight here should not have to go back up for them.

1. **Put `intel_idle.states_off=56` on the kernel command line** — the boot
   hangs, [erratum CHT45](#erratum-cht45-the-processor-may-not-wake-from-c6-or-deeper).
   To try it without rebooting, every idle state has a writable `disable`:

   ```sh
   # what the states are and in what order -- do not assume the numbering
   head -v /sys/devices/system/cpu/cpu0/cpuidle/state*/name

   # C6S, C7 and C7S off, now -- the three the erratum names
   for s in /sys/devices/system/cpu/cpu*/cpuidle/state[3-9]; do
     echo 1 | sudo tee "$s/disable" >/dev/null
   done
   ```

   The recorder's `idle=` column then shows those counters going flat, which is
   how you know the change took rather than assuming it. Undo it by writing `0`
   back. **Do not extend this to `state2`** — that is `C6N`, which the erratum
   does not name and which is worth 19 °C of idle temperature.

2. **Suppress the screensaver** — the idle hangs,
   [as established above](#the-idle-hangs-were-the-screensaver).

3. **Confirm you are not swapping to eMMC.** `swapon --show` should list a zram
   device and nothing else.

4. **Raise the charger's input current limit.** This was the leading theory here
   and it was **wrong** — the unit froze at `ilim=2000mA` with the battery full.
   It is still worth doing on a unit that reads 500 mA, because a machine that
   draws about an ampere while permitted half of one takes the rest out of a
   ten-year-old battery while plugged in and reporting `online`:

   ```
   axp288_charger/input_current_limit:  500000   (500 mA)
   axp288_charger/online:               1
   axp288_fuel_gauge/status:            Discharging
   axp288_fuel_gauge/current_now:      -496000   (496 mA out of the battery)
   ```

   Capacity fell from 95 % to 86 % across an idle session on the charger.
   — **verified on the unit**

   ```sh
   echo 2000000 | sudo tee /sys/class/power_supply/axp288_charger/input_current_limit
   ```

   Then re-read `status`. **The limit is permission, not delivery**: if the supply
   cannot actually source 2 A, VBUS sags, and since the driver pins `Vhold` at
   4.4 V the charger throttles straight back. Still `Discharging` after raising it
   means the problem is the supply — use a plain USB-A 2 A charger on an A-to-C
   cable, direct, no hub. See
   [01-hardware.md](01-hardware.md#ports-otg-and-charging-while-a-hub-is-attached)
   for what the driver does with `Vhold`.

5. Kernel parameters another Vi8 Plus owner reports as their freeze fix:

   ```
   usbcore.autosuspend=-1 pcie_aspm=off intel_idle.max_cstate=1
   ```

   Untested here, and their own note says some of the three may be unnecessary.
   Add them together first; if the freezes stop, remove them one at a time to
   find which one mattered. Source in
   [90-references.md](90-references.md#another-owners-fixes-for-this-exact-tablet).

If the freeze leaves a trace, it will be in `journalctl -b -1 -p err`.

Separately, if the freezes coincide with Wi-Fi activity, the same owner reports
`brcmfmac` firmware crashes cured by turning NetworkManager's power saving off:

```sh
printf '[connection]\nwifi.powersave = 2\n' |
  sudo tee /etc/NetworkManager/conf.d/wifi-powersave-off.conf
sudo systemctl restart NetworkManager
```


### Two things not to bother with, and why

**The firmware's `C-States` item does nothing under Linux.**
`/sys/devices/system/cpu/cpuidle/current_driver` reads `intel_idle` on this unit,
and [the kernel documentation](https://docs.kernel.org/admin-guide/pm/intel_idle.html)
is explicit that `intel_idle` drives idle from its own per-model tables "without
input from system firmware", falling back to ACPI `_CST` only for processors it
does not recognise. Airmont it recognises. The logged state names settle it from
this machine's own data: `C6N`, `C6S`, `C7S` are `intel_idle` names, where ACPI
would report a flat `C1`/`C2`/`C3`. The firmware item changes what ACPI
advertises and nothing reads it. That is why the workaround circulates at all —
Windows *does* take its idle states from ACPI, so `C-States: C1` is a real
setting over there. The one case where it comes back into play is a firmware that
masks `MWAIT` outright, which would show up as `current_driver` reading
`acpi_idle` instead.

**`intel_idle.max_cstate=1` costs 19 °C for no benefit over `states_off=56`.**
See [why not `max_cstate=1`](#erratum-cht45-the-processor-may-not-wake-from-c6-or-deeper)
above. It also needs a reboot to apply and another to undo, where the `disable`
attributes in item 1 need neither.

### The other mechanism that fits, and is not needed to explain this

Before CHT45 was found, C-states were written off here because the boot freezes
land in the busiest moment of boot rather than in idle. That reasoning was about
the wrong mechanism — `busy=` is an average over five seconds, and a core idle
between two bursts of SDIO DMA still enters C6. Intel's MMC maintainer describes
a fault that fits the timing exactly:

> *"Intel Baytrail has been observed sometimes to hang if host controllers are
> using DMA while deep C-states are used"*
> — [mmc: sdhci-acpi: Fix device hang on Intel BayTrail](https://lkml.iu.edu/hypermail/linux/kernel/1503.3/00272.html)

The kernel's workaround is a PM QoS request (`dma_latency = 20`) holding the CPU
out of deep states while a transfer is in flight, gated on the CPU model because
"host controller ACPI HIDs are not unique to Baytrail". The model it matches is
**0x37, Bay Trail**. This tablet is `0x6:4c:3` — **model 0x4C, Airmont**, outside
that guard. Which lines up with where the boot freezes actually stopped: two
seconds after `brcmfmac` finishes pushing firmware to the radio over SDIO, the
heaviest SDIO DMA of the whole boot.

Recorded because it is a second, independent reason to take the deep states away
on this SoC, and because it would explain the same evidence. It is not needed:
`states_off=56` already fixed the fault, and CHT45 names this exact part.
