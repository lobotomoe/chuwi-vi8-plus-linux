# Before you touch anything

**This page spans three places, and they are not in reading order.** Some of it
happens in Windows while you still have it, some on your own computer, and the
backup happens in a Linux live session — which means the install stick has to
exist first, even though building it is the *last* link on this page. Read the
whole thing before starting, then work in this order:

| Where | What |
|---|---|
| Anywhere | [Shopping list](#shopping-list), [check the battery](#check-the-battery-first) |
| **Windows**, before wiping | [have the tablet's identity on record](#have-the-tablets-identity-on-record), [copy your files off](#copy-anything-you-care-about-off-the-tablet) |
| **Your computer** | build the stick — [macOS](10-usb-macos.md) / [Linux](11-usb-linux.md) / [Windows](12-usb-windows.md) |
| **The tablet, live session** | [the backup](#decide-whether-you-want-windows-back) — needs the stick from the row above |

## Shopping list

| Item | Why |
|---|---|
| USB-C OTG hub, 2+ USB-A ports | The tablet has one port and you need two devices on it |
| USB keyboard | The firmware setup menu and GRUB are keyboard-driven |
| USB stick, 8 GB+ | Lubuntu 26.04 is a 3.9 GB image; Debian netinst is 800 MB |
| USB stick or SSD, 16 GB+ (optional) | Somewhere to put the Windows backup image |
| USB mouse (optional) | Much easier than touch in the installer |

A powered hub does not help: the tablet does not accept charge through an OTG
adapter. Charge it to 100 % and work quickly.

## Check the battery first

An install takes 20-40 minutes of screen-on time, and imaging the eMMC to an
external disk over USB 2.0 takes another 25-60 minutes. A tired 2016 battery
may not manage both in one session. Do the backup first, charge again, then
install.

## Decide whether you want Windows back

Once you wipe the eMMC there is no undo. Your options:

**Nothing.** Fine if you are certain. The Windows licence lives in the
firmware's ACPI `MSDM` table, not on the disk, so a future Windows install
activates itself. Confirm it is there before you rely on it — from the live
session:

The kernel exposes every ACPI table it found, so this needs nothing installed:

```sh
ls -l /sys/firmware/acpi/tables/MSDM     # exists = the key is in firmware
```

If you want to see the key itself:

```sh
sudo strings /sys/firmware/acpi/tables/MSDM | tail -1
```

**First, find the eMMC.** Both options below take it as `$emmc`, and **it is not
reliably `/dev/mmcblk0`** — on the reference unit it is `mmcblk2` even with the
card slot empty, because the Wi-Fi radio is an SDIO card holding `mmc0`
([01-hardware.md](01-hardware.md#storage)):

```sh
lsblk -d -o NAME,SIZE,TYPE           # the eMMC is the ~29 GiB one
ls -d /sys/block/mmcblk*boot0        # and it is the only one with boot0
emmc=/dev/mmcblkX                    # set it, then confirm
lsblk "$emmc"
```

**Partition table only.** Cheap and fast, enough to reconstruct the layout:

```sh
sudo sfdisk --dump "$emmc" > /media/usb-disk/emmc-layout.sfdisk
```

**Write it somewhere that survives a reboot.** A live session's home directory
lives in RAM, so a dump written to the current directory is gone the moment you
power off — which is the next thing you do. The microSD card or a second stick
is fine; the eMMC is not, since that is what you are about to erase.

**Full image.** The only real answer if you might want the original Windows
back exactly as it shipped:

```sh
sudo ./scripts/backup-emmc.sh --source "$emmc" --dest /media/usb-disk
```

Check the device name with `lsblk` first — the eMMC is the roughly 29 GiB
`mmcblk` device, and the microSD card is the other one. The script refuses to
write the backup onto the disk it is reading, refuses a partition or a
still-mounted device, stops if the destination is too small for the image, saves
the partition table alongside the image, and checksums the result.

**Keep all four output files together.** The backup is four files:

| File | What restoring needs it for |
|---|---|
| `.img.zst` | the image itself |
| `.sha256` | proves the image is undamaged before anything is overwritten |
| `.size` | proves the image fits the target before anything is overwritten |
| `.sfdisk` | the partition table, for a quick table-only repair |

`scripts/restore-emmc.sh` reads the middle two before it writes a single byte —
see [50-troubleshooting.md](50-troubleshooting.md#getting-back-to-windows).

Chuwi's own forum also hosts factory Windows and Android images for the Vi8
Plus, though they are user-uploaded MediaFire folders of uncertain provenance
and tied to particular serial-number batches. Links are in
[90-references.md](90-references.md). Your own image is worth more than theirs.

## Copy anything you care about off the tablet

The eMMC gets erased entirely. Photos, documents, saved Wi-Fi passwords: move
them now, over the network or to the microSD card.

## Have the tablet's identity on record

Run this in Windows before wiping, and keep the output:

```powershell
Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model
Get-CimInstance Win32_BIOS | Select-Object Manufacturer, SMBIOSBIOSVersion, ReleaseDate
```

If anything later goes wrong, the BIOS version is the first thing you will want
to know. Record the **release date** as well as the version string — on this
tablet two different BIOS builds both call themselves `1ATFG007`, and only the
date tells them apart ([60-bios-firmware.md](60-bios-firmware.md#the-ver-string-is-not-a-version-number)).

`Manufacturer` and `Model` here are the same DMI system fields the kernel matches
its quirks against. If they read `To be filled by O.E.M.`, that single fact
explains the touchscreen, Wi-Fi and audio all failing later —
see [01-hardware.md](01-hardware.md#some-units-ship-with-the-dmi-fields-unfilled-and-it-breaks-three-things-at-once).
If they read `Hampoo` / `D2D3_Vi8A1`, your unit has the good strings: do not
flash the BIOS, because that would probably overwrite them.

## Where to go next

Build the install stick on your computer:

- [macOS](10-usb-macos.md)
- [Linux](11-usb-linux.md)
- [Windows](12-usb-windows.md)
