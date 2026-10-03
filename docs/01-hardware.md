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
| Display | 8.0" IPS, 10-point capacitive touch. **Portrait-native: the scanout is 800x1280**, `/sys/class/graphics/fb0/virtual_size` reads `800,1280` — **verified on the unit**. The kernel has no orientation quirk for this model, so expect to rotate it yourself. See [40-post-install.md](40-post-install.md#if-everything-starts-sideways) |
| Firmware | **32-bit (IA32) UEFI**, no CSM/legacy boot — but see the revision note below; confirm with `fw_platform_size` before trusting it. The unit this guide was written against reports AMI Aptio `2.17.1249`, **BIOS version `1ATFG007`, dated 12/11/2015** |
| Ports | 1x USB Type-C (USB 2.0, power + data, OTG), micro-HDMI 1.4, microSD, 3.5 mm |
| Battery | Li-Po. **Sources disagree:** Notebookcheck's review says 5000 mAh, the 4PDA thread's specification header says Chuwi claims 4000 mAh with owners measuring 3900-4050 mAh. Read your own with `cat /sys/class/power_supply/*/energy_full_design` rather than trusting either |
| Cameras | 2 MP front, 2 MP rear |

The 64-bit CPU with 32-bit-only firmware is the single most important fact about this
device. [docs/02-boot-problem.md](02-boot-problem.md) covers what follows from it.

## Some units ship with the DMI fields unfilled, and it breaks three things at once

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
needed one, as explained above. **Audio is the only one with no automatic second
path**: its quirk keys on the system fields and nothing else supplies the routing,
so it has to be [forced by hand](#forcing-the-quirk-by-hand), or patched properly.

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

## Component-by-component

Every "kernel symbol" below was checked against the configuration actually shipped in
Ubuntu 26.04 LTS (`linux-buildinfo-7.0.0-31-generic`). All of them are enabled.

### Touchscreen — Chipone ICN8505

- Driver: `chipone_icn8505` (`CONFIG_TOUCHSCREEN_CHIPONE_ICN8505=m`)
- Enabled by DMI match in `drivers/platform/x86/touchscreen_dmi.c`
  (`CONFIG_TOUCHSCREEN_DMI=y`), struct `chuwi_vi8_plus_data`.
- Firmware: `chipone/icn8505-HAMP0002.fw`. **Two different numbers get attached to
  that name and they are not interchangeable.** 35012 bytes, SHA-256
  `93e549e0…7cfc7c` is what the kernel's `efi_embedded_fw` descriptor pins when
  extracting from UEFI. What is actually installed on the reference unit is
  Chuwi's own build from the Windows driver package: **34900 bytes**, SHA-256
  `e895933d…ba092b` — **verified on the unit** against the blob extracted from
  `chpntsc.inf`, byte for byte. The full comparison is
  [below](#there-is-more-than-one-build-of-this-firmware).

This firmware is **not** shipped by `linux-firmware` — that repository has no
`chipone/` directory, and its `WHENCE` manifest does not mention `icn8505` or
`chipone` anywhere in its 10534 lines. — **verified**. No distribution packages
it, so there is no package to install; every route to the file goes through
Chuwi. It lives inside the tablet's own
UEFI image, and the kernel extracts it at boot through the EFI embedded-firmware
mechanism (`CONFIG_EFI_EMBEDDED_FIRMWARE=y`) that Hans de Goede added specifically for
this class of tablet. Where that works there is nothing to download, though it does
mean the touchscreen depends on booting via EFI and on that config option being
enabled. On the reference unit it does not work, for two independent reasons — the
DMI quirk does not match, and the blob is not in this BIOS build to begin with.

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

There are two ways to get the file, and on this BIOS build only one of them works.
`linux-firmware` does not carry it, but Chuwi's own Windows driver does — that is
the route that produced a working touchscreen here, below.

The other would be to pull the copy out of your own flash, which is the only way to
get the exact blob the kernel pins: **35012 bytes**, starting with
`b0 07 00 00 e4 07 00 00`, SHA-256
`93e549e0b6a2b4b3889634975ea81378729b8b829eb5ca7f125134f4307cfc7c`.
`sudo ./scripts/dump-bios.sh` reads the flash twice, refuses a dump the two reads
disagree on, searches it for that prefix and installs the result only if the hash
matches.

**On this unit it finds nothing.** The dump was taken — two passes, identical,
8388608 bytes — and reported *"Not found as a contiguous blob"*, matching the same
negative result against all three published images. — **verified on the unit**, see
[60-bios-firmware.md](60-bios-firmware.md#what-could-not-be-determined). So on this
build the EFI extraction has nothing to extract whether the DMI quirk matches or
not, and installing `flashrom` to go looking is time spent confirming an answer
this repository already has. Use the driver package.

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

**Then check the interrupt rate before you consider this finished.** This blob
gives a working touchscreen and a permanent interrupt storm that costs roughly
4 °C and most of the machine's idle depth, for reasons covered in
[the section below](#the-touchscreen-holds-its-interrupt-line-asserted-forever):

```sh
grep CHPN0001 /proc/interrupts; sleep 10; grep CHPN0001 /proc/interrupts
```

Hundreds per second with nobody touching the glass means you have it. The
34884-byte build linked in that section does not do this, on the one unit where
both have been compared.

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

#### Rotate the display and touch stops matching it

**In the orientation the tablet ships in, the axes are correct and there is nothing
on this page you need to do.** This section is for the case where you have
deliberately rotated the display, because then the pointer starts landing opposite
the finger: touch the top right and it goes to the bottom left.

Wall mounting is the usual reason to rotate it, and where the charge cable has to
exit is usually the reason for the angle: the reference unit hangs turned 180° so
that the single USB-C port ends up along the bottom edge and the cable drops away
instead of standing up. Turning the tablet fixes the cable and breaks two other
things in sequence — the display is upside down until you rotate it in software,
and touch is upside down until you do the separate thing below.

Measured off two frames of a video rather than eyeballed, on a unit rotated 180°:
finger at (0.69, 0.26) gave a pointer at (0.30, 0.74), and (0.84, 0.46) gave
(0.18, 0.65) — `x → 1-x, y → 1-y` on both, no axis swap, so a 180° rotation and not
a 90° one. — **verified on the unit**

**This is not a fault in the controller, and an earlier revision of this document
was wrong to read it as one.** The touchscreen reports in the panel's own
coordinates and knows nothing about how the display is rotated; X applies the
rotation to the *output* and, without a transformation matrix, leaves the input
device alone. A correct controller under a 180°-rotated display produces exactly
`x → 1-x, y → 1-y`. So does a controller with both scan directions reversed, which
is why the measurement above cannot tell the two apart — it was never a test of the
firmware, and reading it as one sent this document chasing firmware builds for a
problem that was a missing matrix.

Reading the raw evdev stream *does* tell them apart, because it is taken before any
userspace matrix is applied. On the rotated unit — `xrandr` reporting
`DSI-1 ... inverted` — one deliberate tap on the *visually* top-left corner, which
is physically the panel's opposite corner, read `raw=(759,1262)` against axis ranges
`X (0,799)` and `Y (0,1279)`: 0.95 and 0.99 of full scale. **The controller named
the corner that was actually touched.** — **verified on the unit**

So if the pointer lands wrong, check `xrandr` first. An output that is rotated while
its input is not is the whole explanation, and the matrix below is the fix — not a
different firmware blob.

Two things about swapping firmware builds are worth knowing, both read out of
`icn8505_try_fw_upload()` and both since exercised on the unit:

- **The firmware goes to SRAM, not to any flash on the controller.** The driver's
  own comments say *"Send the firmware to SRAM"* and *"Boot controller from
  SRAM"*. Nothing is written persistently, so a wrong build cannot brick the
  touchscreen — cutting power discards it.
- **Unbind and rebind is enough to load a new blob; a poweroff is not needed.**
  `icn8505_upload_fw()` reads register `0x000a` and skips the upload if it returns
  `0x85` for "already running" — but the controller does not survive a rebind in
  that state, because `_PS0` resets it on the way back in (see
  [the storm section](#the-touchscreen-holds-its-interrupt-line-asserted-forever)).
  Measured: a bind takes ~1500 ms against the ~125 ms `_PS0`'s own sleeps account
  for, and the difference is a full re-upload of the blob over I2C.
  — **verified on the unit**

Fix the orientation in userspace. This is a calibration matrix, which is what it is
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

#### The touchscreen holds its interrupt line asserted, forever

On the reference unit — running the substitute firmware above — the touchscreen
fires **463 interrupts per second with nobody touching it**, and has done since
boot. It costs more than it looks, and it is invisible in `top` except as one
kernel thread.

```sh
grep CHPN0001 /proc/interrupts; sleep 10; grep CHPN0001 /proc/interrupts
cat /sys/kernel/irq/$(awk -F: '/CHPN0001/{print $1}' /proc/interrupts | tr -d ' ')/type
```

— **verified on the unit**: `463/s` sustained over 60 s, `type` reads `level`.

**The mechanism, end to end.** The GPIO is level-triggered (`chv-gpio` hwirq 19).
The driver takes it with `devm_request_threaded_irq(..., NULL, icn8505_irq,
IRQF_ONESHOT, ...)`, so the line is masked while the handler runs and unmasked
when it returns. `icn8505_irq()` then reads `ICN8505_REG_TOUCHDATA` over I2C
*unconditionally* and returns `IRQ_HANDLED` *unconditionally* — including when
`touch_count` is zero. So if the controller never deasserts the line, the cycle
repeats at the speed of one I2C read, which measures out at ~2.2 ms.

Two consequences worth knowing:

- **The kernel's own protection cannot see it.** The spurious-interrupt detector
  disables a line after 100 000 interrupts *nobody claimed*. This handler claims
  every one of them, so `note_interrupt()` never fires and nothing is ever
  logged. The storm is silent by construction.
- **It multiplies on the I2C bus.** Each touchscreen interrupt costs one
  multi-byte I2C read, and the Cherry Trail LPSS controller interrupts per FIFO
  threshold: `808622C1:04`, the controller this touchscreen sits on, runs at
  **~32 000 interrupts per second**. — **verified on the unit**

**What it costs, measured by taking it away.** Unbinding `chipone_icn8505` for one
120 s window between two windows with it bound brackets the storm, so drift in
whatever else the machine is doing shows up as a difference between the two
brackets rather than as a result. `scripts/measure-touchscreen-irq.sh` runs it and
rebinds the driver on every exit path, including `Ctrl-C`; the touchscreen is dead
for the middle window only.

| | 1 bound | 2 unbound | 3 bound again |
|---|---|---|---|
| touchscreen IRQ | 411/s | **0** | 466/s |
| I2C controller IRQ | 27 858/s | **0** | 32 406/s |
| `irq/…-CHPN0001:00` thread | 4.5% of a core | 0% | 3.5% of a core |
| CPU0 idle wakeups | 14 074/s | **41/s** | 23 820/s |
| `C6N` residency | 2.4% of wall | **62.3%** | 3.5% of wall |
| mean `C6N` stay | 44 µs | **1106 µs** | 59 µs |
| `PNIT` | 65.4 °C | **61.6 °C** | 66.2 °C |
| Xorg | 13.7% of a core | 14.2% | 13.8% |
| the browser running on the unit | 83.2% of a core | 87.8% | 73.0% |

— **verified on the unit**

**The CPU time is not the cost.** 4.5% of one core disappears into the noise: total
busy across all cores went 35.6% → 32.4% → 29.9%, putting the unbound window
*between* its brackets rather than below both. Anyone measuring this storm with
`top` alone would conclude it is harmless.

**The idle cost is what matters.** CPU0's wakeups fall from 14 074/s to 41/s — a
factor of 345 — and `C6N` goes from 2.4% of the wall clock to 62.3%. The quality
changes as well as the share: with the storm running, the governor's `C6N` entries
average 44 µs against a 275 µs target residency, so nearly every entry is a net
loss; without it they average 1106 µs, four times the target.

**The thermal cost is about 4 °C.** `PNIT` averaged 65.4 °C and 66.2 °C in the
bracketing windows against 61.6 °C unbound. Treat that as a floor rather than a
figure: 120 s does not settle a fanless chassis, and the run trended warmer
throughout. This is the link to [51-freezes.md](51-freezes.md) — the tablet's idle
temperature is a C-state story, and the core servicing the touchscreen is held out
of the deepest state it is allowed to use.

**The storm never reaches userspace.** Xorg held at 13.7 / 14.2 / 13.8% and the
browser at 83.2 / 87.8 / 73.0%, neither of them tracking the storm. That matches
the driver: `icn8505_irq()` does call `input_sync()` on every interrupt, but with
no finger down `input_mt_sync_frame()` emits no values — `BTN_TOUCH` is unchanged,
the ABS axes are unchanged, and input core drops both — so the frame arrives at
`input_handle_event()`'s flush carrying a lone `SYN_REPORT` and `if (dev->num_vals
>= 2)` discards it. A userspace process burning CPU on this tablet is therefore
not burning it on the touchscreen; look elsewhere.

**Rebinding does not clear it, but that says less than it looks.** The storm
returned at full rate the moment the driver rebound. Rebinding neither resets the
controller nor re-uploads the firmware — `icn8505_upload_fw()` reads register
`0x000a`, sees `0x85` for "already running", and skips the upload. What the middle
window does establish is that the controller holds the line asserted through 140 s
of being ignored entirely, with no driver attached and the IRQ freed. Neither
reading the touch register nor detaching from it deasserts the line.

**It is the firmware build, and swapping it ends the storm.** Everything above was
measured under Chuwi's own `HAMP0002` out of `chpntsc.inf` — `e895933d…ba092b`,
34900 bytes, byte-identical to what the vendor's Windows driver installs, checked
with `sha256sum` on the tablet. So the storm is not the fault of a community
substitute; it is the fault of the manufacturer's own build for this exact panel.
Dropping the 34884-byte build from
[another owner's repository](90-references.md#another-owners-fixes-for-this-exact-tablet)
into `/lib/firmware/chipone/icn8505-HAMP0002.fw` and rebinding the driver takes the
line quiet:

| driver bound in both columns | 34900, Chuwi's own | 34884, the other build |
|---|---|---|
| touchscreen IRQ | 411-490/s | **0/s** |
| I2C controller IRQ | 27 858-34 081/s | **0/s** |
| CPU0 idle wakeups | 14 074/s | **36/s** |
| `C6N` residency | 2.4% of wall | **66.4%** |
| mean `C6N` stay | 44 µs | **1122 µs** |
| `irq/…-CHPN0001:00` thread | 4.5% of a core | **0.0%** |

— **verified on the unit**

The right-hand column is the machine idling as well as it did with the driver
unbound entirely, except that the driver is loaded and the touchscreen works.
That last part was checked rather than assumed, because a controller that has gone
*silent* looks identical to one that has been *fixed* from every angle except a
finger: reading the raw evdev stream afterwards gave `BTN_TOUCH` up and down,
per-frame tracking, releases, and coordinates across the full range of both axes.

The kernel's own pinned build — 35012 bytes — is a third thing again, and could not
be compared: it is not present in this unit's flash. See
[60-bios-firmware.md](60-bios-firmware.md#what-could-not-be-determined).

#### Both operating systems reset this controller, by different routes

This section used to argue that Linux never resets the chip and that this was the
likely cause of the storm. Both halves turned out to be wrong, and the reasoning is
kept here because the wrong version is the intuitive one and someone else will
arrive at it.

Both read the same ACPI, and the interrupt half is identical: the `_CRS` for
`CHPN0001` declares

```
GpioInt  pin 19  Level  ActiveLow  Exclusive  NoWake  debounce 0
```

— **verified** by extracting the DSDT from `P03_C806.108` and decoding the
descriptor. Level-triggered active-low is what *both* operating systems get;
Linux is not misprogramming the line.

The difference is the resource next to it. The same `_CRS` declares a **second**
resource, `GpioIo` on **pin 25**, an output — and:

| | Linux `chipone_icn8505` | Windows `Chpntsc.sys` |
|---|---|---|
| claims the GPIO | **no** — the driver contains no `gpiod_*` call at all | yes: `get gpio resource, TransLH:%d,%d, RawLH:%d,%d.` |
| resets the controller | **no such code path** | yes: `icn85xx_ts_reset` |
| ACPI probe reads | `_SUB` only, to build the firmware filename | full resource list |

— **verified** by grepping the kernel driver, and from strings in
`TP_X64/Chpntsc.sys` in Chuwi's driver package.

`icn8505_probe_acpi()` really does only one thing: `acpi_get_subsystem_id()` into
`snprintf("chipone/icn8505-%s.fw")`. Nothing else in the driver ever looks at the
second resource, and `ICN8505_REG_POWER` is written only on suspend.

**What does not follow — and what an earlier revision of this document claimed — is
that Linux therefore never resets the controller. It does. The reset lives in the
firmware, not in the driver.** `CHPN0001`'s `_PS0` *is* the reset pulse:

```asl
Method (_PS0, 0, Serialized)
{
    If ((^^^^GPO1.AVBL == One)) { ^^^^GPO1.TCTL = One }
    Sleep (0x05)
    If ((^^^^GPO1.AVBL == One)) { ^^^^GPO1.TCTL = Zero }
    Sleep (0x78)
}
```

`TCTL` is a one-bit field of a `GeneralPurposeIo` operation region in `\_SB.GPO1`
whose `Connection` names pin `0x19` — pin 25, the same pin. So `_PS0` asserts the
reset for 5 ms and waits 120 ms for the controller to come back, which is the shape
of the vendor's `ctp_reset()`. Linux runs it at every probe: `i2c_device_probe()`
calls `dev_pm_domain_attach()`, and the ACPI power domain puts the device into D0.

Two independent observations show it actually executes, rather than merely existing:

- `/sys/kernel/debug/gpio` labels pin 25 `ACPI:OpRegion`. That label is applied by
  `acpi_gpio_adr_space_handler()` only when the region is genuinely accessed, and
  `TCTL` is written in exactly two places in the whole DSDT — the two lines above.
  So `AVBL` was set and both writes went through.
- A bind takes **~1500 ms**, where `_PS0`'s own sleeps account for 125 ms. The
  remainder is a full re-upload of the blob, which `icn8505_upload_fw()` performs
  only once register `0x000a` has stopped returning `0x85`. The controller had lost
  its SRAM, so it really was reset.

— **verified on the unit**

And it does not help: a fresh reset followed by a fresh upload of the 34900-byte
blob brings the line straight back down. **The missing-reset theory is refuted.**
What survived it was the build, which is what the table above tests. Do not spend
time driving pin 25 by hand — it is already being driven, and it is not the answer.

One more thing the strings settle: `Chpntsc.sys` carries `icn85xx_*` symbol names
and a stray `/system/bin/ICN87xx.bin` path, so the Windows driver is itself a port
of ChipOne's Android driver. The kernel driver's own comment cites that Android
driver too. All three descend from the same vendor code.

That common ancestor also disposes of the other obvious candidate. Reading
ChipOne's `icn85xx.c` in the rk3188 tree, **there is no interrupt-acknowledge write
anywhere**: the vendor's touch path is
`icn85xx_i2c_rxdata(0x1000, buf, POINT_NUM*POINT_SIZE+2)` and nothing after it —
the same register the kernel driver reads, with no follow-up write to clear a
status bit. So the Linux driver is not missing an ack step either. — **verified**
against
[`bbelos/rk3188-kernel`](https://github.com/bbelos/rk3188-kernel/blob/master/drivers/input/touchscreen/ICN8503/icn85xx.c).

With the ack and the reset both eliminated and the build demonstrated, the
remaining question is not why Linux storms but **why this build of the firmware
does**, on hardware whose vendor shipped it. That is a question about the blob, and
nothing in the driver will answer it.

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
| a1 | `brcm/BCM43430A1.hcd` | yes — `bluez-firmware`, **Ubuntu multiverse** |
| a0 | `brcm/BCM4343A0.hcd` | **no — and not upstream either** |

So on an a1 unit `sudo apt install bluez-firmware` is the whole fix, provided
multiverse is enabled; the package is not in `main`, so a default install will
report it as unavailable rather than as missing a component.

On an a0 unit there is nothing to install, and the reason is worth knowing before
you go looking. `bluez-firmware` repackages the Cypress-licensed set that the
Raspberry Pi project maintains, and that set is `BCM43430A1`, `BCM43430B0`,
`BCM4343A2`, `BCM4345C0`, `BCM4345C5` — **verified** by unpacking
`bluez-firmware_1.2-11ubuntu2_all.deb`, whose `brcm/` directory holds exactly those
five. A0 is not a packaging omission somebody could file a bug about; it is absent
from the licensed release the package is built from. `linux-firmware` has it no
better: its `WHENCE` lists one Broadcom `.hcd` in total, `BCM-0bb4-0306.hcd`. The
vendor file (`BCM4343A0-26M.hcd` in Broadcom's naming) is not redistributed, and a
GitHub-wide search for it returns two hits, both of them somebody's notes rather
than the file.

This matches how the driver's maintainer scores the tablet — his own status table
marks Bluetooth `FIR`, defined there as *"needs firmware which is not in
linux-firmware"*, and his unit is an a1. Read the exact name your kernel asked for
out of `dmesg` rather than assuming; see
[50-troubleshooting.md](50-troubleshooting.md#bluetooth-appears-but-has-no-address).
On this a0 unit it asked for `brcm/BCM4343A0.hcd`, did not get it, and brought
the adapter up anyway with a placeholder address. Both halves of that are visible
without doing anything:

```
Bluetooth: hci0: BCM: firmware Patch file not found, tried:
Bluetooth: hci0: BCM: 'brcm/BCM4343A0.hcd'
Bluetooth: hci0: BCM: 'brcm/BCM.hcd'
```

```
hci0:   Type: Primary  Bus: UART
        BD Address: AA:AA:AA:AA:AA:AA  ACL MTU: 1021:8  SCO MTU: 64:1
        UP RUNNING
```

— **verified on the unit**. `AA:AA:AA:AA:AA:AA` is not a redaction, it is what the
controller reports when it has no patch file: the address lives in the `.hcd`, so
without one every such unit claims the same address. `UP RUNNING` is why this is
easy to miss — the adapter looks healthy and cannot pair.

#### Two chip revisions ship in this model, and they want different NVRAM

`brcmfmac` picks firmware names by chip **revision**. Check which one you have:

```sh
sudo dmesg | grep brcmf_fw_alloc_request
```

```
brcmfmac: brcmf_fw_alloc_request: using brcm/brcmfmac43430a0-sdio for chip BCM43430/0
```

— **verified on the unit**: revision **a0**.

**What `a0` and `a1` actually are.**

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

**Telling them apart is software-only.** The module is soldered under an unmarked
shield, so there is no part number to read even with the case open, and the DMI serial
is no help either: this BIOS ships `product_serial` as a single space. The `dmesg` line
above is the answer — `BCM43430/0` is a0, `BCM43430/1` is a1.

**When the switch happened** — suggestive rather than settled, and useful only as a
prior when buying second-hand. Chuwi serial numbers appear to encode the build month
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

**In practice the speaker is fine anyway.** The driver says outright which bits it
ended up with:

```
bytcr_rt5651 bytcr_rt5651: quirk IN2_MAP enabled
bytcr_rt5651 bytcr_rt5651: quirk MCLK_EN enabled
```

— **verified on the unit**. No `MONO_SPEAKER`, so the DMI entry did not match and the
driver is running on its built-in default. And yet `speaker-test -c 2 -t wav -l 1`
announces both "Front Left" and "Front Right" audibly through the single physical
speaker, with nothing lost — **verified on the unit**. Something below the machine
driver already combines the two channels; the quirk was never what made that work.

The components string does reach userspace, though, and there is direct evidence of
it: `wpctl status` names the capture device **"Built-in Audio Internal Microphone on
IN2"** — **verified on the unit**. That "on IN2" is UCM reading `cfg-mic:in2` out of
the string the machine driver built. So the mechanism works; it is only the two
missing bits that never got into it.

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
it never fires — **and on this tablet that does not matter**, because the driver
asks ACPI first and `ROTM` answers, as the reading above shows. No local hwdb rule
is needed. Note also that the two sources disagree: hwdb carries
`0, 1, 0; 1, 0, 0; 0, 0, 1` while this unit's own firmware reports
`0, -1, 0; -1, 0, 0; 0, 0, 1`. Which of the two is right for this panel has not
been established here; the firmware's is the one in use. For the quirks that *do*
key on DMI, this is the `modalias` to match against, read off the tablet:

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

### Storage

eMMC via `sdhci-acpi`. **Do not hardcode `mmcblk0`. On this tablet it is not
`mmcblk0`.**

The SoC has three SDHC controllers and the eMMC is not on the first one. Read
today off the installed system, kernel `7.0.0-30-generic`, with no card in the
slot:

| host | ACPI | what is on it | block device |
|---|---|---|---|
| `mmc0` | `80860F14:02` | **Wi-Fi** — SDIO, Broadcom `0x02d0:0xa9a6`, driver `brcmfmac` | none, it is not storage |
| `mmc1` | `80860F14:03` | the microSD slot | whatever you insert |
| `mmc2` | `80860F14:00` | **the eMMC** | `mmcblk2`, plus `mmcblk2boot0/1` and `mmcblk2rpmb` |

— **verified on the unit**

So the eMMC came up as `mmcblk2` with **nothing in the card slot at all**, because
the Wi-Fi radio holds `mmc0`. A reader who assumes the eMMC is the lowest-numbered
`mmcblk` is wrong on this hardware, and the mistake lands on `sgdisk --zap-all`.

An earlier capture from a live session, below, shows the same eMMC as `mmcblk0`.
Both readings are real; what varies is not documented here, so **the number is not
something to carry between sessions** — derive it every time:

```sh
lsblk -d -o NAME,SIZE,TYPE          # the eMMC is the ~29 GiB one
```

Two independent confirmations that you have the right device: only the eMMC has
`mmcblkNboot0` and `mmcblkNboot1` siblings, and `cat /sys/block/mmcblkN/device/type`
reads `MMC` for eMMC against `SD` for a card.

Stock `/proc/partitions` on an untouched unit, read from a live session, for
orientation — sizes in 1 KiB blocks. **Note the device number differs from the
table above; that is the point of this section:**

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

That matches what owners have said for years (4PDA #2191, #2410, #3411).

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

Cherry Trail routes the cameras through the Intel ISP2401 ("atomisp") on PCI
`00:03.0` (`8086:22b8`, subsystem `7270`). Both sensors are `ov2680`, 2 MP, and both
are enumerated over ACPI and I2C as `OVTI2680:00` and `OVTI2680:01`.

**Both cameras work, with two locally built modules and no replacement kernel.** —
**verified on the unit**, 2026-10-03 on `7.0.0-34-generic`: both sensors bind,
`/dev/video0` appears, and a frame from the front camera shows the room it is
pointed at. They do not work on a stock install, and getting from one to the other
meant passing three separate walls. `scripts/camera/build-modules.sh` builds the
modules and `scripts/camera/capture.sh` takes a frame from each camera.

**Wall 1: the driver is unbuilt, not missing.** Ubuntu ships
`# CONFIG_INTEL_ATOMISP is not set`, so the only thing claiming the ISP is
`intel_atomisp2_pm`, whose whole job is to park the device in D3cold. Everything
else is already in place: the mainline `ov2680` driver is built and loaded,
`CONFIG_IPU_BRIDGE` and the `videobuf2` modules are built, and the firmware ships in
`linux-firmware-intel-graphics` as
`/usr/lib/firmware/intel/ipu/shisp_2401a0_v21.bin.zst`. Distributions disable the
option because before kernel 6.7 the driver broke unrelated machines (Launchpad
#2017444). atomisp is a module and every dependency is already `=m`, so its subtree
builds against the installed headers — which is also the only way to get matching
symbol CRCs, since `CONFIG_MODVERSIONS=y` and the published `linux-source` package
runs ahead of the installed kernel. Two details decide whether that build works:
atomisp's Makefile writes every include as
`$(srctree)/drivers/staging/media/atomisp/...` while `linux-headers` ships no driver
sources, so the extracted subtree has to be reachable at exactly that path inside the
headers tree; and Secure Boot has to be off, or the unsigned module will not load.
Two warnings from that build are noise: the compiler one compares
`x86_64-linux-gnu-gcc` against `gcc` of the identical version, and BTF generation is
skipped because `pahole` is not installed.

**Wall 2: two identical sensors, one clock name.** `ov2680.c` asks for its clock with
`devm_v4l2_sensor_clk_get(dev, "xvclk")`. On ACPI there is no clock provider to find,
so the helper — `__devm_v4l2_sensor_clk_get()` in `drivers/media/v4l2-core/` —
registers a fixed-rate clock itself and names it after that con_id. Clock names are
global, so the second sensor to probe dies with `-EEXIST`, and which one that is
changes between boots. On atomisp it costs *both* cameras rather than one: the video
nodes are registered from the async notifier's `.complete` callback, which never
fires while one expected subdev is missing.

The helper already has the answer in it. Given a NULL con_id it names the clock
`clk-<dev_name>`, which is unique per sensor, and the registered clock is handed
straight back to the caller rather than looked up by name — so the name is free to
be anything. One argument is the whole fix, and rebuilding `videodev` is not
required: changing `ov2680` alone is enough, and `ov2680` is a small module nothing
holds open. The better form of the same change belongs in the helper, where it
covers every ACPI board with two identical sensors; it is written out in
[`patches/0004-…`](../patches/0004-media-v4l2-core-name-a-registered-sensor-clock-after-the-device.patch).

Two approaches that look like they should work do not, and both were tried first:

- **Deleting one sensor's I2C client cannot work, at any address.**
  `delete_device_store()` only walks `adap->userspace_clients`, the list of clients
  created through `new_device`. An ACPI-enumerated sensor is never on that list, so
  the write returns `ENOENT` whatever address it carries. The addresses, for the
  record, are `0x10` on `i2c-2` and `0x36` on `i2c-0`.
- **Keeping one sensor out of the fwnode graph aborts the whole graph.**
  `ipu_bridge_connect_sensor()` treats an error from the per-sensor parse callback as
  fatal — `goto err_put_adev`, and the caller unwinds every sensor it had already
  built. A port filter there costs both cameras instead of excluding one.
  A filter in atomisp's own `atomisp_csi2_bridge_parse_firmware()` (the `only_port`
  module parameter, kept because it is still useful) narrows only what the notifier
  waits for; `ov2680` binds by ACPI match and `ipu_bridge` builds endpoints for every
  sensor it finds, so the other sensor still probes and still takes the clock.

**Wall 3: the firmware allocation counts `MemFree`, not `MemAvailable`.** With the
sensors sorted out, the driver gets as far as loading the CSS firmware and can fail
there:

```
alloc_pages_bulk() failed
hmm_bo_alloc_pages failed.
css load fw failed.
Failed to init css.
probe with driver atomisp-isp2 failed with error -22
```

The firmware is 11.5 MB — 2953 order-0 pages, requested in one `alloc_pages_bulk()`
call with `__GFP_NOWARN | __GFP_RECLAIM | __GFP_FS`. The bulk allocator does not
reclaim: it checks the zone watermark against `free pages`, and on any shortfall
returns a single page, which the driver reads as failure. So the 700-odd MB of
`MemAvailable` that a kiosk tablet reports is irrelevant — it is page cache, and the
allocator will not turn it back into free pages. This failed at `MemFree` 151 MB with
836 MB in page cache, and succeeded at `MemFree` 673 MB after stopping the browser
and dropping caches. The exact threshold was not measured, only the two outcomes.
On a unit whose watchdog relaunches the browser, stop the watchdog too, or the memory
is back inside a minute.

**What you get.** One capture node, not two: `/dev/video0` with the two sensors as
selectable inputs, plus `/dev/media0`.

| Input | I2C | ACPI | CSI port | Faces |
|---|---|---|---|---|
| 0 | `2-0010` | `OVTI2680:01` | 0 | front, the side the screen is on |
| 1 | `0-0036` | `OVTI2680:00` | 1 | rear |

The port numbers are the driver's own: `atomisp_csi2_parse_sensor_fwnode()` assigns
`V4L2_FWNODE_ORIENTATION_BACK` to link 1 and `FRONT` to everything else, and the ACPI
descriptions agree — `OVTI2680:01` has a real DSM entry (`Using DSM entry CsiPort=0`),
a regulator supplier and a wakeup source, while `OVTI2680:00` gets
`Using default CsiPort=1` because its DSM has nothing to say.

Frames come out as 1600x1200 planar YUV 4:2:0, 2883584 bytes with the padding. The
first frames are a bright noise band over black, before exposure settles — skip a
batch (`--stream-skip=40`) rather than reading the first one. Most of the ISP's
controls return `error 22 getting ctrl` on this build; `image_color_effect` is one of
the few that answers.

**What it costs.** Measured 2026-10-03 with the kiosk dashboard running, which
idles at 3% of the four cores; temperatures stayed between 38 and 40 C
throughout, well under this SoC's 77 C cliff.

| Size | fps | Per frame | Stream | CPU, 4 cores |
|---|---|---|---|---|
| 640x480 | 28 | 452 kB | 12.4 MB/s | 2% |
| 800x600 | 28 | 732 kB | 20.1 MB/s | 2% |
| 1600x1200 | 27 | 2816 kB | 76.6 MB/s | 6% |

**The frame rate is not a knob.** `VIDIOC_S_PARM` returns `EINVAL` and
`--get-parm` reports `Frames per second: invalid (0/0)`; the sensor runs at ~28
fps at every size it offers. Resolution is the only setting that changes the
load, and the way to get a lower rate is to keep the stream open and drop
frames — stopping and restarting it costs about 40 frames of exposure settling
each time.

Two measurement traps, both of which produced wrong numbers here first:

- `--stream-to=/dev/null` measures the driver and the DMA, not the work.
  A `write()` to `/dev/null` never reads the buffer, so the CPU never touches a
  pixel and 1600x1200 looks as cheap as 640x480. The table above pipes the
  frames into `wc -c` instead, which does.
- `--set-fmt-video` belongs to the open file description, not to the device.
  Setting it in one `v4l2-ctl` invocation and streaming in the next silently
  gives full-resolution frames while `--get-fmt-video` cheerfully reports the
  size you asked for. Put both in the same invocation.

Encoding is what actually costs, and it has to be done in software — there is no
JPEG encoder in this ISP's path. PIL at 640x480 and 5 fps takes **about 20% of
one core** (8% of four, with the kiosk running). Scaling that to the sensor's
full 28 fps lands past a whole core, so a few frames per second is the sensible
ceiling for anything that re-encodes here. Over a remote link the raw stream is
not an option either — 12.4 MB/s at 640x480, against roughly 130 kB/s for the
same frames as JPEG at quality 70 and 5 fps.

**Three things to know before trying any of this, all learned the hard way.**

`atomisp` loads once per boot. A second `insmod` in the same session fails at probe
with `-EEXIST`, after a burst of `the pages is not freed, free pages first` and `the bo
is still binded, unbind it first...`. The colliding state is not inside atomisp:
`ipu_bridge`, `intel_skl_int3472_discrete` and `atomisp_gmin_platform` each sit at a
refcount of 1 held by atomisp, and unloading atomisp alone leaves all three in place
along with the fwnode graph `ipu_bridge` built. Reboot between attempts.

**Do not unload `ov2680`.** Its remove path corrupts a list and then crashes —
`WARNING: lib/list_debug.c:62 at __list_del_entry_valid_or_report`, then `Oops: general
protection fault, probably for non-canonical address` — and leaves the module wedged
at refcount `-1`, where it can be neither loaded nor unloaded. Only a reboot clears
that. The way around it is not to unload it: blacklist the stock module so the local
one can be inserted into a clean boot. See
[40-post-install.md](40-post-install.md#cameras).

**It survives a reboot and a kernel upgrade, through DKMS.** —
**verified on the unit**: after `scripts/camera/install-persistent.sh` and a reboot,
`atomisp`, `atomisp_gmin_platform` and `ov2680` load by themselves, both sensors bind,
`/dev/video0` is present, and a frame can be taken without touching a module. Three
things make that work, and each of them is a decision rather than a detail:

- **DKMS, not a copy into `/lib/modules`.** A module is built for one exact kernel, so
  the next update changes `vermagic` and the camera disappears silently. DKMS rebuilds
  on every kernel install, which converts that into a visible build failure, and it is
  why `linux-headers-generic` has to be present as the meta package. It is not a
  guarantee: atomisp is staging, its internal APIs move, and some kernel will need the
  sources refreshed rather than rebuilt.
- **`intel_atomisp2_pm` is blacklisted so atomisp can have the device.** Both match PCI
  `8086:22b8`, and the stub's only job is parking the ISP in D3cold. Nothing is given
  up: with atomisp bound and nothing streaming, the device reads back `D3cold` and
  `runtime_status suspended`, so an idle camera costs nothing measurable.
- **The in-tree `ov2680` is deliberately not blacklisted.** A blacklist matches on
  module name, and the DKMS build carries the same name; it wins because `updates/`
  comes before `kernel/` in the search order. The earlier blacklist existed only while
  the local module had to be inserted by hand into a boot where nothing had claimed the
  sensors yet.

A browser needs two more things that have nothing to do with the driver: Firefox here
is a snap, so its `camera` interface has to be connected, and `getUserMedia` is refused
outside HTTPS or localhost whatever the camera is.

### Power — X-Powers AXP288 PMIC

Battery and charging behaviour is in
[Ports, OTG, and charging](#ports-otg-and-charging-while-a-hub-is-attached) below,
because on this tablet the two cannot be discussed apart.

- `axp288_charger`, `axp288_fuel_gauge`, `CONFIG_INTEL_SOC_PMIC=y`
- Backlight is driven through the Cherry Trail LPSS PWM (`CONFIG_PWM_LPSS=y`).

Battery percentage, charge state and brightness all work. Reported capacity can be a
little optimistic; the fuel gauge is calibrated by the firmware, not by Linux.

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
peaks. See [51-freezes.md](51-freezes.md).

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

Micro-HDMI 1.4 is wired for output up to 1080p with audio, and the kernel drives
it through the same `i915` pipeline as the panel. **Not exercised here** — nothing
has been plugged into that port on the reference unit.

## Verifying all of this on your own device

```sh
sudo ./scripts/collect-hw-report.sh
```

Run it from the live session before you install anything. It writes a single file with
DMI strings, firmware bitness, loaded modules, sound cards, input devices, power supply
state and the relevant `dmesg` lines. If something in the table above does not match
your unit, that report is what you want to look at first.
