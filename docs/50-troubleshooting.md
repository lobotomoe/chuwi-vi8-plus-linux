# Troubleshooting

Ordered roughly by when you hit them.

## It sits on the CHUWI logo after you pick the stick

**Wait ten minutes before doing anything.** This is the single most common false
alarm on this tablet. The firmware redraws its splash screen after you select a
boot device and leaves it up for minutes, and because `Quiet Boot` is `Enabled`
by default the logo stays on screen until a loader replaces it — so the picture
in front of you carries no information at all about whether anything is running.

Owners booting Windows installers from USB put the normal wait at **5-10
minutes** (4PDA post #2719). Four minutes of logo is not a hang; it is the
middle of the normal range.

Two things make this less miserable next time:

- `Boot` -> `Quiet Boot` -> `Disabled`, so POST text replaces the logo and you
  can see progress. It does not speed anything up.
- A USB keyboard with LEDs. `Num Lock` toggling the LED means firmware is alive
  and servicing USB; a dead LED means it is not.

If ten minutes pass with no change, power off by holding the power button for
10-15 seconds and work through
[the stick-not-listed checklist](#the-tablet-does-not-list-the-usb-stick-at-all).

## A setting you changed left it stuck on the Chuwi logo

Changing the wrong item in the firmware setup — especially anything touching
video — can leave the tablet showing the logo and ignoring the keyboard. There is
no CMOS jumper and no coin cell to pull. Recovery, in order:

1. **Power on with `Volume +` held instead of Esc.** One owner recovered exactly
   this state that way and restored the values by hand (4PDA post #721). Try
   this first.
2. **Navigate blind.** Plug in a keyboard with a `Num Lock` LED — if it toggles,
   the firmware is alive and taking input even with no picture, which tells you
   the machine is worth saving. Owners have reset these tablets to defaults
   without a display this way. Our unit's key legend puts Optimized Defaults on
   **F3** and Save & Exit on **F4**; go slowly, and remember `+`/`-` change
   values while `Enter` opens submenus.
3. **HDMI.** Micro-HDMI sometimes still carries a picture when the panel does
   not, which turns a blind recovery into a sighted one.

### DNX mode: the software recovery, before you reach for a programmer

Forum threads on these tablets jump straight to "you need a programmer". That is
usually wrong. Bay Trail and Cherry Trail tablets have a fastboot variant built
into the firmware called **DNX mode**, and Hans de Goede — the kernel developer
behind most of this tablet's driver support — documented using it to recover a
tablet whose BIOS settings were corrupted so badly it would neither boot nor
enter setup. **Cherry Trail is the good case here:** the USB gadget PHY is
integrated into the SoC, so DNX works, where on many Bay Trail units it does not.

Enter it by powering on with **Volume Up and Volume Down held together**. The
tablet prints `DNX FASTBOOT MODE` on the panel — Vi8 Plus owners describe exactly
this (4PDA posts #3499 and #2932), so the mode is present on this model rather
than merely on the platform in general.

**Nobody has confirmed the full recovery on a Vi8 Plus**, and there are two known
ways it disappoints: one owner reports DNX not working on their unit (#2681), and
another could not get the tablet to enumerate on the host at all, showing as an
unknown device on two different PCs (#2935). If the host does not see it, that is
a driver problem on the PC side, not necessarily a dead tablet — try a Linux host,
where `fastboot` from `android-tools` needs no vendor driver.

Then, from a PC with `fastboot` installed and the tablet connected over USB:

```sh
fastboot flash osloader grubia32.efi      # ia32 - this tablet's firmware
fastboot boot empty-aboot.img
```

Those two files are prebuilt and still hosted:
<https://fedorapeople.org/~jwrdegoede/grub-efi-directly-enter-fwsetup/>
(`grubia32.efi`, `grubx64.efi`, `empty-aboot.img`). The GRUB build has a
`grub.cfg` compiled into it containing a single `fwsetup` command, so running it
reboots the tablet straight into its own BIOS setup.

The trick that makes it usable: **swap the USB cable for the OTG adapter and
keyboard while it is rebooting.** If the tablet is left on the plain USB cable
through the reboot you will get the setup menu with no working input. Once you
are in, `load setup defaults`, then save and exit.

Only if DNX mode itself does not come up is the answer disassembly and reflashing
the SPI chip with a **1.8 V** CH341A programmer — the common 3.3 V ones will not
do. That is the reason
[20-uefi-setup.md](20-uefi-setup.md#most-of-this-menu-is-hidden--turn-it-on-first)
tells you to change Secure Boot and nothing else.

### Never disable USB in the firmware setup

Worth its own warning, because it is a one-way door and `SHOW ALL ITEM` puts the
switch in plain sight. A Vi8 Plus owner did exactly this in January 2016:

> *"I DEACTIVATED the USB in the bios hence i couldn't plug anything on the
> tablet or it would crash, i couldn't reset the bios either because i couldn't
> plug ANY keyboard as they are USB. The tablet was lost."*
> — techtablets forum, post #23355

The only input this tablet has is a USB keyboard. Turning USB off removes the
means of turning it back on. They recovered only because Windows still booted and
could flash a stock firmware image from inside it — which is not an option once
you have replaced Windows with Linux. DNX mode above is the route that does not
depend on having a working OS.

## The tablet does not list the USB stick at all

**First, find out whether the firmware sees the stick as a device at all.** These
are two different faults with opposite fixes, and the setup menu will tell you
which one you have:

`Advanced` -> `USB Configuration` -> the `USB Devices:` line

```
USB Devices:  1 Drive, 1 Keyboard, 1 Mouse, 2 Hubs      <- seen; read on below
USB Devices:  1 Keyboard, 1 Mouse, 2 Hubs               <- not seen at all
```

If the stick is **not listed there**, nothing about its filesystem, partitioning
or bootloader matters — rebuilding it will change nothing. Skip to
[the stick is not enumerated](#the-stick-is-not-enumerated-at-all) below.

If it **is** listed but still absent from `Boot Override`, the loader is the
problem and the rest of this section applies.

The single most common cause is then a missing `bootia32.efi`. Put the stick back
in your computer and check:

```sh
ls /Volumes/VI8PLUS/EFI/BOOT/          # macOS
ls /media/$USER/VI8PLUS/EFI/BOOT/      # Linux
dir E:\EFI\BOOT\                       # Windows
```

You need `bootia32.efi` there. `bootx64.efi` alone is invisible to this
firmware.

Then, in order:

1. **Secure Boot is still enabled.** Re-enter setup and confirm it saved.
2. **The stick was written in DD mode.** ISO9660 is read-only; you cannot have
   added `bootia32.efi` to it. Rebuild it —
   [02-boot-problem.md](02-boot-problem.md#why-the-stick-cannot-simply-be-dd-ed).
3. **The hub was attached after power-on.** Power off fully, plug in, power on.
4. **Windows Fast Startup.** `powercfg /h off` in Windows, then a real shutdown.
5. **A picky partition type.** Rebuild from Linux with the partition typed
   `ef00`, or with Rufus (GPT / UEFI non-CSM).

## The stick is not enumerated at all

`USB Configuration` lists the keyboard and the hub but no drive. The firmware is
not seeing the device, so it never gets as far as reading a partition table.

**A lit activity LED on the stick does not mean it enumerated** — that is bus
power, which arrives long before any USB transaction succeeds.

In order:

1. **Try a different hub. This is the one that actually happened.** A USB-C hub
   that passed a keyboard and a mouse through perfectly never presented the stick
   to the firmware at all — no `Drive` on the `USB Devices:` line, in any of its
   ports, with the stick's own activity LED lit the whole time. Swapping to
   another hub made the same stick appear immediately. Nothing about the stick,
   its filesystem or its bootloader was involved. If HID works but storage does
   not, suspect the hub before anything else.
2. **Try a USB 2.0 stick.** This tablet's port is USB 2.0 and its firmware dates
   from 2015 with a single XHCI controller. A USB 3.0 stick behind a USB 3.0 hub
   on a USB 2.0 host is a combination old firmware can fail to enumerate, while
   low-speed HID devices on the same hub keep working — which makes it look like
   the stick is at fault when it is the negotiation.
2. **Power the hub.** With a hub attached this tablet runs on battery, and a stick
   draws far more than a keyboard. If your hub has a Type-C Power Delivery input,
   put a charger in it.
3. **Remove anything you do not need**, starting with the mouse. The volume keys
   and a keyboard are enough for everything in this guide.
4. **Try the hub's SD card reader** if it has one, with a microSD carrying the
   install image. A card reader presents as USB mass storage, so unlike the
   tablet's own microSD slot — which the firmware is
   [not known to boot from](01-hardware.md#storage) — it is an ordinary bootable
   USB device as far as the firmware is concerned.
5. **Try a different hub**, ideally a plain USB 2.0 one.

Confirm each attempt in `USB Configuration` rather than by trying to boot: the
device appearing on the `USB Devices:` line is the signal, and it takes seconds
instead of a ten-minute wait on the splash screen.

## The stick boots to a `grub>` prompt instead of a menu

`bootia32.efi` started but could not find `/boot/grub/grub.cfg`. That means
either the copy is incomplete, or you used an image that has no GRUB menu at all
(the Arch ISO uses systemd-boot and has none — but it also ships its own
`BOOTIA32.EFI`, so you should not be here).

From the prompt you can find and load it manually:

```
grub> ls
grub> ls (hd0,gpt1)/boot/grub/
grub> configfile (hd0,gpt1)/boot/grub/grub.cfg
```

Then rebuild the stick properly.

## The installer boots but the screen is black or garbled

Edit the GRUB entry (press `e`) and append to the `linux` line:

```
video=1280x800@60
```

If that does not do it, work down this ladder, least destructive first:

```
video=1280x800@60          # tell the driver the mode, keep acceleration
i915.modeset=0             # the Cherry Trail-specific one
nomodeset                  # sledgehammer: a picture, but no acceleration
```

**Do not reach for safe graphics first, and do not conclude you have a display
problem from a black screen alone.** This page previously said the plain "Try or
Install" entry black-screens this tablet and that safe graphics was the fix. That
was wrong, and the mistake is worth describing because it is easy to repeat.

The plain entry did black-screen, repeatedly, while safe graphics reached a
desktop — which looks like conclusive evidence about the display driver. It was
not. The live USB was dropping off the bus and taking the root filesystem with
it (see [above](#a-usb-30-stick-cannot-hold-a-link-here)); the two entries differ
in how long they take to get to the point of needing it, which is enough to make
a storage fault look like a graphics fault. With the live filesystem moved to the
microSD card, **the plain entry boots to a working LXQt desktop and runs the
installer through to a finished system.** — **verified on the unit**

So: `nomodeset` is not required on this hardware, and taking it "just to be safe"
costs you acceleration for nothing. Rule out the medium first — the
[kernel log](13-split-media.md#boot-it) says which one you are looking at.

### Why it happens

Cherry Trail drives the panel over **MIPI DSI**, not eDP. `i915` brings such a
panel up in its `vlv_dsi` path, toggling the panel-enable and backlight-enable
GPIOs according to sequences described in the firmware's VBT. On Bay and Cherry
Trail tablets those sequences routinely do not work: on some the backlight comes
on and the LCD stays black, on others the backlight never comes on. Hans de Goede
— the same developer behind this tablet's touchscreen and audio support — has
been [patching exactly this](https://patchwork.kernel.org/project/linux-acpi/patch/20191129185836.2789-3-hdegoede@redhat.com/)
for years.

`nomodeset` works around it by never letting the kernel touch the display
pipeline at all: it keeps using the framebuffer the firmware set up during POST.
That is also why the desktop is slow afterwards — there is no acceleration,
because there is no driver.

It is **not** the touchscreen. An input device cannot affect display output, and
this catches people out.

### Getting acceleration back

Worth doing after the install rather than during it, where a failed attempt costs
one reboot instead of a re-install:

```
video=1280x800@60                      # state the mode explicitly
acpi_backlight=vendor acpi_osi=Linux   # when the panel renders but is unlit
```

From the wider Bay/Cherry Trail community: forcing a mode change from GRUB with
`set gfxpayload=800x600` helps on some units, and a session that came up blind
can sometimes be recovered with
`xrandr --output DSI-1 --off && xrandr --output DSI-1 --auto`.

**This is worth attempting, because KMS is known to work on this exact model.** Hans
de Goede's install notes for the Vi8 Plus write to
`/sys/class/backlight/intel_backlight` and then start a graphical session — that sysfs
node only exists when `i915` has come up with modesetting, so `nomodeset` is a
workaround here and not the ceiling. See
[90-references.md](90-references.md#hans-de-goedes-notes-on-this-exact-tablet).

**One free diagnostic:** shine a light across the screen while it is "black". If
the interface is faintly visible, the panel is rendering and only the backlight
is off — an `acpi_backlight` problem, fixable while keeping acceleration. If
there is genuinely nothing, the panel itself is not lighting up and `nomodeset`
is the answer.

## The live session boots, then slowly falls apart

Symptoms, in this order: the desktop comes up and works, the installer quits on its
own without an error, windows stop repainting, and eventually the screen goes black
and nothing — not even Ctrl+Alt+Del — gets a response.

That is not a crash and not a graphics fault. It is what a running system looks like
when its **root filesystem disappears**. Anything already in page cache keeps working
for a while; the first process that has to read from the squashfs blocks forever, and
the session dies component by component over several minutes.

### A USB 3.0 stick cannot hold a link here

This is the cause seen on the unit this guide was written against, and it is worth
checking first because the fix costs nothing.

The tablet's single Type-C port is wired for USB 2.0. Give it a USB 3.0 stick — through
a USB 3.0 hub, which is what most Type-C hubs are — and the two try to come up at
SuperSpeed anyway. The link does not hold, the device resets in a loop, and the
mass-storage driver never binds. What that looks like in `dmesg`:

```
usb 2-1.1: reset SuperSpeed USB device number 3 using xhci_hcd
usb 2-1.1: reset SuperSpeed USB device number 3 using xhci_hcd
```

Bus 2 is the SuperSpeed side. A device that appears there and only ever gets reset is
the one to suspect — and there will be no matching `usb-storage`/`sd` line anywhere
after it. Meanwhile a keyboard on bus 1 at high speed keeps working perfectly, which
is what makes this so misleading: **input works, so the port is clearly in host mode,
so surely USB is fine.**

It fails intermittently, which is the other reason it is hard to recognise. The same
stick in the same hub may enumerate correctly on one boot and be reset in a loop on
the next, or drop out an hour into a working session. — **verified on the unit**

Fixes, cheapest first:

- **Move the stick to a different port on the hub.** Enough on its own sometimes; it
  was on this unit.
- **Put a USB 2.0 extension cable between hub and stick.** A USB 2.0 A-to-A cable
  physically has no SuperSpeed conductors, so the link is forced down to high speed —
  the mode this port actually supports.
- **Use a USB 2.0 hub, or a USB 2.0 stick.** The durable answer.
- **Put the live filesystem on the microSD card instead.** The firmware cannot boot
  from SD, but it does not have to: it only reads GRUB, the kernel and the initrd off
  the USB, using its own USB stack, and that works. Once the kernel is up, casper will
  find the live filesystem on the SD card, and USB stops mattering for the rest of the
  session — including the entire install.

Note that the last one is the only fix that also protects the **install itself**, which
is 30–60 minutes of continuous reading from that stick.

### The other candidate: the port dropping out of host mode

`extcon_intel_int3496` decides whether the port is host or device, and on this
generation it can flip back to device mode after boot, taking the live USB with it.
Hans de Goede hits this on his own Vi8 Plus and boots with:

```
modprobe.blacklist=extcon_intel_int3496 gpiolib_acpi.run_edge_events_on_boot=0
```

Note the spelling of `blacklist`. His notes have a typo there (`blaclist`), and a
misspelled kernel parameter is silently ignored — you get the same failure and
conclude the workaround does not help.

Both parameters are current — `extcon-intel-int3496` is still built
([drivers/extcon/Makefile](https://github.com/torvalds/linux/blob/master/drivers/extcon/Makefile)),
and `run_edge_events_on_boot` still lives in `gpiolib_acpi`
([gpiolib-acpi-quirks.c](https://github.com/torvalds/linux/blob/master/drivers/gpio/gpiolib-acpi-quirks.c),
`0=no, 1=yes, -1=auto`). — **not reproduced here**: on this unit the port kept host
mode throughout (the keyboard never stopped working), so the SuperSpeed link above was
the actual fault. Reach for these parameters only once you have ruled that out.

**Telling any of this apart from a display problem** costs one boot: append a bare `3`,
which starts the session in text mode. A text login prompt means the system is alive
and the fault was in the display path. Nothing at all means you are in this section.

A weak ten-year-old battery produces a similar picture — the tablet browns out under
load — and the fix overlaps: keep a charger on a 5 V-passing hub. See
[01-hardware.md](01-hardware.md#ports-otg-and-charging-while-a-hub-is-attached).

## `Unable to find a medium containing a live file system`

The initramfs could not find the live filesystem. On this tablet that almost always
means the USB stick is not there — see
[the section above](#a-usb-30-stick-cannot-hold-a-link-here).

It is also the best diagnostic opportunity you get on this machine, because it hands
you a shell. At the prompt:

```
Attempt interactive netboot from a URL?
yes no (default yes): no
```

Answer **`no`** and you land in a BusyBox `(initramfs)` shell with a working keyboard.
From there:

```sh
cat /proc/partitions          # is the stick there at all? look for sda
dmesg | grep -i usb | tail -25
```

Unplug and replug the stick, wait a few seconds, and run `cat /proc/partitions` again —
udev is running, so hotplug works here.

**`exit` does not make it try again.** This is worth knowing before you waste a cycle
on it: leaving the shell resumes the boot script where it stopped, which is at
`run-init`, and since nothing ever got mounted you get

```
No init found. Try passing init= bootarg.
```

and drop straight back to the same shell. Once the stick shows up in
`/proc/partitions`, reboot (`reboot -f`) and boot again — the search only runs from the
start of boot. — **verified on the unit**

## The install finished and now nothing boots

Expected on Ubuntu and Xubuntu: their installer writes a 64-bit GRUB this
firmware cannot execute. Boot the live stick again and:

```sh
lsblk
sudo mount /dev/mmcblk0p2 /mnt
sudo ./scripts/postinstall-grub-ia32.sh --root /mnt
```

Add `--offline-debs /path/to/payload` if the live session has no network; build
that directory beforehand with `scripts/fetch-offline-payload.sh`.

If the script reports that it wrote everything and the tablet still goes
straight to the firmware menu, the firmware is ignoring NVRAM boot entries. The
`--removable` install the script also performs puts a bootloader at
`\EFI\BOOT\bootia32.efi` in the eMMC's ESP, which is the path such firmware
falls back to. Check it landed:

```sh
sudo mount /dev/mmcblk0p1 /mnt2 && ls /mnt2/EFI/BOOT/
```

## `grub-install` says "cannot find EFI directory" or "i386-efi not found"

- "cannot find EFI directory": the ESP is not mounted at the path you passed.
  Mount it (`mount /dev/mmcblk0p1 /mnt/boot/efi`) and pass `--esp`.
- "i386-efi not found": `grub-efi-ia32-bin` is not installed in the *target*
  system. That is what `scripts/postinstall-grub-ia32.sh` installs; if you are
  doing it by hand, `apt install grub-efi-ia32-bin` inside the chroot.

## No sound, only "Dummy Output"

Check the machine driver bound at all:

```sh
dmesg | grep -iE 'bytcr|rt5651|sof'
aplay -l
cat /proc/asound/cards
```

- Driver missing entirely: install `firmware-sof-signed` (Debian/Ubuntu) or
  `sof-firmware` (Arch) and reboot.
- Card present but silent: the UCM profile is missing. Install
  `alsa-ucm-conf`, then `alsamixer` and unmute/raise the speaker channel — the
  kernel quirk for this tablet declares a mono speaker, so there is one output
  slider, not two.
- Headphones swapped left/right: the kernel compensates
  (`BYT_RT5651_HP_LR_SWAPPED`) — but only if the DMI quirk matched, which on a
  unit with unfilled DMI it did not. Check with `dmesg | grep -i 'quirk.*enabled'`
  and force it if needed; the bitmask is derived in
  [01-hardware.md](01-hardware.md#forcing-the-quirk-by-hand). If the DMI *is*
  filled in and they are still swapped, you are on a kernel older than the quirk.
- One speaker but both channels audible: that is the normal, working state here,
  not a symptom. See the note in
  [01-hardware.md](01-hardware.md#audio--realtek-rt5651).

## `monitor-sensor` says "Not Authorized: Sensor claim not allowed"

Nothing to do with the accelerometer — you are running it over SSH. `iio-sensor-proxy`
asks polkit for `net.hadess.SensorProxy.claim-sensor`, and the shipped policy is:

```xml
<allow_any>no</allow_any>
<allow_inactive>no</allow_inactive>
<allow_active>yes</allow_active>
```

An SSH login is an *inactive* session as far as logind is concerned, so the claim is
refused before the sensor is ever touched. Confirm which side you are on:

```sh
loginctl show-session "$XDG_SESSION_ID" -p Active -p Remote -p Type
```

Run `monitor-sensor` from a terminal in the tablet's own desktop session instead. To
test the hardware itself without the daemon or polkit in the way — which does work
over SSH — read the raw channels and tilt the tablet between runs:

```sh
cat /sys/bus/iio/devices/iio:device0/name          # expect bmc150_accel
grep -H . /sys/bus/iio/devices/iio:device*/in_accel_*_raw
```

Note that even in a local session the orientation *labels* will be wrong on a unit
with unfilled DMI, because the mount matrix in systemd's hwdb is keyed on the same
DMI strings. See [01-hardware.md](01-hardware.md#accelerometer--auto-rotation--bosch-bosc0200).

## There is no network icon in the tray

Check whether Wi-Fi actually works before touching anything, because the icon and
the radio are separate problems and the icon is the trivial one:

```sh
nmcli device wifi list
```

Networks listed means the radio, the driver and NetworkManager are all fine and only
the applet is missing. Connect from the shell and carry on:

```sh
nmcli device wifi connect "Your SSID" --ask
```

`--ask` prompts for the passphrase instead of taking it as an argument, which keeps
it out of `~/.bash_history` and out of the process list.

Lubuntu's applet is `nm-tray`. Start it, and if that works add it under
**Preferences -> LXQt settings -> Session Settings -> Autostart**:

```sh
nm-tray &
sudo apt install nm-tray        # if the command is not found
```

If the list is empty instead:

```sh
nmcli device status             # wlan0 "unmanaged"? NetworkManager started before the driver
sudo systemctl restart NetworkManager
rfkill list                     # "Soft blocked: yes"?
sudo rfkill unblock wifi
```

And if there is no `wlan0` at all, it is the firmware, not the applet — see
[01-hardware.md](01-hardware.md#two-chip-revisions-ship-in-this-model-and-they-want-different-nvram).

## Bluetooth does not appear

```sh
dmesg | grep -iE 'bluetooth|btbcm|hci_uart|BCM43430|BCM4343'
```

The chip is attached over a UART, which on Cherry Trail depends on the serdev
driver binding to an ACPI device. It usually works; when it does not, it is
almost always the missing `.hcd` patch file. Read the exact filename the kernel
asked for out of that `dmesg` output rather than guessing — `btbcm` tries several
names and the one it settles on depends on your chip revision.

**The `.hcd` is not in `linux-firmware`.** It ships in a separate package:

```sh
sudo apt install bluez-firmware
ls -l /usr/lib/firmware/brcm/BCM43430A1.hcd*
```

That covers an **a1** unit. An **a0** unit wants `brcm/BCM4343A0.hcd`, which no
Debian or Ubuntu package provides — check which revision you have with the
command in
[01-hardware.md](01-hardware.md#two-chip-revisions-ship-in-this-model-and-they-want-different-nvram)
before hunting for a file that is not there.

Wi-Fi and Bluetooth share the antenna path on this module, so heavy Bluetooth
use degrades 2.4 GHz Wi-Fi throughput. That is the hardware.

## Random freezes

A long-standing complaint on Chuwi's Atom tablets. It happens on the reference
unit too.

**Start by recording, not by guessing.** A hard hang gives the kernel no chance
to flush anything, so the journal simply stops and every theory below looks
equally plausible from the wreckage. One evening of reading journal tails
produced three incompatible explanations and no way to choose between them.

```sh
sudo ./scripts/watch-freeze.sh --install    # samples from boot, flushed to disk
# ... wait for a freeze, power-cycle, then:
sudo ./scripts/watch-freeze.sh --report
```

It writes power, thermals, load, CPU frequency, GPU clock and per-C-state entry
counts every few seconds and forces each line to disk before taking the next, so
the final line is the state the machine was in when it died. That single line
distinguishes most of what follows: a current spike, a thermal climb, and a jump
into a deep idle state look nothing alike.

**Then try to provoke one, rather than waiting.** Every freeze so far has cost a
couple of hours of idling, which is why several theories have been argued and none
settled. `stress-freeze.sh` loads one subsystem at a time while the recorder
watches:

```sh
sudo ./scripts/stress-freeze.sh --list
sudo ./scripts/stress-freeze.sh --phase idle     # the control, first
sudo ./scripts/stress-freeze.sh --phase cpu
sudo ./scripts/stress-freeze.sh --phase wifi
```

**One phase at a time is the whole design, not a limitation.** A combined run that
ends in a freeze is consistent with every hypothesis on this page and separates
none of them, so there is no `--phase all` and asking for one is an error. Two
other things are built in for the same reason: the run aborts above 80 °C, so a
thermal shutdown can never be written up afterwards as a freeze, and `--phase idle`
loads nothing at all — if the tablet dies during *that*, none of the other phases
prove anything.

**What the phases have returned so far**, ten minutes each on the reference
tablet, hottest zone in brackets:

| Phase | Result | Peak |
| --- | --- | --- |
| `idle` (control) | survived | 59 °C |
| `cpu` | survived | 67 °C |
| `mem` | survived | 67 °C |
| `wifi` (scan) | survived | — |
| `gpu` | void — the load never started, see below | — |

The control surviving is what makes the rest mean anything: load was a real
variable in those runs, not a label on a machine that happens to stay up. And
`cpu` and `mem` surviving retires a whole family of theories at once — a tablet
that holds 67 °C through every core at full load and 75 % of RAM under `--verify`
is not freezing because it is too weak, too hot, or short of memory.

That is why `wifi-reload` exists, and it is the phase to run if you only run one.
The `wifi` phase scans on an already-associated radio and changed nothing;
`wifi-reload` unloads `brcmfmac` and brings the whole stack back up on a loop,
which is the event every photographed boot freeze actually sits on. It needs root
and it drops the network every cycle, so over SSH on wireless it must be launched
detached — and the `sudo -v` first is not optional:

```sh
sudo -v
sudo setsid ./scripts/stress-freeze.sh \
  --phase wifi-reload </dev/null &>/tmp/reload.log &
```

A backgrounded `sudo` whose credential timestamp has expired reads the password
from the terminal, takes `SIGTTIN` and stops before it ever execs the script. The
symptom is nothing at all: no run, no marker in the stress log, and an empty
`/tmp/reload.log` — the shell truncated it with the redirect and no process ever
wrote to it. Easy to read as "the script is broken" when nothing has run yet.

**`modprobe -r brcmfmac` fails with "Module brcmfmac is in use", and
NetworkManager is not why.** That was the first guess on this tablet; stopping
NetworkManager, `wpa_supplicant` and the interface itself changed nothing. The
holder is `brcmfmac_wcc`:

```
--- refcnt 1
--- module holders [brcmfmac_wcc]
--- lsmod brcmfmac_wcc           12288  0
--- lsmod brcmfmac              544768  1 brcmfmac_wcc
```

Kernel 6.x split the per-vendor firmware and regulatory hooks out of `brcmfmac`
into their own module, which then registers back into it. `modprobe -r` does not
walk that edge — it removes what a module depends *on*, not what depends on it —
so the chain has to come apart from the top:

```sh
sudo modprobe -r brcmfmac_wcc   # takes brcmfmac and brcmutil with it
sudo modprobe brcmfmac          # asks the kernel for its vendor module again
```

`stress-freeze.sh` reads `/sys/module/brcmfmac/holders/` and removes whatever is
listed rather than naming `brcmfmac_wcc`, since the vendor module differs by chip.
Note the second command is enough to restore the radio: `brcmfmac` requests its
own vendor module when the chip probes, which is also what makes the phase a
faithful copy of the boot sequence rather than an approximation of it.

**A load test that passes without loading anything is worse than no test**, and
this one did it once. The `gpu` phase looped `glmark2 || sleep 1`, `glmark2` could
not reach the display, and the loop spun on the error for ten minutes and reported
"survived 600s". Nothing in the run said otherwise; the arithmetic did, afterwards.
The phase peaked 63 °C against 59 °C for the idle control, on a tablet where the
screensaver alone is worth 15 °C, and the recorder had `gpu=200MHz` — the idle
clock — on every line. Two things changed as a result: every load now runs until
the script kills it, and the sampling loop checks each interval that the load is
still alive and fails the run the moment it is not. That check has since caught a
second false pass, so treat any earlier `SURVIVED` line without a `hottest=` field
as unproven and run it again.

It refuses to run unless the recorder service is active, because a freeze caught
without a record is a wasted freeze and a wasted power cycle.

`--report` marks only the genuine freezes `DIED HERE`. It knows the difference
because each session records the boot id and writes an end marker when it is
asked to stop, so restarting the recorder, shutting the machine down and the
machine vanishing underneath it are three distinguishable endings rather than one
ambiguous gap. Worth insisting on: the first reading of this log counted two
`systemctl restart`s as crashes.

**They cluster at the tail of boot.** Five boots on that tablet ended without a
shutdown sequence, three of them after **21, 22 and 23 seconds** against a normal
17-second boot. Reading the tail of each shows a different last service every
time — `gpu-manager` and `logind`, `bluetoothd` starting its SDP server,
`iio-sensor-proxy`, and twice `wpa_supplicant` with `NetworkManager`. No service
is common to them. A sixth died 19 minutes in while idle, and the owner reports
it freezing on the screensaver. — **observed on the unit**

**Three of those five are the moment a radio powers up** — Bluetooth once, Wi-Fi
twice. That is a current peak, not an idle moment, and it is why the charger is
item 1 below. Read that alongside
[what the recorder caught](#what-the-recorder-actually-caught), which weakens it.

The reading to be careful with is the popular one. Every search for this points
at deep C-states and `intel_idle.max_cstate=1`, and the erratum behind that is
**VLP52, which is Bay Trail only**: the patch written for it matches a single
model, `case 0x37: /* BYT */`, and was never merged. This tablet reports
`family:model:stepping 0x6:4c:3`, and `0x4c` is Airmont — the Cherry Trail core,
a different generation. So the famous fix rests on an erratum this CPU does not
have. Cheap to try, but not the thing to try first. — **verified** by reading the
patch and the CPU model off the unit

What the timing does rule out is screen blanking, which cannot explain a freeze
22 seconds in with the boot log still lit on the panel.

Worth knowing what it is *not*, since all of these were checked here: no OOM,
swap untouched with 1.1 GiB still available, and no I/O or eMMC error anywhere in
the journal. Memory pressure and failing storage both look plausible from the
outside and neither left a trace.

### What the recorder actually caught

Five session ends on the reference unit, two on the desktop and three during
boot. — **measured on the unit**

**The battery voltage never sags.** `bv=` sits between 4206 and 4259 mV in every
sample of every session, including the last one written before each desktop
freeze, with the charger negotiating 2 A and the pack at 99 %. A supply that
collapses under a current peak should show up here, and it does not. Two caveats
keep this from closing the question: the recorder samples every 5 s and a
brownout is a millisecond event, and at the boot freezes there is **no power data
at all** — `axp288_fuel_gauge` has not probed yet at 16-23 s, so those lines read
`bat=?% bst=none`.

**The panel stays lit with the last frame intact.** Every photographed freeze
shows the boot log or the screensaver still on screen, backlight on. A supply
collapse takes the backlight with it, and a thermal trip powers the machine down
rather than parking it on a frame. What that picture does fit is a lockup: the
display controller keeps scanning out the framebuffer it was given while nothing
else advances. — **observed**, and it argues against both the charger and the
thermal readings below being the whole story.

**The six thermal zones, and which of them lies.** — **read off the unit**

```
thermal_zone0  acpitz           43.6 C
thermal_zone1  INT3400 Thermal  20.0 C
thermal_zone2  STR0             43.6 C
thermal_zone3  PNIT             59.0 C
thermal_zone4  soc_dts0         53.0 C
thermal_zone5  soc_dts1         50.0 C
```

`INT3400` is the DPTF policy device. It has no sensor behind it and reports a
constant 20 °C. `soc_dts0` and `soc_dts1` are the SoC's own digital thermal
sensors — the closest thing here to a die temperature. `PNIT` reads about 6 °C
above them and is the hottest zone, which matters because the recorder used to
log the maximum: every `temp=` in the older logs is `PNIT`, and every `temp=20C`
in a first sample is `INT3400` being the only zone registered that early rather
than a cold machine. It now records all six, with a `--- thermal zones` line
naming them.

**And the trip points say the freezes are not thermal.** — **read off the unit**

```
acpitz    critical 100.0 C
STR0      passive 61.05 C   hot 82.05 C   critical 85.05 C
PNIT      passive 85.05 C
soc_dts0  passive 0 C, 0 C      (unprogrammed)
soc_dts1  passive 0 C, 0 C      (unprogrammed)
```

Two of `STR0`'s passive trips read `-274000`, which is below absolute zero and
means unset, as do the SoC sensors' zeroes. What is set is a throttling trip at
61 °C and a critical one at 85 °C on the skin sensor. The hottest reading ever
recorded here is 70-71 °C on `PNIT`, whose own trip is at 85 °C, so nothing has
come close to a critical trip.

That matters more than the margin, because of what a critical trip *does*: the
thermal core powers the machine off. A tablet that overheated past a trip would
be found switched off, not sitting on a lit frame of the boot log. Overheating
would have to hang the hardware silently *below* every configured trip to explain
what is actually seen, which is a much larger claim than "it runs warm".

**The screensaver costs 15-20 °C.** Idle with `xscreensaver` running: 67-71 °C,
`gpu=400MHz`, load ~1.3. The same machine idle with it gone: 51-57 °C, `busy=3%`.
The last desktop sample before a freeze was 70 °C with the GPU at 400 MHz and the
charge current fallen from 1024 to 592 mA — the system drawing more of the 2 A
budget, not the supply giving less. — **measured**

**Acceleration works, so a software-rendering theory does not hold.** Xorg says so
outright, and reading its log costs nothing — no `mesa-utils`, no network:

```
(II) modeset(0): glamor X acceleration enabled on Mesa Intel(R) HD Graphics (CHV)
(II) modeset(0): glamor: Using OpenGL 4.6 context.
(II) AIGLX: Loaded and initialized crocus
```

— **verified on the unit**. `CHV` is Cherryview, and `crocus` is the right driver
for it, not a fallback: Mesa lists the Cherryview PCI IDs `0x22b0`-`0x22b3` in
[`include/pci_ids/crocus_pci_ids.h`](https://gitlab.freedesktop.org/mesa/mesa/-/blob/main/include/pci_ids/crocus_pci_ids.h),
with the renderer string `Intel(R) HD Graphics` that the log prints back. The
newer `iris` covers later generations and is *not* the one to expect here.

Two numbers from the recorder said the same thing before the log was read, and
they are the cheap check if you have no X log to hand: `gpu=` sits at 200 MHz idle
and moves to 400 MHz exactly while the screensaver runs — `gt_cur_freq_mhz` exists
only under `i915`, and a GPU with nothing to do stays on its bottom step — while
`busy=` reads 14 % through the same window, where a full-screen GL animation at
800x1280 falling back to `llvmpipe` would cost multiples of that across four
Airmont cores.

So the reading that "the graphics are broken, and the CPU overheats doing their
work" fails on both halves.

**Boot freezes land at 16-23 s of uptime**, three of three. The one sample
captured at the edge read 77 °C and `busy=90%` at `up=23`, on a SoC that had been
running 70 °C six minutes earlier and never cooled.

`pkill -f xscreensaver` does **not** stick — the LXQt session respawns it, and
`ps` shows it back a minute later. Suppress the autostart entry instead:

```sh
xscreensaver-command -exit
mkdir -p ~/.config/autostart
printf '[Desktop Entry]\nType=Application\nName=xscreensaver\nHidden=true\n' \
  > ~/.config/autostart/xscreensaver.desktop
```

**The one test worth doing during a freeze** costs nothing and splits the
remaining hypotheses: press Caps Lock on the USB keyboard and watch its LED. The
LED is driven by the kernel's HID layer, so if it still toggles the kernel is
alive and only userspace is wedged; if it is dead, so is the kernel, and no
amount of userspace tuning will help.

Things to try, in order:

1. **Raise the charger's input current limit.** On the reference unit the numbers
   leave no room for interpretation:

   ```
   axp288_charger/input_current_limit:  500000   (500 mA)
   axp288_charger/online:               1
   axp288_fuel_gauge/status:            Discharging
   axp288_fuel_gauge/current_now:      -496000   (496 mA out of the battery)
   ```

   The deficit equals the cap. The tablet draws about an ampere, is permitted
   half of it from the wall, and takes the rest out of a ten-year-old battery —
   while plugged in and reporting `online`. Capacity fell from 95 % to 86 %
   across an idle session on the charger. — **verified on the unit**

   That is the whole freeze story: at a consumption peak — a radio coming up, the
   CPU stepping — the machine needs one and a half to two amps, may take 0.5 A,
   and the battery has to cover the difference. Which is exactly what its own
   maintainer describes it failing to do.

   ```sh
   echo 2000000 | sudo tee /sys/class/power_supply/axp288_charger/input_current_limit
   ```

   Then re-read `status`. **The limit is permission, not delivery**: if the supply
   cannot actually source 2 A, VBUS sags, and since the driver pins `Vhold` at
   4.4 V the charger throttles straight back. Still `Discharging` after raising it
   means the problem is the supply — use a plain USB-A 2 A charger on an A-to-C
   cable, direct, no hub.

   ```sh
   cat /sys/class/power_supply/axp288_charger/input_current_limit
   echo 2000000 | sudo tee /sys/class/power_supply/axp288_charger/input_current_limit
   ```

   See [01-hardware.md](01-hardware.md#ports-otg-and-charging-while-a-hub-is-attached)
   for why this is needed and what the driver does with `Vhold`.
2. Confirm you are not swapping to eMMC. `swapon --show` should list a zram
   device and nothing else.
3. Take the deep C-states away — but do it at runtime, not in the firmware and
   not on the kernel command line. Every idle state has a writable `disable`
   attribute, so the experiment needs no reboot and is undone by writing `0`
   back:

   ```sh
   # what the states are and in what order -- do not assume the numbering
   head -v /sys/devices/system/cpu/cpu0/cpuidle/state*/name

   # everything deeper than C1 off, now
   for s in /sys/devices/system/cpu/cpu*/cpuidle/state[2-9]; do
     echo 1 | sudo tee "$s/disable" >/dev/null
   done
   ```

   The recorder's `idle=` column then shows the deep counters going flat, which
   is how you know the change took rather than assuming it. That check is not
   available with `intel_idle.max_cstate=1`, which needs a reboot to apply and
   another to undo.

   The firmware route — `C-States: C1` — is the worst of the three. The Aptio
   build here has no `Power` tab; with `SHOW ALL ITEM` on it is under
   **`Advanced` -> `PPM Configuration`** ([20-uefi-setup.md](20-uefi-setup.md#what-to-change)).
   But `/sys/devices/system/cpu/cpuidle/current_driver` says `intel_idle` on this
   unit, and `intel_idle` carries its own per-model tables instead of reading the
   firmware's ACPI `_CST`, so the setting may do nothing at all.

   Expect little either way, and see the VLP52 caveat above: the erratum behind
   the popular advice is Bay Trail, and this is Airmont. **The boot freezes argue
   against C-states on their own** — they land 16-23 s in, while services are
   still starting. That is the busiest the machine ever is, and a deep-idle bug
   needs a machine that has gone to sleep.
4. Kernel parameters another Vi8 Plus owner reports as their freeze fix:

   ```
   usbcore.autosuspend=-1 pcie_aspm=off intel_idle.max_cstate=1
   ```

   Untested here, and their own note says some of the three may be unnecessary.
   Add them together first; if the freezes stop, remove them one at a time to
   find which one mattered. Source in
   [90-references.md](90-references.md#another-owners-fixes-for-this-exact-tablet).

If the freeze leaves a trace, it will be in `journalctl -b -1 -p err`.

Separately, if the freezes coincide with Wi-Fi activity, the same owner reports
`brcmfmac` firmware crashes cured by turning NetworkManager's power saving off:

```sh
printf '[connection]\nwifi.powersave = 2\n' |
  sudo tee /etc/NetworkManager/conf.d/wifi-powersave-off.conf
sudo systemctl restart NetworkManager
```

## The touchscreen does not respond

```sh
dmesg | grep -iE 'icn8505|touchscreen_dmi|efi.*firmware'
cat /sys/class/dmi/id/product_name          # must be D2D3_Vi8A1
```

The controller firmware is extracted from the tablet's own UEFI image at boot,
which needs `CONFIG_EFI_EMBEDDED_FIRMWARE=y` (present in Ubuntu and Debian
kernels) and an EFI boot. If you somehow booted without EFI, the touchscreen
cannot work — check `ls /sys/firmware/efi`.

If `product_name` is not `D2D3_Vi8A1`, the kernel's DMI table does not match
your unit and it will not extract the firmware. On the reference tablet it
reads `To be filled by O.E.M.`, which is what the BIOS itself ships — this is
the common case, not an exotic one, and it breaks two other things at the same
time. The cause is in
[01-hardware.md](01-hardware.md#some-units-ship-with-the-dmi-fields-unfilled-and-it-breaks-three-things-at-once).

**You can fix this without a patched kernel.** The driver builds the firmware
filename from the ACPI `_SUB` object, not from DMI, and it looks in
`/lib/firmware` before it looks in UEFI. So all that is missing is the file, and
Chuwi's own Windows driver contains it:

```sh
sudo ./scripts/extract-touchscreen-fw.sh --download --install    # ~217 MiB
sudo modprobe -r chipone_icn8505 && sudo modprobe chipone_icn8505
dmesg | grep -i icn8505
```

The script picks the right blob by reading the name your kernel asked for, and
refuses to install anything whose SHA-256 it does not recognise. If you would
rather use the copy from your own flash, `sudo ./scripts/dump-bios.sh` gets that
one instead.
There are prepared kernel patches for it in [`patches/`](../patches/).

## Wi-Fi does not see the network

The radio is 2.4 GHz only. If the SSID is 5 GHz-only, split the band on the
router or use a different network. Confirm the interface exists first:

```sh
ip link
dmesg | grep -i brcmfmac
rfkill list
```

**If there is no `wlan0` at all**, this is not a network problem — the chip
never initialised, because it could not find its calibration data. That is the
expected state on a fresh install of this tablet. Fix it with the file copy in
[01-hardware.md](01-hardware.md#wi-fi--bluetooth--ampak-ap6212-broadcom-bcm43430),
and reboot rather than reloading the module.

## Everything is just slow

It is a 2016 Atom with 2 GB of RAM and eMMC. Realistic expectations: a text
editor, a terminal, a media player, and one browser with a handful of tabs.
zram helps materially; nothing else will change the shape of the machine.

## Getting back to Windows

If you took a full image, boot the live stick and restore it:

```sh
lsblk                                   # confirm which device is the eMMC
sudo ./scripts/restore-emmc.sh \
  --image /media/usb-disk/emmc-tablet-20260815-120000.img.zst \
  --target /dev/mmcblk0
```

The script verifies the image against its `.sha256` sidecar, refuses a target the
image would not fit on (from the `.size` sidecar), refuses a partition or a
still-mounted device, and makes you type `RESTORE /dev/mmcblk0` back — all before
it writes anything. Do not shortcut it with a bare `dd` — a typo in `of=` on this
path destroys the disk you are restoring onto.

Images made before the `.size` sidecar existed still restore; the script warns
that it cannot check the fit rather than refusing.

Then reboot. The licence key is in the firmware's ACPI `MSDM` table, so a clean
Windows install activates itself too — but a clean Windows install on this
tablet needs Chuwi's drivers, which are only on their forum.
