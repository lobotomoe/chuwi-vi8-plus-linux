"""Drag the dashboard up and down continuously, the way a finger scrolls it."""
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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from touchdevice import touchscreen

device = open(touchscreen(), "wb", buffering=0)
seconds = float(sys.argv[1]) if len(sys.argv) > 1 else 4.0
x = 400


def send(kind, code, value):
    device.write(struct.pack(EVENT, 0, 0, kind, code, value))


def sync():
    send(EV_SYN, SYN_REPORT, 0)


def drag(start, stop, tracking):
    send(EV_ABS, ABS_MT_SLOT, 0)
    send(EV_ABS, ABS_MT_TRACKING_ID, tracking)
    send(EV_ABS, ABS_MT_POSITION_X, x)
    send(EV_ABS, ABS_MT_POSITION_Y, start)
    send(EV_KEY, BTN_TOUCH, 1)
    send(EV_ABS, ABS_X, x)
    send(EV_ABS, ABS_Y, start)
    sync()
    # The panel itself only reports 36 times a second, so matching that rate is
    # as close to a real finger as injection gets.
    for index in range(1, 19):
        time.sleep(0.028)
        y = start + (stop - start) * index // 18
        send(EV_ABS, ABS_MT_POSITION_Y, y)
        send(EV_ABS, ABS_Y, y)
        sync()
    send(EV_ABS, ABS_MT_TRACKING_ID, -1)
    send(EV_KEY, BTN_TOUCH, 0)
    sync()


tracking = 1
until = time.time() + seconds
while time.time() < until:
    drag(900, 300, tracking); tracking += 1
    time.sleep(0.15)
    drag(300, 900, tracking); tracking += 1
    time.sleep(0.15)
print("swiped")
