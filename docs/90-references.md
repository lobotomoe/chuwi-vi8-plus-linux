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

## Hans de Goede's notes on this exact tablet

The single most useful outside source for this device. De Goede maintains Bay and
Cherry Trail tablet support upstream, owns a Chuwi Vi8 Plus, and keeps a working
file of per-tablet notes including his own Fedora install procedure for it:

<https://github.com/jwrdegoede/sunxi-fedora-scripts/blob/master/x86-tablet-info>

What it establishes, all of it matching this repository's own findings where the two
overlap:

- `Cherry Trail x5-Z8300, 2G RAM`, `8" 800x1280 LCD`. The 800x1280 confirms the
  panel scans out **portrait**. — **verified on the unit** (Windows "About" reports
  2.00 GB and an x5-Z8300; the display orientation was seen in the firmware setup)
- Wi-Fi is `brcmfmac43430`, touchscreen is `Chipone ICN8505, fw in EFI`, PMIC is
  `AXP288`, audio codec `ALC5651`. — **corroborates** the table in
  [01-hardware.md](01-hardware.md)
- Charging is `only through Type-C 5V/2A, does not do PD`, and a C-to-C cable to a
  modern charger yields `only 500mA`; he uses a USB-A charger with a USB-A-to-C
  cable, through a hub that always passes the 5 V. — **not yet verified here**
- His boot parameters are
  `modprobe.blacklist=extcon_intel_int3496 gpiolib_acpi.run_edge_events_on_boot=0 3`,
  to stop `extcon_intel_int3496` switching the port back to device mode, which
  otherwise makes the live session lose its root filesystem. **His file misspells it
  as `blaclist`** — a misspelled kernel parameter is silently ignored. — **not yet
  verified here**; see
  [50-troubleshooting.md](50-troubleshooting.md#the-live-session-boots-then-slowly-falls-apart)
- He runs `echo 20 > /sys/class/backlight/intel_backlight/brightness` and then
  `systemctl start gdm`. `intel_backlight` exists only under `i915` with modesetting,
  so **KMS works on this model** and `nomodeset` is a workaround rather than the
  ceiling. — **not yet verified here**

One caution: he notes `Battery is dead (browns out on consumption peaks)` and that
his unit `needs to always have a charger connected`. That is his particular unit's
battery, not a property of the model — though a ten-year-old original battery will
behave the same way.

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
- With `SHOW ALL ITEM` enabled, the `Advanced` tab carries exactly these
  submenus, in this order: `Trusted Computing`, `ACPI Settings`, `Serial Port
  Console Redirection`, `CPU Configuration`, `PPM Configuration`, `Thermal`,
  `Android`, `PCI Subsystem Settings`, `Network Stack Configuration`,
  `USB Configuration`, `Platform Trust Technology`, `Security Configuration`,
  `System Component`. — **verified from a photograph of the running setup menu,
  August 2026.** Three of these matter here: `PPM Configuration` is where AMI
  puts C-state options on this platform; `USB Configuration` is the one that
  bricks the tablet if USB is turned off, and on this firmware it also lists
  detected mass-storage devices, which separates "the firmware cannot see the
  stick" from "it sees it but finds no loader" (4PDA #2831 describes exactly that
  split); and `Android` is presumably the dual-boot machinery, unexplored here.
- `Security` -> `Secure Boot menu` -> `Key Management` reports **every Secure Boot
  key store empty** — `Platform Key(PK)`, `Key Exchange Keys`, `Authorized
  Signatures`, `Forbidden Signatures` and `Authorized TimeStamps` all show
  `Size 0 | Key# 0`, with `Provision Factory Default keys [Disabled]`. That is
  direct confirmation, at the key-store level rather than inferred from
  `System Mode: Setup`, that Secure Boot cannot engage on this tablet. The
  `Secure Boot Mode` selector offers `Standard` and `Custom`, and sits on
  `Custom`. — **verified from photographs of the running setup menu, August 2026**
- `Advanced` -> `USB Configuration` reports `USB Module Version 11`, one `XHCI`
  controller, `XHCI Hand-off [Enabled]`, `USB Mass Storage Driver Support
  [Enabled]`, and the tunables `USB transfer time-out [20 sec]`, `Device reset
  time-out [20 sec]`, `Device power-up delay [Auto]`. It also enumerates attached
  devices under `USB Devices:`, which is what makes it a diagnostic — a stick
  that does not appear there is not being seen by the firmware at all, so no
  amount of rebuilding its filesystem or bootloader will help.
  — **verified from a photograph of the running setup menu, August 2026**
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
Обсуждение" (Russian), 3999 posts across 201 pages, December 2015 to April 2026. Readable
without an account. By far the largest body of first-hand experience with this exact
model, and the only place several of the facts below appear at all. It is a forum:
individual posts are unverified owner reports, and they are cited as such. Where a
claim below is corroborated by more than one independent poster, that is noted.

Post numbers are the thread's own (`#NNNN`, up to #4002), shown against each post
and reachable by paging to `&st=` in multiples of 20.

- **Esc and Del enter setup — settled by the firmware itself.** With `Quiet Boot`
  disabled, the POST screen reads *"Press <DEL> or <ESC> to enter setup."* above
  `BIOS Date: 12/11/2015 21:15:52  Ver: 1ATFG007`. — **verified from a photograph
  of the POST screen, August 2026.** The owner reports that pointed at Esc
  (#636, #990, techtablets #23272) were right. `F7` as a one-off boot menu
  (#993, #2719) and `Volume +` (#318, #721) remain owner report only — the POST
  screen does not advertise either.
- **The CHUWI splash sits for 5-10 minutes after you select a USB device, and
  that is normal.** Post #2719 gives the full working procedure for booting a
  Windows installer this way. Corroborated by owners who mistook it for a hang
  (#2609, #3345, #3741). This is the single most useful thing in the thread.
- **Ubuntu 20.04 was installed successfully on this tablet in May 2020**, post
  #3875: `bootia32.efi` alone in `\EFI\BOOT\` with everything else deleted, stick
  written with Rufus, and a working network connection required or the install
  fails at the end. Sound, graphics, brightness, screen orientation and the
  physical buttons worked; Wi-Fi and touch did not — that predates
  `chipone_icn8505` reaching a released Ubuntu kernel. Arch also installs
  (#3876).
- **The default setup menu genuinely has no Secure Boot entry.** Post #960 —
  *"в биос зашёл с помощью Esc ... но secury boot нет, есть quiet boot, fast boot
  и boot опции 1,2,3,4"* — is an owner hitting exactly the truncated menu that
  `SHOW ALL ITEM` unhides, and concluding the setting does not exist.
- **Firmware revisions differ in bitness.** BIOS `D2D3_Vi8A1.232` on dual-boot
  units reports 32-bit for Windows and 64-bit for Android (#2861); those units
  have a `Boot architecture` item (#2613, #2655); revision 1608 is reported
  64-bit (#2940). Converting a 32-bit unit to 64-bit firmware is described as a
  guaranteed brick (#2626).
- **Bricking is usually caused by a bad setup setting, not by flashing** (#1270,
  #973, #713). Recovery routes: power on holding Volume + (#721), or blind
  navigation confirmed by a keyboard's Num Lock LED (#993, #1000). Last resort
  is a CH341A programmer at **1.8 V**, not 3.3 V (#1246).
- **DNX mode exists on this model and is entered exactly as de Goede describes.**
  Post #3499 spells it out — *"Выключить планшет. Затем включить его, зажав
  качельки громкости "+" и "-" вместе. На экране планшета должна появиться
  надпись 'DNX FASTBOOT MODE..'"* — and post #2932 is an owner landing in
  `Entering dnx mode. Waiting for fastboot command` by accident. Two caveats
  worth carrying: one owner reports DNX simply not working on their unit (#2681),
  and another could not get a Vi8 Plus in DNX to enumerate on the host at all,
  showing as an unknown device on two different PCs (#2935). So DNX is the right
  first thing to try, not a guarantee.
- **The USB-C port enumerates only what was attached before power-on** (#3720),
  and a stick the firmware missed can appear after a re-seat (#2214).
- **The firmware boot menu does not offer the microSD slot**, only USB mass
  storage (#791). Owners asked whether Windows could be reinstalled from a card
  and were told no — "sd карточки не получается, нада флешка" (#2191), with the
  suggested workaround being to run the installer's `Setup.exe` from the already
  running system rather than booting the card (#2410); asked again in #3411. No
  post in the thread reports booting from the slot. Strong, but still second-hand:
  **not tried on the unit behind this guide.**
- **Cards dropping out is a recurring complaint on this model**, independent of
  booting: undetected cards of any size (#894), a card that needs re-seating after
  every boot (#2572), 32 and 64 GB cards that kept falling off (#3046). Fixes
  owners report: SD controller in **PCI mode rather than AHCI** (#3335), and an
  item under `Advanced` -> `System Component` (#3046). `Sdcard RCOMP Trigger Delay`
  is also suspected of being involved (#2299). Relevant to
  [13-split-media.md](13-split-media.md), which puts the live filesystem on a card.
- Battery: the thread's specification header states Chuwi claims 4000 mAh with
  owners measuring 3900-4050 mAh, contradicting Notebookcheck's 5000 mAh.
  Unresolved; read `energy_full_design` on your own unit.
- The Ventoy mention in the thread (#3997) is for a **Chuwi Hi10 CWI515**, not
  this tablet. Nothing in the thread confirms Ventoy's IA32 loader on a Vi8 Plus,
  and testing here found it does not work — see below.

## Ventoy IA32 on this tablet: still unknown, and here is why

An earlier revision of this file claimed Ventoy had been tested here and did not
work. **That claim was wrong and is retracted.** What actually happened is worth
recording, because it is a trap anyone debugging this hardware can fall into.

A Ventoy stick carrying a Linux ISO, plugged in before power-on, did not appear
under `Boot Override` on a Chuwi Vi8 Plus (BIOS `1ATFG007`) with Secure Boot off
and `Fast Boot` disabled. The obvious reading — Ventoy's IA32 loader is not being
found — is what got written down.

Then `Advanced` -> `USB Configuration` showed:

```
USB Devices:  1 Keyboard, 1 Mouse, 2 Hubs
```

**No mass-storage device at all**, with `USB Mass Storage Driver Support
[Enabled]`, across every port of the hub, while the keyboard hot-plugged and
responded instantly. The firmware was never enumerating the stick as a USB
device, so it never reached the point of looking at its partitions, filesystem or
`\EFI\BOOT\`. Nothing about Ventoy's layout — exFAT data partition, loaders on a
second partition — can influence whether a device enumerates, because enumeration
happens below all of that.

So this tells us nothing about Ventoy IA32 on a Vi8 Plus. The remaining
candidates are the OTG power budget (this tablet runs on battery whenever a hub
is attached, and a stick draws far more than a keyboard) and the stick itself.
— **verified from photographs of the setup menu, August 2026**

The lesson generalises: **before concluding anything about a bootloader, confirm
in `USB Configuration` that the firmware sees the device at all.** An absent
entry under `Boot Override` has two very different causes and they need opposite
fixes.

## Recovery, and corroboration from outside 4PDA

The 4PDA findings above were cross-checked against English-language and vendor
sources. Where those agree, it is noted; where they disagree, that is noted too,
because a claim repeated by one community is not the same as a verified one.

- **Hans de Goede, "Soft unbricking Bay- and Cherry-Trail tablets with broken
  BIOS settings"** — the DNX mode recovery: power on holding both volume keys,
  then `fastboot flash osloader grubia32.efi` and `fastboot boot
  empty-aboot.img`, where that GRUB has `fwsetup` compiled into its `grub.cfg`
  and drops the tablet into its own BIOS setup. Swap the cable for the OTG
  keyboard during the reboot or you get a menu with no input. The author is the
  kernel developer behind this tablet's touchscreen, audio and EFI
  embedded-firmware support, so this is as authoritative as this topic gets. The
  original LiveJournal has since been deleted; read it at
  <https://web.archive.org/web/20210507014353/https://hansdegoede.livejournal.com/25342.html>
  — **verified, and the binaries are still hosted** at
  <https://fedorapeople.org/~jwrdegoede/grub-efi-directly-enter-fwsetup/>
  (`grubia32.efi`, `grubx64.efi`, `empty-aboot.img`; directory listing checked
  August 2026). Cherry Trail has the USB gadget PHY in the SoC, so DNX works
  here; many Bay Trail units display DNX but cannot use it.
- **techtablets.com, "Chuwi vi8 plus Boot in USB to install Ubuntu"**, January
  2016 — <https://techtablets.com/forum/topic/chuwi-vi8-plus/>. Six posts, this
  exact model, entirely independent of 4PDA. Confirms **Esc** enters setup,
  `Boot Override` **in the last tab** is what actually boots the stick, and that
  adding `bootia32.efi` to `EFI/BOOT` is the whole fix. Three further points:
  - Reordering the boot list did **not** work — *"it seems like 'windows boot
    manager' is overriding the settings"* (#23272). `Boot Override` did.
  - Disabling USB in setup bricked the tablet outright (#23355), recoverable only
    because Windows still booted and could reflash from inside itself. This is
    the specific trap `SHOW ALL ITEM` exposes.
  - A stock Ubuntu ISO with `bootx64.efi` still present, plus an added
    `bootia32.efi`, reached the GRUB menu — **counter-evidence** to the claim
    below that the x64 loader has to be deleted.
  - A second owner could not enter setup with Esc and got in with the volume
    keys instead (#34717), which is why both are documented.
- **Dell KB 000141299, "Systems with 32 bit processor will not boot to USB key if
  both 32 bit and 64 bit images are present"** — prescribes a key carrying only
  the 32-bit loader. **Retired by Dell** — the `en-us` and `en-ca` locales both
  return "The chosen document is not currently available" (checked August 2026),
  and the text quoted here survives only in search-engine indexes rather than
  having been read from the live article, so treat it as weak. Its stated mechanism — that
  the firmware "will not boot past the bootx64.efi boot file" — also contradicts
  the UEFI specification, under which IA32 firmware looks only for
  `\EFI\BOOT\BOOTIA32.EFI`. Taken together with the techtablets counter-evidence,
  this repository keeps `bootx64.efi` on the stick and lists deleting it as a
  troubleshooting step rather than a rule.
- **Slow USB boot is characteristic of the platform, not of this tablet.** The
  Bay/Cherry Trail Linux community reports sticks taking many minutes with
  nothing on screen, independently of the 4PDA figure of 5-10 minutes. The
  black-screen-after-GRUB symptom and the `i915.modeset=0` workaround come from
  the same body of reports.
  <https://sturmflut.github.io/linux/ubuntu/2015/02/04/installing-ubuntu-on-baytrail-tablets-version-2/>
  <https://github.com/hakuna-m/wubiuefi/issues/27>

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

## BIOS / UEFI firmware

Background for [60-bios-firmware.md](60-bios-firmware.md). The firmware images
themselves are not redistributed here; the findings below come from parsing
copies obtained from the sources listed.

### Verified by parsing the images

Three 8 MB SPI images were extracted with
[`uefi-firmware-parser`](https://github.com/theopolis/uefi-firmware-parser) and
their SMBIOS defaults, ACPI tables and Intel flash descriptors read directly.

| Image | SHA-256 |
|---|---|
| `P03_C806.109` | `0d72b3ceac2c46c869c1337873238c63612a74759c907e9aa89ab824050742de` |
| `bios.bin` (dual-boot) | `0068258628377e3ce2a6c2a04cb9a42da88696f72c23a3282effb08fe91d2800` |
| `CHUWI.D86JLBNR03.bin` | `77a94ca41343a795784c13bba5c0f67aa587602d7d0211dcbc4620a7bc29416d` |
| `P03_C806.rom.exe` | `6434433c075c063e934ff05a76c5596c6c10845f6da165ffe98c8716d53e0e0f` |

- `P03_C806.109` SMBIOS type 1 hard-codes `To be filled by O.E.M.` for both
  system manufacturer and product name; type 2 manufacturer is `Hampoo`, SKU is
  `MRD`. **A BIOS update therefore cannot fix the unfilled DMI.** — **verified**
- The single-OS image declares the touchscreen as ACPI `HAMP0002`; the dual-boot
  image declares `HAMP0005`, which no kernel driver claims. — **verified**
- `CHUWI.D86JLBNR03.bin` is an **InsydeH2O / ValleyView (Bay Trail)** image, not a
  Vi8 Plus BIOS, despite being distributed as one. — **verified** three ways:
  by BIOS-vendor and SoC strings in the image, by its flash-region layout, and by
  `touchscreen_dmi.c`, which matches `DMI_BIOS_VERSION` "CHUWI.D86JLBNR" together
  with `DMI_SYS_VENDOR` "Insyde" / `DMI_PRODUCT_NAME` "i86" for the Chuwi Vi8
  **CWI506**. The archive folder these come from is labelled "CHUWI VI8 PLUS" and
  contains four Bay Trail Vi8 images and no Vi8 Plus BIOS at all.
- Flash descriptors differ between the single-OS and dual-boot images (BIOS region
  4096 KiB at `0x400000` vs 6144 KiB at `0x200000`). — **verified**
- The ICN8505 touchscreen firmware was **not** found in either Cherry Trail image,
  searched by the kernel's `prefix`/`length` descriptor across all decompressed
  sections. — **verified absent** from what could be decompressed

### Kernel precedent for generic DMI

- `brcmfmac/dmi.c` — the Chuwi Hi8 Pro entry matching `DMI_BOARD_VENDOR` "Hampoo"
  + `DMI_BOARD_NAME` "Cherry Trail CR" + `DMI_PRODUCT_SKU` "MRD" + `DMI_BIOS_DATE`,
  with the comment *"Above strings are too generic, also match on BIOS date"*.
  The template for a Vi8 Plus patch.
  <https://github.com/torvalds/linux/blob/master/drivers/net/wireless/broadcom/brcm80211/brcmfmac/dmi.c>
  — **verified**
- `linux-firmware` ships `brcmfmac43430-sdio.Hampoo-D2D3_Vi8A1.txt`, the NVRAM
  file this tablet needs, reachable only if the DMI strings are correct.
  <https://gitlab.com/kernel-firmware/linux-firmware/-/tree/main/brcm> — **verified**
- Hans de Goede, `touchscreen_dmi.c` patch adding the Vi8 Plus, with the
  `efi_embedded_fw` descriptor (prefix, length 35012, SHA-256).
  <https://patchwork.kernel.org/project/linux-input/patch/20200111145703.533809-11-hdegoede@redhat.com/>
  — **verified**

### Releases and flashing

- needrom, Chuwi Vi8 Plus stock ROM listing BIOS `CHT-P03_C806_108_20151211` —
  the build the reference tablet shipped with.
  <https://www.needrom.com/download/chuwi-vi8-plus/>
- Chuwi official forum, single-boot and dual-boot firmware threads.
  <https://forum.chuwi.com/t/vi8-plus-official-version-singleboot-chuwi-vi8-plus-windows-10-bios-driver-download/956>
  <https://forum.chuwi.com/t/vi8-plus-official-version-dualboot-chuwi-vi8-plus-dualboot-android-windows-bios/930>
- "How to upgrade the Chuwi Vi8 Plus BIOS?" — reports upgrading from
  `P03_C806.108` by running `P03_C806.rom.exe`.
  <http://billyfung2010.blogspot.com/2017/04/how-to-upgrade-chuwi-vi8-plus-bios.html>
- TechTablets forum, `fpt.efi -f` from the EFI shell and `afuefi.efi /O` to back
  up the running ROM. <https://techtablets.com/forum/topic/update-bios-firmware-updated-drivers/>
- AMI DMIEdit / AMIDEWIN / AMIDEDOS / AMIDEEFI — the OEM DMI provisioning tools.
  Switch names for the system manufacturer and product fields could **not** be
  confirmed from a primary AMI source; both the datasheet mirror and the
  secondary wiki returned 403.

### Recovery

- Hans de Goede, "Soft unbricking Bay- and Cherry-Trail tablets with broken BIOS
  settings" — DnX mode via volume-up + volume-down, `fastboot flash osloader`.
  Cherry Trail integrates the gadget PHY into the SoC, so DnX is available even
  on Windows-only units. <https://hansdegoede.livejournal.com/25342.html>
  (LiveJournal returns 404 to automated fetches; mirrored at
  <http://news.tuxmachines.org/node/150888>)
- "Teclast X98 Air 3G: unbricking a Bay Trail tablet".
  <https://ao2.it/en/blog/2014/12/30/teclast-x98-air-3g-unbricking-bay-trail-tablet>

## Distributions

- Lubuntu 26.04 LTS release notes. <https://lubuntu.me/lubuntu-26-04-lts-released/>
- Debian installer images. <https://www.debian.org/CD/>
- Arch Linux downloads. <https://archlinux.org/download/>
- Ventoy. <https://www.ventoy.net/>
- Rufus. <https://rufus.ie/>
