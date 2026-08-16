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

### Chuwi's own "BIOS download" thread does not contain a BIOS

The official forum thread titled *"[Singleboot] Chuwi Vi8 Plus Windows 10, Bios,
Driver Download"* is the obvious place to look for something newer. It offers
three things, and none of them is a BIOS: a MediaFire folder of the Windows 10
32-bit system, `Hi8_Pro_drivers_C806_X64.zip`, and a tutorial document. Whatever
BIOS is in there is bundled inside the Windows ROM, and going by needrom's
listing of the same ROM that would be `.108` — **older** than the `.109` in the
archives described below.

So `P03_C806.109`, 2016-02-25, remains the last BIOS Chuwi published for this
tablet, and it is already in the material examined here.

That driver filename is worth noticing on its own: Chuwi ships **Hi8 Pro**
drivers for the Vi8 Plus, and `C806` is the same platform code as this tablet's
`P03_C806` BIOS. The two models are one hardware platform as far as the vendor
is concerned, which independently corroborates the kernel's note that they carry
the same AmPak AP6212 Wi-Fi module.

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
| ACPI `BOSC0200` accelerometer + `ROTM` | present | absent |
| ACPI `CHPN0001` touchscreen | present | absent |

— **verified** by string extraction over the decompressed contents, by parsing the
Intel flash descriptor, and by extracting the DSDT from each image.

The last two rows are the hardest to argue with: this tablet's accelerometer and
its Chipone touchscreen are simply not declared in that firmware's ACPI tables.
Whatever machine it is for, it is not one with a Vi8 Plus's peripherals on it.

ValleyView is Bay Trail. Insyde is the BIOS vendor on the **original Chuwi Vi8
(CWI506)** — which is exactly the tablet
[the README warns about confusing this one with](../README.md#do-not-confuse-it-with-the-chuwi-vi8).
Writing it to a Vi8 Plus would flash a Bay Trail firmware onto a Cherry Trail
SoC with a different region map. Do not.

The kernel settles it from a third direction. `touchscreen_dmi.c` identifies
these BIOS version strings by name:

```c
/* Chuwi Vi8 (CWI501) */   DMI_MATCH(DMI_BIOS_VERSION, "CHUWI.W86JLBNR01"),
/* Chuwi Vi8 (CWI506) */   DMI_MATCH(DMI_BIOS_VERSION, "CHUWI.D86JLBNR"),
```

both alongside `DMI_SYS_VENDOR` "Insyde" and `DMI_PRODUCT_NAME` "i86" — the
original Vi8's DMI, not this tablet's. `D86JLBNR03` matches the second prefix.
— **verified**

### Where the mislabelled images come from

The archive mirrors carry a folder labelled **"CHUWI VI8 PLUS"** whose contents
are, in full:

| File | What it actually is |
|---|---|
| `CHUWI VI8 PLUS W86JLBNR01` | Chuwi Vi8 **CWI501** |
| `CHUWI VI8 PLUS W86JFBNR01` | same `W86` family |
| `CHUWI VI8 PLUS W86GFBN02` | same `W86` family |
| `CHUWI VI8 PLUS D86JLBNR03` | Chuwi Vi8 **CWI506** |

Four Bay Trail Vi8 images and not one Vi8 Plus BIOS. The first and last are
identified by the kernel entries quoted above; the middle two share the same
`W86`/`D86` naming and Insyde lineage. Nothing in that folder belongs on a
CWI519, and the label is the only thing suggesting otherwise.

If you are hunting for firmware for this tablet, judge the file, not the folder:
a real Vi8 Plus image is 8 MiB, identifies as American Megatrends, and contains
the strings `Hampoo` and `CherryTrail CR`. `scripts/dump-bios.sh` plus the
checks in this page's tables are enough to tell them apart before you flash
anything.

---

## Does a BIOS update fix the touchscreen, Wi-Fi or audio?

No, and this is the part worth reading carefully, because the reasoning is not
obvious from the outside.

All four broken quirks come down to one thing: the tablet reports
`To be filled by O.E.M.` as its system vendor and product name, so no kernel
quirk matches ([the full explanation is in
01-hardware.md](01-hardware.md#some-units-ship-with-the-dmi-fields-unfilled-and-it-breaks-three-things-at-once)).
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
sudo ./scripts/dump-bios.sh
```

That reads the chip twice and refuses to keep a dump unless both reads agree,
records the DMI strings alongside it, and extracts
`chipone/icn8505-HAMP0002.fw` if this build carries it. It never writes.

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

### The dual-boot image also breaks the touchscreen on Linux

Worth knowing before anyone flashes it hoping to fix something. The two images
declare the **same touchscreen controller under a different subsystem ID**:

| Image | `_HID` | `_SUB` | Kernel then asks for |
|---|---|---|---|
| Single-OS `P03_C806.109` | `CHPN0001` | `HAMP0002` | `chipone/icn8505-HAMP0002.fw` |
| Dual-boot `bios.bin` | `CHPN0001` | `HAMP0005` | `chipone/icn8505-HAMP0005.fw` |

— **verified** by extracting the DSDT from each image and reading the `TCS1` /
`TCS5` device scope.

`chipone_icn8505` builds its firmware filename out of `_SUB`
([01-hardware.md](01-hardware.md#touchscreen--chipone-icn8505)), so on the
dual-boot firmware it stops asking for the file the kernel's quirk knows about.
Upstream's `chuwi_vi8_plus_data` names `HAMP0002` and nothing else, which means
flashing the dual-boot image turns a touchscreen that mainline supports into one
it does not. A different blob does exist under that name in the wild — Dax89's
repository carries `HAMP0005.bin`, 34884 bytes and a different hash from
`HAMP0002.bin` — but no kernel entry points at it.

The dual-boot DSDT differs in other ways too: it declares `OBDA8723`, a Realtek
8723 Bluetooth/Wi-Fi part that the single-OS image does not mention. Treat the two
as firmware for meaningfully different board configurations rather than as two
settings of one tablet.

### Why there is no Linux port of `P03_C806.rom.exe` here

The obvious idea is to take the Windows flasher apart and rebuild it for Linux.
It is not worth doing, for three separate reasons.

**The flasher is a wrapper, not a flasher.** `P03_C806.rom.exe` is a Delphi
installer stub — nine PE sections, of which `.rsrc` is 6.4 MB and everything
else is boilerplate — carrying `SETT`, `SCRIPT` and a 6390674-byte `ITEMS`
resource in the layout Smart Install Maker uses. `ITEMS` has a Shannon entropy
of 8.00, so it is compressed or encrypted and does not give up its contents to
signature scanning. — **verified**. Whatever does the actual writing is inside
that blob, and on this platform it can only be Intel FPT or AMI AFU driving the
PCH SPI controller.

**That controller already has a free, portable, maintained driver: flashrom.**
Reimplementing PCH SPI programming to avoid using it would be rewriting a
well-tested tool from scratch, in the one domain where a bug means a dead
tablet.

**And the descriptor does not stand in the way.** The host CPU master has read
and write permission on every region of this flash:

```
FLMSTR1 (host CPU/BIOS): 0xffff0000
    read : Descriptor, BIOS, ME/TXE, GbE, PDR
    write: Descriptor, BIOS, ME/TXE, GbE, PDR
```

— **verified** by parsing the descriptor in both Cherry Trail images.

So the Linux flasher already exists, and this tablet is not descriptor-locked
against it. Note that the descriptor is only one of three gates: `BIOS_CNTL`
(BLE / SMM_BWP) and the SPI Protected Range registers are set at runtime by the
BIOS and can only be read on the tablet. `scripts/dump-bios.sh` prints whatever
flashrom reports about them.

One hard version requirement if you ever do write: **flashrom 1.5.0 issues an
invalid opcode when erasing or writing on Braswell and earlier**, leaving an
incomplete flash and a possibly bricked device. Fixed in 1.5.1. Reading is
unaffected.

### There is no macOS path, and it is worth knowing why

Flashing "from macOS" is not a software gap, it is a wiring one. The SPI chip is
soldered inside the tablet, and flashrom's `internal` programmer flashes *the
machine it is running on*. A MacBook has no data path to the tablet's SPI bus —
the USB-C port speaks USB, not SPI.

The two ways another computer can reach that chip:

- **DnX mode** — the tablet does the flashing; the host only hands it an EFI
  binary over fastboot. See below.
- **A hardware SPI programmer** — a CH341A and an SOIC-8 clip on the chip
  itself. Here flashrom on macOS is genuinely useful, because it drives *the
  programmer* (`-p ch341a_spi`), not the tablet. This is also the only route
  that still works on a tablet that will not power on. It must be a **1.8 V**
  programmer; the common 3.3 V ones will damage this chip.

## If it goes wrong: DnX mode

Power on holding **volume-up and volume-down together** and the tablet enumerates
as a fastboot device, from which a working EFI binary can be handed to it. That
is the escape hatch for corrupted settings and bad flashes, and Cherry Trail is
the good case for it — the USB gadget PHY is on the SoC, so it works even on
units that only ever shipped Windows.

The full procedure, with the prebuilt binaries, the cable-swap trick that makes
the recovered setup menu usable, and what owners of this exact model report,
is in
[50-troubleshooting.md](50-troubleshooting.md#dnx-mode-the-software-recovery-before-you-reach-for-a-programmer).
Read it before flashing, not after.

## What could not be determined

Stated plainly, because guessing here is how tablets get bricked:

- **Whether the ICN8505 touchscreen firmware is in these images.** It is not
  present in either Cherry Trail image as a contiguous blob — searched by the
  kernel's own 8-byte prefix across all 6270 extracted files, with a secondary
  recursive LZMA pass. — **verified absent**.

  That search is worth trusting more than a bare "not found", because the same
  extraction *does* yield the DSDT, with `BOSC0200`, `ROTM`, `CHPN0001` and
  `HAMP0002` all readable in it. A search that finds the ACPI tables and not the
  firmware is a search that was actually looking. What still cannot be ruled out
  is a driver holding the blob compressed inside its own data section, which no
  string search reaches. `sudo ./scripts/dump-bios.sh` on the tablet settles it.
- **What `.109` actually changed.** Only that it is distributed as a microSD
  ("TF card") reading fix. Whether that affects the SD slot's inability to appear
  as a boot device ([13-split-media.md](13-split-media.md)) is untested. The
  `.108` image is needed to diff against; a copy is linked from a 2017 write-up
  and has not been downloaded or checked here —
  <https://mega.nz/#!ZhZEGbAR!nU3qqsNt175V7xtCeiNDugItaZvzuRQ4eXNNTtMoKG8>
  (via <http://billyfung2010.blogspot.com/2017/04/how-to-upgrade-chuwi-vi8-plus-bios.html>).
  Note it ships under the **same** `P03_C806.rom.exe` filename as `.109`, so the
  executable's name tells you nothing about which version is inside.
- **Whether AMIDEEFI runs on this firmware**, and its exact switch names.

Sources for this page are in [90-references.md](90-references.md#bios--uefi-firmware).
