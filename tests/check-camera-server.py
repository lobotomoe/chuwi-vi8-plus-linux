#!/usr/bin/env python3
"""Checks for scripts/camera/server, the parts that do not need the hardware.

Both of these were real mistakes rather than hypothetical ones. The driver pads
its rows at some resolutions and not others, which shears the picture if the
stride is ignored; and a health check written as `age or DEFAULT` called the
camera unhealthy exactly when it had just delivered a frame, because 0.0 is
falsy.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "scripts", "camera", "server"))

from encode import Encoder, gamma_table  # noqa: E402
from handler import is_healthy  # noqa: E402

failures = []


def check(name, condition, detail=""):
    if not condition:
        failures.append(f"{name}: {detail}" if detail else name)


def synthetic_frame(stride, width, height, luma_value=200, pad_value=17):
    """One frame laid out the way the ISP lays them out, padding included."""
    rows = []
    for _ in range(height):
        rows.append(bytes([luma_value] * width) + bytes([pad_value] * (stride - width)))
    luma = b"".join(rows)
    half_stride, half_w, half_h = stride // 2, width // 2, height // 2
    chroma_rows = []
    for _ in range(half_h):
        chroma_rows.append(bytes([128] * half_w) + bytes([pad_value] * (half_stride - half_w)))
    chroma = b"".join(chroma_rows)
    return luma + chroma + chroma


# The three geometries this driver actually reports, with the sizeimage it
# returns for each. The picture must fit inside the buffer every time.
for width, height, stride, sizeimage in ((640, 480, 640, 462848),
                                         (800, 600, 832, 749568),
                                         (1600, 1200, 1600, 2883584)):
    encoder = Encoder(width, height, stride)
    check(f"{width}x{height} picture fits the driver's buffer",
          encoder.picture_bytes <= sizeimage,
          f"{encoder.picture_bytes} > {sizeimage}")

# 800x600 is the one with padded rows, so it is the one that shears when the
# stride is ignored. Every pixel must be the luma value, never the padding.
encoder = Encoder(800, 600, 832, rotate=0, gamma=1.0, quality=95)
jpeg = encoder.to_jpeg(synthetic_frame(832, 800, 600))
check("padded rows produce a JPEG", jpeg[:2] == b"\xff\xd8", repr(jpeg[:2]))

from io import BytesIO  # noqa: E402

from PIL import Image  # noqa: E402

decoded = Image.open(BytesIO(jpeg))
check("padded frame keeps its asked-for size", decoded.size == (800, 600), str(decoded.size))
greyscale = decoded.convert("L")
extremes = greyscale.getextrema()
check("no padding column bled into the picture", extremes[0] > 150,
      f"darkest pixel is {extremes[0]}, padding would show as ~17")

for rotate, expected in ((0, (640, 480)), (90, (480, 640)),
                         (180, (640, 480)), (270, (480, 640))):
    rotated = Encoder(640, 480, 640, rotate=rotate, gamma=1.0)
    size = Image.open(BytesIO(rotated.to_jpeg(synthetic_frame(640, 640, 480)))).size
    check(f"rotate={rotate} gives {expected}", size == expected, str(size))

try:
    Encoder(640, 480, 640, rotate=45)
    check("a rotation that is not a right angle is refused", False, "no error raised")
except ValueError:
    pass

try:
    Encoder(640, 480, 320)
    check("a stride narrower than the width is refused", False, "no error raised")
except ValueError:
    pass

check("gamma 1.0 builds no table", gamma_table(1.0) is None)
table = gamma_table(2.2)
check("gamma table covers the byte range", len(table) == 256, str(len(table)))
check("gamma table keeps the endpoints", (table[0], table[255]) == (0, 255),
      f"{table[0]}, {table[255]}")
check("gamma 2.2 brightens the middle", table[64] > 64, str(table[64]))
check("gamma table rises monotonically",
      all(a <= b for a, b in zip(table, table[1:])))

# The falsy-zero bug: a frame delivered this instant is the healthiest state
# there is, and it must not read as a missing frame.
check("a frame 0.0 seconds old is healthy",
      is_healthy({"capture_alive": True, "last_frame_age_s": 0.0}))
check("a fresh frame is healthy",
      is_healthy({"capture_alive": True, "last_frame_age_s": 0.4}))
check("a stale frame is not healthy",
      not is_healthy({"capture_alive": True, "last_frame_age_s": 30.0}))
check("no frame yet is not healthy",
      not is_healthy({"capture_alive": True, "last_frame_age_s": None}))
check("a dead capture is not healthy",
      not is_healthy({"capture_alive": False, "last_frame_age_s": 0.1}))

if failures:
    for failure in failures:
        print(f"FAIL {failure}")
    sys.exit(1)
print("camera server checks passed")
