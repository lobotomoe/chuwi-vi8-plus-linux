# Installing Arch Linux

Arch is the odd one out here: its ISO is the **only** one that boots this tablet
with no modification at all, and its bootloader story is the cleanest — but you
type every step yourself.

## Why the Arch ISO just boots

Current Arch images ship both bootloaders:

```
EFI/BOOT/BOOTIA32.EFI    systemd-boot 261.2 (ia32)
EFI/BOOT/BOOTx64.EFI     systemd-boot 261.2 (x64)
```

The 32-bit build starts under the tablet's firmware and boots the 64-bit kernel
through the EFI handover protocol — systemd-boot implements exactly the mixed
mode described in [02-boot-problem.md](02-boot-problem.md). Nothing from
`artifacts/` is needed.

Write the ISO however you like, including plain `dd` or Rufus in DD mode:

```sh
sudo dd if=archlinux-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

`scripts/make-media.sh` also works and will detect the existing `BOOTIA32.EFI` and
leave it alone.

Verified against `archlinux-2026.08.01-x86_64.iso`. Run
`./scripts/check-iso-ia32.sh` on your download if you want to confirm it for
yourself.

## Sanity check once you are in the live shell

```sh
cat /sys/firmware/efi/fw_platform_size     # 32
cat /sys/class/dmi/id/product_name          # D2D3_Vi8A1
```

If the first prints `32`, you are running a 64-bit kernel under 32-bit firmware.
Everything below follows from that.

## Wi-Fi

```sh
iwctl
[iwd]# device list
[iwd]# station wlan0 scan
[iwd]# station wlan0 get-networks
[iwd]# station wlan0 connect YOUR_SSID
```

2.4 GHz only — a 5 GHz SSID will not be in the list, and that is the radio, not
a bug.

## Partition and install

```sh
lsblk                                       # eMMC is the ~29 GiB mmcblk device

# GPT: 512 MB ESP + the rest as root. No swap partition; use zram later.
sgdisk --zap-all /dev/mmcblk0
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:EFI /dev/mmcblk0
sgdisk -n 2:0:0     -t 2:8304 -c 2:root /dev/mmcblk0

mkfs.fat -F 32 /dev/mmcblk0p1
mkfs.ext4 /dev/mmcblk0p2

mount /dev/mmcblk0p2 /mnt
mount --mkdir /dev/mmcblk0p1 /mnt/boot

pacstrap -K /mnt base linux linux-firmware sof-firmware \
    networkmanager iwd alsa-ucm-conf iio-sensor-proxy \
    nano sudo zram-generator

genfstab -U /mnt >> /mnt/etc/fstab
arch-chroot /mnt
```

`sof-firmware` and `alsa-ucm-conf` are what make the RT5651 audio work;
`iio-sensor-proxy` is what makes rotation work.

## Bootloader — systemd-boot

`bootctl` reads `/sys/firmware/efi/fw_platform_size` and installs the matching
binary, so on this tablet it writes the **ia32** build without being asked. This
is the least error-prone option:

```sh
bootctl install
bootctl status | head -20        # "Current Boot Loader ... systemd-boot ... ia32"
```

Then an entry:

```sh
cat > /boot/loader/entries/arch.conf <<'EOF'
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTUUID=REPLACE_ME rw
EOF

blkid -s PARTUUID -o value /dev/mmcblk0p2    # paste this into the file above
```

`bootctl install` also writes `\EFI\BOOT\BOOTIA32.EFI` as the removable-media
fallback, which on this firmware is often the entry that actually gets used.

## Bootloader — GRUB, if you prefer it

```sh
pacman -S grub efibootmgr
grub-install --target=i386-efi --efi-directory=/boot --bootloader-id=arch
grub-install --target=i386-efi --efi-directory=/boot --removable
grub-mkconfig -o /boot/grub/grub.cfg
```

`--target=i386-efi` is the whole point; the default would be `x86_64-efi` and
would produce a bootloader the firmware cannot execute. Arch's `grub` package
contains every target, so there is nothing extra to install.

## archinstall

`archinstall` works here **if you choose systemd-boot as the bootloader**,
because that path ends in `bootctl install` and inherits the detection above.
Its GRUB path has no 32-bit EFI handling at all — there is no `i386-efi` string
anywhere in archinstall's source — so if you want GRUB, do it by hand as above
after archinstall finishes, or fix it afterwards with:

```sh
./scripts/postinstall-grub-ia32.sh --root /mnt
```

## Finish

```sh
systemctl enable NetworkManager
passwd
exit
umount -R /mnt
reboot
```

## Next

[40-post-install.md](40-post-install.md) — the tablet-specific tuning applies to
Arch too, and `scripts/postinstall-tune.sh` knows about `pacman`.
