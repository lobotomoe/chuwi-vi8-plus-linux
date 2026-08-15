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

## Base specification

| | |
|---|---|
| Model | Chuwi Vi8 Plus, CWI519 (2016) |
| SoC | Intel Atom x5-Z8300, Cherry Trail, 4 cores, x86-64 (some later retail listings quote the x5-Z8350 — check `lscpu`; both are Cherry Trail and behave identically here) |
| GPU | Intel HD Graphics (Gen8 / Cherry Trail) |
| RAM | 2 GB DDR3L, soldered |
| Storage | 32 GB eMMC + microSD slot |
| Display | 8.0" IPS, 1280x800, native landscape, 10-point capacitive touch |
| Firmware | **32-bit (IA32) UEFI**, no CSM/legacy boot |
| Ports | 1x USB Type-C (USB 2.0, power + data, OTG), micro-HDMI 1.4, microSD, 3.5 mm |
| Battery | 5000 mAh Li-Po |
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
- microSD appears as a second `mmcblk` device.

The firmware **cannot boot from the microSD slot**. Linux must be installed to the
eMMC. You can put `/home` on the SD card afterwards if you want.

### Cameras

Cherry Trail routes the cameras through the Intel ISP2400 ("atomisp"). The mainline
driver is in `drivers/staging/` and does not produce a usable camera on this hardware.
Treat both cameras as non-functional. This is not going to change.

### Ports and the OTG problem

The single USB-C port carries both power and data, at USB 2.0 speed. There is no power
delivery path that survives an OTG adapter: **while a hub is attached, the tablet is on
battery.** Charge to 100 % before you start, and do not leave the live session sitting
idle for an hour before you begin the install.

Micro-HDMI 1.4 output works, up to 1080p, with audio.

## Verifying all of this on your own device

```sh
sudo ./scripts/collect-hw-report.sh
```

Run it from the live session before you install anything. It writes a single file with
DMI strings, firmware bitness, loaded modules, sound cards, input devices, power supply
state and the relevant `dmesg` lines. If something in the table above does not match
your unit, that report is what you want to look at first.
