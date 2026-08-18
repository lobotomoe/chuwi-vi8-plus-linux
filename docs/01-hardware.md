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

### Some units ship with the DMI fields unfilled, and it breaks three things at once

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

**You can spot it without running anything.** The Ubuntu installer builds the
default hostname out of the same DMI, so on an affected unit the shell prompt
reads `chuwi@chuwi-tobefilledbyoem` — the placeholder, lowercased and stripped of
punctuation. — **verified on the unit**. A prompt like that is the cheapest
possible confirmation that everything below applies to your tablet.

Chuwi left the two system fields at the SMBIOS placeholder. The board fields are
correct, but almost every kernel quirk matches on the **system** fields, so none of
them fire:

| Component | What the kernel matches on | Result with unfilled DMI |
|---|---|---|
| Touchscreen (ICN8505) | `DMI_SYS_VENDOR` "Hampoo" + `DMI_PRODUCT_NAME` "D2D3_Vi8A1" + `DMI_BOARD_NAME` "Cherry Trail CR" | no match — firmware never extracted, driver probe fails |
| Wi-Fi NVRAM | `snprintf("%s-%s", sys_vendor, product_name)` in `brcmfmac/dmi.c` | looks for `...-sdio.To be filled by O.E.M.-To be filled by O.E.M..txt` |
| Audio (RT5651) | `Hampoo` + `D2D3_Vi8A1` | no match — no mono-speaker / swapped-headphone correction |

**The accelerometer is the exception, and it is worth knowing why.** systemd's
hwdb does carry a `svnHampoo:pnD2D3_Vi8A1` entry that cannot match here, but on
this tablet it is never needed: `bmc150-accel` asks ACPI first and only falls
back to the hwdb-supplied property if that fails.

```c
if (!bmc150_apply_acpi_orientation(dev, &data->orientation)) {
	ret = iio_read_mount_matrix(dev, &data->orientation);
```

For a `BOSC0200` device the ACPI path looks for a `ROTM` method, and this tablet's
DSDT has one. Extracted from `P03_C806.109` and read directly:

```
Device ACC2:
  _HID  BOSC0200
  _CID  BOSC0200
  _DDN  "Accelerometer"
  _UID  7
  _CRS  ... \_SB.PCI0.I2C3
  ROTM  "0 -1 0"  "-1 0 0"  "0 0 1"
```

— **verified by extracting the DSDT from the published BIOS image.** `ROTM` sits
inside the `ACC2` device scope, about 100 bytes after its `_HID`, and carries the
matrix literally. The same object with the same values is in the dual-boot image.

Re-derive it yourself rather than taking this on trust:

```sh
python3 -m venv venv && venv/bin/pip install uefi-firmware
venv/bin/python scripts/inspect-bios-image.py P03_C806.109
```

```
    BOSC0200   x2   at 50055, 50070
    ROTM       x1   at 50163
    mount matrix: 0 -1 0 / -1 0 0 / 0 0 1
```

The offsets are positions inside the extracted DSDT, so they shift with the
extraction method; the structure is what matters.

So the orientation reference survives unfilled DMI, and you know in advance what it
should say. Confirm on your unit:

```sh
cat /sys/bus/iio/devices/iio:device0/in_accel_mount_matrix
```

```
0, -1, 0; -1, 0, 0; 0, 0, 1
```

That is the firmware's own matrix. An identity matrix (`1, 0, 0; 0, 1, 0; 0, 0, 1`)
means nothing was found. Auto-rotation may still not happen even with the right
matrix, but if so that is LXQt not acting on the sensor rather than the sensor being
unreferenced — see [40-post-install.md](40-post-install.md#automatic-rotation).

A giveaway before you check anything: the installer proposes a hostname like
`chuwi-tobefilledbyoem`, because it builds one out of these same fields.

Both of the components that matter can be fixed without DMI, because in each case the
driver's *second* attempt uses a name that does not depend on it —
[Wi-Fi](#wi-fi--bluetooth--ampak-ap6212-broadcom-bcm43430) and
[touchscreen](#touchscreen--chipone-icn8505) below. The accelerometer never
needed one, as explained above. **Audio is the only one genuinely stuck**: its
quirk keys on the system fields with no second path, so it needs a kernel patch.

**A BIOS update does not fix this.** The placeholder is baked into the firmware
image: the newest BIOS Chuwi published (`P03_C806.109`, 2016-02-25) hard-codes
`To be filled by O.E.M.` as its SMBIOS system manufacturer and product name, so
flashing it changes nothing. That was checked by parsing the image —
[60-bios-firmware.md](60-bios-firmware.md) has the dump and the rest of the
firmware story, including why the dual-boot BIOS would make things worse.

The proper fix is upstream, and it has a close precedent. `brcmfmac/dmi.c`
already handles the sibling Chuwi Hi8 Pro by matching the board fields plus the
BIOS date, with the comment *"Above strings are too generic, also match on BIOS
date"*:

```c
DMI_EXACT_MATCH(DMI_BOARD_VENDOR, "Hampoo"),
DMI_EXACT_MATCH(DMI_BOARD_NAME, "Cherry Trail CR"),
DMI_EXACT_MATCH(DMI_PRODUCT_SKU, "MRD"),
DMI_MATCH(DMI_BIOS_DATE, "05/10/2016"),
```

A Vi8 Plus with unfilled DMI matches the first three exactly — the BIOS image
confirms the SKU really is `MRD` — and differs only in the date (`12/11/2015`,
or `02/25/2016` on the newer build).

Three such patches are written and in [`patches/`](../patches/) — touchscreen,
Wi-Fi and audio. They apply cleanly against current mainline but have not been
tested on hardware or submitted; [`patches/README.md`](../patches/README.md)
lists what has to be confirmed first.

The other route is to write the two system strings back into the firmware with
AMI's DMI editor, which would make all three quirks match at once. Untested here;
the risks are in [60-bios-firmware.md](60-bios-firmware.md#what-would-actually-fix-it).

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

This firmware is **not** shipped by `linux-firmware` — that repository has no
`chipone/` directory, and its `WHENCE` manifest does not mention `icn8505` or
`chipone` anywhere in its 10534 lines. — **verified**. No distribution packages
it, so there is no package to install; every route to the file goes through
Chuwi. It lives inside the tablet's own
UEFI image, and the kernel extracts it at boot through the EFI embedded-firmware
mechanism (`CONFIG_EFI_EMBEDDED_FIRMWARE=y`) that Hans de Goede added specifically for
this class of tablet. Nothing to download; it just works, but it does mean the
touchscreen depends on booting via EFI and on that config option being enabled.

Check it landed:

```sh
dmesg | grep -iE 'icn8505|efi.*firmware'
```

**On a unit with [unfilled DMI](#some-units-ship-with-the-dmi-fields-unfilled-and-it-breaks-three-things-at-once)
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

And the filename in that message does **not** come from the DMI quirk. Note that the
I2C device is `CHPN0001` while the file is `HAMP0002` — the driver builds
`chipone/icn8505-<_SUB>.fw` from the ACPI `_SUB` (subsystem ID) object of the
touchscreen node, via `acpi_get_subsystem_id()`. Nothing in that path reads DMI.

That is not just how the driver is written, it is what this tablet's firmware
declares. From the DSDT extracted out of `P03_C806.109`:

```
Device TCS1:
  _HID  CHPN0001
  _CID  PNP0C50
  _SUB  HAMP0002
```

— **verified by extracting the DSDT from the published BIOS image**, which
`scripts/inspect-bios-image.py` reports as:

```
    CHPN0001 _SUB -> HAMP0002
    kernel will request chipone/icn8505-HAMP0002.fw
```

The lookup order settles the rest. `firmware_request_platform()` is documented in the
kernel as trying the filesystem first and falling back to the UEFI copy only *"if
direct filesystem lookup fails"*. So **a file in `/lib/firmware/chipone/` takes
priority over the UEFI extraction and works with the DMI still unfilled.** The quirk's
only job on this tablet is to make that file unnecessary — `chuwi_vi8_plus_data`
carries an `embedded_fw` entry and no `properties`, so a missed match costs the
firmware and nothing else.

That makes the touchscreen the one broken component you can fix today without
building a kernel.

There are two ways to get the file. `linux-firmware` does not carry it, but Chuwi's
own Windows driver does — that is the easy route, below. The other is to pull the
copy out of your own flash, which is the only way to get the exact blob the kernel
pins: **35012 bytes**, starting with `b0 07 00 00 e4 07 00 00`, SHA-256
`93e549e0b6a2b4b3889634975ea81378729b8b829eb5ca7f125134f4307cfc7c`.

`sudo ./scripts/dump-bios.sh` does that job: it reads the flash twice, refuses a
dump the two reads disagree on, searches it for that prefix and installs the result
only if the hash matches. It needs `flashrom`, which no distribution installs by
default — `sudo apt install flashrom` first.

#### Chuwi ships the firmware itself, in its own driver

You do not need to dump your flash and you do not need a stranger's copy. Chuwi's
Windows touch driver carries the firmware inside its INF as hex, in a section keyed
by the same `HAMP000x` names the ACPI `_SUB` reports:

```
[Chpntsc_Device_Firmware.AddReg]
HKR,,"HAMP0001",0x00000001,b0,07,00,00,e4,07,00,00,...
HKR,,"HAMP0002",0x00000001,b0,07,00,00,e4,07,00,00,...
...through HAMP0007
```

That is the primary source: a signed vendor package (`Chpntsc.cat`, DriverVer
04/21/2016), not a re-upload. [`scripts/extract-touchscreen-fw.sh`](../scripts/extract-touchscreen-fw.sh)
reads it back out and checks the result against a known hash:

```sh
sudo ./scripts/extract-touchscreen-fw.sh --download --install     # ~217 MiB
```

Run without `--name` it reads the name your own kernel asked for out of `dmesg`,
which is the only authoritative answer for your unit.

**This is the route that was run on the reference unit, and it works.** The
detection read `HAMP0002` off that machine's own `dmesg`, the package hashed as
expected, the blob matched the 2016-04-21 table, and `--install` wrote
`/lib/firmware/chipone/icn8505-HAMP0002.fw`. Reloading the driver is enough — no
reboot:

```sh
sudo modprobe -r chipone_icn8505 && sudo modprobe chipone_icn8505
```

The probe then succeeds and the touchscreen registers as an input device:

```
input: CHPN0001:00 as /devices/pci0000:00/808622C1:04/i2c-4/i2c-CHPN0001:00/input/input25
```

— **verified on the unit**, with the DMI still unfilled, on a stock distribution
kernel and no patch. Note the device is named after the ACPI ID, so it is
`CHPN0001` you grep `/proc/bus/input/devices` for, not `icn8505`.

This also settles, for one build, the question left open below: the vendor
package's **34900-byte** `HAMP0002` is accepted by the controller even though the
kernel's EFI path pins 35012 bytes. Do not read more into the probe than it says
— the driver's post-upload checks are computed over the file it just sent, so
they prove the I2C transfer, not the blob's provenance. The 34884-byte GitHub
build is still untried here.

#### With that build the axes come out rotated 180°

Touch works and the pointer tracks the finger, but **both axes are inverted** —
touch the top right and the pointer goes to the bottom left. Measured off two
frames of a video of the unit rather than eyeballed: finger at (0.69, 0.26) gave
a pointer at (0.30, 0.74), and finger at (0.84, 0.46) gave (0.18, 0.65). That is
`x → 1-x, y → 1-y` on both, with no axis swap, so it is a 180° rotation and not
a 90° one. — **verified on the unit**

This is not something the DMI quirk can explain, and it is worth being precise
about why, because it is tempting to blame [patch 0001](../patches/):
`chuwi_vi8_plus_data` carries an `embedded_fw` descriptor and **nothing else** —
no `.properties`, no `.acpi_name` — so there are no axis properties for a missed
DMI match to have cost. The orientation arrives from the controller: the driver
reads the resolution out of the chip over I2C, then applies
`touchscreen_parse_properties()`, and upstream sets no `touchscreen-inverted-*`
for this model at all. On the maintainer's unit, running the blob out of EFI, the
axes must therefore already be correct.

Which points at the firmware build rather than the hardware. We are loading a
*different* build of `HAMP0002` than the one the kernel pins, and the scan
direction is the controller firmware's business. Untested hypothesis, and the
experiment that would settle it is cheap: load the 34884-byte build and see
whether the axes flip.

Two things about that experiment are worth knowing before running it, both read
out of `icn8505_try_fw_upload()`:

- **The firmware goes to SRAM, not to any flash on the controller.** The driver's
  own comments say *"Send the firmware to SRAM"* and *"Boot controller from
  SRAM"*. Nothing is written persistently, so a wrong build cannot brick the
  touchscreen — cutting power discards it.
- **Swapping the file and reloading the module does nothing.** `icn8505_upload_fw()`
  reads register `0x000a` first and skips the upload entirely if it returns
  `0x85`, meaning the controller is already running. So a new blob needs the
  controller to lose power: a full poweroff, not `modprobe -r` and not
  necessarily a warm reboot.

Fix it in userspace meanwhile. This is a calibration matrix, which is what it is
for — it survives reboots and works under both X11 and Wayland:

```sh
# /etc/udev/rules.d/99-chuwi-touchscreen.rules
ACTION=="add|change", KERNEL=="event[0-9]*", ATTRS{name}=="CHPN0001:00", \
  ENV{LIBINPUT_CALIBRATION_MATRIX}="-1 0 1 0 -1 1"
```

To try it before committing to it, on an X11 session:

```sh
xinput set-prop "CHPN0001:00" --type=float \
  "Coordinate Transformation Matrix" -1 0 1 0 -1 1 0 0 1
```

Do **not** send this upstream as a `touchscreen-inverted-x`/`-y` quirk. If the
cause is the substitute firmware build, such a quirk would break every unit that
gets the blob out of EFI the way the driver intends.

| `_SUB` | Size | SHA-256 |
|---|---|---|
| `HAMP0001` | 34980 | `3e0f9cd2…ff7c58` |
| `HAMP0002` | 34900 | `e895933d…ba092b` |
| `HAMP0003` | 38580 | `5a08fb42…8f6c47` |
| `HAMP0004` | 38580 | `25c059c4…2e124b` |
| `HAMP0005` | 34884 | `4f1deaf3…c897ba` |
| `HAMP0006` | 38580 | `921c04b4…9b88ff` |
| `HAMP0007` | 38580 | `7cb400fe…2fffc5` |

— **verified** by extracting all seven from the package.

#### There is more than one build of this firmware

Do not expect the hashes to line up across sources. For `HAMP0002` alone there are
three different blobs in circulation:

| Where | Size | SHA-256 |
|---|---|---|
| Kernel's pinned value, from **UEFI** | 35012 | `93e549e0…7cfc7c` |
| Chuwi driver package, 2016-04-21 | 34900 | `e895933d…ba092b` |
| [`Dax89/chuwi-dev`](https://github.com/Dax89/chuwi-dev) and [`sciboy12`](https://github.com/sciboy12/vi8-plus-linux-fixes), byte-identical to each other | 34884 | `d9db81b9…c99327` |

The two GitHub copies are **one source, not two** — Dax89 committed in 2016,
sciboy12 in 2025 — and both are almost certainly an older vendor INF, since
`HAMP0004` from that repository is **byte-identical** to the one this script pulls
out of the 2016-04-21 package. So the lineage is clear; only the version differs.

None of this stops any of them working. The pinned length and hash are how the
kernel finds the blob in EFI memory; a file in `/lib/firmware` is loaded as-is, and
the driver's post-upload length and CRC32 checks compare against the file it just
sent, so they verify the I2C transfer rather than the file's provenance. Start with
the vendor package's copy — it is the one with a signature behind it.

It is still **34884 bytes rather than the 35012 the kernel pins**, and the obvious
explanation is wrong: appending or prepending 128 zero or `0xff` bytes does not produce
the kernel's SHA-256, so this is not the UEFI blob with padding trimmed. It is a
different build of the same firmware.

That does not make it useless. The length and hash are how the kernel finds the blob in
**EFI memory**; a file in `/lib/firmware` is simply loaded and sent, and the driver's
own post-upload length and CRC32 checks compare against the size of the file it just
transferred — they verify the I2C transfer, not the file's authenticity. So a 34884-byte
file will not be rejected for being the wrong size. Whether the controller boots from it
is the actual open question.

Reasonable to try if your own flash turns out not to carry the blob. Extract your own
first if you can — a touchscreen firmware is not a thing to take on trust.

### Wi-Fi / Bluetooth — AmPak AP6212 (Broadcom BCM43430)

- Wi-Fi driver: `brcmfmac` over SDIO (`CONFIG_BRCMFMAC=m`, `CONFIG_BRCMFMAC_SDIO=y`)
- NVRAM: `brcm/brcmfmac43430-sdio.Hampoo-D2D3_Vi8A1.txt`, present in `linux-firmware`
  since 2018. Any current distribution has it — **but see the chip revision note
  below before assuming it is the file your unit needs.**
- **2.4 GHz only.** The chip has no 5 GHz radio. This is not a driver limitation.
- Bluetooth: BCM43430 attached over UART, driver `hci_uart` + `btbcm`, patch file
  `brcm/BCM43430A1.hcd` — **from `bluez-firmware`, not `linux-firmware`.**

Wi-Fi is reliable **once it has NVRAM**.

Bluetooth needs its own patch file, and this is the one place the two chip revisions
diverge in a way no amount of configuration fixes:

| Revision | File `btbcm` looks for | Packaged? |
|---|---|---|
| a1 | `brcm/BCM43430A1.hcd` | yes — `bluez-firmware` on both Debian and Ubuntu |
| a0 | `brcm/BCM4343A0.hcd` | **no — no Debian or Ubuntu package ships it** |

So on an a1 unit `sudo apt install bluez-firmware` is the whole fix. On an a0 unit
there is nothing to install: the vendor file (`BCM4343A0-26M.hcd` in Broadcom's
naming) is not redistributed, and a GitHub-wide search for it returns two hits, both
of them somebody's notes rather than the file.

This matches how the driver's maintainer scores the tablet — his own status table
marks Bluetooth `FIR`, defined there as *"needs firmware which is not in
linux-firmware"*, and his unit is an a1. Read the exact name your kernel asked for
out of `dmesg` rather than assuming; see
[50-troubleshooting.md](50-troubleshooting.md#bluetooth-does-not-appear).

#### Two chip revisions ship in this model, and they want different NVRAM

`brcmfmac` picks firmware names by chip **revision**. Check which one you have:

```sh
sudo dmesg | grep brcmf_fw_alloc_request
```

```
brcmfmac: brcmf_fw_alloc_request: using brcm/brcmfmac43430a0-sdio for chip BCM43430/0
```

— **verified on the unit**: revision **a0**.

##### What `a0` and `a1` actually are

Not tablet revisions. They are **silicon steppings of the Broadcom BCM43430 die** —
mask revisions of the chip inside the AmPak module, changed by the module vendor
during production. Two CWI519s with the same model number, the same carton and the
same BIOS can differ here. Nothing on the outside of the tablet says which you have,
and it is not a "Rev 1 / Rev 2" of the product.

The kernel knows three steppings, keyed on the chip's `chiprev` register:

| `chiprev` | Stepping | Wi-Fi firmware basename | Bluetooth name in `btbcm` |
|---|---|---|---|
| 0 | A0 | `brcm/brcmfmac43430a0-sdio` | `BCM4343A0` (LMP subver `0x2122`) |
| 1 | A1 | `brcm/brcmfmac43430-sdio` — **no suffix** | `BCM43430A1` (LMP subver `0x2209`) |
| ≥ 2 | B0 | `brcm/brcmfmac43430b0-sdio` | `BCM43430B0` |

Two traps live in that table. The A1 Wi-Fi basename carries **no revision suffix** at
all — it is the historical default from before the other steppings existed, which is
exactly why `linux-firmware`'s file for this board has no `a0` in its name and why an
a0 unit silently finds nothing. And the Bluetooth side spells the same two steppings
inconsistently: `BCM4343A0` against `BCM43430A1`, one digit apart.

B0 is a later part — it is the one in the Raspberry Pi Zero W — and is not expected in
a 2015-2016 tablet.

##### How to tell which one you have

From software only. The module is soldered to the board under an unmarked shield, so
there is no part number to read even with the case open, and the DMI serial is no help
either: this BIOS ships `product_serial` as a single space. The `dmesg` line above is
the answer — `BCM43430/0` is a0, `BCM43430/1` is a1.

##### When the switch happened

Suggestive rather than settled. Chuwi serial numbers appear to encode the build month
as `YYMM` after the `Q32G22` prefix, and the driver maintainer's collection notes both
serials and chip revisions for the sibling Hi8:

| Serial | Reads as | Model | Revision |
|---|---|---|---|
| `Q32G22**1509**10320` | 2015-09 | Hi8 (CWI509) | a0 |
| `Q32G22**1512**035xx` | 2015-12 | Hi8 (CWI509) | a0 |
| `PQ32G22**1604**11929` | 2016-04 | Hi8 Pro (CWI513) | a0 |
| `Q32G22**1605**05024` | 2016-05 | Hi8 (CWI509) | **a1** |

Seven serials across his Chuwi tablets all carry a valid month in those positions,
which is what makes the reading credible; none of it is documented by Chuwi. On that
evidence the changeover falls around mid-2016, and this tablet's BIOS date of
2015-12-11 sits comfortably on the a0 side — which is what it turned out to be.

Useful as a prior when buying a second-hand unit. Not a substitute for the `dmesg`
check.

That matters because the NVRAM `linux-firmware` ships for this tablet is
`brcmfmac43430**-sdio.Hampoo-D2D3_Vi8A1.txt` — no `a0`, so it came from a unit with the
**a1** revision. The same tablet model shipped with both. There is no `a0` file named
for this board, so an `a0` unit finds nothing and the chip never initialises:

```
Direct firmware load for brcm/brcmfmac43430a0-sdio.txt failed with error -2
brcmfmac: brcmf_sdio_htclk: HT Avail timeout (1000000): clkctl 0x50
```

The DMI leak is wider than the NVRAM file. The board suffix goes into the
*firmware binary* lookup too, so on a unit with unfilled DMI the driver first
asks for this:

```
Direct firmware load for brcm/brcmfmac43430a0-sdio.To be filled by O.E.M.-To be filled by O.E.M..bin failed with error -2
```

— **verified on the unit**, placeholder, spaces and all. That one is harmless:
the driver falls back to the generic firmware and loads it —
`Firmware: BCM43430/0 wl0: May 29 2017 version 7.13.53.9 (r664949)`. Only the
NVRAM failure is fatal.

**One real limitation survives the fix**, and it is worth knowing about because
nothing on the desktop reports it:

```
brcmfmac: brcmf_c_process_clm_blob: no clm_blob available (err=-2), device may have limited channels available
```

— **verified on the unit**. The CLM blob carries per-regulatory-domain channel
data, `linux-firmware` has none for this chip, so the radio falls back to a
conservative built-in channel list. On 2.4 GHz that mostly costs channels 12–14
depending on domain. There is no fix here — the blob does not exist to install.

The NVRAM fix itself does not need DMI: after the DMI-derived name fails, the
driver falls back to the plain `brcm/brcmfmac43430a0-sdio.txt`, so put an NVRAM
there.

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

On a unit with [unfilled DMI](#some-units-ship-with-the-dmi-fields-unfilled-and-it-breaks-three-things-at-once)
this quirk does not fire, and unlike Wi-Fi and the touchscreen there is no
DMI-independent fallback.

**In practice the speaker is fine anyway.** On the reference tablet — DMI unfilled,
so the quirk cannot have matched — `speaker-test -c 2 -t wav -l 1` announces both
"Front Left" and "Front Right" audibly through the single physical speaker, with
nothing lost. **Verified on the unit.** Something below the machine driver already
mixes the two channels down; the quirk was never the thing making that work. An
earlier revision of this file predicted half the audio would disappear, which was
wrong.

So `MONO_SPEAKER` is worth setting for correctness, not for rescue. The half of the
quirk still unverified here is `HP_LR_SWAPPED` — that needs headphones and an ear.

#### Forcing the quirk by hand

The module takes a `quirk=` override — `module_param_named(quirk, quirk_override,
int, 0444)` — so the table entry can be applied without a DMI match. The value,
built from the constants in `bytcr_rt5651.c` and `include/dt-bindings/sound/rt5651.h`:

| Bit | Constant | Value |
| --- | --- | --- |
| 17 | `BYT_RT5651_MCLK_EN` | `0x020000` |
| 13 | `OVCD_SF_0P75` (`1 << 13`) | `0x002000` |
| 8-12 | `OVCD_TH_2000UA` (`20 << 8`) | `0x001400` |
| 4-7 | `JD1_1` (`1 << 4`) | `0x000010` |
| 0-3 | `IN2_MAP` (enum index 2) | `0x000002` |
| 22 | `BYT_RT5651_HP_LR_SWAPPED` | `0x400000` |
| 23 | `BYT_RT5651_MONO_SPEAKER` | `0x800000` |
| | **total** | **`0xC23412`** |

The first five are `BYT_RT5651_DEFAULT_QUIRKS | BYT_RT5651_IN2_MAP`, which is also
the driver's built-in default — so a unit that matches nothing is already running
`0x23412`, and **the only difference the missing quirk makes is the top two bits**:
mono speaker and swapped headphones.

```sh
echo 'options snd_soc_sst_bytcr_rt5651 quirk=0xC23412' |
  sudo tee /etc/modprobe.d/chuwi-vi8-plus-audio.conf
sudo reboot
dmesg | grep -iE 'Overriding quirk|quirk MONO_SPEAKER'
```

Both bits are **advisory to userspace, not routing changes**: the machine driver
only feeds them into the card's components string —

```c
snprintf(byt_rt5651_components, sizeof(byt_rt5651_components),
         "cfg-spk:%s cfg-mic:%s%s",
         (byt_rt5651_quirk & BYT_RT5651_MONO_SPEAKER) ? "1" : "2",
         mic_name[BYT_RT5651_MAP(byt_rt5651_quirk)],
         (byt_rt5651_quirk & BYT_RT5651_HP_LR_SWAPPED) ? " cfg-hp:lrswap" : "");
```

— and UCM picks the profile off that. So the symptom of the missing quirk is
`cfg-spk:2` on a one-speaker tablet, and the fix only works with `alsa-ucm-conf`
installed. `MONO_SPEAKER` is the one bit that announces itself in the log;
`HP_LR_SWAPPED` has no `dev_info`, so headphones have to be judged by ear.

The value is **derived from the kernel source, not yet confirmed on hardware**.

The placeholder is visible here too. ALSA builds the card's long name out of the
same DMI fields, so `aplay -l` on an affected unit reports:

```
1 [rt5651         ]: SOF - sof-bytcht rt5651
                     Hampoo-TobefilledbyO.E.M.-TobefilledbyO.E.M.-CherryTrailCR
```

— **verified on the unit**. Two things worth reading off that line. The card is
driven through **SOF** rather than the legacy SST path, and the machine driver
doing it is still `snd_soc_sst_bytcr_rt5651` — loaded, and in use — which is the
module [`patches/0003`](../patches/) modifies, so the quirk table is the right
place to fix this on a current kernel.

### Accelerometer / auto-rotation — Bosch BOSC0200

- Driver: `bmc150_accel`
- systemd's `hwdb.d/60-sensor.hwdb` carries the mount matrix for this exact device:
  `sensor:modalias:acpi:BOSC0200:*:dmi:*:svnHampoo:pnD2D3_Vi8A1:*` with
  `ACCEL_MOUNT_MATRIX=0, 1, 0; 1, 0, 0; 0, 0, 1`.

Install `iio-sensor-proxy` and rotation works in any Wayland/GNOME/KDE session.
See [40-post-install.md](40-post-install.md#screen-rotation).

The hwdb entry matches on `svnHampoo:pnD2D3_Vi8A1`, so on a unit with
[unfilled DMI](#some-units-ship-with-the-dmi-fields-unfilled-and-it-breaks-three-things-at-once)
the mount matrix is not applied and auto-rotation has no idea which way is up. The
accelerometer itself still works — you can copy the matrix into a local hwdb rule
matched on something your unit actually reports. This is the `modalias` to match
against, read off the tablet:

```
dmi:bvnAmericanMegatrendsInc.:bvrP03_C806.108:bd12/11/2015:br5.11:svnTobefilledbyO.E.M.:pnTobefilledbyO.E.M.:pvrTobefilledbyO.E.M.:rvnHampoo:rnCherryTrailCR:rvrTobefilledbyO.E.M.:cvnToBeFilledByO.E.M.:ct3:cvrToBeFilledByO.E.M.:skuMRD:pfaCherryTrailCR:
```

— **verified on the unit**. Note `rvnHampoo:rnCherryTrailCR`, the board fields, as
the only usable anchors; and note that the placeholder is spelled two ways in the
same string — `svnTobefilledbyO.E.M.` but `cvnToBeFilledByO.E.M.` — so a rule that
matches one capitalisation will not match the other.

**Binding is not the problem; reading it is.** The device does appear, as
`iio:device0` under `i2c-BOSC0200:00`, but `iio-sensor-proxy` cannot get samples
out of it:

```
Could not find trigger name associated with .../i2c-BOSC0200:00/iio:device0
Buffer '/dev/iio:device0' did not have data within 0.5s
```

— **verified on the unit**. So auto-rotation fails for a second, separate reason
beyond the missing mount matrix: no IIO trigger is registered, so the buffered
read that `iio-sensor-proxy` performs never returns data. A plausible cause is
that the driver got no usable interrupt from ACPI and therefore registered no
data-ready trigger, which would leave polling as the only route — **untested
hypothesis**, and worth confirming with `ls /sys/bus/iio/devices/` and
`cat /sys/bus/iio/devices/iio:device0/in_accel_*_raw` before anyone chases it.
If the raw reads work while buffered reads do not, that diagnosis is right.

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

**A charger that is detected is not a charger that is feeding you.** On the
reference unit the input was capped at **500 mA** while the battery supplied the
rest:

```
axp288_charger/input_current_limit:  500000
axp288_charger/online:               1
axp288_fuel_gauge/status:            Discharging
axp288_fuel_gauge/current_now:      -496000
```

The 496 mA leaving the battery against a 500 mA cap is the arithmetic of a
machine drawing roughly an ampere and being allowed half of it. Capacity fell
from 95 % to 86 % over an idle session with the cable in. — **verified on the
unit**

That was through a hub with its own power input. Moving the same charger
**directly** to the tablet's port swung it by more than an ampere:

```
axp288_fuel_gauge/status:       Charging
axp288_fuel_gauge/current_now:  576000
```

Charging the battery at 576 mA *while also running the system* is not possible
under a 500 mA cap, so a directly attached charger negotiates a higher limit on
its own. The hub was presenting itself as an ordinary 500 mA port. — **verified
on the unit**

Raising the limit by hand did **not** rescue the hub case: the write was
accepted, the value read back as `2000000`, and the battery then drained *faster*
(496 mA to 656 mA). The limit is permission, not delivery. If the supply cannot
source it, VBUS sags into the 4.4 V `Vhold` floor and the charger throttles
straight back.

The 500 mA is not a fault or a worn part. It is the driver following the USB
spec, and the branch is right there in `axp288_charger`:

```c
} else if (extcon_get_state(edev, EXTCON_CHG_USB_SDP) > 0) {
        current_limit = 500000;      /* SDP  -> 500 mA */
} else if (extcon_get_state(edev, EXTCON_CHG_USB_CDP) > 0) {
        current_limit = 1500000;     /* CDP  -> 1.5 A  */
} else if (extcon_get_state(edev, EXTCON_CHG_USB_DCP) > 0) {
        current_limit = 2000000;     /* DCP  -> 2 A    */
}
```

A hub looks like a Standard Downstream Port, so it gets the 500 mA a downstream
port is entitled to. A dumb wall charger enumerates as a Dedicated Charging Port
and gets 2 A. **So the rule is not "avoid this hub" but "do not power this tablet
through a hub at all"** — the tablet needs more than 500 mA to run, so any SDP
source leaves it eating the battery. Charger direct, or an OTG charging hub with
a supply behind it.

One practical trap: `axp288_charger` was **absent from sysfs entirely** on one
boot, leaving only `axp288_fuel_gauge`, so the write failed with `No such file or
directory` while charging carried on regardless — nothing had set a limit, and
the hardware default was more generous than the driver's SDP verdict. Check
`ls /sys/class/power_supply/` before reading anything into a failed write.

Two things in `axp288_charger` cause that, and one is fixable from userspace:

- **The input current limit.** It is a discrete ladder — 100, 500, 900, 1500,
  2000 mA and up — and what gets negotiated may be far below what the supply can
  give. The driver exposes it **writable** through sysfs
  (`POWER_SUPPLY_PROP_INPUT_CURRENT_LIMIT` appears in both
  `property_is_writeable` and `set_property`), so no raw register poking is
  needed:

  ```sh
  cat /sys/class/power_supply/axp288_charger/input_current_limit   # µA
  echo 2000000 | sudo tee /sys/class/power_supply/axp288_charger/input_current_limit
  ```

  The driver clears its internal `valid` flag on that write, so expect the value
  to be reconsidered when the charger is next re-detected.
- **`Vhold`, which is not exposed at all.** The driver pins it to the vendor
  default with the comment *"Set Vhold to the factory default / recommended
  4.4V"*. Vhold is the input-voltage floor: if VBUS sags under that — a thin
  cable, a long one, a hub — the charger throttles its input rather than pulling
  the rail down further. Hans de Goede's own procedure for this exact model
  lowers it to 4.3 V with `i2cset`, alongside setting the input current to 2 A.
  That is a raw PMIC register write; treat it as the step after the sysfs one,
  not before it.

This is not a footnote on this tablet. The same notes record its battery as
*"dead (browns out on consumption peaks)"*, needing *"always have a charger
connected"* — and starving the charger is what forces the battery to carry the
peaks. See [50-troubleshooting.md](50-troubleshooting.md#random-freezes).

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
