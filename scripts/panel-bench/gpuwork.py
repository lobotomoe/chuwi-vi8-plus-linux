"""Does the GPU do the work when this dashboard scrolls, or does the CPU?

about:support would say, but Marionette refuses to navigate there from the
content context and widening the kiosk's permissions for one answer is a bad
trade. The kernel already knows: every DRM client's /proc/<pid>/fdinfo carries
drm-engine-<name>, a nanosecond counter of time that client spent on that
engine. If the render engine barely moves while the page is being dragged, the
compositing is happening on the CPU.

Two windows, because a single number is not a rate: one with the panel idle and
one with a finger dragging it, same length.
"""
import os
import subprocess
import sys
import time

WINDOW = 6.0


def clients():
    """Every DRM client we can see, as {client id: {engine: nanoseconds}}."""
    found = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = "/proc/%s/fd" % entry
        try:
            names = os.listdir(fd_dir)
        except OSError:
            continue
        for name in names:
            try:
                if not os.readlink("%s/%s" % (fd_dir, name)).startswith("/dev/dri/"):
                    continue
                with open("/proc/%s/fdinfo/%s" % (entry, name)) as handle:
                    text = handle.read()
            except OSError:
                continue
            if "drm-client-id" not in text:
                continue
            client_id, engines = None, {}
            for line in text.splitlines():
                key, _, value = line.partition(":")
                value = value.strip()
                if key == "drm-client-id":
                    client_id = value
                elif key.startswith("drm-engine-"):
                    engines[key[len("drm-engine-"):]] = int(value.split()[0])
            if client_id is not None:
                found[client_id] = (entry, engines)
    return found


def window(label, command=None):
    before = clients()
    process = subprocess.Popen(command) if command else None
    time.sleep(WINDOW)
    after = clients()
    if process:
        process.wait()
    print("%s:" % label)
    busy = False
    for client_id, (pid, engines) in sorted(after.items()):
        if client_id not in before:
            continue
        previous = before[client_id][1]
        for engine, value in sorted(engines.items()):
            delta = value - previous.get(engine, 0)
            if delta <= 0:
                continue
            busy = True
            try:
                comm = open("/proc/%s/comm" % pid).read().strip()
            except OSError:
                comm = "?"
            print("   %-18s %-10s %8.1f ms  %5.1f%% of the window"
                  % (comm, engine, delta / 1e6, delta / 1e7 / WINDOW))
    if not busy:
        print("   no engine time at all")


window("idle")
swipe = os.path.join(os.path.dirname(os.path.abspath(__file__)), "swipe.py")
window("scrolling", [sys.executable, swipe, str(WINDOW)])
