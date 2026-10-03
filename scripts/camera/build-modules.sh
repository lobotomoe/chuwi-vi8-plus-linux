#!/usr/bin/env bash
#
# Build the two modules this tablet needs for a working camera, against the
# installed headers rather than a replacement kernel.
#
#   atomisp.ko   the capture driver Ubuntu ships unbuilt (CONFIG_INTEL_ATOMISP
#                is unset), extracted from linux-source and built out of tree
#   ov2680.ko    the sensor driver, with one argument changed so that two
#                identical sensors can both have a clock -- see
#                patches/0004-media-v4l2-core-name-a-registered-sensor-clock-after-the-device.patch
#
# Run it on the tablet. Secure Boot has to be off or the unsigned modules will
# not load. Nothing is installed into /lib/modules; capture.sh insmods the
# built files by path.

set -o errexit
set -o nounset
set -o pipefail

build_root="${BUILD_ROOT:-$HOME/src}"
atomisp_dir="$build_root/atomisp-build"
ov2680_dir="$build_root/ov2680-build"
ksrc="/lib/modules/$(uname -r)/build"
atomisp_src="$atomisp_dir/src/drivers/staging/media/atomisp"

log() { printf -- '--- %s\n' "$*"; }

[[ -d $ksrc ]] || {
  printf 'error: no kernel headers at %s\n' "$ksrc" >&2
  exit 1
}

log "kernel source"
mkdir -p "$atomisp_dir/src" "$atomisp_dir/deb"
if [[ ! -f $atomisp_dir/src/drivers/staging/media/atomisp/Makefile ]]; then
  # linux-source-7.0.0 runs ahead of the running kernel, and with
  # CONFIG_MODVERSIONS=y a module built from the newer tree will not load. Only
  # the driver sources are taken from it; the symbol CRCs come from the headers.
  ( cd "$atomisp_dir/deb" && apt-get download "linux-source-$(uname -r | cut -d- -f1)" \
      && dpkg-deb -x ./*.deb . )
  tar -xf "$atomisp_dir"/deb/usr/src/linux-source-*/linux-source-*.tar.bz2 \
      -C "$atomisp_dir/src" --strip-components=1 --wildcards \
      '*/drivers/staging/media/atomisp/*' '*/drivers/media/i2c/ov2680.c'
fi

# atomisp's Makefile writes its includes as $(srctree)/drivers/staging/..., and
# linux-headers ships no driver sources, so the subtree has to be reachable at
# exactly that path inside the headers tree.
log "linking the subtree into the headers tree"
sudo mkdir -p "$ksrc/drivers/staging/media"
sudo ln -sfn "$atomisp_src" "$ksrc/drivers/staging/media/atomisp"

log "atomisp"
make -C "$ksrc" M="$atomisp_src" \
     CONFIG_INTEL_ATOMISP=y CONFIG_VIDEO_ATOMISP=m modules

log "ov2680 with a per-device clock name"
mkdir -p "$ov2680_dir"
cp "$atomisp_dir/src/drivers/media/i2c/ov2680.c" "$ov2680_dir/ov2680.c"
python3 - "$ov2680_dir/ov2680.c" <<'PY'
import sys

path = sys.argv[1]
src = open(path).read()
old = 'sensor->xvclk = devm_v4l2_sensor_clk_get(dev, "xvclk");'
new = ('/*\n'
       '\t * NULL, not "xvclk": with no clock provider on ACPI the core helper\n'
       '\t * registers one itself and uses this argument as its name, which is\n'
       '\t * global. Two identical sensors collide; NULL makes the helper\n'
       '\t * derive a unique name from the device instead.\n'
       '\t */\n'
       '\tsensor->xvclk = devm_v4l2_sensor_clk_get(dev, NULL);')
if new in src:
    print("ov2680 already patched")
elif old in src:
    open(path, "w").write(src.replace(old, new, 1))
    print("ov2680 patched")
else:
    sys.exit("ov2680: could not find the devm_v4l2_sensor_clk_get call")
PY
printf 'obj-m += ov2680.o\n' > "$ov2680_dir/Makefile"
make -C "$ksrc" M="$ov2680_dir" modules

log "built"
modinfo "$atomisp_src/atomisp.ko" | grep -E '^filename|^vermagic'
modinfo "$ov2680_dir/ov2680.ko" | grep -E '^filename|^vermagic'
printf '\nvermagic has to match "%s"; if it does not, the modules will not load.\n' \
       "$(uname -r)"
