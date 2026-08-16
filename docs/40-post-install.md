# After the install

Run the tuning script first — it reports before it changes anything:

```sh
sudo ./scripts/postinstall-tune.sh            # dry run
sudo ./scripts/postinstall-tune.sh --apply
```

It sets up zram swap, enables weekly TRIM, installs `iio-sensor-proxy` and caps
the journal. The rest of this page is the detail behind those, plus everything
the script deliberately leaves to you.

## Memory: zram, not swap on eMMC

2 GB is enough for a light desktop and a couple of browser tabs, and not much
more. A swap partition on eMMC turns memory pressure into a machine that stops
responding for thirty seconds at a time, and wears the flash while doing it.

Compressed swap in RAM is the right answer:

```ini
# /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
```

```sh
sudo systemctl daemon-reload
sudo systemctl start systemd-zram-setup@zram0.service
zramctl                      # should show a 1 GB zram0 in use as swap
```

A 1 GB zram device typically holds 2.5-3 GB of real pages at zstd ratios, which
is the difference between "slow" and "unusable" when a browser is open.

## Screen rotation

The accelerometer is a Bosch BOSC0200 on the `bmc150_accel` driver. systemd's
hwdb carries the correct mount matrix for this tablet — but under
`Hampoo`/`D2D3_Vi8A1`, so it only applies if your unit reports those strings.
On a unit with [unfilled DMI](01-hardware.md#some-units-ship-with-the-dmi-fields-unfilled-and-it-breaks-four-things-at-once)
nothing matches and rotation has no orientation reference; rotate by hand as
below. There is no userspace workaround for the matrix itself.

```sh
sudo apt install iio-sensor-proxy       # or: pacman -S iio-sensor-proxy
monitor-sensor                          # tilt the tablet, watch the output
```

### Rotating it once, by hand, in Lubuntu

Before any of the automatic-rotation machinery: if the desktop simply comes up
sideways and you want it fixed, that is a two-minute GUI job. Lubuntu 26.04 ships
LXQt 2.3 on **X11** — the Wayland session is not on the ISO — so the normal tool
works:

**Preferences -> LXQt settings -> Monitor Settings**, then the **Advanced** tab, and
the **Rotation** dropdown. "Inverted" is upside down.

The same thing from a terminal, which is quicker to experiment with:

```sh
xrandr --query | grep -w connected      # find the output name, e.g. DSI-1
xrandr --output DSI-1 --rotate right    # or: left, normal, inverted
```

If the touchscreen then registers touches in the wrong place, that is expected —
X rotates the picture but not the digitiser's coordinate space. Rotate the input
device with the matching transformation matrix, e.g. for `right`:

```sh
xinput set-prop "<device name>" "Coordinate Transformation Matrix" 0 1 0 -1 0 1 0 0 1
```

### Automatic rotation

GNOME and KDE Plasma rotate by themselves once the daemon is running. LXQt and
Xfce do not — they need something to act on the events. On LXQt with X11, a
minimal approach:

```sh
sudo apt install screen-rotate           # if packaged for your release
# or use iio-sensor-proxy + a small xrandr script bound to monitor-sensor output
```

### If everything starts sideways

Check this before assuming it is broken. The setup menu on this tablet renders
upright while the tablet is held in portrait, with the Windows button at the
bottom — and firmware draws at the panel's native scanout orientation. That is
consistent with a **portrait-native panel** (800x1280 scanned out, presented as
1280x800 in landscape use), which is the norm for 8" Windows tablets.

If that is what this panel is, GRUB, the kernel console and the desktop will all
start rotated 90°, because **the kernel has no panel-orientation quirk for this
model**. `drivers/gpu/drm/drm_panel_orientation_quirks.c` covers the Chuwi HiBook
(CWI514) and Hi10 Pro (CWI529) but not the Vi8 Plus, so nothing corrects it
automatically. The HiBook entry matches on `Hampoo` + `Cherry Trail CR`, which
this tablet also reports, but it is declared for a 1200x1920 panel and the lookup
compares resolution before anything else, so it cannot misfire here.

Settle it in the live session before installing:

```sh
cat /sys/class/graphics/fb0/virtual_size        # 1280,800 or 800,1280
xrandr --query | grep -w connected               # X11
```

If it is portrait-native, the fixes are, in order of preference:

```sh
# the desktop session, per-output and persistent - try this first
xrandr --output DSI-1 --rotate right

# the kernel console and GRUB, if those matter to you too
# add to GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub, then update-grub
fbcon=rotate:1 video=DSI-1:panel_orientation=right_side_up
```

Replace `DSI-1` with the connector name `xrandr` actually reports. If early boot
is garbled rather than merely rotated, `video=1280x800@60` is the separate fix
for that.

## Audio

The kernel already knows this tablet's quirks: mono speaker, headphone channels
swapped in hardware, IN2 microphone mapping. Userspace needs the matching UCM
profile, which lives in `alsa-ucm-conf`:

```sh
sudo apt install alsa-ucm-conf firmware-sof-signed    # Debian/Ubuntu
sudo pacman -S alsa-ucm-conf sof-firmware             # Arch

aplay -l          # expect a card using bytcr-rt5651
```

If you get a "Dummy Output" instead of a real card, see
[50-troubleshooting.md](50-troubleshooting.md#no-sound-only-dummy-output).

## Touchscreen

On a unit whose DMI is filled in, there is nothing to install: the kernel
matches the strings, loads `chipone_icn8505`, and pulls the controller's
firmware out of the tablet's own UEFI image.

**On the reference tablet this does not happen** — the DMI is unfilled, so the
quirk never matches and the driver probe fails for want of firmware. The
workaround, and how to get the firmware out of your own flash, are in
[01-hardware.md](01-hardware.md#touchscreen--chipone-icn8505). Confirm which
case you are in:

```sh
dmesg | grep -i icn8505
xinput list            # or: libinput list-devices
```

An on-screen keyboard is worth having if you ever use it without the hub:
`onboard` (X11) or `squeekboard`/`maliit` (Wayland).

## Wi-Fi and Bluetooth

Wi-Fi needs `linux-firmware`, which every distribution installs by default — but
on the reference tablet that was **not enough**, and `wlan0` never appeared. The
calibration data is shipped under a name derived from the DMI strings, so an
unfilled unit cannot reach it, and an `a0`-revision radio cannot reach it either.
One file copy and a reboot fix it; the recipe is in
[01-hardware.md](01-hardware.md#wi-fi--bluetooth--ampak-ap6212-broadcom-bcm43430).

It is **2.4 GHz only** — that is the BCM43430 radio, not a driver limitation,
and no amount of configuration will make 5 GHz networks appear.

Bluetooth is the same chip over a UART. Check:

```sh
sudo systemctl status bluetooth
bluetoothctl list
dmesg | grep -iE 'bluetooth|btbcm|hci_uart'
```

If `hci0` never appears, see
[50-troubleshooting.md](50-troubleshooting.md#bluetooth-does-not-appear).

## eMMC longevity

32 GB of cheap eMMC, roughly 20 GB usable after the OS. Two settings pay for
themselves:

```sh
sudo systemctl enable --now fstrim.timer
```

and `noatime` on the root filesystem, which removes one write per file read.
Edit `/etc/fstab` yourself — the tuning script deliberately does not:

```
UUID=...  /  ext4  defaults,noatime  0 1
```

Keeping `/home` on the microSD card is a reasonable way to buy space, at the
cost of SD-card speed. Do it deliberately, with a real `/etc/fstab` entry and
`nofail`, not by symlinking directories around.

## Battery and power

`upower -i $(upower -e | grep BAT)` should report a real percentage and rate.
The AXP288 fuel gauge is calibrated by the firmware, so the reported capacity of
a nine-year-old battery will be optimistic; trust the trend, not the number.

Expect noticeably worse idle drain than Windows. Cherry Trail's deep idle states
depend on firmware cooperation that Linux does not always get, and the platform
is long past anyone tuning it. `powertop --auto-tune` is worth a try; measure
before and after rather than assuming.

## Suspend

`s2idle` is the only mode available. It works, but the tablet will be warmer and
emptier after a night asleep than Windows would leave it. Shutting down is a
legitimate strategy on a machine that boots in under a minute.

## What is not going to work

The cameras. Cherry Trail routes them through the Intel ISP, and the mainline
driver in `drivers/staging/` does not produce a usable device. Do not spend an
evening on it.

## Sensible software for 2 GB of RAM

- Browser: Firefox ESR with a hard tab limit, or a Chromium with
  `--process-per-site`. Both will swap; zram is what makes that survivable.
- Terminal, editor, file manager: whatever your desktop shipped.
- Avoid Snap and Flatpak here. Both trade disk and RAM for convenience, and this
  machine has neither to spare. Prefer distribution packages.

## Verify the result

```sh
sudo ./scripts/collect-hw-report.sh
```

Compare against the report you took from the live session before installing. If
something worked then and does not now, the difference is in that diff.
