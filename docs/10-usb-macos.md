# Building the install stick on macOS

macOS has no Ventoy build and cannot even mount a hybrid Linux ISO any more
(`hdiutil` answers "no mountable file systems"). The scripted route below works
around both.

## What the script does

1. Repartitions the stick: GPT, one FAT32 partition covering the whole device.
2. Unpacks the ISO into scratch space, because the ISO cannot be mounted.
3. Copies the tree onto the stick with `rsync -rt` — symbolic links are skipped
   and hard links become independent files, neither of which FAT32 supports and
   neither of which any distribution needs in order to boot or install.
4. Drops `artifacts/bootia32.efi` into `EFI/BOOT/` on the stick, unless the ISO
   already ships one (Arch does).

## Steps

**1. Download an ISO.** [Lubuntu 26.04 LTS](https://lubuntu.me/downloads/) is
the recommendation; see the [README](../README.md#which-distribution-and-why-not-plain-ubuntu).
Note the SHA-256 published beside the image — pass it to the build script in
step 4 and it will check it for you before the stick is touched.

**2. Confirm what the ISO needs:**

```sh
./scripts/check-iso-ia32.sh ~/Downloads/lubuntu-26.04-desktop-amd64.iso
```

Expect `EFI/BOOT/BOOTIA32.EFI MISSING` and `/boot/grub/grub.cfg present` — that
is exactly the case `bootia32.efi` handles.

**3. Find the stick.** Plug it in, then:

```sh
diskutil list external physical
```

Read carefully. You want the whole-disk node, `/dev/disk4`, not a slice like
`/dev/disk4s1`.

**4. Build it:**

```sh
sudo ./scripts/make-media.sh \
  --iso ~/Downloads/lubuntu-26.04-desktop-amd64.iso \
  --sha256 <the digest from lubuntu.me> \
  --device /dev/disk4
```

The script checks the ISO against that digest first, prints the device's
details, then makes you type `ERASE /dev/disk4` before it does anything. It
refuses internal disks outright. `--sha256` is optional but you will get a
warning without it: this image is what boots the tablet as root.

A 3.9 GB image takes about 10-15 minutes on a USB 2.0 stick, most of it in the
copy. It ejects the stick when it is done.

Scratch space: unpacking needs as much free disk as the ISO is big, in
`$TMPDIR`. If your boot volume is tight, point it elsewhere:

```sh
sudo ./scripts/make-media.sh --iso ... --device ... --scratch /Volumes/Big
```

**5. Optional, Ubuntu flavours only — carry the 32-bit GRUB package along.**

If the tablet will not have Wi-Fi during the install, or you want to be able to
repair the bootloader without a network:

The build script ejects the stick when it finishes, so unplug it and plug it back
in first — `/Volumes/VI8PLUS` only exists once macOS has re-mounted it.

```sh
./scripts/fetch-offline-payload.sh --release resolute
ls -d /Volumes/VI8PLUS            # confirm it is mounted before copying
cp -R payload /Volumes/VI8PLUS/
sync && diskutil eject /Volumes/VI8PLUS
```

(`resolute` is the codename of 26.04 LTS. Use `--release noble` for 24.04, and
so on.) Debian does not need this — its netinst carries `grub-efi-ia32-bin` in
its own package pool.

## Doing it by hand instead

If you would rather not run the script:

```sh
# 1. Partition and format: GPT + one FAT32 partition, no separate helper partition
diskutil unmountDisk force /dev/disk4
diskutil eraseDisk -noEFI FAT32 VI8PLUS GPT /dev/disk4

# 2. Unpack the ISO (macOS tar is libarchive and reads ISO9660)
mkdir -p /tmp/iso && tar -xf ~/Downloads/lubuntu-26.04-desktop-amd64.iso -C /tmp/iso

# 3. Copy, skipping symlinks and materialising hard links
rsync -rt /tmp/iso/ /Volumes/VI8PLUS/

# 4. Add the 32-bit bootloader
mkdir -p /Volumes/VI8PLUS/EFI/BOOT
cp artifacts/bootia32.efi /Volumes/VI8PLUS/EFI/BOOT/

# 5. Flush and eject
sync && diskutil eject /dev/disk4

# 6. Clean up (ISO trees unpack read-only)
chmod -R u+w /tmp/iso && rm -rf /tmp/iso
```

Do **not** use `cp -RL` instead of `rsync`: Debian and Ubuntu ISOs contain a
self-referential symlink (`debian -> .`, `ubuntu -> .`) and dereferencing it
recurses forever.

## If the tablet does not list the stick

macOS types the partition "Microsoft Basic Data" rather than "EFI System".
Firmware searching removable media for `\EFI\BOOT\BOOTIA32.EFI` normally scans
every FAT volume regardless, but if this firmware turns out to be picky, rebuild
the stick from a Linux machine (`sgdisk -t 1:ef00`, see
[11-usb-linux.md](11-usb-linux.md)) or from Windows with Rufus.

Other things to check are in [50-troubleshooting.md](50-troubleshooting.md).

## Next

[20-uefi-setup.md](20-uefi-setup.md) — getting into the tablet's firmware and
booting the stick.
