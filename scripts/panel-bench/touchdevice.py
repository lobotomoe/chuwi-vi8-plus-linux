"""Find the multitouch screen's event node, instead of hardcoding one.

The node number is not stable across machines and not even guaranteed across
boots on one machine, so every tool here asks for it rather than naming it.

The answer comes from the kernel through EVIOCGBIT rather than from parsing
/proc/bus/input/devices: that file prints its capability bitmaps as hex words
whose width is not stated anywhere in the file, so reading bit 53 out of it is a
guess about the word size that happens to work on one architecture.
"""
import fcntl
import glob
import os
import struct

EV_ABS = 0x03
ABS_MT_POSITION_X = 0x35
ABS_CNT = 0x40

# _IOC(_IOC_READ, 'E', 0x20 + EV_ABS, length), the EVIOCGBIT(EV_ABS, len) macro
# written out, because Python has no header to read it from.
_IOC_READ = 2


def _eviocgbit(event_type, length):
    return (_IOC_READ << 30) | (length << 16) | (ord("E") << 8) | (0x20 + event_type)


def _reports_multitouch(path):
    try:
        handle = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    except OSError:
        return False
    try:
        buffer = bytearray(ABS_CNT // 8)
        fcntl.ioctl(handle, _eviocgbit(EV_ABS, len(buffer)), buffer, True)
    except OSError:
        return False
    finally:
        os.close(handle)
    bits = int.from_bytes(bytes(buffer), "little")
    return bool(bits >> ABS_MT_POSITION_X & 1)


def touchscreen():
    """The first event node that reports absolute multitouch coordinates.

    PANEL_TOUCH_DEVICE overrides the search, for a machine with more than one
    touch device or a kernel that does not answer the ioctl.
    """
    override = os.environ.get("PANEL_TOUCH_DEVICE")
    if override:
        return override
    for path in sorted(glob.glob("/dev/input/event*")):
        if _reports_multitouch(path):
            return path
    raise SystemExit(
        "no multitouch device found in /dev/input/event*; "
        "set PANEL_TOUCH_DEVICE to the right node. "
        "Reading these nodes needs root or membership of the input group."
    )


if __name__ == "__main__":
    print(touchscreen())
