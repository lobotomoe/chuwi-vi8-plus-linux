# Building the install stick on Linux

**Use the script.** It is Option A below, and it is the one that has actually
booted this tablet. Ventoy looks like the easier route and is kept here as Option
B, but see the warning on it first.

## Pick a USB 2.0 stick, and a USB 2.0 hub

Do this before you build anything, because no amount of getting the stick's contents
right will help if the tablet cannot read it.

The Type-C port is wired for USB 2.0, but the SoC still exposes a SuperSpeed bus. A
USB 3.0 stick behind a USB 3.0 hub — which is what most Type-C hubs are — negotiates
SuperSpeed, fails to hold the link, and resets in a loop without ever appearing as a
disk. It is intermittent, so it will work once and convince you the hardware is fine.

If USB 2.0 parts are what you have, a **USB 2.0 A-to-A extension cable** between hub
and stick does the job too: it has no SuperSpeed conductors, so the link is forced
down to a mode that works.

Symptoms and the full diagnosis are in
[50-troubleshooting.md](50-troubleshooting.md#a-usb-30-stick-cannot-hold-a-link-here).

---

## Option A: the script (one ISO, nothing else on the stick)

Skip to [the script section](#the-script) below.

---

## Option B: Ventoy — unproven on this tablet

> **Not known to work, and not known to fail.** An attempt here never got far
> enough to find out: the firmware did not enumerate the stick as a USB device at
> all, so Ventoy's loader was never reached. See
> [90-references.md](90-references.md#ventoy-ia32-on-this-tablet-still-unknown-and-here-is-why).
>
> Ventoy labels its IA32 support experimental and its author develops it without
> IA32 hardware. Option A is the path this repository is built around and the one
> its scripts and tests cover, so prefer it unless you specifically want to carry
> several ISOs.

If you do try Ventoy and the stick does not show up under `Boot Override`, check
`Advanced` -> `USB Configuration` **before** blaming the bootloader — if the
device is not listed there, the problem is upstream of anything Ventoy does.

That is exactly what happened in the attempt above, and the hub turned out to be the
reason: swapping to a different one made the same stick appear immediately. Worth
knowing before you conclude anything about Ventoy — and worth reading the stick and
hub note at the top of this page first.

[Ventoy](https://www.ventoy.net/) installs its own bootloader on the stick and
then boots ISO files you simply copy on. It has carried IA32 UEFI support since
v1.0.30, which on paper is exactly what this tablet needs.

```sh
# Download and verify Ventoy from https://github.com/ventoy/Ventoy/releases
tar -xf ventoy-*-linux.tar.gz && cd ventoy-*

lsblk -o NAME,SIZE,TRAN,RM,MODEL          # find the stick
sudo ./Ventoy2Disk.sh -i -g /dev/sdX      # -g = GPT layout

# then just copy ISOs onto the new "Ventoy" partition
cp ~/Downloads/lubuntu-26.04-desktop-amd64.iso /media/$USER/Ventoy/
```

Caveats worth knowing:

- Ventoy's IA32 support is still labelled experimental by upstream, and its
  author develops it without real IA32 hardware.
- Secure Boot must be off either way.
- If a particular ISO refuses to boot under Ventoy, fall back to Option B for
  that ISO rather than fighting it.

---

## The script

One ISO, nothing else on the stick, and the layout this firmware expects.

**1. Check what the ISO needs:**

```sh
./scripts/check-iso-ia32.sh ~/Downloads/lubuntu-26.04-desktop-amd64.iso
```

**2. Find the stick — read this twice before continuing:**

```sh
lsblk -o NAME,SIZE,TRAN,RM,MODEL
```

You want the whole disk (`/dev/sdb`), not a partition (`/dev/sdb1`).

**3. Build it:**

```sh
sudo ./scripts/make-usb.sh \
  --iso ~/Downloads/lubuntu-26.04-desktop-amd64.iso \
  --sha256 <the digest from the distribution's SHA256SUMS> \
  --device /dev/sdb
```

The script checks the ISO against that digest before anything else, refuses any
device that is neither removable nor USB-attached, prints what it found, and
makes you type `ERASE /dev/sdb` before touching anything. `--sha256` is optional
but you will get a warning without it: this image is what boots the tablet as
root.

Needs `sgdisk` (`gdisk` package), `mkfs.vfat` (`dosfstools`) and `rsync`.

What it produces: GPT, a single FAT32 partition typed `ef00` (EFI System)
covering the whole stick, the ISO's contents copied onto it, and
`artifacts/bootia32.efi` in `EFI/BOOT/`.

**4. Optional, Ubuntu flavours only — carry the 32-bit GRUB package:**

The build script unmounts the stick when it finishes, so replug it (or mount it
by hand) before copying — the path below only exists once something has mounted
it.

```sh
./scripts/fetch-offline-payload.sh --release resolute
findmnt -no TARGET /dev/sdb1      # where your desktop mounted it, if anywhere
sudo cp -R payload /media/$USER/VI8PLUS/
sync
```

Debian's netinst already ships `grub-efi-ia32-bin` in its pool, so skip this
for Debian.

---

## Doing it by hand instead

```sh
sudo umount /dev/sdb?* 2>/dev/null
sudo sgdisk --zap-all /dev/sdb
sudo sgdisk --new=1:2048:0 --typecode=1:ef00 --change-name=1:VI8PLUS /dev/sdb
sudo mkfs.vfat -F 32 -n VI8PLUS /dev/sdb1

sudo mkdir -p /mnt/iso /mnt/usb
sudo mount -o loop,ro ~/Downloads/lubuntu-26.04-desktop-amd64.iso /mnt/iso
sudo mount /dev/sdb1 /mnt/usb

sudo rsync -rt /mnt/iso/ /mnt/usb/          # -r without -l: skip symlinks
sudo mkdir -p /mnt/usb/EFI/BOOT
sudo cp artifacts/bootia32.efi /mnt/usb/EFI/BOOT/

sync && sudo umount /mnt/iso /mnt/usb
```

`rsync -rt` rather than `cp -a` on purpose: FAT32 has neither symlinks nor hard
links, and Debian/Ubuntu ISOs contain a self-referential `debian -> .` symlink
that makes any dereferencing copy recurse forever.

## Next

[20-uefi-setup.md](20-uefi-setup.md) — getting into the tablet's firmware and
booting the stick.
