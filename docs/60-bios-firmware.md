# The BIOS on this tablet

Most of the awkward parts of running Linux here trace back to the firmware, so
"should I update the BIOS first?" is a fair question to ask before starting.

**The short answer is no.** The newest BIOS Chuwi published for this tablet does
not fix any of the Linux problems, and one of the images circulating under the
name "Vi8 Plus BIOS" is for a completely different tablet and would brick this
one. The rest of this page is the evidence for that, and what does help instead.

Everything below marked **verified** was established by parsing the actual
firmware images — SHA-256 in the table further down — not from forum claims.

---

## Which BIOS am I running

From a running Linux system:

```sh
cat /sys/class/dmi/id/bios_vendor /sys/class/dmi/id/bios_version \
    /sys/class/dmi/id/bios_date
sudo dmidecode -t bios -t system -t baseboard
```

Or in the firmware setup itself, on the `Main` page:

```
BIOS Date: 12/11/2015 21:15:52  Ver: 1ATFG007
```

### The `Ver:` string is not a version number

This is the trap. `1ATFG007` is an AMI build tag, and Chuwi did **not** change it
between releases — the 2015-12-11 build and the 2016-02-25 build both call
themselves `1ATFG007`. — **verified**: the 2016-02-25 image carries the signon
string `BIOS Date: 02/25/2016 20:37:26 Ver: 1ATFG007`, while the reference tablet
displays the same `Ver:` with a December 2015 date.

**Read the date, not the `Ver:` string.** The real version lives in the SMBIOS
type 0 record (`/sys/class/dmi/id/bios_version`), where the two builds are
`P03_C806.108` and `P03_C806.109`.

---

## The releases that are known to exist

| Build | SMBIOS version | Setup shows | For | Notes |
|---|---|---|---|---|
| `CHT-P03_C806_108_20151211` | `P03_C806.108` | `Ver: 1ATFG007`, 12/11/2015 | Windows 10, single-OS | What the reference tablet shipped with |
| `CHT-P03_C806_109_20160225` | `P03_C806.109` | `Ver: 1ATFG007`, 02/25/2016 | Windows 10, single-OS | The last one published. Distributed as *"to solve issue with no read TF card"* |
| dual-boot image | `5.11` | `Ver: D2D3_Vi8_I.211`, 03/14/2016 | Android + Windows | Different flash layout, different touchscreen ACPI ID — see below |

There is no evidence of any release after 2016-03-14, and no custom, modded or
community BIOS for this tablet was found. The BIOS modding forums that cover
Cherry Trail devices (Win-Raid, MyDigitalLife) carry threads for other tablets
but nothing for the Vi8 Plus.

`P03_C806.108` is listed on needrom as part of the full stock Windows 10 ROM
(`VI8 PLUS WIN10.CHUWI.S.10.TH2.1212.V200`); the BIOS is not published separately.

---

## What is actually in the two archives

| File | SHA-256 (first 16) | What it really is |
|---|---|---|
| `P03_C806.109` | `0d72b3ceac2c46c8` | AMI Aptio, Cherry Trail. Full 8 MB SPI image. **The genuine latest Vi8 Plus BIOS** |
| `P03_C806.rom.exe` | `6434433c075c063e` | Windows flasher wrapping the above |
| `bios.bin` | `0068258628377e3c` | AMI Aptio, Cherry Trail, dual-boot. Full 8 MB SPI image |
| `CHUWI.D86JLBNR03.bin` | `77a94ca41343a795` | **InsydeH2O, ValleyView (Bay Trail). Not this tablet.** |

Two useful things fell out of this:

- The folder labelled *"Vi8 plus Latest BIOS"* and the one labelled
  *"BIOS 20160225 (to solve issue with no read TF card)"* contain **byte-identical
  files**. They are one release, not two. — **verified by SHA-256**
- The dual-boot archive ships its own flashing kit: `fpt.efi` (Intel Flash
  Programming Tool), a `startup.nsh` that walks `fs0:`..`fs4:` looking for itself,
  and 32- and 64-bit EFI shell binaries.

### One of those files is not a Vi8 Plus BIOS at all

`CHUWI.D86JLBNR03.bin` is distributed as "CHUWI VI8 PLUS". It is not.

| Evidence | `P03_C806.109` (real Vi8 Plus) | `CHUWI.D86JLBNR03.bin` |
|---|---|---|
| BIOS vendor strings | American Megatrends (AMI Aptio) | `Insyde`, `H2O` |
| SoC codename in modules | `CherryView` ×4 | `ValleyView` ×15 |
| `Hampoo` / `Cherry Trail CR` | present | absent |
| Flash layout (BIOS region) | 4096 KiB at `0x400000` | 3072 KiB at `0x500000` |

— **verified** by string extraction over the decompressed contents and by parsing
the Intel flash descriptor.

ValleyView is Bay Trail. Insyde is the BIOS vendor on the **original Chuwi Vi8
(CWI506)** — which is exactly the tablet
[the README warns about confusing this one with](../README.md#do-not-confuse-it-with-the-chuwi-vi8).
Writing it to a Vi8 Plus would flash a Bay Trail firmware onto a Cherry Trail
SoC with a different region map. Do not.

---

## Does a BIOS update fix the touchscreen, Wi-Fi or audio?

No, and this is the part worth reading carefully, because the reasoning is not
obvious from the outside.

All four broken quirks come down to one thing: the tablet reports
`To be filled by O.E.M.` as its system vendor and product name, so no kernel
quirk matches ([the full explanation is in
01-hardware.md](01-hardware.md#some-units-ship-with-the-dmi-fields-unfilled-and-it-breaks-four-things-at-once)).
DMI strings are supplied by the firmware, so a BIOS update is a reasonable place
to look for a fix.

It is not there. The SMBIOS defaults extracted from the **newest** BIOS image
read:

```
-- SMBIOS type 0
   BIOS Version                = 'P03_C806.109'
   BIOS Release Date           = '02/25/2016'
-- SMBIOS type 1
   Manufacturer (sys_vendor)   = 'To be filled by O.E.M.'
   Product Name (product_name) = 'To be filled by O.E.M.'
   Version                     = 'To be filled by O.E.M.'
   SKU Number                  = 'MRD'
   Family                      = 'CherryTrail CR'
-- SMBIOS type 2
   Manufacturer (board_vendor) = 'Hampoo'
```

— **verified** by parsing the SMBIOS defaults out of the extracted firmware
volume (FFS `daf4bf89-ce71-4917-b522-c89d32fbc59f`).

**The placeholder is what the BIOS ships.** Updating from `.108` to `.109`
replaces `To be filled by O.E.M.` with `To be filled by O.E.M.`. Nothing changes.

The dual-boot BIOS is worse, not better: its defaults are `Default string` rather
than the correct `D2D3_Vi8A1`, and it declares the touchscreen under ACPI ID
**`HAMP0005`** instead of `HAMP0002` — for which the kernel has no entry at all.
— **verified** by extracting the ACPI tables from both images.

### So where does `D2D3_Vi8A1` come from?

Some Vi8 Plus units do report `Hampoo` / `D2D3_Vi8A1` — that is what the kernel
quirks were written against, and linux-firmware ships an NVRAM file named
literally `brcmfmac43430-sdio.Hampoo-D2D3_Vi8A1.txt` for it.

That string appears in **none** of the three images. — **verified**

The explanation that fits every observation is that the BIOS ships with
placeholders and the **factory** writes the real strings afterwards, with a DMI
provisioning tool of the AMIDE family. On units where that step was skipped or
lost, the placeholders survive into the field. This is an inference, not a
verified fact — but it is consistent with all of: the shipped image containing
placeholders, other units reporting real strings, reflashing not helping, and
such a tool existing for exactly this purpose.

It has an uncomfortable corollary: **if your tablet does report `D2D3_Vi8A1`,
flashing any of these images would very likely overwrite that and break the
touchscreen, Wi-Fi and audio.** A BIOS update on a working unit is a downgrade.

---

## What would actually fix it

### 1. Write the DMI strings back (untested here, most promising)

AMI's DMI editor exists as `AMIDEWIN` (Windows), `AMIDEDOS`, and `AMIDEEFI` — a
UEFI-shell build, which is what this tablet could use, given a 32-bit (IA32)
binary. Setting the two system fields to the values the kernel expects would make
**all four** quirks match at once:

```
sys_vendor   = Hampoo
product_name = D2D3_Vi8A1
```

That single change would give the touchscreen its firmware lookup, point
brcmfmac at the purpose-made `Hampoo-D2D3_Vi8A1` NVRAM file, enable the RT5651
audio routing quirk, and let the systemd hwdb accelerometer entry
(`svnHampoo:pnD2D3_Vi8A1`) apply.

**This has not been tried on the reference tablet.** Before anyone does: the
switch names for the two fields could not be confirmed from a primary AMI source
(the DMIEdit datasheet is behind a 403). The tool writes to firmware, has no
built-in backup, and a bad write is a brick. Dump the flash first (below), and
have the DnX recovery path ready.

### 2. A kernel patch, which is the clean fix

Upstream already handles tablets whose DMI is generic — by matching on the board
fields plus the BIOS date. The precedent is a near-exact structural match for
this tablet, in `brcmfmac/dmi.c`:

```c
{
	/* Chuwi Hi8 Pro with D2D3_Hi8Pro.233 BIOS */
	.matches = {
		DMI_EXACT_MATCH(DMI_BOARD_VENDOR, "Hampoo"),
		DMI_EXACT_MATCH(DMI_BOARD_NAME, "Cherry Trail CR"),
		DMI_EXACT_MATCH(DMI_PRODUCT_SKU, "MRD"),
		/* Above strings are too generic, also match on BIOS date */
		DMI_MATCH(DMI_BIOS_DATE, "05/10/2016"),
	},
	.driver_data = (void *)&chuwi_hi8_pro_data,
},
```

— **verified** against current mainline.

A Vi8 Plus with unfilled DMI matches the same three fields, and the BIOS defaults
confirm the SKU really is `MRD`. Only the date differs (`12/11/2015`, or
`02/25/2016` on the newer build). That is a submittable patch, and the same shape
applies to `touchscreen_dmi.c`.

Note the comment in that file: *"The Chuwi Hi8 Pro uses the same Ampak AP6212
module as the Chuwi Vi8 Plus and the nvram for the Vi8 Plus is already in
linux-firmware"* — the Wi-Fi calibration data this tablet needs is already
shipped and merely unreachable.

### 3. The per-component workarounds

Already documented, and they need no firmware changes at all — see
[01-hardware.md](01-hardware.md) for Wi-Fi and the touchscreen, and
[50-troubleshooting.md](50-troubleshooting.md).

---

## If you decide to flash anyway

Nothing here is needed for Linux. Read [recovery](#if-it-goes-wrong-dnx-mode)
first.

**Back up what you have first.** The tablet's own flash is the only copy of its
factory DMI, and — if the touchscreen firmware is in there — the only copy of
that too:

```sh
sudo flashrom -p internal -r vi8plus-stock-$(date +%F).bin
sudo flashrom -p internal -r verify.bin
cmp vi8plus-stock-*.bin verify.bin      # two reads must be identical
```

Two methods exist, both Chuwi's own:

**From an EFI shell** (what the dual-boot archive is built for): put `fpt.efi`,
`bios.bin` and `startup.nsh` on a FAT32 stick, boot the shell, and it runs

```
fpt.efi -f bios.bin
reset
```

**From Windows**: run `P03_C806.rom.exe`, wait for the console window to close,
reboot.

### The dual-boot image repartitions the flash

This is not a like-for-like swap. The two Cherry Trail images divide the same
8 MB chip differently:

| Region | Single-OS `P03_C806.109` | Dual-boot `bios.bin` |
|---|---|---|
| BIOS | 4096 KiB at `0x400000` | 6144 KiB at `0x200000` |
| TXE | 4092 KiB at `0x001000` | 2044 KiB at `0x001000` |

— **verified** by parsing the flash descriptor in each image.

`fpt.efi -f` writes the whole 8 MB, descriptor included, so switching between
these rewrites the region map and replaces the Intel TXE firmware with a build
half the size. Getting back is a full reflash, not a settings change.

## If it goes wrong: DnX mode

Cherry Trail SoCs carry a firmware-level recovery mode, and unlike Bay Trail they
integrate the USB gadget PHY into the SoC — so it is available even on tablets
that only ever shipped Windows.

Power on holding **volume-up and volume-down together**. The tablet enumerates as
a fastboot device, and Hans de Goede's method is to hand it an EFI binary to run:

```sh
fastboot flash osloader some-efi-binary.efi
fastboot boot some-android-boot.img
```

That is the escape hatch for corrupted BIOS settings and bad flashes. The
hardware fallback below it is an SPI programmer (CH341A and an SOIC-8 clip) on
the flash chip itself, which requires opening the tablet.

## What could not be determined

Stated plainly, because guessing here is how tablets get bricked:

- **Whether the ICN8505 touchscreen firmware is in these images.** It is not
  present in either Cherry Trail image as a contiguous blob — searched by the
  kernel's own 8-byte prefix and 35012-byte length across all 166 PE modules,
  39 TE modules and every extracted section, with a secondary zlib/LZMA pass.
  — **verified absent** from what could be decompressed. It cannot be ruled out
  that a driver stores it compressed inside its own data section. The reference
  tablet runs `.108`, which was not available for comparison; a `flashrom` dump
  of the tablet itself would settle both questions at once.
- **What `.109` actually changed.** Only that it is distributed as a microSD
  ("TF card") reading fix. Whether that affects the SD slot's inability to appear
  as a boot device ([13-split-media.md](13-split-media.md)) is untested — the
  `.108` image would be needed to diff against.
- **Whether AMIDEEFI runs on this firmware**, and its exact switch names.

Sources for this page are in [90-references.md](90-references.md#bios--uefi-firmware).
