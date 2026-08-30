# Building the install stick on Windows

Three routes. Rufus is the shortest and the most widely trodden; use it unless
you have a reason not to.

---

## Pick a USB 2.0 stick, and a USB 2.0 hub

Do this before you build anything, because no amount of getting the stick's
contents right will help if the tablet cannot read it.

The Type-C port is wired for USB 2.0, but the SoC still exposes a SuperSpeed bus.
A USB 3.0 stick behind a USB 3.0 hub — which is what most Type-C hubs are —
negotiates SuperSpeed, fails to hold the link, and resets in a loop without ever
appearing as a disk. It is intermittent, so it will work once and convince you the
hardware is fine. A **USB 2.0 A-to-A extension cable** between hub and stick also
does it: no SuperSpeed conductors, so the link is forced down to a mode that works.

Symptoms and the full diagnosis are in
[50-troubleshooting.md](50-troubleshooting.md#a-usb-30-stick-cannot-hold-a-link-here).

---

## Option A: Rufus (recommended)

1. Get [Rufus](https://rufus.ie/) and your ISO.
2. Select the stick under **Device**, the ISO under **Boot selection**.
3. **Partition scheme: GPT**, **Target system: UEFI (non CSM)**,
   **File system: FAT32**.
4. Press START. When Rufus asks how to write the image, choose
   **"Write in ISO Image mode"**, not DD mode.

   This matters. DD mode reproduces the ISO byte for byte, leaving a read-only
   ISO9660 filesystem you cannot add anything to. ISO Image mode formats FAT32
   and copies the files, which is what makes the next step possible.

5. When it finishes, open the stick in Explorer and copy
   `artifacts\bootia32.efi` from this repository into the `EFI\BOOT\` folder
   that is already there.

   The folder should end up containing `bootia32.efi` alongside `bootx64.efi`
   and `grubx64.efi`.

That is the whole job. If the ISO already contains `BOOTIA32.EFI` — current Arch
images do — leave it alone and skip step 5.

---

## Option B: Ventoy

[Ventoy](https://www.ventoy.net/) has carried IA32 UEFI support since v1.0.30.
Run `Ventoy2Disk.exe`, choose **GPT** under Option -> Partition Style, install
to the stick, then copy ISO files onto the resulting `Ventoy` partition. No
`bootia32.efi` step at all.

Upstream still labels the IA32 support experimental and develops it without real
IA32 hardware, so if an image misbehaves, fall back to Option A for that image.

**Not known to work on this tablet, and not known to fail.** The one attempt here
never got as far as testing Ventoy: the firmware did not enumerate the stick as a
USB device at all, which is a hub problem rather than a Ventoy one. Nobody has
since retried it on a stick this firmware does see. Prefer Option A unless you
specifically want to carry several ISOs —
[why it is still open](90-references.md#ventoy-ia32-on-this-tablet-still-unknown-and-here-is-why).

---

## Option C: the PowerShell script

`scripts\make-media.ps1` is the scripted equivalent of Option A. From an
**elevated** PowerShell:

```powershell
Get-Disk                                    # find the disk number of the stick

.\scripts\make-media.ps1 `
    -IsoPath C:\Users\you\Downloads\lubuntu-26.04-desktop-amd64.iso `
    -Sha256 <the digest from the distribution's SHA256SUMS> `
    -DiskNumber 2
```

It checks the ISO against that digest first, prints the disk's details, refuses
the boot/system disk and anything that is not USB-attached, and makes you type
`ERASE 2` before it starts. Then it
partitions GPT + FAT32, mounts the ISO, copies with `robocopy`, and installs
`bootia32.efi`.

Windows' own FAT32 formatter refuses to create volumes above 32 GB. That is a
limit on the *volume*, not on the stick: with a larger stick the script creates a
31 GB FAT32 partition and leaves the rest unallocated, which is far more than any
installer image needs. It tells you when it does this. If you want the whole
stick usable as one volume, use Rufus or Ventoy instead.

---

## Sanity check before you unplug it

```powershell
Get-ChildItem E:\EFI\BOOT
```

You want to see `bootia32.efi` there. If you only see `bootx64.efi`, the tablet
will not show the stick in its boot menu at all.

## Optional: carry the 32-bit GRUB package for the installed system

Only needed for Ubuntu flavours, and only if you would rather not depend on
Wi-Fi during the install. From the same elevated PowerShell, using a WSL or Git
Bash shell:

```sh
./scripts/fetch-offline-payload.sh --release resolute
```

Then copy the `payload` directory onto the stick. Debian's netinst already
carries `grub-efi-ia32-bin` in its own pool.

## Next

[20-uefi-setup.md](20-uefi-setup.md) — getting into the tablet's firmware and
booting the stick.
