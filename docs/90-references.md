# References

Sources for the claims made in this repository. Everything marked **verified**
was checked directly — against the kernel or distribution source, or by
inspecting the actual ISO — rather than taken from a forum post.

## The 32-bit UEFI problem

- Linux kernel, `arch/x86/Kconfig` — `CONFIG_EFI_MIXED` and
  `CONFIG_EFI_HANDOVER_PROTOCOL`, including the note that a mixed-mode kernel
  **cannot** be booted via the EFI stub.
  <https://github.com/torvalds/linux/blob/master/arch/x86/Kconfig> — **verified**
- Ubuntu 26.04 LTS kernel configuration (`linux-buildinfo-7.0.0-31-generic`):
  `CONFIG_EFI_MIXED=y`, `CONFIG_EFI_HANDOVER_PROTOCOL=y`,
  `CONFIG_EFI_EMBEDDED_FIRMWARE=y`, `CONFIG_TOUCHSCREEN_CHIPONE_ICN8505=m`,
  `CONFIG_SND_SOC_INTEL_BYTCR_RT5651_MACH=m`, `CONFIG_BRCMFMAC_SDIO=y`.
  <http://archive.ubuntu.com/ubuntu/pool/main/l/linux/> — **verified**
- Debian wiki, UEFI: 32-bit firmware detection and `grub-efi-ia32`.
  <https://wiki.debian.org/UEFI>
  *Correction:* that page states the amd64 installation media carry bootloaders
  for both i386 and amd64. As of `debian-13.6.0-amd64-netinst.iso` this is not
  true — its ESP contains only `bootx64.efi` and `grubx64.efi`, with 14 KB free.
  The **installed system** does get `grub-efi-ia32`; the **boot media** does not.
  — **verified by inspecting the ISO**
- Ubuntu bug 1793894, "bootia32.efi + 32bit UEFI + SecureBoot => not signed" —
  why Secure Boot cannot work here.
  <https://bugs.launchpad.net/bugs/1793894>
- Ubuntu bug 1341944, "32-Bit UEFI bootloader support needed".
  <https://bugs.launchpad.net/ubuntu/+source/grub2/+bug/1341944>
- Ventoy IA32 UEFI support (experimental since v1.0.30).
  <https://www.ventoy.net/en/doc_ia32.html>
- systemd-boot's x86 EFI handover implementation, including the mixed-mode
  comment and `XLF_EFI_HANDOVER_32`.
  <https://github.com/systemd/systemd/blob/main/src/boot/linux_x86.c> — **verified**
- `bootctl`'s firmware-architecture detection, which reads
  `/sys/firmware/efi/fw_platform_size` and returns `ia32` on mixed-mode systems.
  <https://github.com/systemd/systemd/blob/main/src/bootctl/bootctl-util.c> — **verified**
- archiso `mkarchiso`, which builds `BOOTIA32.EFI` alongside the x64 loader.
  <https://github.com/archlinux/archiso> — **verified against
  `archlinux-2026.08.01-x86_64.iso`, which ships systemd-boot 261.2 (ia32)**

## Installer behaviour

- Lubuntu's Calamares configuration, `before_bootloader_context.conf` — the step
  that picks `grub-efi-ia32` vs `grub-efi-amd64-signed` from
  `/sys/firmware/efi/fw_platform_size`, after `apt-cdrom add` has pointed apt at
  the medium.
  <https://github.com/lubuntu-team/calamares-settings-ubuntu/blob/ubuntu/oracular/common/modules/before_bootloader_context.conf> — **verified**
  *Caveat:* that repository's newest branch is `ubuntu/plucky` (25.04) and it was
  last touched in January 2026, so it does **not** cover 26.04. The config is
  byte-identical on `ubuntu/oracular` and `ubuntu/plucky`. The corroborating
  evidence for 26.04 is the ISO itself, which carries `grub-efi-ia32`,
  `grub-efi-ia32-bin` and `grub-efi-ia32-unsigned` in `pool/main/g/grub2/`
  alongside `grub-efi-amd64-signed` — exactly the two halves of that conditional.
  — **verified against `lubuntu-26.04-desktop-amd64.iso`**
- Calamares' bootloader module, which maps 32-bit firmware to the `i386-efi`
  GRUB target.
  <https://github.com/calamares/calamares/blob/calamares/src/modules/bootloader/main.py> — **verified**
- curtin's `install_grub.py`, which selects `grub-efi-ia32` from the *target
  architecture* and never consults `fw_platform_size` — the reason Ubuntu's and
  Xubuntu's installers leave this tablet unbootable.
  <https://github.com/canonical/curtin/blob/master/curtin/commands/install_grub.py> — **verified**

## Chuwi Vi8 Plus hardware in the kernel

- Touchscreen: `chuwi_vi8_plus_data` in `drivers/platform/x86/touchscreen_dmi.c`,
  Chipone ICN8505, firmware `chipone/icn8505-HAMP0002.fw` extracted from the
  tablet's own UEFI. — **verified**
- The patch series that added it, with the firmware's size and SHA-256:
  <https://patchwork.kernel.org/project/linux-input/patch/20200111145703.533809-11-hdegoede@redhat.com/>
- Audio: the `Hampoo` / `D2D3_Vi8A1` quirk in
  `sound/soc/intel/boards/bytcr_rt5651.c` —
  `BYT_RT5651_IN2_MAP | BYT_RT5651_HP_LR_SWAPPED | BYT_RT5651_MONO_SPEAKER`.
  <https://github.com/torvalds/linux/blob/master/sound/soc/intel/boards/bytcr_rt5651.c> — **verified**
- Wi-Fi: the Vi8 Plus's AmPak AP6212 (BCM43430) NVRAM,
  `brcm/brcmfmac43430-sdio.Hampoo-D2D3_Vi8A1.txt`, shipped in `linux-firmware`;
  referenced in `drivers/net/wireless/broadcom/brcm80211/brcmfmac/dmi.c`. — **verified**
- Accelerometer mount matrix, systemd `hwdb.d/60-sensor.hwdb`:
  `sensor:modalias:acpi:BOSC0200:*:dmi:*:svnHampoo:pnD2D3_Vi8A1:*`.
  <https://github.com/systemd/systemd/blob/main/hwdb.d/60-sensor.hwdb> — **verified**

## The firmware setup menu

- The firmware on a CWI519 identifies itself as **`Aptio Setup Utility`,
  `Version 2.17.1249`, "Copyright (C) 2015 American Megatrends, Inc."** Tabs are
  `Main / Advanced / Chipset / Security / Boot / Save & Exit`. The `Security` tab
  carries only `Administrator Password` and `User Password` (length 3–20) — no
  Secure Boot entry. The on-screen key legend gives `F4: Save & Exit`,
  `F3: Optimized Defaults`, `F2: Previous Values`, `+/-: Change Opt.`
  — **verified from a photograph of the running setup menu, August 2026**
- `Save & Exit` -> **`SHOW ALL ITEM`**, default `[Disabled]`, help text *"Enable
  or Disable show all setup item"*. Chuwi suppresses most of the setup menu with
  it, which is why Secure Boot is absent from both `Security` and `Boot` in the
  default view. The `Boot` tab ships with `Bootup NumLock State [On]`,
  `Quiet Boot [Enabled]`, `Fast Boot [Disabled]`, a fixed boot order of
  `USB Lan / USB Key / USB Hard Disk / Hard Disk: Windows Boot Manager`, and only
  `UEFI Hard Disk Drive BBS Priorities`. `Save & Exit` also carries `Boot
  Override`, `Launch EFI Shell from filesystem device` and `Windows 10 - Push
  Button Reset`. — **verified from photographs of the running setup menu,
  August 2026**. Searching for documentation of `SHOW ALL ITEM` on Chuwi hardware
  turns up nothing; the on-screen help is the source.
- With `SHOW ALL ITEM` enabled, `Security` gains `▶ Secure Boot menu` and
  `▶ Secure Flash update`. The latter is a read-only report (`Signed BIOS update
  Enabled`, `Public Key store Sha256`, `Signature algorithm PKCS#1v1.5/PSS`,
  `BIOS flash method Runtime,Capsule,Recovery`, `Flash write-protection
  Disabled`) and is not where Secure Boot is configured. `Save & Exit` also gains
  `Reset System with ME disable ModeMEUD000`. — **verified from photographs of
  the running setup menu, August 2026**
- AMI Aptio locks the Secure Boot setting until an Administrator (supervisor)
  password is set; setting one makes it selectable, and clearing it afterwards
  leaves the choice in place.
  <https://www.makeuseof.com/secure-boot-grayed-out-bios/>
- No panel-orientation quirk exists for the Vi8 Plus in
  `drivers/gpu/drm/drm_panel_orientation_quirks.c`; the file covers the Chuwi
  HiBook (CWI514) and Hi10 Pro (CWI529). The HiBook entry matches on
  `Hampoo` + `Cherry Trail CR`, which the Vi8 Plus also reports, but it is
  declared for a 1200x1920 panel and `drm_get_panel_orientation_quirk()` compares
  width and height before consulting the DMI match, so it cannot misfire on this
  tablet.
  <https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/drm_panel_orientation_quirks.c>
  — **verified**
- Chuwi Vi8 family: Esc on a USB keyboard immediately after power-on enters the
  setup menu, and the one-off boot choice lives under `Boot Override` in the last
  tab. Community reports, not verified per-unit here.
  <https://techtablets.com/forum/topic/chuwi-vi8-plus/>
  <https://techtablets.com/2015/01/chuwi-vi8-bios-settings-menus/>

## The 4PDA owners' thread

<https://4pda.to/forum/index.php?showtopic=713525> — "Chuwi Vi8 Plus —
Обсуждение", 4191 posts across 201 pages, December 2015 to February 2026. Readable
without an account. By far the largest body of first-hand experience with this exact
model, and the only place several of the facts below appear at all. It is a forum:
individual posts are unverified owner reports, and they are cited as such. Where a
claim below is corroborated by more than one independent poster, that is noted.

Post numbers are the thread's own (`#NNNN`), reachable by paging to them.

- **Esc enters setup; F7 is the one-off boot menu; Volume + also enters setup.**
  Multiple independent reports (#8455, #13025, #13040, #34449, and #4193/#9596 for
  Volume +). Esc is separately **verified on the unit this guide was written
  against**.
- **The CHUWI splash sits for 5-10 minutes after you select a USB device, and
  that is normal.** Post #34449 gives the full working procedure for booting a
  Windows installer this way. Corroborated by owners who mistook it for a hang
  (#33062, #42091, #46715). This is the single most useful thing in the thread.
- **Ubuntu 20.04 was installed successfully on this tablet in May 2020**, post
  #3875: `bootia32.efi` alone in `\EFI\BOOT\` with everything else deleted, stick
  written with Rufus, and a working network connection required or the install
  fails at the end. Sound, graphics, brightness, screen orientation and the
  physical buttons worked; Wi-Fi and touch did not — that predates
  `chipone_icn8505` reaching a released Ubuntu kernel. Arch also installs
  (#3876).
- **The default setup menu genuinely has no Secure Boot entry.** Post #12579 —
  *"в биос зашёл с помощью Esc ... но secury boot нет, есть quiet boot, fast boot
  и boot опции 1,2,3,4"* — is an owner hitting exactly the truncated menu that
  `SHOW ALL ITEM` unhides, and concluding the setting does not exist.
- **Firmware revisions differ in bitness.** BIOS `D2D3_Vi8A1.232` on dual-boot
  units reports 32-bit for Windows and 64-bit for Android (#36155); those units
  have a `Boot architecture` item (#33087, #33636); revision 1608 is reported
  64-bit (#37112). Converting a 32-bit unit to 64-bit firmware is described as a
  guaranteed brick (#33310).
- **Bricking is usually caused by a bad setup setting, not by flashing** (#16457,
  #12779, #9535). Recovery routes: power on holding Volume + (#9597), or blind
  navigation confirmed by a keyboard's Num Lock LED (#13040, #13097). Last resort
  is a CH341A programmer at **1.8 V**, not 3.3 V (#16151).
- **The USB-C port enumerates only what was attached before power-on** (#46482),
  and a stick the firmware missed can appear after a re-seat (#28075).
- **The firmware boot menu does not offer the microSD slot**, only USB mass
  storage (#10561) — consistent with this repo's requirement to install to eMMC.
- Battery: the thread's specification header states Chuwi claims 4000 mAh with
  owners measuring 3900-4050 mAh, contradicting Notebookcheck's 5000 mAh.
  Unresolved; read `energy_full_design` on your own unit.
- The Ventoy mention in the thread (#3997) is for a **Chuwi Hi10 CWI515**, not
  this tablet. Nothing in the thread confirms Ventoy's IA32 loader on a Vi8 Plus.

## The device itself

- Notebookcheck review of the Chuwi Vi8 Plus (CWI519) — ports, the single USB-C
  that cannot charge while hosting, 2.4 GHz-only Wi-Fi, panel, battery.
  <https://www.notebookcheck.net/Chuwi-Vi8-Plus-CWI519-Tablet-Review.159094.0.html>
- Chuwi's own forum, Vi8 Plus firmware threads. User-uploaded MediaFire folders
  tied to particular serial batches; treat as a last resort, and prefer your own
  backup.
  <https://forum.chuwi.com/t/topic/930>
  <https://forum.chuwi.com/t/vi8-plus-corrupted-bios/5273>

## Prior art on Linux on Atom tablets

Useful for context and for the firmware-menu conventions, but note that most of
it targets the **Bay Trail** generation — the original Chuwi Vi8, the ASUS
T100TA, the Dell Venue 8 Pro — which uses different silicon from the Vi8 Plus.
See the comparison table in the [README](../README.md#do-not-confuse-it-with-the-chuwi-vi8).

- `Manouchehri/vi8` — the original Chuwi Vi8 (Bay Trail).
  <https://github.com/Manouchehri/vi8>
- `jfwells/linux-asus-t100ta` — the historic source of `bootia32.efi` binaries.
  <https://github.com/jfwells/linux-asus-t100ta>
- Sturmflut, "Installing Ubuntu on BayTrail tablets (version 2)".
  <https://sturmflut.github.io/linux/ubuntu/2015/02/04/installing-ubuntu-on-baytrail-tablets-version-2/>
- Hackaday, "Liberating a $50 Windows tablet" — creating a 32-bit UEFI live stick.
  <https://hackaday.io/project/83212-liberating-a-50-windows-tablet/log/115347-creating-a-32-bit-uefi-comaptible-live-boot-stick>
- `willyneutron/lubuntu_in_chuwi_Hi10Pro` — a Cherry Trail Chuwi, closer to this
  tablet than the Bay Trail guides.
  <https://github.com/willyneutron/lubuntu_in_chuwi_Hi10Pro>

## Distributions

- Lubuntu 26.04 LTS release notes. <https://lubuntu.me/lubuntu-26-04-lts-released/>
- Debian installer images. <https://www.debian.org/CD/>
- Arch Linux downloads. <https://archlinux.org/download/>
- Ventoy. <https://www.ventoy.net/>
- Rufus. <https://rufus.ie/>
