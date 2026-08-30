# References

Sources for the claims made in this repository.

Two markers appear throughout. **verified** means the claim was checked against
the thing itself rather than against someone's account of it — kernel or
distribution source, an ISO, a firmware image, a driver package, a photograph of
the setup menu. **verified on the unit** means it was observed on the reference
tablet. Anything with neither marker is a report, and is attributed.

Sections run roughly in the order the guide needs them — booting, installing,
the hardware, the freezes, the firmware — and end with the community sources
that corroborate rather than establish. If you are chasing one claim:

| Looking for | Section |
|---|---|
| why the stick will not boot, `bootia32.efi` | [The 32-bit UEFI problem](#the-32-bit-uefi-problem) |
| why Lubuntu and not Ubuntu | [Installer behaviour](#installer-behaviour) |
| a driver, a quirk, a kernel symbol | [hardware in the kernel](#chuwi-vi8-plus-hardware-in-the-kernel), [de Goede's notes](#hans-de-goedes-notes-on-this-exact-tablet) |
| the setup menu's contents | [The firmware setup menu](#the-firmware-setup-menu) |
| CHT45, idle states | [The freezes](#the-freezes-intels-own-erratum) |
| a BIOS image, a hash, the touchscreen blob | [BIOS / UEFI firmware](#bios--uefi-firmware) |
| what other owners report | [4PDA](#the-4pda-owners-thread), [recovery](#recovery-and-corroboration-from-outside-4pda), [another owner's fixes](#another-owners-fixes-for-this-exact-tablet) |

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
- casper, the Ubuntu live-boot scripts. `scripts/casper` sets `mountpoint=/cdrom`
  on line 7 and mounts the boot medium there whatever it physically is, and parses
  `live-media=` into `LIVEMEDIA` — the two facts
  [13-split-media.md](13-split-media.md#check-it-worked) depends on. Debian's
  `live-boot` uses `/run/live/medium` for the same job, which is why a path copied
  from a Debian guide finds nothing here. — **verified** against the
  `casper_26.04.2` source tarball.
  <http://archive.ubuntu.com/ubuntu/pool/main/c/casper/>
- curtin's `install_grub.py`, which selects `grub-efi-ia32` from the *target
  architecture* and never consults `fw_platform_size` — the reason Ubuntu's and
  Xubuntu's installers leave this tablet unbootable.
  <https://github.com/canonical/curtin/blob/master/curtin/commands/install_grub.py> — **verified**

## Chuwi Vi8 Plus hardware in the kernel

- Touchscreen: `chuwi_vi8_plus_data` in `drivers/platform/x86/touchscreen_dmi.c`,
  Chipone ICN8505, firmware `chipone/icn8505-HAMP0002.fw`, which the entry is
  written to extract from the tablet's own UEFI. — **verified**. The `HAMP0002`
  half is also confirmed against the tablet's own firmware: the DSDT extracted
  from `P03_C806.109` declares `_HID CHPN0001` / `_SUB HAMP0002`. The blob itself
  was *not* found in either published image, see
  [60-bios-firmware.md](60-bios-firmware.md#what-could-not-be-determined)
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

What it establishes — matching this repository's findings except on the
touchscreen firmware, where his unit and this one disagree (see
[60-bios-firmware.md](60-bios-firmware.md#what-could-not-be-determined)):

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

- His reinstall procedure for this model **reconfigures the charger by hand**:
  `static i2cset` to `set input current to 2A and vhold to 4.3V`. Read alongside
  the entry above, that says the AXP288 does not negotiate anything like 2 A on
  its own here, and that the 4.4 V input-voltage floor the driver programs is too
  high for the cabling people actually use. — **the sysfs half of it is confirmed
  possible**: `input_current_limit` is writable, so only `vhold` needs `i2cset`.
  See [01-hardware.md](01-hardware.md#ports-otg-and-charging-while-a-hub-is-attached)

One caution, and it turned out to be the most useful line in the file: he notes
`Battery is dead (browns out on consumption peaks)` and that his unit `needs to
always have a charger connected`. Easy to read as one worn-out battery — but he
would not be raising the input current limit by hand if the charger were feeding
the machine properly, and on the reference unit here the supply reported itself
`online` while the battery discharged at 2.3 W. A ten-year-old cell and a starved
charger produce the same symptom, and this tablet appears to have both.

### Three more files in the same repository

`x86-tablet-info` is the one usually cited, but the repository holds three others
that say something about this model.

**[`x86-tablet-status`](https://github.com/jwrdegoede/sunxi-fedora-scripts/blob/master/x86-tablet-status)**
— a per-component status matrix against linux-next. The Vi8 Plus row, decoded with
the file's own legend:

| Component | | Component | |
|---|---|---|---|
| LCD | works | speaker | works |
| Wi-Fi | works | headphones | works |
| touchscreen | works | jack detection | works |
| accelerometer | works | USB host | works |
| battery monitor | works | USB device | works |
| charge 2 A | works | Bluetooth | **`FIR`** |
| buttons | works | charge 3 A | n/a |
| brightness | works | touchpad / lid | n/a |
| suspend | `yes` | tablet-mode switch | locked on |

Two entries in that row are worth reading closely.

`FIR` is defined in the file as *"needs firmware which is not in linux-firmware"* —
which is the Bluetooth `.hcd` situation described in
[01-hardware.md](01-hardware.md#wi-fi--bluetooth--ampak-ap6212-broadcom-bcm43430).

Suspend is scored `yes`, not `S0i3`. Other rows in the same table do say `S0i3`, so
the distinction is deliberate: the tablet suspends, but is not recorded as reaching
the deep power state, and battery drain while suspended should be expected to match.

**[`x86-codec-info`](https://github.com/jwrdegoede/sunxi-fedora-scripts/blob/master/x86-codec-info)**
— per-tablet audio routing. The Vi8 Plus line reads
`mono / mono in2 / JD1_1`, confirming the mono speaker, the IN2 microphone mapping
and the jack-detect source in [`patches/0003`](../patches/) without anyone having to
boot a kernel. `HP_LR_SWAPPED` is not covered by that table and remains uncorroborated
outside the kernel's own entry.

**[`brcmfmac-notes`](https://github.com/jwrdegoede/sunxi-fedora-scripts/blob/master/brcmfmac-notes)**
— Wi-Fi and Bluetooth firmware per tablet. His Vi8 Plus is
`brcmfmac43430-sdio` with `BCM43430A1-26M.hcd`, i.e. an **a1** unit, and the
country code needs `ALL->X2`. The a0 tablets in the same list (Onda V80 Plus,
Jumper ezPad mini 3, Chuwi Hi8) take `BCM4343A0-26M.hcd` instead. This is the
clearest outside evidence that the a0/a1 split in this model is real and that the
two revisions want different files on both radios.

### Why no distribution ships the a0 patch file

- Ubuntu `bluez-firmware`, **multiverse**, `1.2-11ubuntu2`. Its `brcm/` directory
  holds `BCM43430A1`, `BCM43430B0`, `BCM4343A2`, `BCM4345C0`, `BCM4345C5` and
  nothing else — **verified** by downloading the `.deb` from the archive and
  listing it, not from a package-search page.
  <http://archive.ubuntu.com/ubuntu/pool/multiverse/b/bluez-firmware/>

- Upstream of that package: the Cypress-licensed blobs the Raspberry Pi project
  carries, same five files, same absence.
  <https://github.com/RPi-Distro/bluez-firmware/tree/master/debian/firmware/broadcom>

- `linux-firmware` is not an alternative. Its `WHENCE` declares exactly one
  Broadcom `.hcd`, `BCM-0bb4-0306.hcd`, plus a symlink to it.
  <https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/WHENCE>

So the a0 gap is upstream of packaging: the file is missing from the licensed
release itself, which is why there is no bug to file and no PPA to add.

## The firmware setup menu

The setup menu was photographed on a running CWI519 in August 2026 and
transcribed in [20-uefi-setup.md](20-uefi-setup.md), which is the single source
for what it contains: Aptio Setup Utility 2.17.1249, the six tabs, the key
legend, the `SHOW ALL ITEM` switch that reveals the Secure Boot and Key
Management submenus, and `Advanced` -> `USB Configuration` as the enumeration
diagnostic. — **verified from photographs of the running setup menu, August 2026**

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
  (#2609, #3345, #3741).
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
  post in the thread reports booting from the slot, and this has since been
  [confirmed on the unit](01-hardware.md#storage) — a card in the same layout that
  boots this tablet from USB does not appear under `Boot Override` at all.
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

A Ventoy stick carrying a Linux ISO, plugged in before power-on, did not appear
under `Boot Override` (BIOS `1ATFG007`, Secure Boot off, `Fast Boot` disabled).
The obvious reading is that Ventoy's IA32 loader was not found. It is the wrong
one — `Advanced` -> `USB Configuration` showed:

```
USB Devices:  1 Keyboard, 1 Mouse, 2 Hubs
```

**No mass-storage device at all**, with `USB Mass Storage Driver Support
[Enabled]`, across every port of the hub, while the keyboard hot-plugged and
responded instantly. The firmware never enumerated the stick, so it never reached
the point of looking at its partitions, filesystem or `\EFI\BOOT\`. Nothing
about Ventoy's layout can influence whether a device enumerates.

So this says nothing about Ventoy IA32 on a Vi8 Plus. The remaining candidates
are the OTG power budget and the stick itself.
— **verified from photographs of the setup menu, August 2026**

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
  original LiveJournal URL does not serve automated fetches; read it at
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

## The freezes: Intel's own erratum

- **Intel® Atom™ Z8000 Processor Series Specification Update**, document
  **332067**. The source of erratum **CHT45**, *"Processor May Not Wake From C6
  or Deeper Sleep State"*, quoted verbatim in
  [51-freezes.md](51-freezes.md#erratum-cht45-the-processor-may-not-wake-from-c6-or-deeper)
  along with its `No Fix` status and the S-Spec / stepping table that ties it to
  the Z8300 in this tablet.
  <https://www.intel.com/content/dam/www/public/us/en/documents/specification-updates/atom-z8000-spec-update.pdf>

  Intel reissues this document under the same number, so the revision you
  download will not be the one that was read — errata keep their identifiers
  across revisions, but page numbers and the summary table do not. Distributors
  mirror older revisions if the current one has dropped something:
  <https://www.mouser.com/pdfdocs/atom-z8000-spec-update.pdf>

- The identification of *which* idle states the erratum names is not from Intel;
  it is the MWAIT hints the kernel prints for this CPU, decoded and tabulated in
  the same section — **verified on the unit**, and the reason the fix disables
  three states rather than all of them.

- The same table upstream, in the driver's own source: `cht_cstates` in
  `drivers/idle/intel_idle.c`, which offers `C1` `0x00`, `C6N` `0x58`, `C6S`
  `0x52`, `C7` `0x60`, `C7S` `0x64`, in that order.
  <https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/idle/intel_idle.c>

  This settles two things the sysfs read on its own could not. **`POLL` really is
  bit 0**: `intel_idle_cpuidle_driver_init()` calls `cpuidle_poll_state_init()`,
  tests `disabled_states_mask & BIT(0)` against that state, and only then sets
  `drv->state_count = 1` before appending the per-CPU table — so `C1` lands at
  index 1 and `C6N` at index 2, and `states_off=56` takes `C6S`, `C7`, `C7S` and
  nothing else. And **a kernel upgrade will not renumber them**: the block is
  byte-identical from `v5.15` through mainline except for `&intel_idle` losing
  its `&`. — **verified** by fetching the file at `v5.15`, `v6.6`, `v6.12` and
  mainline and diffing the block.

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

### The firmware images, and their hashes

Extracted with
[`uefi-firmware-parser`](https://github.com/theopolis/uefi-firmware-parser) and
their SMBIOS defaults, ACPI tables and Intel flash descriptors read directly. The
findings drawn from them — the hard-coded `To be filled by O.E.M.`, the
`HAMP0002`/`HAMP0005` split, `CHUWI.D86JLBNR03.bin` being a Bay Trail image, the
differing flash-region layouts, and the touchscreen firmware being absent from
all of them — are argued in
[60-bios-firmware.md](60-bios-firmware.md), which owns them. This is the
provenance:

| Image | SHA-256 |
|---|---|
| `P03_C806.108` (`dos/bios.bin` = `windows/P03_C806.108`) | `5ba88aad…0c3900`, from the stock ROM below |
| `P03_C806.109` | `0d72b3ceac2c46c869c1337873238c63612a74759c907e9aa89ab824050742de` |
| `bios.bin` (dual-boot) | `0068258628377e3ce2a6c2a04cb9a42da88696f72c23a3282effb08fe91d2800` |
| `CHUWI.D86JLBNR03.bin` | `77a94ca41343a795784c13bba5c0f67aa587602d7d0211dcbc4620a7bc29416d` |
| `P03_C806.rom.exe` (Windows flasher, not an SPI image) | `6434433c075c063e934ff05a76c5596c6c10845f6da165ffe98c8716d53e0e0f` |

Re-derive any of it with
[`scripts/inspect-bios-image.py`](../scripts/inspect-bios-image.py), which is
read-only.

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

### flashrom: the chip's voltage, and the one release that must not write

Both read from the flashrom tree itself rather than from a release announcement
or a forum summary. Background for
[61-flashing.md](61-flashing.md#flashing-from-linux-the-flasher-the-descriptor-and-the-lockdown).

- `flashchips/winbond.c`, the `W25Q64.W` entry: `.voltage = {1700, 1950}`. The
  whole case for a 1.8 V programmer rests on this line — it is the chip
  database's own figure, not an inference from the `.W` in the part name.
  <https://github.com/flashrom/flashrom/blob/main/flashchips/winbond.c>

- Release notes, v1.5.1: *"Users with older Intel-based platforms
  (Broadwell/Braswell and earlier) flashing using the internal programmer option
  might encounter an 'Invalid OPCODE' error when erasing/writing which would lead
  to an incomplete flash and potentially a bricked device. External flashing was
  not affected at all."*
  <https://github.com/flashrom/flashrom/blob/main/doc/release_notes/v_1_5.rst>

  The upstream ticket and the fix:
  <https://ticket.coreboot.org/issues/573>
  <https://review.coreboot.org/c/flashrom/+/85612>

  The notes name Braswell, not Cherry Trail. The two are the same 14 nm Airmont
  generation under different branding, so this tablet sits inside that window —
  **inferred** from the generation, and the reason 61-flashing.md states a
  version floor rather than a tested result.

### The stock ROM, and the only copy of `P03_C806.108`

`Chuwi-Vi8-Plus-5BS2R-C806.rar`, 4278459662 bytes, SHA-256
`cd2f09bcde7caba61fafdfffeb9fa31b6ccfa908bb8232cd821ead2f0d4040e0`. Free
registration required. — **verified** by downloading and unpacking it.

<https://www.needrom.com/download/chuwi-vi8-plus/>

Contains the full Windows 10 image (`VI8 PLUS WIN10.CHUWI.S.10.TH2.1212.V200`)
and, in `BIOS/CHT-P03_C806_108_20151211/`, the `.108` BIOS twice — `dos/bios.bin`
and `windows/P03_C806.108` are byte-identical, SHA-256 `5ba88aad…0c3900`. It is
the only place this BIOS is published; see
[60-bios-firmware.md](60-bios-firmware.md#what-changed-between-108-and-109).

Unpack it with a RAR5-capable tool. `bsdtar -x -f ARCHIVE 'Chuwi-*/BIOS/*'`
extracts just the BIOS directory; p7zip reports *"Unsupported Method"* and writes
zero-byte files, and Homebrew's `unrar` is unsigned so macOS Gatekeeper blocks it
without printing anything.

### Chuwi's own driver package — the primary source for the touchscreen firmware

`Hi8_Pro_drivers_C806_X64.zip`, 227034543 bytes, SHA-256
`92a4163ec7d0388888a31666ef8340d2056e3ec866639d9cdd7275dac817561f`. Linked from
Chuwi's own Vi8 Plus forum thread, mirrored on MediaFire and on Chuwi's Box
account.

- <https://www.mediafire.com/file/180vqqbk3rus2s1/Hi8_Pro_drivers_C806_X64.zip/file>
- <https://chuwiinnovationtechnologyshenz.box.com/s/wwqnnrtpe0lsd90nrzlux47q04cvwp56>

— **verified** by downloading and unpacking it.

`drivers_C806_X64/TP_X64/chpntsc.inf` (DriverVer 04/21/2016, catalogue
`Chpntsc.cat`) holds all seven ICN8505 firmware blobs as hex under
`[Chpntsc_Device_Firmware.AddReg]`, keyed by ACPI `_SUB` name. This is where the
copies floating around GitHub ultimately come from —
[`scripts/extract-touchscreen-fw.sh`](../scripts/extract-touchscreen-fw.sh) reads
them straight out of it.

Also in the package, both worth knowing:

- `Wifi_x64` is **Realtek** (`netrtwlans.inf`, *"Realtek Wireless 802.11b/g/n
  SDIO"*, DriverVer 04/29/2016), not Broadcom.
- `Bt_x64` contains **no Bluetooth driver**: it holds `prnms009.inf`,
  `Class=Printer`, `Provider="Microsoft"` — Microsoft Print to PDF.

### Where the second copy of the touchscreen firmware comes from

<https://github.com/Dax89/chuwi-dev> — **inspected, not tested here**

A Chipone reverse-engineering repository aimed at the Chuwi Hi10. It carries raw
controller dumps named by ACPI `_SUB` string, `hi10/HAMP0001.bin` through
`HAMP0005.bin`, plus an out-of-tree `chipone_ts` driver and a Vi10 Ultimate DSDT.

`HAMP0002.bin` — the `_SUB` this tablet's touchscreen reports — is **byte-identical
to the file in `sciboy12/vi8-plus-linux-fixes`**, confirmed with `cmp`: both 34884
bytes, both SHA-256 `d9db81b9…c99327`.

That is one source, not two. This copy was committed **2016-07-15**, the other
**2025-07-30**, nine years later; the later one is most plausibly a copy of this one
or of a shared vendor original. Do not read the match as independent corroboration.

What it does establish is that this file is **contemporaneous with the hardware** and
comes from someone who was writing a driver for the controller, which is better
standing than an undated upload. Treat `Dax89/chuwi-dev` as the origin and
`sciboy12` as a mirror.

`HAMP0001` and `HAMP0005` share the same 34884-byte length and the same prefix but
hash differently — they are sibling tablets' firmware for the same controller, and
are not interchangeable. `HAMP0003`, `HAMP0004` and the Vi10 file are a different
controller generation (38580 bytes, prefix `30 05 00 00 64 05 00 00`).

The 128-byte gap against the kernel's pinned 35012 is **not** padding: appending or
prepending 128 zero or `0xff` bytes to the 34884-byte file produces none of the
kernel's SHA-256. It is a different build, not a trimmed one.
## Another owner's fixes for this exact tablet

`sciboy12/vi8-plus-linux-fixes` — the only other repository found that targets the
Vi8 Plus specifically, written against Arch. Independent confirmation that this
tablet's unfilled DMI is a real production variant rather than one bad unit: it
ships an NVRAM file named, literally,
`brcmfmac43430a0-sdio.To be filled by O.E.M.-To be filled by O.E.M..txt`, which
works precisely because `brcmfmac` builds the filename out of the DMI strings.
<https://github.com/sciboy12/vi8-plus-linux-fixes> — **inspected, not tested here**

What it offers, with what we could establish about each:

- `chipone/icn8505-HAMP0002.fw`, **34884 bytes**, SHA-256 `d9db81b9…c99327`.
  Begins with the same `b0 07 00 00 e4 07 00 00` the kernel looks for, so it is a
  genuine ICN8505 image — but it is **128 bytes shorter** than the 35012 the kernel
  pins. See the entry below: a second, unrelated upload of the identical bytes
  turned up, which is what raises this from "some file" to a real candidate.
- `brcm/brcmfmac43430a0-sdio.*.txt`. The a0-named NVRAM this tablet needs, but the
  content is Broadcom's generic `BCM943430WLSELG` reference file, which says of
  itself *"The following parameter values are just placeholders, need to be
  updated"*. Prefer the board-specific Linaro file that linux-firmware already
  ships for this mainboard — see
  [01-hardware.md](01-hardware.md#wi-fi--bluetooth--ampak-ap6212-broadcom-bcm43430).
  (All three files, theirs and linux-firmware's, carry the same
  `macaddr=00:90:4c:c5:12:38`; the reference tablet still came up with a real
  AmPak address, so the driver is not taking the MAC from NVRAM.)
- Untested leads worth trying: `usbcore.autosuspend=-1 pcie_aspm=off
  intel_idle.max_cstate=1` against random freezes, `i915 pwm-lpss-platform` in
  the initramfs module list for backlight control, and disabling NetworkManager's
  Wi-Fi power save to stop firmware crashes.
- Agrees with this repo that both cameras are unusable.

