# Troubleshooting

Ordered roughly by when you hit them.

## The tablet does not list the USB stick at all

The single most common cause is a missing `bootia32.efi`. Put the stick back in
your computer and check:

```sh
ls /Volumes/VI8PLUS/EFI/BOOT/          # macOS
ls /media/$USER/VI8PLUS/EFI/BOOT/      # Linux
dir E:\EFI\BOOT\                       # Windows
```

You need `bootia32.efi` there. `bootx64.efi` alone is invisible to this
firmware.

Then, in order:

1. **Secure Boot is still enabled.** Re-enter setup and confirm it saved.
2. **The stick was written in DD mode.** ISO9660 is read-only; you cannot have
   added `bootia32.efi` to it. Rebuild it —
   [02-boot-problem.md](02-boot-problem.md#why-the-stick-cannot-simply-be-dd-ed).
3. **The hub was attached after power-on.** Power off fully, plug in, power on.
4. **Windows Fast Startup.** `powercfg /h off` in Windows, then a real shutdown.
5. **A picky partition type.** Rebuild from Linux with the partition typed
   `ef00`, or with Rufus (GPT / UEFI non-CSM).

## The stick boots to a `grub>` prompt instead of a menu

`bootia32.efi` started but could not find `/boot/grub/grub.cfg`. That means
either the copy is incomplete, or you used an image that has no GRUB menu at all
(the Arch ISO uses systemd-boot and has none — but it also ships its own
`BOOTIA32.EFI`, so you should not be here).

From the prompt you can find and load it manually:

```
grub> ls
grub> ls (hd0,gpt1)/boot/grub/
grub> configfile (hd0,gpt1)/boot/grub/grub.cfg
```

Then rebuild the stick properly.

## The installer boots but the screen is black or garbled

Edit the GRUB entry (press `e`) and append to the `linux` line:

```
video=1280x800@60
```

`nomodeset` is the sledgehammer version — it gets you a picture but no
acceleration, and it is almost never needed on Cherry Trail with a modern
kernel. Try `video=` first.

## The install finished and now nothing boots

Expected on Ubuntu and Xubuntu: their installer writes a 64-bit GRUB this
firmware cannot execute. Boot the live stick again and:

```sh
lsblk
sudo mount /dev/mmcblk0p2 /mnt
sudo ./scripts/postinstall-grub-ia32.sh --root /mnt
```

Add `--offline-debs /path/to/payload` if the live session has no network; build
that directory beforehand with `scripts/fetch-offline-payload.sh`.

If the script reports that it wrote everything and the tablet still goes
straight to the firmware menu, the firmware is ignoring NVRAM boot entries. The
`--removable` install the script also performs puts a bootloader at
`\EFI\BOOT\bootia32.efi` in the eMMC's ESP, which is the path such firmware
falls back to. Check it landed:

```sh
sudo mount /dev/mmcblk0p1 /mnt2 && ls /mnt2/EFI/BOOT/
```

## `grub-install` says "cannot find EFI directory" or "i386-efi not found"

- "cannot find EFI directory": the ESP is not mounted at the path you passed.
  Mount it (`mount /dev/mmcblk0p1 /mnt/boot/efi`) and pass `--esp`.
- "i386-efi not found": `grub-efi-ia32-bin` is not installed in the *target*
  system. That is what `scripts/postinstall-grub-ia32.sh` installs; if you are
  doing it by hand, `apt install grub-efi-ia32-bin` inside the chroot.

## No sound, only "Dummy Output"

Check the machine driver bound at all:

```sh
dmesg | grep -iE 'bytcr|rt5651|sof'
aplay -l
cat /proc/asound/cards
```

- Driver missing entirely: install `firmware-sof-signed` (Debian/Ubuntu) or
  `sof-firmware` (Arch) and reboot.
- Card present but silent: the UCM profile is missing. Install
  `alsa-ucm-conf`, then `alsamixer` and unmute/raise the speaker channel — the
  kernel quirk for this tablet declares a mono speaker, so there is one output
  slider, not two.
- Headphones swapped left/right: the kernel already compensates
  (`BYT_RT5651_HP_LR_SWAPPED`). If they are still swapped, you are on a kernel
  older than the quirk; update it.

## Bluetooth does not appear

```sh
dmesg | grep -iE 'bluetooth|btbcm|hci_uart|BCM43430'
ls /lib/firmware/brcm/BCM43430A1.hcd
```

The chip is attached over a UART, which on Cherry Trail depends on the serdev
driver binding to an ACPI device. It usually works; when it does not, it is
almost always the missing `.hcd` patch file, which comes from `linux-firmware`.

Wi-Fi and Bluetooth share the antenna path on this module, so heavy Bluetooth
use degrades 2.4 GHz Wi-Fi throughput. That is the hardware.

## Random freezes

A long-standing complaint on Chuwi's Atom tablets. Two things to try, in order:

1. In the firmware setup, `Power -> Advanced CPU Control -> C-States -> C1`.
   Costs battery life. This is the fix people report most often, though it was
   established on the Bay Trail generation rather than this one.
2. Confirm you are not swapping to eMMC. `swapon --show` should list a zram
   device and nothing else.

If the freeze leaves a trace, it will be in `journalctl -b -1 -p err`.

## The touchscreen does not respond

```sh
dmesg | grep -iE 'icn8505|touchscreen_dmi|efi.*firmware'
cat /sys/class/dmi/id/product_name          # must be D2D3_Vi8A1
```

The controller firmware is extracted from the tablet's own UEFI image at boot,
which needs `CONFIG_EFI_EMBEDDED_FIRMWARE=y` (present in Ubuntu and Debian
kernels) and an EFI boot. If you somehow booted without EFI, the touchscreen
cannot work — check `ls /sys/firmware/efi`.

If `product_name` is not `D2D3_Vi8A1`, the kernel's DMI table does not match
your unit and it will not enable the touchscreen. Attach
`scripts/collect-hw-report.sh` output to a report upstream rather than guessing.

## Wi-Fi does not see the network

The radio is 2.4 GHz only. If the SSID is 5 GHz-only, split the band on the
router or use a different network. Confirm the interface exists first:

```sh
ip link
dmesg | grep -i brcmfmac
rfkill list
```

## Everything is just slow

It is a 2016 Atom with 2 GB of RAM and eMMC. Realistic expectations: a text
editor, a terminal, a media player, and one browser with a handful of tabs.
zram helps materially; nothing else will change the shape of the machine.

## Getting back to Windows

If you took a full image, boot the live stick and restore it:

```sh
lsblk                                   # confirm which device is the eMMC
sudo ./scripts/restore-emmc.sh \
  --image /media/usb-disk/emmc-tablet-20260815-120000.img.zst \
  --target /dev/mmcblk0
```

The script verifies the image against its `.sha256` sidecar before it writes
anything, refuses a partition or a still-mounted device, and makes you type
`RESTORE /dev/mmcblk0` back. Do not shortcut it with a bare `dd` — a typo in
`of=` on this path destroys the disk you are restoring onto.

Then reboot. The licence key is in the firmware's ACPI `MSDM` table, so a clean
Windows install activates itself too — but a clean Windows install on this
tablet needs Chuwi's drivers, which are only on their forum.
