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

The accelerometer is a Bosch BOSC0200 on the `bmc150_accel` driver, and unlike
the touchscreen and Wi-Fi it does **not** depend on DMI: the driver asks ACPI for
the mount matrix first, and on this model it comes from an ACPI `ROTM` method that
is present in the firmware — read out of the published BIOS image, where it spells
the matrix out as `0 -1 0 / -1 0 0 / 0 0 1`. So there is nothing to calibrate even
on a unit with
[unfilled DMI](01-hardware.md#some-units-ship-with-the-dmi-fields-unfilled-and-it-breaks-three-things-at-once).
Confirm the matrix was picked up:

```sh
cat /sys/bus/iio/devices/iio:device0/in_accel_mount_matrix
```

It should print `0, -1, 0; -1, 0, 0; 0, 0, 1`. An identity matrix means ACPI
supplied nothing.

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

## On-screen keyboard

Not optional. There is no built-in keyboard, so without one the tablet cannot
type its own Wi-Fi passphrase, let alone a login form. On X11 — which is what
Lubuntu/LXQt gives you here — that is `onboard`; on Wayland, `squeekboard` or
`maliit`.

```sh
sudo apt install onboard
```

Installing it is not enough, and the defaults are wrong for a touch-only
machine. Four settings matter:

```sh
gsettings set org.gnome.desktop.interface toolkit-accessibility true
gsettings set org.onboard.auto-show enabled true
gsettings set org.onboard.auto-show tablet-mode-detection-enabled false
gsettings set org.onboard start-minimized true
gsettings set org.onboard.icon-palette in-use true
gsettings set org.onboard.window force-to-top true
gsettings set org.onboard.window docking-enabled false
```

- **`toolkit-accessibility`** is what makes auto-show possible at all: onboard
  learns that a text field has focus over AT-SPI, and without it the keyboard
  never appears by itself. Onboard will otherwise pop a dialog asking to enable
  it — set it here instead, so it is configuration rather than a click someone
  has to remember. Applications started *before* this was turned on will not be
  introspectable until they restart.
- **`tablet-mode-detection-enabled false`** — onboard can gate auto-show on the
  machine being in tablet mode, and this hardware has no tablet-mode switch at
  all (`/proc/bus/input/devices` lists a `Lid Switch` and nothing else of the
  kind). Leave the gate on and auto-show waits for a signal that never arrives.
- **`start-minimized` + `icon-palette`** give the behaviour you want: nothing
  covering the screen until you touch a text field, and a small floating icon to
  summon the keyboard by hand when an application does not report focus.
- **`force-to-top` + `docking-enabled false`** so it floats above a fullscreen
  application instead of trying to shrink its work area.

Autostart it per-user:

```sh
cat > ~/.config/autostart/onboard.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Onboard on-screen keyboard
Exec=onboard
Terminal=false
EOF
```

Verify by touching a text field rather than by checking that the process
exists — `pgrep onboard` succeeding tells you nothing about whether auto-show
works. The keyboard's window should be unmapped with nothing focused and
mapped once a field has focus:

```sh
id=$(xwininfo -root -children | grep '"Onboard":' | awk '{print $1}')
xwininfo -id "$id" | grep 'Map State'     # touch a field, run it again
```

### An application that started before accessibility was on never appears

This is the failure that wastes the evening. Every setting above can be
correct, onboard can be running, and the keyboard still never shows — because
onboard learns about focus only from applications registered on the AT-SPI bus,
and a program checks that bus **once, at startup**. Anything launched before
`toolkit-accessibility` was turned on stays invisible to it for the rest of its
life. List what is actually registered:

```sh
python3 - <<'EOF'
import gi
gi.require_version("Atspi", "2.0")
from gi.repository import Atspi
Atspi.init()
d = Atspi.get_desktop(0)
for i in range(d.get_child_count()):
    print(d.get_child_at_index(i).get_name())
EOF
```

If the application you care about is missing from that list, restarting it is
usually enough. Firefox needs more than that when it is started from a script
or a session file, because it reads an environment variable rather than asking
the bus again:

```sh
export GNOME_ACCESSIBILITY=1
```

Set it in whatever launches the browser, not in your interactive shell.

### Size and appearance

The defaults are a small yellowish keyboard in the top-left corner, which on a
[portrait-native panel](#if-everything-starts-sideways) is both too small to
type on and in the way. Onboard keeps separate geometry per orientation, in
pixels:

```sh
gsettings set org.onboard.window.portrait x 0
gsettings set org.onboard.window.portrait y 840        # 1280 - 440
gsettings set org.onboard.window.portrait width 800
gsettings set org.onboard.window.portrait height 440
```

Theming has a trap in it. Onboard rewrites `org.onboard.theme-settings` from
its theme file every time it starts, so colours and fonts set with `gsettings`
survive until the next restart and no further — and with
`system-theme-tracking-enabled` left at its default it picks the theme from the
desktop's GTK theme, overriding the choice entirely. The durable way is a theme
file of your own:

```sh
gsettings set org.onboard system-theme-tracking-enabled false
mkdir -p ~/.local/share/onboard/themes
cat > ~/.local/share/onboard/themes/Custom.theme <<'EOF'
<?xml version="1.0"?>
<theme format="1.3" name="Custom">
  <color_scheme>Charcoal</color_scheme>
  <key_style>flat</key_style>
  <roundrect_radius>20.0</roundrect_radius>
  <key_size>92.0</key_size>
  <key_fill_gradient>0.0</key_fill_gradient>
  <key_stroke_gradient>0.0</key_stroke_gradient>
  <key_label_font>Ubuntu</key_label_font>
  <key_label_overrides/>
  <key_shadow_strength>0.0</key_shadow_strength>
  <key_shadow_size>0.0</key_shadow_size>
</theme>
EOF
gsettings set org.onboard theme ~/.local/share/onboard/themes/Custom.theme
```

`<color_scheme>` names a `.colors` file from `/usr/share/onboard/themes/`;
`Charcoal` is neutral grey, `DarkRoom` is olive despite the name.

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
