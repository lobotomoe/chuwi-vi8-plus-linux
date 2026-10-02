"""One definition of the scroll measurement, so two browsers can be compared.

The page-side code is written as a promise because that is what Chromium's
Runtime.evaluate wants; Marionette's callback form just wraps it.
"""

import statistics
import subprocess
import threading

FIND_SCROLLER = """
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
JSON.stringify([window.__benchScroller.tagName,
                window.__benchScroller.scrollHeight,
                window.__benchScroller.clientHeight]);
"""


def record_frames(milliseconds):
    return """
new Promise(function (resolve) {
    const target = window.__benchScroller;
    const intervals = [];
    let previous = null;
    let lowest = target.scrollTop, highest = target.scrollTop;
    const start = performance.now();
    function frame(now) {
        if (previous !== null) intervals.push(now - previous);
        previous = now;
        lowest = Math.min(lowest, target.scrollTop);
        highest = Math.max(highest, target.scrollTop);
        if (now - start < %d) requestAnimationFrame(frame);
        else resolve({intervals: intervals, travelled: highest - lowest});
    }
    requestAnimationFrame(frame);
})
""" % milliseconds


def swipe(seconds):
    thread = threading.Thread(
        target=subprocess.run,
        args=(["python3", "/tmp/swipe.py", str(seconds)],),
        kwargs={"stdout": subprocess.DEVNULL},
        daemon=True,
    )
    thread.start()
    return thread


def score(label, measured, moving):
    intervals = measured["intervals"]
    if len(intervals) < 5:
        print(f"{label:26} only {len(intervals)} frames, not a measurement")
        return
    ordered = sorted(intervals)
    # The panel runs at 59.99 Hz, so past 25 ms a vsync was missed.
    late = sum(1 for value in intervals if value > 25)
    gate = "" if not moving else (
        f"  travelled={measured['travelled']:.0f}px"
        if measured["travelled"] > 100 else "  NEVER MOVED")
    print(f"{label:26} frames={len(intervals):4d}  "
          f"fps={1000 / statistics.median(intervals):5.1f}  "
          f"median={statistics.median(intervals):5.1f}  "
          f"p95={ordered[int(len(ordered) * 0.95)]:6.1f}  "
          f"worst={ordered[-1]:6.1f}  late={100 * late / len(intervals):4.1f}%{gate}")
