# Split media: boot from USB, run from the SD card

This is the answer to a specific, nasty failure: the tablet reads the USB stick well
enough to start booting and then loses it, sometimes minutes into a working desktop.
If that is happening to you, read
[50-troubleshooting.md](50-troubleshooting.md#a-usb-30-stick-cannot-hold-a-link-here)
first — that section explains the cause and lists cheaper fixes. Come here when the
cheaper fixes are not available or not enough.

## The idea

The USB port on this tablet is the unreliable component. Nothing else is.

But the USB stick is only genuinely needed for about fifteen seconds. The firmware
reads `\EFI\BOOT\BOOTIA32.EFI`, GRUB reads its config, the kernel and the initrd get
loaded — roughly 150 MB, read by the **firmware's own USB stack**, which has worked on
every attempt including the ones that failed later.

Everything after that — nearly 4 GB, read continuously for the whole 30–60 minutes of
the install — is the live filesystem. And that does not have to be on the same medium.

So put it on the microSD card in the tablet's **own** slot. The kernel reads that over
the SoC's SD controller, which does not involve USB at any point.

| | Boot medium (USB stick) | Live medium (microSD card) |
|---|---|---|
| Holds | bootloader, kernel, initrd | the whole ISO |
| Size | ~150 MB | ~4 GB |
| Read by | firmware, then briefly by GRUB | the kernel, for the whole session |
| Read over | USB | the SD controller |
| For how long | ~15 seconds | the entire install |

Once the kernel is running, the USB stick can fall off the bus and nothing breaks. It
is not needed again.

**The card must go in the tablet's own microSD slot.** Not in the card reader of a
USB hub — that is a USB device on the same path you are trying to get away from.

## Build both

Same script, run twice. The order does not matter.

**The live medium** — the microSD card, the whole ISO, no special flag:

```sh
sudo ./scripts/make-media.sh \
  --iso ~/Downloads/lubuntu-26.04-desktop-amd64.iso \
  --sha256 <digest from the distribution's SHA256SUMS> \
  --device /dev/diskN
```

**The boot medium** — the USB stick, with `--boot-only`:

```sh
sudo ./scripts/make-media.sh \
  --iso ~/Downloads/lubuntu-26.04-desktop-amd64.iso \
  --device /dev/diskM \
  --boot-only
```

The second one takes seconds rather than twenty minutes, because it copies four files
instead of unpacking 4 GB. If a boot medium ever goes bad, rebuilding it is cheap.

The two get different volume labels — `VI8PLUS` for the live medium, `VI8BOOT` for the
boot medium — so you can tell them apart while both are plugged into the same machine.

## What ends up on the boot medium

```
/vmlinuz                      the kernel, at the root of the volume
/initrd                       the initrd, likewise
/boot/grub/grub.cfg           the distribution's own menu, with the paths rewritten
/boot/grub/fonts/unicode.pf2
/EFI/BOOT/bootia32.efi
```

The kernel and initrd sit at the **root** of the volume, and this is deliberate.

The live-boot scripts find the live filesystem by scanning every block device for a
directory called `casper` (Ubuntu) or `live` (Debian) that contains a squashfs. If the
boot medium had a `casper/` directory holding a kernel but no squashfs, it would be a
thing that looks like a live medium and is not — the exact ambiguity this whole
arrangement exists to remove. With the kernel at the root there is no such directory,
so the only medium that can be chosen is the SD card.

That is why `--boot-only` rewrites the kernel and initrd paths in the copied
`grub.cfg`. It also drops any `search` lines, which set GRUB's `$root` by hunting for
the ISO's volume label — pointless here, because `$root` is already this volume: GRUB
just loaded the file from it.

## Boot it

Put the card in the tablet's microSD slot, plug in the stick, and boot the stick
exactly as in [20-uefi-setup.md](20-uefi-setup.md). The GRUB menu is the
distribution's own, so pick the entry you would normally pick.

## Check it worked

Once you have a desktop:

```sh
findmnt -no SOURCE /run/live/medium 2>/dev/null || mount | grep -i medium
```

An `mmcblk` device means the live filesystem is coming from the card and USB is out of
the picture. An `sd` device means it found the stick instead — which should not be
possible with a stick built by `--boot-only`, and means something else is plugged in.

`lsblk` is worth a look too. The eMMC is `mmcblk0`; the card is usually `mmcblk2`,
because `mmcblk1` is taken by the eMMC's boot hardware partitions.

## Pinning the medium explicitly

Not normally needed, and worth knowing anyway. casper accepts a device on the kernel
command line:

```
live-media=/dev/mmcblk2p1
```

Press `e` at the GRUB menu and add it to the `linux` line. Reach for this only if the
scan picks the wrong device — and check the number with `lsblk` first, because
`mmcblk` numbering is assigned in probe order and is not guaranteed.

## Why not just boot the card and skip the stick

Because the firmware will not. `make-media.sh` puts `\EFI\BOOT\BOOTIA32.EFI` on
everything it builds, so the card is a bootable volume in its own right — and it
still does not appear under `Boot Override`. That was
[tested here](01-hardware.md#storage), not assumed.

Hence the split: the firmware can only start from USB, so USB carries the start and
nothing else.

## Cards drop out on this model too

Worth knowing before you move your root filesystem onto one. The 4PDA thread carries
years of reports of microSD cards vanishing from the running system, needing a
re-seat after every boot, or never being detected — see
[90-references.md](90-references.md#the-4pda-owners-thread). Two firmware settings
come up as fixes: the SD controller in **PCI mode rather than AHCI**, and an item
under `Advanced` -> `System Component`.

This is not a reason to skip the split. A card that works is far steadier than the
USB path this page exists to route around, and on the unit behind this guide the card
enumerated cleanly (`mmcblk2`, 58.2 GiB) in the same session where the USB stick
would not enumerate at all. But if the card starts misbehaving, look in the firmware
before concluding the approach is wrong.

## What this does not fix

Only the reading of the live filesystem moves off USB. The keyboard is still on USB,
so a hub that drops devices will still drop the keyboard — annoying during the
installer, but recoverable by replugging, and it cannot corrupt anything.

Power is also unchanged. If the tablet is browning out under load, see
[01-hardware.md](01-hardware.md#ports-otg-and-charging-while-a-hub-is-attached).

## Next

[20-uefi-setup.md](20-uefi-setup.md) — booting the stick from the tablet's firmware.
