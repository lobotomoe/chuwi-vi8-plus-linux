#!/usr/bin/env bash
#
# Take one frame from each camera. Run it on a freshly booted tablet, after
# build-modules.sh, and expect to reboot before running it again.
#
# Three conditions have to hold at the same time, and none of them survives a
# second attempt in the same session:
#
#   1. atomisp binds once per boot. What its CSI2 bridge attaches to the ACPI
#      devices on the first load is never torn down, so a second insmod fails
#      at probe with -EEXIST.
#   2. Both sensors need a clock, which is what the locally built ov2680 is
#      for. The stock module must not take them first: unloading it oopses the
#      kernel, so keep it out with a modprobe blacklist (see 40-post-install).
#   3. The CSS firmware is 11.5 MB of pages taken with alloc_pages_bulk(),
#      which never reclaims -- only MemFree counts, not MemAvailable. The
#      kiosk browser and the page cache have to go first, and the watchdog
#      timer has to be stopped or the browser is back within a minute.

set -o nounset
set -o pipefail

outdir="${1:-$HOME/camera-try}"
build_root="${BUILD_ROOT:-$HOME/src}"
atomisp_src="$build_root/atomisp-build/src/drivers/staging/media/atomisp"
ov2680_ko="$build_root/ov2680-build/ov2680.ko"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

log() { printf -- '--- %s\n' "$*"; }
memfree() { awk '/^MemFree/{print $2}' /proc/meminfo; }

mkdir -p "$outdir"

if lsmod | grep -q '^atomisp '; then
  log "atomisp is already loaded; it binds once per boot, so reboot first"
  exit 1
fi
if lsmod | grep -q '^ov2680 '; then
  log "the stock ov2680 holds the sensors and unloading it is not safe here"
  exit 1
fi

log "up $(cut -d' ' -f1 /proc/uptime)s, MemFree $(memfree) kB"

log "freeing memory"
systemctl --user stop kiosk-watchdog.timer 2>/dev/null || true
pkill -f 'snap/firefox' || log "no kiosk browser was running"
sleep 3
sync
echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
sleep 1
log "MemFree $(memfree) kB"

log "modules"
for m in mc videodev v4l2-async v4l2-fwnode v4l2-cci videobuf2-common \
         videobuf2-v4l2 videobuf2-vmalloc ipu-bridge intel_skl_int3472_discrete; do
  sudo modprobe "$m" || log "modprobe $m failed"
done
sudo insmod "$ov2680_ko" || log "insmod ov2680 reported the above"
# intel_atomisp2_pm parks the ISP in D3cold and has to let go of the device.
sudo rmmod intel_atomisp2_pm || log "rmmod intel_atomisp2_pm reported the above"
sudo insmod "$atomisp_src/pci/atomisp_gmin_platform.ko" || log "gmin reported the above"
sudo insmod "$atomisp_src/atomisp.ko" || log "insmod atomisp reported the above"
sleep 10

log "sensors bound"
find /sys/bus/i2c/drivers/ov2680 -maxdepth 1 -name 'i2c-*' -printf '%f\n' || true
log "inputs"
v4l2-ctl -d /dev/video0 --list-inputs 2>/dev/null | grep -E 'Input|Name' || {
  log "no capture node appeared"
  journalctl -k -b 0 --no-pager -o cat | grep -iE 'atomisp|ov2680' | tail -20
  exit 1
}

for input in 0 1; do
  v4l2-ctl -d /dev/video0 --set-input="$input" > /dev/null 2>&1 || continue
  out="$outdir/input$input.raw"
  rm -f "$out"
  # The first frames come out before exposure settles, as a bright noise band
  # over black, so skip a batch rather than reporting the first one.
  timeout 90 v4l2-ctl -d /dev/video0 --stream-mmap --stream-skip=40 \
      --stream-count=1 --stream-to="$out" > /dev/null 2>&1
  if [[ -s $out ]]; then
    log "input $input -> $out ($(stat -c %s "$out") bytes)"
  else
    log "input $input produced no frame"
  fi
done

log "the frames are 1600x1200 planar YUV 4:2:0 with padding; to view one:"
cat <<'VIEW'
    head -c 2880000 input0.raw > f.yuv
    ffmpeg -f rawvideo -pix_fmt yuv420p -s 1600x1200 -i f.yuv \
           -vf transpose=1 frame.png
VIEW

log "restoring the kiosk"
systemctl --user start kiosk-watchdog.timer 2>/dev/null || true
setsid nohup sh "$HOME/.local/bin/ha-kiosk.sh" > /dev/null 2>&1 < /dev/null &
