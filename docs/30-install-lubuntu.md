# Installing Lubuntu 26.04 LTS

This is the recommended path: it is Ubuntu, supported until April 2029, light
enough for 2 GB of RAM, and — unlike every other Ubuntu flavour — its installer
detects 32-bit firmware and installs a 32-bit GRUB by itself.

## Why this flavour and not Ubuntu or Xubuntu

Lubuntu installs with **Calamares** rather than Ubuntu's own installer, and
Lubuntu's Calamares configuration contains this step, run before the bootloader
is written:

```sh
apt install -y grub-efi-$(if grep -q 64 /sys/firmware/efi/fw_platform_size; \
                          then echo amd64-signed; else echo ia32; fi)
```

It reads the firmware's word size and installs the matching GRUB. The step before
it runs `apt-cdrom add -m -d=/media/cdrom/` and deletes the `deb http` lines from
`/etc/apt/sources.list`, the intent being to pull the package **from the ISO's own
pool** rather than the network. The pool is definitely there:
`lubuntu-26.04-desktop-amd64.iso` carries `grub-efi-ia32`, `grub-efi-ia32-bin`
and `grub-efi-ia32-unsigned` in `pool/main/g/grub2/`.

**This works, and it works offline.** An install was run here start to finish from
a FAT32 copy of the ISO built by `make-media.sh`, **with no network at all** — no
Wi-Fi, no Ethernet, Calamares warning about it on the way past. The result boots.
Afterwards the firmware's `Boot Override` lists:

```
Ubuntu          <- NVRAM entry, \EFI\ubuntu\
UEFI OS         <- removable-media fallback, \EFI\BOOT\BOOTIA32.EFI
```

— **verified on the unit**

Both paths, so the install survives firmware that ignores NVRAM boot entries. GRUB's
own menu carries `Memory test (mt86+ia32)`, which is the giveaway that the 32-bit
build is the one installed. `postinstall-grub-ia32.sh` was not needed.

That settles the doubt this section used to carry about whether `apt-cdrom` can find
a FAT32 copy of the ISO the way it finds a `dd`-written one. It can, or the step
found what it needed some other way; either way the outcome is a booting 32-bit
GRUB. Connecting Wi-Fi first remains the safer habit, and if you do end up with an
unbootable install, [postinstall-grub-ia32.sh](../scripts/postinstall-grub-ia32.sh)
with `--offline-debs` is the recovery.

Ubuntu and Xubuntu use curtin, which picks the GRUB flavour from the *target
architecture* rather than the firmware — there is no reference to
`fw_platform_size` anywhere in curtin's source. On an amd64 install it writes a
64-bit GRUB, which this firmware cannot execute. That install completes and then
does not boot. It is recoverable
([postinstall-grub-ia32.sh](../scripts/postinstall-grub-ia32.sh)), but there is
no reason to walk into it.

## Get the image

<https://lubuntu.me/downloads/> — `lubuntu-26.04-desktop-amd64.iso`, 3.9 GB.
Check the SHA-256 against the one published beside it.

An 8 GB stick is the practical minimum.

## Build the stick and boot it

[macOS](10-usb-macos.md) / [Linux](11-usb-linux.md) /
[Windows](12-usb-windows.md), then [20-uefi-setup.md](20-uefi-setup.md).

The GRUB menu you get comes from `artifacts/bootia32.efi`, which the ISO does
not provide. Everything after that menu is stock Lubuntu.

## Install

**1.** At the GRUB menu choose **Try or Install Lubuntu**. The live desktop
takes a while on this hardware — a few minutes on eMMC-speed USB 2.0 is normal.

**2.** Wi-Fi is optional but useful (updates, language packs). Remember: 2.4 GHz
only.

**3.** Start **Install Lubuntu** from the desktop.

**4.** Partitioning: **Erase disk**, target the eMMC. Confirm which device that
is before clicking anything — the microSD card, if inserted, is another
`mmcblk` device of similar naming.

- No swap partition. zram afterwards is better on 2 GB of RAM and it does not
  wear the eMMC. Calamares' "no swap" option is fine.
- Leave the ESP size at the default.
- ext4.

**5.** Let it run. The `grub-efi-ia32` step happens near the end, after files are
copied. If you are watching the log (`View -> Show log` or
`/var/log/calamares.log` afterwards) you will see the `apt install grub-efi-ia32`
line go by.

**6.** Reboot and remove the stick.

## If it does not boot after the install

Boot the Lubuntu stick again, open a terminal in the live session, and:

```sh
lsblk                                   # find the new root partition
sudo mount /dev/mmcblk0p2 /mnt          # adjust to what lsblk showed
sudo ./scripts/postinstall-grub-ia32.sh --root /mnt
```

If the live session has no network and you need the package locally, add
`--offline-debs /path/to/payload` after running
`scripts/fetch-offline-payload.sh` on your computer beforehand.

The script installs GRUB twice: once as a named NVRAM entry, once with
`--removable` so `\EFI\BOOT\bootia32.efi` exists. Tablet firmware of this era
frequently ignores NVRAM entries and only ever boots the removable path, so both
are worth having.

## First things after first boot

```sh
sudo ./scripts/postinstall-tune.sh              # shows what it would change
sudo ./scripts/postinstall-tune.sh --apply
```

Then read [40-post-install.md](40-post-install.md) for rotation, audio and the
rest.

## A note on Ubuntu 26.04 proper

If you specifically want GNOME, the install is the same but you will be fighting
2 GB of RAM the whole way, and you must repair the bootloader afterwards as
described above. Try it in the live session before committing — if the live
desktop already swaps, the installed system will be worse.
