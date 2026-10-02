# panel-bench

Measuring how a tablet actually feels, rather than guessing. The reasoning
behind these, and the results they produced, are in
[docs/53-performance.md](../../docs/53-performance.md).

`scrot` manages about 14 captures a second on hardware this size, so nothing
outside the browser can tell 60 fps from 20. These drive the browser's own
debugging protocol and record `requestAnimationFrame` intervals from inside the
page while a real touch swipe is injected into the touchscreen's event node.

    touchdevice.py             # which event node the touchscreen is, if you are curious
    swipe.py 6                 # six seconds of drags at a real finger's event rate
    tap-inject.py 6 6          # one tap, at a coordinate of your choosing
    scrollbench.py             # frame timing during a scroll, Firefox via Marionette
    browserbench.py 9222 name  # the same, for anything speaking the devtools protocol
    taplatency.py              # how long the page takes to open a dialog after a tap
    gpuwork.py                 # whether the GPU is doing the compositing, from the kernel
    viewport.py                # whether the page still owns the whole panel
    prefs.py                   # Firefox's live prefs and their defaults
    rss.sh /snap/firefox       # resident memory and process count for one browser

## Before anything will attach

Firefox needs `MOZ_MARIONETTE=1`. Setting it on the production kiosk rather than
on a throwaway instance is the point — restarting the browser to measure it
destroys the state being measured, which is a day's worth of lesson in
[53-performance.md](../../docs/53-performance.md). Only `prefs.py` needs more
than that: the chrome context, which since Firefox 156 also wants
`-remote-allow-system-access`, and which is worth enabling for a run and not
leaving on.

Chromium needs `--remote-debugging-port=9222` and, to be comparable to anything,
`--force-device-scale-factor=1.5` to match what Firefox derives from panel DPI.

Injecting touch events needs write access to `/dev/input/event*`, so root. The
node is found by asking the kernel which device reports multitouch coordinates;
`PANEL_TOUCH_DEVICE` overrides that if the machine has more than one, and

    sudo python3 touchdevice.py

prints what it would pick.

## Reading the output

Score on **late frames**, the share of frames past 25 ms on a 59.99 Hz panel.
Median fps sits at 60 even when every sixth frame is dropped, and p95 is bimodal
here — 17 ms or 33 ms, nothing between — so neither makes a usable headline.

**Alternate A-B-A-B, not A-B-A.** The first pass of a session is reliably the
worst, and that warm-up has twice been large enough to invent an effect that did
not exist. If the second A does not return near the first A, the run has no
resolution and its result is not worth quoting.

Every run is gated on the page having moved: `travelled` in the output. An
ungated run reports a flawless 60 fps when the panel was dark, or when the swipe
was swallowed by the idle dimmer.
