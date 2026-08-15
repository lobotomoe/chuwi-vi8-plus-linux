# Installing Debian 13 "trixie"

This is the path with the fewest surprises. The Debian installer detects 32-bit
firmware on its own and installs `grub-efi-ia32` **from the ISO's own package
pool**, so it finishes correctly even with no network at all. Nothing in this
guide needs a repair step afterwards.

The one thing Debian does not do for you is boot: its ISOs ship only
`bootx64.efi`, so the stick still needs `artifacts/bootia32.efi` added. That is
what [10](10-usb-macos.md)/[11](11-usb-linux.md)/[12-usb-windows.md](12-usb-windows.md)
did.

## Which image

| Image | Size | Use it when |
|---|---|---|
| `debian-13.x.0-amd64-netinst.iso` | ~800 MB | You will have Wi-Fi during the install and want to choose the desktop |
| `debian-live-13.x.0-amd64-lxqt.iso` | ~2.8 GB | You want to try before installing; LXQt is the lightest sensible desktop for 2 GB RAM |
| `debian-live-13.x.0-amd64-xfce.iso` | ~3.0 GB | Xfce instead; slightly heavier, more familiar |

Both from <https://www.debian.org/CD/>. The netinst pulls packages over Wi-Fi,
which works, but it is slow on a 2.4 GHz-only radio — the live images are less
waiting overall.

Verified against Debian 13.6.0: the ISO carries `grub-efi-ia32-bin`,
`grub-efi-ia32-unsigned` and `grub-efi-ia32` in `pool/main/g/grub2/`.

## Install

**1.** Boot the stick ([20-uefi-setup.md](20-uefi-setup.md)). At the GRUB menu
pick **Graphical install** (netinst) or **Live** then the desktop installer.

**2.** Wi-Fi. On the netinst, the installer asks for firmware early; Broadcom
BCM43430 is covered by `firmware-brcm80211`, which Debian 13 includes in its
non-free-firmware pool on the ISO itself. Accept when it offers to load it.
Remember the radio is 2.4 GHz only — a 5 GHz-only SSID simply will not appear.

**3.** Partitioning. On 32 GB there is nothing clever to do:

- **Guided - use entire disk**, target `/dev/mmcblk0` (confirm with `lsblk`
  first that it is the ~29 GiB device and not the microSD card).
- **All files in one partition.**
- Let it create the ESP itself. 512 MB is plenty and Debian's default is fine.
- **No swap partition.** Set up zram afterwards instead
  ([40-post-install.md](40-post-install.md)); swapping to eMMC is slow and
  wears the flash.

**4.** Desktop selection (`tasksel`). Pick **LXQt** or **Xfce**. Not GNOME, not
KDE — 2 GB of RAM will not carry them.

**5.** Bootloader. The installer will offer to install GRUB to the primary
drive; say yes. It notices the 32-bit firmware and pulls `grub-efi-ia32`
instead of `grub-efi-amd64`. You will see it in the log as
`grub-installer: info: Installing grub-efi-ia32`.

**6.** Reboot, remove the stick.

## If it does not boot afterwards

Boot the live/installer stick again, drop to a shell, and:

```sh
sudo mkdir -p /mnt
sudo mount /dev/mmcblk0p2 /mnt          # the root partition; check with lsblk
sudo ./scripts/postinstall-grub-ia32.sh --root /mnt
```

The script mounts the ESP, installs `grub-efi-ia32-bin` if it is missing, and
runs `grub-install` twice — once to write an NVRAM entry, once with
`--removable` so `\EFI\BOOT\bootia32.efi` exists as a fallback. On this firmware
the fallback is frequently the thing that actually works.

## Notes specific to this tablet

- The installer's default `/boot/efi` of 512 MB is more than enough. Do not
  shrink it below 100 MB.
- Debian 13 ships Linux 6.12 LTS, which has every driver this tablet needs (see
  [01-hardware.md](01-hardware.md)). No backports kernel is required.
- Filesystem: ext4. Btrfs on a slow eMMC with 2 GB of RAM buys you nothing here.

## Next

[40-post-install.md](40-post-install.md)
