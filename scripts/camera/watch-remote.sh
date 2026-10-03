#!/usr/bin/env bash
#
# Watch the tablet's camera from another machine, over ssh.
#
# The tablet encodes to JPEG before anything leaves it. Raw frames are 12.4 MB/s
# at 640x480, which no remote link here will carry; the same frames as JPEG at
# quality 70 and five per second are about 130 kB/s. Encoding is software --
# this ISP has no JPEG path -- and costs roughly 20% of one of the tablet's
# cores at that rate, so raising EVERY is how you buy the CPU back.
#
# The sensor is fixed at ~28 fps and refuses VIDIOC_S_PARM, so EVERY is the only
# frame rate control there is. Keeping one stream open matters: each restart
# costs about 40 frames of exposure settling.
#
# ffplay runs on this machine; the gamma is a viewing correction for a driver
# with no 3A, and transpose undoes the tablet's mounting rotation.
#
# Press q or close the window to stop. That tears the stream down on the tablet.

set -o nounset

host=${HOST:-chuwi}
width=${WIDTH:-640}
height=${HEIGHT:-480}
# The ISP pads the buffer past the picture: 462848 against 460800 of pixels at
# 640x480. Read it from `v4l2-ctl --get-fmt-video` (Size Image) for other sizes.
frame_bytes=${FRAME_BYTES:-462848}
every=${EVERY:-6}
quality=${QUALITY:-70}
input=${INPUT:-0}
helper=${HELPER:-/tmp/yuv-to-mjpeg.py}

scp -q "$(dirname -- "${BASH_SOURCE[0]}")/yuv-to-mjpeg.py" "$host:$helper"

# The settings expand here, on this machine, which is the point: they are this
# script's variables and the tablet has never heard of them.
# shellcheck disable=SC2029
ssh "$host" "v4l2-ctl -d /dev/video0 --set-input=$input > /dev/null 2>&1
  v4l2-ctl -d /dev/video0 --set-fmt-video=width=$width,height=$height \
      --stream-mmap --stream-skip=40 --stream-count=100000 --stream-to=- 2>/dev/null \
  | python3 $helper $width $height $frame_bytes $every $quality" \
| ffplay -hide_banner -loglevel warning \
    -f mjpeg -fflags nobuffer -flags low_delay \
    -vf "transpose=1,eq=gamma=2.2:brightness=0.10,scale=$height:$width" \
    -window_title "tablet camera, input $input" -i -
