# After the install

Run the tuning script first — it reports before it changes anything:

```sh
sudo ./scripts/postinstall-tune.sh            # dry run
sudo ./scripts/postinstall-tune.sh --apply
```

It sets up zram swap, enables weekly TRIM, installs `iio-sensor-proxy` and caps
the journal, and warns if swap is still on the eMMC. The rest of this page is the
detail behind those, plus everything the script deliberately leaves to you.

## Stop the freezes first

The script does not do this one, and nothing else on this page matters until it
is done. Without it the reference unit hung on **10 of 17 boots** — a silicon
erratum Intel marks *No Fix*, cured by taking away the three idle states it
names:

```sh
printf 'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT intel_idle.states_off=56"\n' |
  sudo tee /etc/default/grub.d/99-cstate-cht45.cfg
sudo update-grub
```

Reboot, then confirm it took — the bit numbering counts `POLL` as index 0, so an
off-by-one silently disables the wrong three states:

```sh
for s in /sys/devices/system/cpu/cpu0/cpuidle/state*; do
  printf '%s %-5s disable=%s usage=%s\n' "${s##*/}" "$(cat $s/name)" \
    "$(cat $s/disable)" "$(cat $s/usage)"
done
```

`C6S`, `C7` and `C7S` must read `disable=1` with `usage=0`; `POLL`, `C1` and
`C6N` must be untouched. Do not disable `C6N` as well — the erratum does not name
it, and losing it costs 19 °C of idle temperature.

The erratum text, the measurement behind the 10-of-17, and the second fault that
wears the same symptom are in [51-freezes.md](51-freezes.md).

## Memory: zram, not swap on eMMC

2 GB is enough for a light desktop and a couple of browser tabs, and not much
more. A swap partition on eMMC turns memory pressure into a machine that stops
responding for thirty seconds at a time, and wears the flash while doing it.

Compressed swap in RAM is the right answer, and **the script has already done
this half** — this is what it wrote, for checking against or for doing by hand if
you skipped it:

```ini
# /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
```

```sh
zramctl                      # should show a 1 GB zram0 in use as swap
```

A 1 GB zram device typically holds 2.5-3 GB of real pages at zstd ratios, which
is the difference between "slow" and "unusable" when a browser is open.

**The other half is yours, and the script says so rather than doing it** — it
would mean editing `/etc/fstab`, which the script does not touch. **Lubuntu's
installer creates a 512 MB `/swapfile` on the eMMC**, and that file keeps being
used no matter what zram does — on the reference tablet it was holding 339 MB,
with `/proc/pressure/io` reporting the machine stalled on IO 4-6% of the time.
Take it out once zram is running, so pages have somewhere to go while it is
removed:

```sh
swapon --show                       # zram0 should be listed, priority 100
sudo swapoff /swapfile
sudo sed -i '/^\/swapfile/s/^/#/' /etc/fstab
sudo rm /swapfile
```

Expect `kswapd0` to become visible in `top` afterwards: the cost of memory
pressure moves from flash IO to CPU spent compressing. That is the trade you
want on this machine, but it is not free, and the real fix is asking less of
2 GB.

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

The script has already installed `iio-sensor-proxy`; if you skipped it,
`sudo apt install iio-sensor-proxy` (or `pacman -S iio-sensor-proxy`). Either way
this is the test:

```sh
monitor-sensor                          # tilt the tablet, watch the output
```

**On the reference unit this is where it stops.** The sensor binds and the matrix
is right, but `iio-sensor-proxy` cannot get samples out of it — *"Could not find
trigger name"*, then *"Buffer did not have data within 0.5s"*. If you see that,
the rest of this section will not work either; rotate by hand
[below](#rotating-it-once-by-hand-in-lubuntu). Details and the untested
hypothesis in
[01-hardware.md](01-hardware.md#accelerometer--auto-rotation--bosch-bosc0200).

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

Check this before assuming it is broken. **This panel is portrait-native** —
`/sys/class/graphics/fb0/virtual_size` reads `800,1280` — **verified on the
unit**, which is the norm for 8" Windows tablets and matches the firmware setup
rendering upright with the tablet held in portrait.

So GRUB, the kernel console and the desktop will all start rotated 90°, because
**the kernel has no panel-orientation quirk for this model**. `drivers/gpu/drm/drm_panel_orientation_quirks.c` covers the Chuwi HiBook
(CWI514) and Hi10 Pro (CWI529) but not the Vi8 Plus, so nothing corrects it
automatically. The HiBook entry matches on `Hampoo` + `Cherry Trail CR`, which
this tablet also reports, but it is declared for a 1200x1920 panel and the lookup
compares resolution before anything else, so it cannot misfire here.

Confirm it on your own unit, and get the connector name while you are there:

```sh
cat /sys/class/graphics/fb0/virtual_size        # 800,1280 here
xrandr --query | grep -w connected               # X11
```

Worth running in the live session too, if you get there before reading this — the
answer does not change after installing, but knowing it in advance saves meeting a
sideways installer with no idea whether it is a fault.

The fixes, in order of preference:

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

### Dragging a finger does not scroll Firefox

The digitiser works, taps land, and pages still refuse to scroll. Firefox on
X11 treats touches as touches only when it is told to read XInput2; otherwise
every touch arrives as an emulated mouse button, and a drag selects text
instead of panning:

```sh
export MOZ_USE_XINPUT2=1
```

It has to be set in whatever launches the browser — a `.desktop` entry, a
session script — not in a shell you happened to type it into. Before blaming
the browser, confirm the kernel and udev agree it is a touchscreen at all:

```sh
udevadm info /dev/input/eventN | grep ID_INPUT     # ID_INPUT_TOUCHSCREEN=1
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
machine:

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
  has to remember. It has a startup-ordering trap of its own, [below](#an-application-that-started-before-accessibility-was-on-never-appears).
- **`auto-show enabled`** is the switch for the behaviour everything else here
  supports: the keyboard rising when a text field takes focus and going away
  when it loses it. Off by default.
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

Every setting above can be correct, onboard can be running, and the keyboard still never shows — because
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

Those numbers are for the 800x1280 scanout this panel actually has; `y` is
simply panel height minus keyboard height, so substitute if you changed the
keyboard size.

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

`bluetoothctl list` printing an adapter is not enough — check the address it
reports. On the reference unit `hci0` comes up `UP RUNNING` with the placeholder
`AA:AA:AA:AA:AA:AA`, which means the controller never received its firmware
patch. That, and the case where the adapter does not appear at all, are in
[50-troubleshooting.md](50-troubleshooting.md#bluetooth-appears-but-has-no-address).

## eMMC longevity

32 GB of cheap eMMC, roughly 20 GB usable after the OS. Two settings pay for
themselves. The first, `fstrim.timer`, the script has already enabled — confirm
with `systemctl is-enabled fstrim.timer`.

The second is `noatime` on the root filesystem, which removes one write per file
read. Edit `/etc/fstab` yourself — the tuning script deliberately does not:

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

**Check the charger's input current limit.** The `axp288_charger` driver can leave
it at 500 mA, which is less than this tablet draws — so it runs the battery down
while plugged in and reporting `online`:

```sh
cat /sys/class/power_supply/axp288_charger/input_current_limit   # 500000 is too low
echo 2000000 | sudo tee /sys/class/power_supply/axp288_charger/input_current_limit
```

The limit is permission, not delivery: if the supply cannot source 2 A it throttles
straight back, and `status` stays `Discharging`. Use a plain USB-A 2 A charger on an
A-to-C cable, no hub. Mechanism in
[01-hardware.md](01-hardware.md#ports-otg-and-charging-while-a-hub-is-attached).

Expect noticeably worse idle drain than Windows. Cherry Trail's deep idle states
depend on firmware cooperation that Linux does not always get, and the platform
is long past anyone tuning it. `powertop --auto-tune` is worth a try; measure
before and after rather than assuming.

## Suspend

`s2idle` is the only mode available — `cat /sys/power/mem_sleep` says so, and
there is no S3 to enable. **Not exercised on the reference unit**, so treat what
follows as the platform's reputation rather than as a measurement: the
`bmc150`/Cherry Trail maintainer's own status table scores this class of tablet
as suspending but not reaching S0i3, which means a warmer and emptier tablet
after a night asleep than Windows would leave it.

Test it yourself before relying on it, and do it while you can still reach a
power button:

```sh
systemctl suspend        # then wake it, and check nothing came back broken
journalctl -b -p warning --since "-5 min"
```

Shutting down is a legitimate strategy on a machine that boots in well under a
minute, and it is the strategy this repo can vouch for.

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

## When it feels slow, check these before blaming the GPU

The GPU is driven properly by `i915` and Mesa, and proving that first costs one
command:

```sh
glxinfo -B | grep -E 'renderer|Accelerated|direct rendering'
```

That should name `Mesa Intel(R) HD Graphics (CHV)` with `Accelerated: yes`. If
it says `llvmpipe` instead, rendering really is on the CPU. Note the GPU tops
out at 500 MHz (`/sys/class/drm/card*/gt_RP0_freq_mhz`) — that is the chip, not
a misconfiguration, and it is also why anything that makes it draw twice hurts.

Which is the first real culprit: **LXQt runs `picom`, a compositor.** On the
reference tablet it burned around 12% of the CPU redrawing a fullscreen window
that needed no compositing. Turn it off for good:

```sh
echo 'Hidden=true' | sudo tee -a /etc/xdg/autostart/picom.desktop
```

Killing it mid-session is pointless — `lxqt-session` supervises it and starts a
replacement within seconds. The change takes effect at the next login.

The second is memory, covered above: no swap on eMMC, zram instead. The third
is the browser itself, which on 2 GB is the whole budget. Measure rather than
guess — `top -o %CPU`, `cat /proc/pressure/io`, and `free -m` tell you within a
minute which of the three you are actually looking at.

## Verify the result

```sh
sudo ./scripts/collect-hw-report.sh
```

Compare against the report you took from the live session before installing. If
something worked then and does not now, the difference is in that diff.
