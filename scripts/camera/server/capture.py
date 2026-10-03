"""Hold the capture device open for the life of the process, newest frame kept.

Why it is held open rather than opened per request, which is what "on demand"
would suggest: the ISP powers up when the device is opened, and that power-on
allocates through `alloc_pages_bulk()`, which never reclaims. Only MemFree
counts, never MemAvailable. When the allocation falls short the driver gives up
on the power-on, the PCI device's runtime PM latches `error`, and every
subsequent open returns EINVAL -- not just the one that failed. This driver
binds once per boot, so recovering from that needs a reboot.

Measured on this tablet: open failed at MemFree 96 MB with 860 MB of
MemAvailable and 977 MB of reclaimable cache, and dropping the caches did not
revive it because the error state had already latched. The same open succeeds at
119 MB. So the device is opened once, early at boot while memory is still free,
and never closed.

Frames arrive through `v4l2-ctl --stream-to=-`, which turns on `--silent`, so
stdout carries nothing but frame bytes. One flag breaks that: `--set-input`
prints its confirmation to stdout and would wedge 49 bytes into the first
frame, so selecting the input is a separate invocation.
"""
import logging
import re
import subprocess
import threading
import time

log = logging.getLogger("camera.capture")

# Only two data points bracket the real threshold -- a failure at 96 MB and a
# success at 119 MB -- so this is a margin, not a measurement.
DEFAULT_MEMFREE_FLOOR_KB = 150 * 1024

_GEOMETRY = {
    "width": re.compile(r"Width/Height\s*:\s*(\d+)/(\d+)"),
    "stride": re.compile(r"Bytes per Line\s*:\s*(\d+)"),
    "sizeimage": re.compile(r"Size Image\s*:\s*(\d+)"),
}


def memfree_kb():
    with open("/proc/meminfo") as meminfo:
        for line in meminfo:
            if line.startswith("MemFree:"):
                return int(line.split()[1])
    raise RuntimeError("/proc/meminfo has no MemFree line")


class CaptureError(RuntimeError):
    pass


class Capture:
    """A single long-lived reader of one V4L2 capture node."""

    def __init__(self, device, input_index, width, height, settle_frames=20,
                 v4l2_ctl="/usr/bin/v4l2-ctl", memfree_floor_kb=DEFAULT_MEMFREE_FLOOR_KB):
        self.device = device
        self.input_index = input_index
        self.width = width
        self.height = height
        self.settle_frames = settle_frames
        self.v4l2_ctl = v4l2_ctl
        self.memfree_floor_kb = memfree_floor_kb

        self.stride = None
        self.frame_bytes = None

        self._process = None
        self._thread = None
        self._frame = None
        self._frame_number = 0
        self._frame_at = None
        self._condition = threading.Condition()
        self._stopping = False

    def _format_args(self):
        return [f"--set-fmt-video=width={self.width},height={self.height},"
                "pixelformat=YU12"]

    def probe(self):
        """Learn the real buffer geometry from the driver instead of computing it."""
        free = memfree_kb()
        if free < self.memfree_floor_kb:
            raise CaptureError(
                f"MemFree is {free // 1024} MB, below the {self.memfree_floor_kb // 1024} MB "
                "floor; opening the ISP now risks latching its runtime PM into `error`, "
                "which needs a reboot to clear")
        log.info("probing %s with MemFree %d MB", self.device, free // 1024)

        result = subprocess.run(
            [self.v4l2_ctl, "-d", self.device, *self._format_args(), "--get-fmt-video"],
            capture_output=True, text=True, timeout=30, check=False)
        if result.returncode != 0:
            raise CaptureError(f"v4l2-ctl could not read the format back: "
                               f"{result.stdout.strip()} {result.stderr.strip()}")

        found = {}
        for name, pattern in _GEOMETRY.items():
            match = pattern.search(result.stdout)
            if not match:
                raise CaptureError(f"no {name} in: {result.stdout.strip()}")
            found[name] = match
        width, height = (int(found["width"].group(1)), int(found["width"].group(2)))
        if (width, height) != (self.width, self.height):
            raise CaptureError(f"asked for {self.width}x{self.height}, "
                               f"driver chose {width}x{height}")
        self.stride = int(found["stride"].group(1))
        self.frame_bytes = int(found["sizeimage"].group(1))
        log.info("%dx%d, stride %d, %d bytes per frame",
                 width, height, self.stride, self.frame_bytes)

    def start(self):
        if self.frame_bytes is None:
            raise CaptureError("probe() has to run before start()")

        # Its own invocation: this one talks on stdout and would corrupt frames.
        select = subprocess.run(
            [self.v4l2_ctl, "-d", self.device, f"--set-input={self.input_index}"],
            capture_output=True, text=True, timeout=30, check=False)
        if select.returncode != 0:
            raise CaptureError(f"could not select input {self.input_index}: "
                               f"{select.stdout.strip()} {select.stderr.strip()}")
        log.info("input %d selected: %s", self.input_index, select.stdout.strip())

        # No --stream-count, which means stream until the process is killed.
        # The first frames out of this sensor are a bright noise band over black
        # while exposure settles, so they are dropped before anything can read
        # them as a picture.
        self._process = subprocess.Popen(
            [self.v4l2_ctl, "-d", self.device, *self._format_args(),
             "--stream-mmap", f"--stream-skip={self.settle_frames}",
             "--stream-to=-"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
        self._thread = threading.Thread(target=self._pump, name="capture", daemon=True)
        self._thread.start()

    def _pump(self):
        stream = self._process.stdout
        buffer = bytearray(self.frame_bytes)
        view = memoryview(buffer)
        while not self._stopping:
            filled = 0
            while filled < self.frame_bytes:
                read = stream.readinto(view[filled:])
                if not read:
                    if not self._stopping:
                        log.error("capture stream ended after %d frames", self._frame_number)
                    return
                filled += read
            with self._condition:
                self._frame = bytes(buffer)
                self._frame_number += 1
                self._frame_at = time.monotonic()
                self._condition.notify_all()

    def wait_for_frame(self, after=0, timeout=10.0):
        """The newest frame once its number passes `after`. None on timeout."""
        deadline = time.monotonic() + timeout
        with self._condition:
            while self._frame_number <= after:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    return None, after
                self._condition.wait(remaining)
            return self._frame, self._frame_number

    def status(self):
        with self._condition:
            age = None if self._frame_at is None else time.monotonic() - self._frame_at
            return {
                "frames": self._frame_number,
                "last_frame_age_s": None if age is None else round(age, 2),
                "input": self.input_index,
                "width": self.width,
                "height": self.height,
                "stride": self.stride,
                "frame_bytes": self.frame_bytes,
                "capture_alive": self._process is not None and self._process.poll() is None,
                "memfree_mb": memfree_kb() // 1024,
            }

    def stop(self):
        self._stopping = True
        if self._process is not None and self._process.poll() is None:
            self._process.terminate()
            try:
                self._process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._process.kill()
