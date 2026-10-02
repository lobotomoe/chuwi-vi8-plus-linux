# Making a slow tablet feel fast

Everything here was measured on the reference unit, but the numbers are the
least transferable part of it. What transfers is the method, and the list of
things that looked guilty and were not — because a weak tablet invites the same
wrong guesses on every machine, and each one costs an evening.

The short version: **one setting was worth more than every other change
combined, and almost everything that felt like it should matter was worth
nothing.** Hunting background daemons on a machine like this is a way to spend a
day and recover one per cent of one core.

## Nothing outside the browser can see 60 fps

`scrot` manages about 14 captures a second on this hardware. A screen recorder
cannot tell 60 fps from 20 here, so every judgement made by looking at the panel
or at a capture is an impression, not a measurement.

The frame timing has to come from inside the page: a `requestAnimationFrame`
recorder running in the browser while a real touch swipe is injected into the
touchscreen's event node ([52-freeze-tools.md](52-freeze-tools.md) has the same
argument about recording before guessing). `scripts/panel-bench/` does this.

**Score on late frames — the share of frames past 25 ms.** Not median fps, which
sits at 60.8 even when every sixth frame is dropped, and not p95, which on a
59.99 Hz panel is bimodal: it reads 17 ms or 33 ms and nothing in between, so it
jumps between two values that differ by a factor of two and tells you nothing
about the tail that is actually visible.

**Gate every run on the page having moved.** The swipe goes down and comes back
up, so comparing scroll position before and after reports zero travel every
time; record the distance covered *during* the recording instead. Without that
gate a run reports a flawless 60 fps when the panel was dark, or when the swipe
was swallowed by the idle dimmer, and a flawless result from a test that never
ran is worse than no test — the same failure that once produced a ten-minute
`survived` from a GPU load that never started.

## One A/B is not enough, and this is the expensive lesson

Run-to-run spread here is wide, and worse than wide, it is **directional**: the
first pass of a session is reliably the worst one. Two examples from the same
evening, both of which produced a confident wrong answer first:

| | pass 1 | pass 2 | pass 3 | pass 4 |
| --- | --- | --- | --- | --- |
| rotation, first attempt (A-B-A') | 12.8% | 4.1% | 4.5% | — |
| rotation, four alternating passes | 3.8% | 4.4% | 4.0% | 4.4% |

The first attempt reads as a threefold win from switching the display rotation
off. The second shows the effect does not exist: within each arm the spread is
0.2 and 0.0 points, between the arms it is 0.5 points, and it favours the
*rotated* arm. The 12.8% was warm-up.

**The test is not "did B beat A". It is "did the gap between the arms exceed the
gap between two identical passes".** Alternate A-B-A-B, and if the second A does
not come back near the first A, the experiment has no resolution and its result
must be thrown away rather than reported with a caveat. A service that was
suspected of costing frames produced 5.3 / 3.8 / 3.8 / 2.9 across four passes —
a monotone decline through both arms, which is a warm-up curve with the
treatment painted on top of it.

## What was actually wrong: the CPU governor

`schedutil` on `intel_cpufreq`, measured against `performance` on the real
dashboard:

| governor | p95 frame | late frames |
| --- | --- | --- |
| `schedutil` | 34.0 / 33.8 ms | 8.9% / 9.3% |
| **`performance`** | **17.3 / 17.3 ms** | **2.3% / 2.9%** |
| `schedutil` again | 33.7 / 32.9 ms | 8.1% / 5.7% |

Three times less late, and nothing else found since has come close. On a
wall-mounted panel that never runs on battery it costs 1-2 °C at idle — 48 °C
becomes 49-50 °C, against a throttle cliff at 77 °C
([51-freezes.md](51-freezes.md)) — so there is nothing to trade away.

**The trap that hides this.** Sample the clock during a scroll and it reaches
1840 MHz, the top of the ramp, which reads as "the governor is doing its job".
Reaching the top of the ramp is not the same as reaching it *before the frame
was due*, and a frequency sample cannot tell the difference. Do not conclude a
governor is innocent from a frequency reading. A-B it.

## Leave the measuring port open in the production browser

The instrument resets the specimen. Attaching a frame recorder normally means
starting the browser with a remote-control port, and starting the browser clears
exactly the accumulated state you are trying to measure. A whole day went into
chasing a slowdown that could not be attributed to anything, because every
attempt to measure it destroyed it first.

So the kiosk launcher carries `MOZ_MARIONETTE=1` permanently. Three things make
that acceptable rather than reckless, and all three are worth checking on any
machine where you do the same:

- The port listens on `127.0.0.1` only.
- It needs no extra privilege for this. Scroll measurement runs in the ordinary
  content context; only reading the browser's own preferences needs the chrome
  context, and that is the one thing worth *not* enabling permanently.
- It takes nothing from the display. Verify rather than assume: the page's
  viewport must still equal the panel. Here 533x853 CSS pixels at 1.5x is exactly
  800x1280, and `outerHeight` equals `innerHeight`, so no notification bar
  appeared above the content.

The visible cost is that `navigator.webdriver` becomes true, which sites with
bot detection can see. For a dashboard on a wall that is nothing; for a browser
used for the open web, decide deliberately.

## Read rates, never totals

`ps times=` and the counters in `/proc/<pid>/stat` accumulate from process
start. On a machine with a long uptime they are history, and history looks
exactly like load.

This produced the single most confident wrong answer of the investigation:
`upowerd` had accumulated 700 seconds of CPU and sat near the top of the
process list, so it was obviously polling the battery too hard. Measured over a
real 60-second window it was using **0.3% of a core**, and an A-B-A of the
setting that was supposed to fix it changed nothing at all. The 700 seconds were
23 hours of ordinary operation.

Take two snapshots a window apart and subtract. Over a 60-second idle window on
the full desktop, **every userspace process together came to about 2% of one
core**, and several of the applets that looked worth removing did not appear in
the list at all because they use no CPU to speak of. Hiding them buys memory,
not frames.

One more trap in the same family: **`/proc/<pid>/io` is readable only by the
process's own user.** An unprivileged census of who is writing to disk silently
omits every root daemon and returns a tidy, complete-looking, wrong answer.

## Ask the kernel whether the GPU is doing the work

Software compositing on an Atom-class GPU would be the whole frame budget, so
this is worth settling early, and the browser's own about page is not the only
way to ask. Every DRM client's `/proc/<pid>/fdinfo/<fd>` carries
`drm-client-id` and `drm-engine-<name>`, a nanosecond counter of time that
client spent on that engine:

| | render engine time |
| --- | --- |
| panel idle | 0 |
| 6 s of dragging | 805 ms, 13.4% of the window |

So compositing is on the GPU, and the GPU is nearly idle while doing it — there
is no headroom to win there, and software WebRender was never the problem.

Two reasons to prefer this over the browser's self-report: it needs no
permission at all, and it measures the hardware rather than a configuration
string. `scripts/panel-bench/gpuwork.py` does it. Note the one implementation
detail that matters: filter processes by `readlink` on the fd first and only
read `fdinfo` for the ones pointing at `/dev/dri/`. Across 1591 open fds that
took a full `/proc` sweep from 228 ms to 43 ms, finding the same clients — and
`readlink` sees through a snap's mount namespace, so a sandboxed browser is
still found.

## A swap figure here is not memory pressure

With zram ([40-post-install.md](40-post-install.md)), a reported 400 MB of swap
in use means roughly 290 MB of pages compressed into about 62 MB of RAM, with no
eMMC traffic whatsoever. Read as disk swapping it looks like a machine in
trouble; it is a machine doing what it was configured to do.

Run `cat /proc/swaps` before drawing any conclusion from a swap number. On this
unit the zram device also absorbed the entire "the panel is short of memory"
theory, which had no other evidence behind it — zero OOM kills across a full
day, and `avail` never below 670 MB.

## A long-lived session gets slower on its own

Measured on one unchanged configuration across a single day:

| | late frames | worst frame |
| --- | --- | --- |
| morning | 4.7-6.3% | 50-84 ms |
| same evening | 9.8-14.5% | 250 ms |
| after a reboot | 2.9-5.3% | 33-50 ms |

Nothing was changed between those rows. Several hours went into attributing that
drift to background services, and all of them were innocent.

**Re-measure after a reboot before investigating a regression.** If the numbers
come back, the regression is in accumulated state, not in anything you installed
this week. A nightly restart of the browser alone — far cheaper than rebooting a
wall display — is the obvious next thing to test, and the test is simply to
measure immediately before and immediately after the restart and compare.

## The innocent list

Each of these was suspected on this unit, measured properly, and cleared. The
column that matters is the last one, because it is what the next person can skip:

| Suspect | Verdict | How it was settled |
| --- | --- | --- |
| CPU governor | **guilty** | A-B-A, 3x fewer late frames |
| Deep C-states | costly to disable | pinning the CPU out of C6+ raised median idle from 54 °C to 73 °C over 93 000 samples, against a 77 °C cliff |
| Background daemons | innocent | 60 s rate window: ~2% of one core, all of userspace |
| `upowerd` battery polling | innocent | A-B-A, no difference; the 700 s was history |
| Dashboard CSS animations | innocent | `getAnimations()` across all 331 shadow roots: 0 running |
| Display rotation 180° | innocent | four alternating passes, 0.5 pt gap favouring rotated |
| GPU / software compositing | innocent | `drm-engine-render`, 13.4% busy while scrolling |
| Memory pressure | innocent | zram, 0 OOM kills in a day |
| A logging service writing to eMMC | innocent | four passes, treatment gap below the warm-up drift |

## Where the time actually goes

What is left after all of that is CPU-side frame building, and it is driven by
the page rather than by the machine: nine dashboard tiles expand to 2246-2437
DOM nodes across 331 shadow roots. On hardware this size the content is the
budget, and the largest remaining lever is the dashboard's own configuration —
fewer cards, simpler cards.

The browser choice is the one machine-side lever still worth having, and it is
not close:

| | idle late | scrolling late | worst frame | RSS / processes |
| --- | --- | --- | --- | --- |
| Firefox 156 | 0-1% | **5-6%** | 50-84 ms | 860 MB / 10 |
| Chromium 153 | 0.0% | **24.5%** | 117.5 ms | 1196 MB / 14 |

**Equalise the device pixel ratio before comparing two browsers, or the
comparison is worthless.** Firefox takes 1.5x from the X server's DPI on this
8-inch panel and lays out an 853 px viewport; Chromium defaults to 1.0 and laid
out 1280 px — half as much content again, on a machine that is short of exactly
that. The first run without `--force-device-scale-factor=1.5` reported 31% late
and meant nothing at all.
