# The freeze recorder and the stress harness

Two scripts written for [51-freezes.md](51-freezes.md), and useful for any
intermittent fault on this machine. Neither is needed once the fixes on that page
are applied — they are here because the method is what transfers to another unit
when the conclusions do not.

## Record first, do not guess

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

## Provoke a freeze instead of waiting for one

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

## What the phases have returned

Ten minutes each on the reference tablet, hottest zone in brackets:

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

## Two traps these scripts walk into

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

