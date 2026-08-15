# Why a normal Linux USB stick does not boot, and what fixes it

## The problem in one paragraph

The Vi8 Plus has a 64-bit CPU and a **32-bit UEFI firmware**. Firmware can only execute
EFI binaries built for its own word size, and it looks for exactly one filename on
removable media: `\EFI\BOOT\BOOTIA32.EFI`. Every mainstream 64-bit Linux ISO ships
`\EFI\BOOT\BOOTX64.EFI` and nothing else. The firmware finds no file it can run, so the
stick never even shows up as a boot option. There is no error message; the device is
simply invisible.

There is no CSM / legacy BIOS mode on this tablet to fall back to.

## Why 32-bit Linux is not the answer

The obvious-looking fix — install the i386 build of a distribution — is a dead end:

- Ubuntu dropped i386 installation images after 18.04. There is no 32-bit Ubuntu to
  install.
- Debian still has i386, but you would be running a 32-bit userland on a 64-bit CPU for
  no reason, on a device where every megabyte of the 2 GB of RAM matters.

The right fix is a **32-bit bootloader that loads a 64-bit kernel**.

## How a 32-bit bootloader boots a 64-bit kernel

This is a real, supported, upstream mechanism, not a hack:

1. The firmware runs a 32-bit EFI bootloader (`bootia32.efi`).
2. The bootloader hands the 64-bit kernel over through the **EFI handover protocol**,
   entering at the kernel's 32-bit entry point.
3. The kernel switches the CPU to long mode itself and then talks to the 32-bit
   firmware through **EFI mixed mode**.

Both halves must be present:

| Requirement | Where | Status |
|---|---|---|
| `CONFIG_EFI_MIXED=y` | kernel | Enabled in Ubuntu 26.04 (`7.0.0-31-generic`) and Debian 13 |
| `CONFIG_EFI_HANDOVER_PROTOCOL=y` | kernel | Enabled; upstream default is `y` |
| A bootloader that uses the handover protocol | boot media | GRUB `i386-efi`, or systemd-boot `ia32` |

The kernel's own documentation is explicit about the second half:

> Note that it is not possible to boot a mixed-mode enabled kernel via the EFI boot
> stub - a bootloader that supports the EFI handover protocol must be used.
> — `arch/x86/Kconfig`, `config EFI_MIXED`

**This is why rEFInd, or pointing the firmware straight at `vmlinuz.efi`, does not
work here.** You need GRUB or systemd-boot in between.

Both are supported. Which one you need depends on the distribution:

| Boot media | 32-bit bootloader on the ISO? | What you do |
|---|---|---|
| Arch Linux (2026.08 and later) | **Yes** — `EFI/BOOT/BOOTIA32.EFI`, systemd-boot ia32 | Nothing. Write the ISO and boot it. |
| Ubuntu / Lubuntu / Xubuntu | No | Add `bootia32.efi` (this repo) |
| Debian 13 netinst / live | No | Add `bootia32.efi` (this repo) |

Verified by inspecting the ISOs themselves; `scripts/check-iso-ia32.sh` does the same
check on any ISO you have locally, so you never have to take this table on faith.

## The `bootia32.efi` in this repo

`artifacts/bootia32.efi` is **not** a random binary from a forum post. It is
`gcdia32.efi` taken from Debian's `grub-efi-ia32-unsigned` package — a monolithic
32-bit GRUB built by Debian for removable media, with every GRUB module already
compiled in and a built-in prefix of `/boot/grub`.

That prefix is the whole trick: dropped onto a USB stick as
`/EFI/BOOT/bootia32.efi`, it starts, reads `/boot/grub/grub.cfg` from that same stick,
and shows you the distribution's own boot menu. Ubuntu, Lubuntu, Xubuntu and Debian
ISOs all keep their GRUB menu at exactly that path, so one file works for all of them
with no configuration.

Full download URL, upstream package version and checksums are recorded in
[`artifacts/PROVENANCE.md`](../artifacts/PROVENANCE.md). `scripts/fetch-bootia32.sh`
re-derives the file from Debian's archive if you would rather not trust the committed
copy — it resolves the current package version from Debian's signed package index,
verifies the SHA-256 from that index, and extracts the binary.

## Why the stick cannot simply be `dd`-ed

The usual advice — write the ISO to the stick with `dd` or Rufus in DD mode — does not
help here, because an ISO written that way is a read-only ISO9660 filesystem. You
cannot add `bootia32.efi` to it afterwards. The small FAT partition that hybrid ISOs
carry for EFI booting is sized to the byte for the files already in it: the Debian 13.6
netinst leaves 14 KB free, and `bootia32.efi` is 1.8 MB.

So instead the stick is built the other way around: format it FAT32 yourself, copy the
**contents** of the ISO onto it, and add `bootia32.efi`. That is exactly what
`scripts/make-usb.sh` and `scripts/make-usb.ps1` do, and it is also what Rufus does in
"ISO image mode".

The alternative is [Ventoy](https://www.ventoy.net/), which keeps ISOs as files and
carries its own IA32 UEFI support. It is a good option on Windows and Linux, and it is
covered in those two guides. There is no macOS build of Ventoy.

## Secure Boot

Turn it off, and leave it off.

Neither Ubuntu nor Arch ships a Microsoft-signed 32-bit EFI bootloader for x86 — Ubuntu
has `grub-efi-ia32-unsigned` but no `grub-efi-ia32-signed`, and the corresponding
Launchpad bug has been open since 2018. Debian does sign an ia32 GRUB, but the shim
chain on this firmware is not worth the trouble when you are wiping the device anyway.

[docs/20-uefi-setup.md](20-uefi-setup.md) covers where the setting lives.

## What this means for the installed system, not just the stick

Getting the installer to boot is half the job. The system you install also needs a
32-bit GRUB in its own ESP, or the tablet will not boot after you remove the USB stick.

- **Lubuntu / Debian**: their installers (Calamares and debian-installer respectively)
  detect 32-bit firmware and do this for you.
- **Xubuntu / Ubuntu**: their installer does not. Repair it afterwards with
  `scripts/postinstall-grub-ia32.sh`.
- **Arch**: you run `bootctl install` or `grub-install --target=i386-efi` yourself
  anyway.

Details are in each distribution's guide.
