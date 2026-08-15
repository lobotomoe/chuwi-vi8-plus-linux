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
cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name \
    /sys/class/dmi/id/board_vendor /sys/class/dmi/id/board_name
```

**Run all four, not the first three, and read the next section before you conclude
anything.**

A Vi8 Plus with complete DMI reports `Hampoo` / `D2D3_Vi8A1` / `Hampoo` /
`Cherry Trail CR`. Those strings are what the kernel matches on to enable the
touchscreen, the Wi-Fi calibration data, the audio quirks and the accelerometer
orientation.

`scripts/collect-hw-report.sh`, run from a live session, dumps all of this plus the
driver state in one file.

### Some units ship with the DMI fields unfilled, and it breaks four things at once

Check this early. It is invisible, it is not a fault in your tablet, and it is the
single explanation for a whole cluster of "nothing works out of the box".

The unit behind this guide — BIOS `1ATFG007`, 12/11/2015 — reports:

```
sys_vendor:    To be filled by O.E.M.
product_name:  To be filled by O.E.M.
board_vendor:  Hampoo
board_name:    Cherry Trail CR
```

— **verified on the unit**

Chuwi left the two system fields at the SMBIOS placeholder. The board fields are
correct, but almost every kernel quirk matches on the **system** fields, so none of
them fire:

| Component | What the kernel matches on | Result with unfilled DMI |
|---|---|---|
| Touchscreen (ICN8505) | `DMI_SYS_VENDOR` "Hampoo" + `DMI_PRODUCT_NAME` "D2D3_Vi8A1" + `DMI_BOARD_NAME` "Cherry Trail CR" | no match — firmware never extracted, driver probe fails |
| Wi-Fi NVRAM | `snprintf("%s-%s", sys_vendor, product_name)` in `brcmfmac/dmi.c` | looks for `...-sdio.To be filled by O.E.M.-To be filled by O.E.M..txt` |
| Audio (RT5651) | `Hampoo` + `D2D3_Vi8A1` | no match — no mono-speaker / swapped-headphone correction |
| Accelerometer mount matrix | hwdb `svnHampoo:pnD2D3_Vi8A1` | no match — rotation has no orientation reference |

A giveaway before you check anything: the installer proposes a hostname like
`chuwi-tobefilledbyoem`, because it builds one out of these same fields.

Both of the components that matter can be fixed without DMI, because in each case the
driver's *second* attempt uses a name that does not depend on it —
[Wi-Fi](#wi-fi--bluetooth--ampak-ap6212-broadcom-bcm43430) and
[touchscreen](#touchscreen--chipone-icn8505) below. Audio and the accelerometer
matrix have no equivalent escape hatch and would need a kernel patch.

The proper fix is upstream: an additional DMI entry matching `DMI_BOARD_VENDOR`
"Hampoo" + `DMI_BOARD_NAME` "Cherry Trail CR" together with something narrow enough
to avoid catching every Hampoo Cherry Trail board — the BIOS version or date. That
has not been submitted.

### If your tablet reports something else entirely

The rest of this repo still mostly applies — any Cherry Trail tablet with 32-bit UEFI
boots the same way — but the per-device quirks in the table below will not.

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

**On a unit with [unfilled DMI](#some-units-ship-with-the-dmi-fields-unfilled-and-it-breaks-four-things-at-once)
it does not just work.** What that looks like:

```
chipone_icn8505 i2c-CHPN0001:00: Direct firmware load for chipone/icn8505-HAMP0002.fw failed with error -2
chipone_icn8505 i2c-CHPN0001:00: Firmware request error -2
chipone_icn8505 i2c-CHPN0001:00: probe with driver chipone_icn8505 failed with error -2
```

— **verified on the unit**

Read that carefully, because it is better news than it looks. The I2C device is found,
the driver binds to it, and the probe fails on exactly one thing: a missing file. The
hardware and the driver are fine.

And the filename in that message does **not** come from the DMI quirk — the driver
builds `chipone/icn8505-<ACPI HID>.fw` from the ACPI device's own ID. So dropping the
file into `/lib/firmware/chipone/` makes the touchscreen work with the DMI still
unfilled; the quirk's only job was to extract that same file from the UEFI image.

Getting the file means pulling it out of your own firmware — it is not redistributed
anywhere. The kernel records exactly what to look for: **35012 bytes**, starting with
`b0 07 00 00 e4 07 00 00`, SHA-256
`93e549e0b6a2b4b3889634975ea81378729b8b829eb5ca7f125134f4307cfc7c`. Dump the SPI flash
read-only (`flashrom -p internal -r`) or take an official Chuwi BIOS image, find the
blob, and check it against that hash before installing it.

### Wi-Fi / Bluetooth — AmPak AP6212 (Broadcom BCM43430)

- Wi-Fi driver: `brcmfmac` over SDIO (`CONFIG_BRCMFMAC=m`, `CONFIG_BRCMFMAC_SDIO=y`)
- NVRAM: `brcm/brcmfmac43430-sdio.Hampoo-D2D3_Vi8A1.txt`, present in `linux-firmware`
  since 2018. Any current distribution has it — **but see the chip revision note
  below before assuming it is the file your unit needs.**
- **2.4 GHz only.** The chip has no 5 GHz radio. This is not a driver limitation.
- Bluetooth: BCM43430A1 attached over UART, driver `hci_uart` + `btbcm`, patch file
  `brcm/BCM43430A1.hcd` from `linux-firmware`.

Wi-Fi is reliable **once it has NVRAM**. Bluetooth on UART-attached Broadcom parts on
Cherry Trail is the one component worth verifying on your own unit rather than trusting
a table — see [50-troubleshooting.md](50-troubleshooting.md#bluetooth-does-not-appear).

#### Two chip revisions ship in this model, and they want different NVRAM

`brcmfmac` picks firmware names by chip **revision**. Check which one you have:

```sh
sudo dmesg | grep brcmf_fw_alloc_request
```

```
brcmfmac: brcmf_fw_alloc_request: using brcm/brcmfmac43430a0-sdio for chip BCM43430/0
```

— **verified on the unit**: revision **a0**.

That matters because the NVRAM `linux-firmware` ships for this tablet is
`brcmfmac43430**-sdio.Hampoo-D2D3_Vi8A1.txt` — no `a0`, so it came from a unit with the
**a1** revision. The same tablet model shipped with both. There is no `a0` file named
for this board, so an `a0` unit finds nothing and the chip never initialises:

```
Direct firmware load for brcm/brcmfmac43430a0-sdio.txt failed with error -2
brcmfmac: brcmf_sdio_htclk: HT Avail timeout (1000000): clkctl 0x50
```

The fix does not need DMI: after the DMI-derived name fails, the driver falls back to
the plain `brcm/brcmfmac43430a0-sdio.txt`, so put an NVRAM there.

```sh
ls /lib/firmware/brcm/ | grep 43430          # what your distribution ships
sudo sh -c 'zstd -dc "/lib/firmware/brcm/brcmfmac43430-sdio.Hampoo-D2D3_Vi8A1.txt.zst" \
    > /lib/firmware/brcm/brcmfmac43430a0-sdio.txt'
sudo reboot
ip -br link                                   # wlan0 appears
```

— **verified on the unit**: `wlan0` comes up with an AmPak MAC (`00:17:cd:…`), and
NetworkManager finds networks normally. The board's own NVRAM works on the `a0`
revision, so the a1/a0 split is in the *filename*, not in the calibration data. The
file even says so in its header: *"NVRAM config file for the 43430 WiFi/BT chip as
found on the Chuwi Vi8 Plus"*.

**Reboot — do not just reload the module.** After the first failed boot the chip is
left wedged by the `HT Avail timeout`, and `modprobe -r brcmfmac && modprobe brcmfmac`
comes back with a different error that looks like a second, unrelated problem:

```
brcmfmac mmc2:0001:1: probe with driver brcmfmac failed with error -16
```

`-16` is `EBUSY`, not a firmware failure — note there is no `-2` line with it, which
means the NVRAM *was* found. Only a power cycle of the SDIO function clears it, and a
reboot is the simple way to get one.

If the board's own file does not work, the fallbacks are the `a0` ones, all from 8"
Cherry Trail tablets with the same AmPak module: `ilife-S806` first — upstream already
associates it with a Hampoo `Cherry Trail CR` board in `brcmfmac/dmi.c` — then
`ONDA-V80 PLUS`, then `jumper-ezpad-mini3`. Each attempt is one file copy and one
reboot.

### Audio — Realtek RT5651

- Machine driver: `bytcr_rt5651` (`CONFIG_SND_SOC_INTEL_BYTCR_RT5651_MACH=m`)
- The Vi8 Plus has an explicit quirk entry upstream in
  `sound/soc/intel/boards/bytcr_rt5651.c`, matched on `Hampoo` / `D2D3_Vi8A1`:
  `BYT_RT5651_IN2_MAP | BYT_RT5651_HP_LR_SWAPPED | BYT_RT5651_MONO_SPEAKER`.

So the speaker is mono and the headphone channels are swapped in hardware — the kernel
already compensates. Userspace needs the matching UCM profile, which is in
`alsa-ucm-conf` on every current distribution.

On a unit with [unfilled DMI](#some-units-ship-with-the-dmi-fields-unfilled-and-it-breaks-four-things-at-once)
this quirk does not fire, and unlike Wi-Fi and the touchscreen there is no
DMI-independent fallback: expect stereo routing on a mono speaker and headphone
channels the wrong way round. The `bytcr_rt5651.c` quirk can be forced with the
module's `quirk=` parameter if you are prepared to work out the bitmask, but that
has not been tried here.

### Accelerometer / auto-rotation — Bosch BOSC0200

- Driver: `bmc150_accel`
- systemd's `hwdb.d/60-sensor.hwdb` carries the mount matrix for this exact device:
  `sensor:modalias:acpi:BOSC0200:*:dmi:*:svnHampoo:pnD2D3_Vi8A1:*` with
  `ACCEL_MOUNT_MATRIX=0, 1, 0; 1, 0, 0; 0, 0, 1`.

Install `iio-sensor-proxy` and rotation works in any Wayland/GNOME/KDE session.
See [40-post-install.md](40-post-install.md#screen-rotation).

The hwdb entry matches on `svnHampoo:pnD2D3_Vi8A1`, so on a unit with
[unfilled DMI](#some-units-ship-with-the-dmi-fields-unfilled-and-it-breaks-four-things-at-once)
the mount matrix is not applied and auto-rotation has no idea which way is up. The
accelerometer itself still works — you can copy the matrix into a local hwdb rule
matched on something your unit actually reports.

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

The firmware **does not boot from the microSD slot**. Install Linux to the eMMC and
start from a USB stick.

This was tested here, not assumed: a card built by `scripts/make-media.sh` — GPT,
FAT32, carrying `\EFI\BOOT\BOOTIA32.EFI`, the same layout that boots this tablet
from a USB stick — was put in the slot and **does not appear under `Boot Override`
at all**. — **verified on the unit**

That matches what owners have said for years (4PDA #2191, #2410, #3411) and closes
a question this document previously answered on their word alone.

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
