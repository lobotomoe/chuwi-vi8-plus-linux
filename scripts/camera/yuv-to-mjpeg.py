#!/usr/bin/env python3
"""Read planar YUV 4:2:0 frames on stdin, write JPEGs on stdout.

The ISP delivers more bytes per frame than the picture needs -- 462848 for a
640x480 frame against 460800 of pixels -- so the frame size on the wire is a
separate number from the geometry, and the padding sits at the end.

Only every nth frame is encoded. The sensor runs at a fixed ~28 fps and refuses
VIDIOC_S_PARM, so dropping frames here is the only way to pick a rate, and
keeping the stream open is what avoids paying 40 frames of exposure settling
every time.
"""
import sys
import time
from PIL import Image

width, height, frame_bytes, every = (int(a) for a in sys.argv[1:5])
quality = int(sys.argv[5]) if len(sys.argv) > 5 else 70

y_size = width * height
uv_size = y_size // 4
stdin = sys.stdin.buffer
stdout = sys.stdout.buffer

index = 0
encoded = 0
started = time.monotonic()

while True:
    frame = stdin.read(frame_bytes)
    if len(frame) < frame_bytes:
        break
    index += 1
    if index % every:
        continue

    y = Image.frombytes("L", (width, height), frame[:y_size])
    u = Image.frombytes("L", (width // 2, height // 2),
                        frame[y_size:y_size + uv_size])
    v = Image.frombytes("L", (width // 2, height // 2),
                        frame[y_size + uv_size:y_size + 2 * uv_size])
    image = Image.merge("YCbCr", (y, u.resize((width, height)),
                                  v.resize((width, height))))
    image.convert("RGB").save(stdout, "JPEG", quality=quality)
    stdout.flush()
    encoded += 1

    if encoded % 50 == 0:
        elapsed = time.monotonic() - started
        print(f"{encoded} frames, {encoded / elapsed:.1f} fps out",
              file=sys.stderr, flush=True)
