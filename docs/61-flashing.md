# Flashing the BIOS, and recovering from a bad one

**Nothing on this page is needed to run Linux.**
[60-bios-firmware.md](60-bios-firmware.md) is the argument for why: no published
BIOS fixes the touchscreen, Wi-Fi or audio on this tablet, and one image
circulating as a Vi8 Plus BIOS is for a different machine. This page exists
because people flash anyway, and because the recovery path is worth knowing
before you need it rather than after.

Read [DnX mode](#if-it-goes-wrong-dnx-mode) first.

## Back up what you have first

**Back up what you have first.** The tablet's own flash is the only copy of its
factory DMI, and — if the touchscreen firmware is in there — the only copy of
that too:

```sh
sudo apt install flashrom          # not installed by default
sudo ./scripts/dump-bios.sh
```

Ubuntu 26.04 ships flashrom `1.6.0`, comfortably past the 1.5.0 erase bug
[noted below](#flashing-from-linux-the-flasher-the-descriptor-and-the-lockdown) — and reading
was never affected by it anyway.

That reads the chip twice and refuses to keep a dump unless both reads agree,
records the DMI strings alongside it, and extracts
`chipone/icn8505-HAMP0002.fw` if this build carries it. It never writes.

Three methods exist, all three Chuwi's own. Both EFI ones are host-independent —
copy the directory onto a FAT32 stick from Linux, macOS or anything else, boot
it, and `startup.nsh` runs itself.

**From an EFI shell, the stock `.108` package**: copy **the contents of** `dos/`
to the root of a FAT32 stick — not the `dos/` directory itself, or the firmware
will not find `\EFI\BOOT\BOOTIA32.EFI` — and boot it. This is the one to prefer:
it writes only the BIOS region and leaves the descriptor and TXE alone:

```
afuefi.efi bios.bin /p /b /n /x /reboot /r
```

**From an EFI shell, the dual-boot archive**: put `fpt.efi`, `bios.bin` and
`startup.nsh` on a FAT32 stick, boot the shell, and it runs

```
fpt.efi -f bios.bin
reset
```

`fpt -f` writes the **whole 8 MB including the descriptor and TXE**, which is why
it [repartitions the flash](#the-dual-boot-image-repartitions-the-flash). Do not
reach for this one unless you mean to switch board configuration.

**From Windows**: run `P03_C806.rom.exe`, wait for the console window to close,
reboot.

Whichever you pick, do it on mains power, and verify `bios.bin`'s SHA-256 against
the [table of archive contents](60-bios-firmware.md#what-is-actually-in-the-archives) before copying it — `afuefi`
is invoked with `/x`, so it will not check for you. None of this has been tested
here; this repository has never flashed this tablet.

## The dual-boot image repartitions the flash

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

## The dual-boot image also breaks the touchscreen on Linux

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

## Flashing from Linux: the flasher, the descriptor, and the lockdown

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
against it. But the descriptor is only one of three gates, and the other two are
set at runtime by the BIOS and can only be read on the tablet. They have now been
read, and they are shut:

```
Enabling flash write... SPI Configuration is locked down.
```

— **verified on the unit**, from `sudo ./scripts/dump-bios.sh`.

**That closes the flashrom write path on this unit.** Reading works — the dump
below came out clean — but `BIOS_CNTL`/SPI Protected Range lockdown means
flashrom cannot program this chip from Linux no matter what the descriptor
permits. Writing means the vendor's own
[EFI route](60-bios-firmware.md#there-is-an-official-efi-flashing-path-and-it-predates-the-windows-one),
which runs before the BIOS locks anything, or a hardware programmer.

The chip itself:

```
Found Winbond flash chip "W25Q64.W" (8192 kB, SPI)
mapped at physical address 0x00000000ff800000
```

— **verified on the unit**

This settles the programmer-voltage question, which until now rested on one
owner's report. The `.W` suffix is not decoration: flashrom's own chip table
gives `W25Q64.W` a `.voltage` of `{1700, 1950}`, i.e. **1.7–1.95 V**. A stock
CH341A drives 3.3 V — **1.7× the chip's maximum**. Use a 1.8 V programmer, or a
level shifter in front of a 3.3 V one. — **verified** against
[flashrom's own chip table](90-references.md#flashrom-the-chips-voltage-and-the-one-release-that-must-not-write).

One hard version requirement if you ever do write: **flashrom 1.5.0 raises
`Invalid OPCODE` when erasing or writing through the `internal` programmer on
Broadwell/Braswell and earlier**, leaving an incomplete flash and a possibly
bricked device. Fixed in 1.5.1. External programmers were never affected, so the
CH341A route is safe on any version — it is the `internal` route, from the
tablet's own Linux, that has the version floor.


## There is no macOS path, and it is worth knowing why

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

