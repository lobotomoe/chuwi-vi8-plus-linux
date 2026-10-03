"""Turn the ISP's planar YUV 4:2:0 frames into JPEG.

Two numbers from the driver have to be respected or the picture comes out
wrong. `bytesperline` is not always the width: at 800x600 the luma rows are 832
bytes with only the first 800 of each carrying picture, so rows are read at the
stride and then cropped. And `sizeimage` is larger than the picture -- 462848
against 460800 of pixels at 640x480 -- with the slack sitting after the planes.

The chroma planes follow the luma plane at half its stride, which holds for
every size this driver offers: 640x480, 800x600 and 1600x1200 all account for
exactly stride*h + 2*(stride/2 * h/2) bytes of picture.

There is no 3A anywhere in this driver -- no exposure, no gain, nothing but
`image_color_effect` -- so indoor frames arrive dark and stay dark. A gamma
curve on the luma plane is the only correction available, and it buys
visibility at the cost of amplifying sensor noise.
"""
import io

from PIL import Image

# Clockwise degrees -> the PIL transpose that produces them.
_ROTATIONS = {
    90: Image.Transpose.ROTATE_270,
    180: Image.Transpose.ROTATE_180,
    270: Image.Transpose.ROTATE_90,
}


def gamma_table(gamma):
    """A 256-entry lookup table for `out = in ** (1/gamma)`, as ffmpeg's eq does."""
    if gamma == 1.0:
        return None
    return [min(255, round(255.0 * (value / 255.0) ** (1.0 / gamma)))
            for value in range(256)]


class Encoder:
    def __init__(self, width, height, stride, rotate=0, gamma=1.0, quality=70):
        if rotate not in (0, 90, 180, 270):
            raise ValueError(f"rotate must be 0, 90, 180 or 270, not {rotate}")
        if stride < width:
            raise ValueError(f"stride {stride} is narrower than width {width}")
        self.width = width
        self.height = height
        self.stride = stride
        self.rotate = rotate
        self.quality = quality
        self._gamma = gamma_table(gamma)
        self._planes_bytes = (stride * height
                              + 2 * (stride // 2) * (height // 2))

    @property
    def picture_bytes(self):
        """Bytes of a frame that carry planes, ignoring the driver's trailing slack."""
        return self._planes_bytes

    def _plane(self, frame, offset, stride, width, height):
        size = stride * height
        end = offset + size
        if end > len(frame):
            raise ValueError(f"frame is {len(frame)} bytes, need {end} for a plane")
        plane = Image.frombytes("L", (stride, height), frame[offset:end])
        if stride != width:
            plane = plane.crop((0, 0, width, height))
        return plane, end

    def to_jpeg(self, frame):
        luma, offset = self._plane(frame, 0, self.stride, self.width, self.height)
        if self._gamma is not None:
            luma = luma.point(self._gamma)
        half_stride = self.stride // 2
        blue, offset = self._plane(frame, offset, half_stride,
                                   self.width // 2, self.height // 2)
        red, offset = self._plane(frame, offset, half_stride,
                                  self.width // 2, self.height // 2)

        size = (self.width, self.height)
        image = Image.merge("YCbCr", (
            luma,
            blue.resize(size, Image.Resampling.NEAREST),
            red.resize(size, Image.Resampling.NEAREST),
        )).convert("RGB")
        if self.rotate:
            image = image.transpose(_ROTATIONS[self.rotate])

        out = io.BytesIO()
        image.save(out, "JPEG", quality=self.quality)
        return out.getvalue()
