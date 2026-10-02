"""Score the dashboard's scrolling from inside the page, against real touches.

Everything here is gated on the page actually having moved: a measurement taken
while the panel is dark, or while the swipe landed on nothing, looks like a
perfect 60 fps and means nothing.
"""

import statistics
import subprocess
import sys
import threading
import time

sys.path.insert(0, "/tmp")
from marionette import Marionette

SCROLLER = """
// The dashboard may scroll the document or an element inside it; take whichever
// actually has somewhere to go.
window.__benchScroller = (function () {
    let best = document.scrollingElement;
    let span = best ? best.scrollHeight - best.clientHeight : 0;
    for (const node of document.querySelectorAll('*')) {
        const reach = node.scrollHeight - node.clientHeight;
        if (reach > span && getComputedStyle(node).overflowY !== 'visible') {
            best = node; span = reach;
        }
    }
    return best;
})();
return [window.__benchScroller.tagName, window.__benchScroller.scrollHeight,
        window.__benchScroller.clientHeight, window.__benchScroller.scrollTop];
"""

POSITION = "return window.__benchScroller.scrollTop;"

RECORD_FRAMES = """
const done = arguments[arguments.length - 1];
const milliseconds = arguments[0];
const target = window.__benchScroller;
const intervals = [];
let previous = null, lowest = target.scrollTop, highest = target.scrollTop;
const start = performance.now();
function frame(now) {
    if (previous !== null) intervals.push(now - previous);
    previous = now;
    lowest = Math.min(lowest, target.scrollTop);
    highest = Math.max(highest, target.scrollTop);
    if (now - start < milliseconds) requestAnimationFrame(frame);
    else done({intervals: intervals, travelled: highest - lowest});
}
requestAnimationFrame(frame);
"""

RECORD_LATENCY = """
const done = arguments[arguments.length - 1];
const milliseconds = arguments[0];
// Scroll events for the root scroller are dispatched to the document, not to
// the <html> element that document.scrollingElement returns.
const target = window.__benchScroller === document.scrollingElement
    ? document : window.__benchScroller;
const samples = [];
let touches = 0, scrolls = 0, pending = null;
function onTouch() { touches++; if (pending === null) pending = performance.now(); }
function onScroll() {
    scrolls++;
    if (pending !== null) { samples.push(performance.now() - pending); pending = null; }
}
addEventListener('touchstart', onTouch, {capture: true, passive: true});
target.addEventListener('scroll', onScroll, {capture: true, passive: true});
setTimeout(function () {
    removeEventListener('touchstart', onTouch, {capture: true});
    target.removeEventListener('scroll', onScroll, {capture: true});
    done({samples: samples, touches: touches, scrolls: scrolls});
}, milliseconds);
"""


def swipe(seconds):
    thread = threading.Thread(
        target=subprocess.run,
        args=(["python3", "/tmp/swipe.py", str(seconds)],),
        kwargs={"stdout": subprocess.DEVNULL},
        daemon=True,
    )
    thread.start()
    return thread


def score(label, intervals):
    if len(intervals) < 5:
        print(f"{label:24} only {len(intervals)} frames, not a measurement")
        return
    ordered = sorted(intervals)
    # The panel runs at 59.99 Hz, so past 25 ms a vsync was missed.
    late = [index for index, value in enumerate(intervals) if value > 25]
    print(f"{label:24} frames={len(intervals):4d}  "
          f"fps={1000 / statistics.median(intervals):5.1f}  "
          f"median={statistics.median(intervals):5.1f}  "
          f"p95={ordered[int(len(ordered) * 0.95)]:6.1f}  "
          f"worst={ordered[-1]:6.1f}  late={100 * len(late) / len(intervals):4.1f}%")
    if len(late) > 2:
        # A stall that repeats once per gesture is the cost of starting one;
        # a stall scattered everywhere is ordinary main-thread work.
        gaps = [late[i + 1] - late[i] for i in range(len(late) - 1)]
        print(f"{'':24} late frames at {late[:12]}")
        print(f"{'':24} median gap between them: {statistics.median(gaps):.0f} frames")


def main():
    subprocess.run(["python3", "/tmp/swipe.py", "0.1"], stdout=subprocess.DEVNULL)
    time.sleep(3)

    client = Marionette()
    try:
        tag, height, visible, top = client.script(SCROLLER)
        print(f"scroller: <{tag}> {height}px in a {visible}px window, at {top}")
        if height - visible < 200:
            print("nothing to scroll; the rest would be meaningless")
            return

        score("idle", client.script(RECORD_FRAMES, asynchronous=True, args=[3000])["intervals"])

        thread = swipe(7)
        measured = client.script(RECORD_FRAMES, asynchronous=True, args=[6000])
        thread.join()
        # The swipe goes down and back up, so start and end positions match;
        # only the distance travelled in between says the page really moved.
        label = "scrolling" if measured["travelled"] > 100 else "scrolling (NEVER MOVED)"
        score(label, measured["intervals"])
        print(f"{'':24} travelled {measured['travelled']:.0f}px during the recording")

        thread = swipe(7)
        measured = client.script(RECORD_LATENCY, asynchronous=True, args=[6000])
        thread.join()
        samples = measured["samples"]
        print(f"{'page saw':24} {measured['touches']} touchstarts, "
              f"{measured['scrolls']} scroll events")
        if samples:
            print(f"{'touch to first scroll':24} n={len(samples):3d}  "
                  f"median={statistics.median(samples):5.1f}ms  "
                  f"worst={max(samples):5.1f}ms")
    finally:
        client.close()


if __name__ == "__main__":
    main()
