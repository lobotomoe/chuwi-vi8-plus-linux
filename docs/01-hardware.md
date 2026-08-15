# Hardware inventory and Linux driver status

## Identify your tablet

Do this before anything else. Several Chuwi models share a case and a name.

**From Windows** (PowerShell):

```powershell
Get-CimInstance Win32_ComputerSystem   | Select-Object Manufacturer, Model
Get-CimInstance Win32_BaseBoard        | Select-Object Manufacturer, Product
Get-CimInstance Win32_BIOS             | Select-Object Manufacturer, SMBIOSBIOSVersion
```

**From a Linux live session:**

```sh
cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name /sys/class/dmi/id/board_name
```

A Chuwi Vi8 Plus reports:

```
Hampoo
D2D3_Vi8A1
Cherry Trail CR
```

Those three strings are what the kernel itself matches on to enable the touchscreen,
the audio quirks and the accelerometer orientation. If your tablet reports something
else, the rest of this repo still mostly applies (any Cherry Trail tablet with 32-bit
UEFI works the same way), but the per-device quirks in the table below will not.

`scripts/collect-hw-report.sh`, run from a live session, dumps all of this plus the
driver state in one file.

### Not every Vi8 Plus has 32-bit firmware

This matters more than anything else in this document, because the whole premise of
this repository rests on it.

Chuwi shipped this model in several revisions, and owners on the 4PDA thread report
firmware that is **not** 32-bit:

- The common Windows-only units are 32-bit UEFI running 32-bit Windows 10. That is
  what this guide targets.
- **Dual-boot (Android + Windows) units behave differently.** One owner reports BIOS
  `D2D3_Vi8A1.232` presenting as 32-bit when booting Windows and **64-bit when
  booting Android**, with `x64` appended to the version string in the menu
  (post #2861). Those units expose a **`Boot architecture`** setting the 32-bit
  units do not have (posts #2613, #2655).
- BIOS revision **1608** is reported as 64-bit when booting Windows (post #2940).

So "the Vi8 Plus has 32-bit UEFI" is true of this model in general and **not
guaranteed of your unit**. Check before you build anything:

```sh
cat /sys/firmware/efi/fw_platform_size      # 32 -> this guide applies
```

That needs a booted Linux, which is the thing you cannot do yet. **From Windows,
while you still have it**, this answers the same question:

```powershell
$env:PROCESSOR_ARCHITECTURE                 # x86 -> 32-bit Windows
Confirm-SecureBootUEFI                      # errors if not booted via UEFI
```

UEFI requires the firmware and the operating system to share a bitness, so a
**32-bit Windows booted in UEFI mode means 32-bit firmware** — which is the case
this repository is written for, and what the stock Vi8 Plus ships with. If that
reports `AMD64`, stop and re-read this section before building a stick.

If it reports `64`, you do not have this repository's problem at all — install
normally with the distribution's own 64-bit media and ignore everything here about
`bootia32.efi`. If your firmware has a `Boot architecture` item, leave it alone
unless you know exactly which way your unit boots; owners who tried to move a
32-bit unit to 64-bit firmware bricked it, and there is no software path back
(post #2626).

## Base specification

| | |
|---|---|
| Model | Chuwi Vi8 Plus, CWI519 (2016) |
| SoC | Intel Atom x5-Z8300, Cherry Trail, 4 cores, x86-64 (some later retail listings quote the x5-Z8350 — check `lscpu`; both are Cherry Trail and behave identically here) |
| GPU | Intel HD Graphics (Gen8 / Cherry Trail) |
| RAM | 2 GB DDR3L, soldered |
| Storage | 32 GB eMMC + microSD slot |
| Display | 8.0" IPS, 1280x800, 10-point capacitive touch. Scanout orientation is probably **portrait** (800x1280) — the firmware setup renders upright with the tablet held portrait — and the kernel has no orientation quirk for this model, so expect to rotate it yourself. See [40-post-install.md](40-post-install.md#if-everything-starts-sideways) |
| Firmware | **32-bit (IA32) UEFI**, no CSM/legacy boot — but see the revision note below; confirm with `fw_platform_size` before trusting it. The unit this guide was written against reports AMI Aptio `2.17.1249`, **BIOS version `1ATFG007`, dated 12/11/2015** |
| Ports | 1x USB Type-C (USB 2.0, power + data, OTG), micro-HDMI 1.4, microSD, 3.5 mm |
| Battery | Li-Po. **Sources disagree:** Notebookcheck's review says 5000 mAh, the 4PDA thread's specification header says Chuwi claims 4000 mAh with owners measuring 3900-4050 mAh. Read your own with `cat /sys/class/power_supply/*/energy_full_design` rather than trusting either |
| Cameras | 2 MP front, 2 MP rear |

The 64-bit CPU with 32-bit-only firmware is the single most important fact about this
device. [docs/02-boot-problem.md](02-boot-problem.md) covers what follows from it.

## Component-by-component

Every "kernel symbol" below was checked against the configuration actually shipped in
Ubuntu 26.04 LTS (`linux-buildinfo-7.0.0-31-generic`). All of them are enabled.

### Touchscreen — Chipone ICN8505

- Driver: `chipone_icn8505` (`CONFIG_TOUCHSCREEN_CHIPONE_ICN8505=m`)
- Enabled by DMI match in `drivers/platform/x86/touchscreen_dmi.c`
  (`CONFIG_TOUCHSCREEN_DMI=y`), struct `chuwi_vi8_plus_data`.
- Firmware: `chipone/icn8505-HAMP0002.fw`, 35012 bytes,
  SHA-256 `93e549e0b6a2b4b3889634975ea81378729b8b829eb5ca7f125134f4307cfc7c`.

This firmware is **not** shipped by `linux-firmware`. It lives inside the tablet's own
UEFI image, and the kernel extracts it at boot through the EFI embedded-firmware
mechanism (`CONFIG_EFI_EMBEDDED_FIRMWARE=y`) that Hans de Goede added specifically for
this class of tablet. Nothing to download; it just works, but it does mean the
touchscreen depends on booting via EFI and on that config option being enabled.

Check it landed:

```sh
dmesg | grep -iE 'icn8505|efi.*firmware'
```

### Wi-Fi / Bluetooth — AmPak AP6212 (Broadcom BCM43430)

- Wi-Fi driver: `brcmfmac` over SDIO (`CONFIG_BRCMFMAC=m`, `CONFIG_BRCMFMAC_SDIO=y`)
- NVRAM: `brcm/brcmfmac43430-sdio.Hampoo-D2D3_Vi8A1.txt`, present in `linux-firmware`
  since 2018. Any current distribution has it.
- **2.4 GHz only.** The chip has no 5 GHz radio. This is not a driver limitation.
- Bluetooth: BCM43430A1 attached over UART, driver `hci_uart` + `btbcm`, patch file
  `brcm/BCM43430A1.hcd` from `linux-firmware`.

Wi-Fi is reliable. Bluetooth on UART-attached Broadcom parts on Cherry Trail is the one
component worth verifying on your own unit rather than trusting a table — see
[50-troubleshooting.md](50-troubleshooting.md#bluetooth-does-not-appear).

### Audio — Realtek RT5651

- Machine driver: `bytcr_rt5651` (`CONFIG_SND_SOC_INTEL_BYTCR_RT5651_MACH=m`)
- The Vi8 Plus has an explicit quirk entry upstream in
  `sound/soc/intel/boards/bytcr_rt5651.c`, matched on `Hampoo` / `D2D3_Vi8A1`:
  `BYT_RT5651_IN2_MAP | BYT_RT5651_HP_LR_SWAPPED | BYT_RT5651_MONO_SPEAKER`.

So the speaker is mono and the headphone channels are swapped in hardware — the kernel
already compensates. Userspace needs the matching UCM profile, which is in
`alsa-ucm-conf` on every current distribution.

### Accelerometer / auto-rotation — Bosch BOSC0200

- Driver: `bmc150_accel`
- systemd's `hwdb.d/60-sensor.hwdb` carries the mount matrix for this exact device:
  `sensor:modalias:acpi:BOSC0200:*:dmi:*:svnHampoo:pnD2D3_Vi8A1:*` with
  `ACCEL_MOUNT_MATRIX=0, 1, 0; 1, 0, 0; 0, 0, 1`.

Install `iio-sensor-proxy` and rotation works in any Wayland/GNOME/KDE session.
See [40-post-install.md](40-post-install.md#screen-rotation).

### Power — X-Powers AXP288 PMIC

- `axp288_charger`, `axp288_fuel_gauge`, `CONFIG_INTEL_SOC_PMIC=y`
- Backlight is driven through the Cherry Trail LPSS PWM (`CONFIG_PWM_LPSS=y`).

Battery percentage, charge state and brightness all work. Reported capacity can be a
little optimistic; the fuel gauge is calibrated by the firmware, not by Linux.

### Storage

- eMMC via `sdhci-acpi`, appears as `/dev/mmcblk0` (occasionally `mmcblk1` — always
  check with `lsblk` rather than assuming).
- microSD appears as a **separate** `mmcblk` device, and not necessarily the next
  number: on this unit a card in the slot came up as `mmcblk2`, because `mmcblk1` is
  taken by the eMMC's own boot hardware partitions (`mmcblk0boot0`, `mmcblk0boot1`).
  Check, never assume.

Stock `/proc/partitions` on an untouched unit, for orientation — sizes in 1 KiB blocks:

```
179  0  30310400  mmcblk0        # eMMC, ~28.9 GiB usable of a "32 GB" part
179  1    102400  mmcblk0p1      # ESP
179  2     16384  mmcblk0p2      # Microsoft reserved
179  3  29728768  mmcblk0p3      # Windows
179  4    460800  mmcblk0p4      # Windows recovery
179  8      4096  mmcblk0boot0
179 16      4096  mmcblk0boot1
```

— **verified on the unit**

The firmware is **not known to boot from the microSD slot**, so plan on installing
Linux to the eMMC and on a USB stick to start from. Owners asked about booting a
card at least three times over the thread's life and were told it does not work
(4PDA #2191, #2410, #3411); nobody there reports having done it. That is decent
evidence and not proof — it has not been tried on the unit behind this guide. If
you are about to build a card anyway, look for it under `Boot Override` first: it
costs one reboot, and if it is there you can skip the stick entirely.

You can put `/home` on the SD card afterwards if you want.

**Card detection is a known sore spot on this model**, separately from booting.
Owners report cards that vanish from the running system, need a re-seat after every
boot, or are never detected at all (#894, #2572, #3046). Two firmware settings come
up as fixes: putting the SD controller in **PCI mode rather than AHCI** (#3335), and
an item under `Advanced` -> `System Component` (#3046). There is also an
`Sdcard RCOMP Trigger Delay` item people associate with drop-outs (#2299). Worth
knowing before you rely on a card for anything.

The card is still useful during the install, though: the kernel reads it over the SD
controller rather than over USB, so a live filesystem placed there is immune to the
USB problems described in
[50-troubleshooting.md](50-troubleshooting.md#a-usb-30-stick-cannot-hold-a-link-here).

### Cameras

Cherry Trail routes the cameras through the Intel ISP2400 ("atomisp"). The mainline
driver is in `drivers/staging/` and does not produce a usable camera on this hardware.
Treat both cameras as non-functional. This is not going to change.

### Ports, OTG, and charging while a hub is attached

The single USB-C port carries both power and data, at USB 2.0 speed.

**It will still try to talk to USB 3.0 devices, and fail.** The SoC's xHCI exposes a
SuperSpeed root bus, so a USB 3.0 stick behind a USB 3.0 hub negotiates SuperSpeed,
cannot hold the link, and resets forever without ever becoming a block device — while
a keyboard on the high-speed bus works flawlessly through the same hub. Prefer USB 2.0
storage and USB 2.0 hubs here; it is not a preference for compatibility's sake, it is
the difference between working and not. See
[50-troubleshooting.md](50-troubleshooting.md#a-usb-30-stick-cannot-hold-a-link-here). —
**verified on the unit**

**Charging is 5 V / 2 A and nothing else.** The port does not speak USB Power Delivery.
A modern PD charger reached over a C-to-C cable commonly settles on 500 mA, which is
less than the tablet draws with a hub attached — it discharges while plugged in. Use a
plain **USB-A charger with a USB-A-to-C cable**.

A data-only hub leaves the tablet on battery, so charge to 100 % before you start and
do not let the live session idle for an hour before you begin the install. But that is
a property of the hub, not of the tablet: **a hub that passes 5 V through (an "OTG
charging hub" with its own power input) charges the tablet while the port stays in host
mode.** Hans de Goede, who maintains this class of tablet upstream and owns this exact
model, installs Fedora on it that way — see [90-references.md](90-references.md#hans-de-goedes-notes-on-this-exact-tablet).

Applying 5 V is itself an event the port-role driver reacts to, so the order matters:
bring the tablet up with the hub in OTG mode and no 5 V, then apply power once you are
already at the firmware menu. If the port flips to device mode *after* Linux has
started, a running live session loses its root filesystem — see
[50-troubleshooting.md](50-troubleshooting.md#the-live-session-boots-then-slowly-falls-apart).

Micro-HDMI 1.4 output works, up to 1080p, with audio.

## Verifying all of this on your own device

```sh
sudo ./scripts/collect-hw-report.sh
```

Run it from the live session before you install anything. It writes a single file with
DMI strings, firmware bitness, loaded modules, sound cards, input devices, power supply
state and the relevant `dmesg` lines. If something in the table above does not match
your unit, that report is what you want to look at first.
