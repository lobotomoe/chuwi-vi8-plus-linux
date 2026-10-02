"""One tap on the touchscreen, as the hardware would report it.

swipe.py drags continuously; this is the single short press needed to ask what
happens to the touch that wakes a dark panel. Default coordinates are the screen
corner, which on this dashboard is background: the wake press is passed through
to the page now, and a tap in the middle would toggle whatever card it landed
on, in someone's actual home.
"""
import os
import struct
import sys
import time

EVENT = "llHHi"
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
SYN_REPORT, BTN_TOUCH = 0, 0x14A
ABS_X, ABS_Y = 0x00, 0x01
ABS_MT_SLOT, ABS_MT_POSITION_X = 0x2F, 0x35
ABS_MT_POSITION_Y, ABS_MT_TRACKING_ID = 0x36, 0x39

x = int(sys.argv[1]) if len(sys.argv) > 1 else 6
y = int(sys.argv[2]) if len(sys.argv) > 2 else 6
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from touchdevice import touchscreen

device = open(touchscreen(), "wb", buffering=0)


def send(kind, code, value):
    device.write(struct.pack(EVENT, 0, 0, kind, code, value))


def sync():
    send(EV_SYN, SYN_REPORT, 0)


send(EV_ABS, ABS_MT_SLOT, 0)
send(EV_ABS, ABS_MT_TRACKING_ID, 77)
send(EV_ABS, ABS_MT_POSITION_X, x)
send(EV_ABS, ABS_MT_POSITION_Y, y)
send(EV_KEY, BTN_TOUCH, 1)
send(EV_ABS, ABS_X, x)
send(EV_ABS, ABS_Y, y)
sync()

time.sleep(0.08)

send(EV_ABS, ABS_MT_SLOT, 0)
send(EV_ABS, ABS_MT_TRACKING_ID, -1)
send(EV_KEY, BTN_TOUCH, 0)
sync()
print("tapped at %d,%d" % (x, y))
