# Linux on the Chuwi Vi8 Plus (CWI519)

Everything needed to replace Windows with a modern Linux desktop on the Chuwi Vi8 Plus
tablet, from macOS, Linux or Windows.

The Vi8 Plus is an 8" Intel Cherry Trail tablet: 64-bit CPU, **32-bit UEFI firmware**,
2 GB RAM, 32 GB eMMC, and a single USB-C port that cannot charge and host a USB device
at the same time. Every awkward step in this repo comes from one of those four facts.

The good news: as of 2026 every piece of silicon in this tablet is supported by the
stock kernel of a current distribution. Nothing has to be compiled.

---

## Do not confuse it with the Chuwi Vi8

Most search results for "Chuwi Vi8 Linux" are about the **original Vi8 (CWI506)**, a
2014 *Bay Trail* tablet with completely different parts. Following those guides on a
Vi8 Plus makes you install drivers you do not need and miss the ones you do.

| | Chuwi Vi8 (CWI506) | **Chuwi Vi8 Plus (CWI519)** |
|---|---|---|
| SoC | Atom Z3735F (Bay Trail) | **Atom x5-Z8300/Z8350 (Cherry Trail)** |
| DMI product | `i86`, vendor `Insyde` | **`D2D3_Vi8A1`, vendor `Hampoo`** |
| Touchscreen | Silead GSL3676 | **Chipone ICN8505** |
| Wi-Fi | Realtek RTL8723BS | **Broadcom BCM43430 (AmPak AP6212)** |
| Audio codec | Realtek RT5640 | **Realtek RT5651** |
| Ports | micro-USB | **USB Type-C**, micro-HDMI |

Confirm which one you have before doing anything else — see
[docs/01-hardware.md](docs/01-hardware.md#identify-your-tablet).

---

## What you need

- The tablet, **charged to 100 %** (you cannot charge it during the install).
- A **USB-C OTG hub** with at least two USB-A ports.
- A **USB keyboard**. The firmware setup menu does respond to touch on some units, but
  do not bet the install on it.
- A **USB stick, 8 GB or larger**.
- Optionally a second USB stick or a USB SSD if you want a full image backup of Windows.
- A computer running macOS, Linux or Windows to build the install stick.

---

## The short version

1. **Read [docs/02-boot-problem.md](docs/02-boot-problem.md).** It explains why a
   normal Ubuntu USB stick will never appear in this tablet's boot menu, and why the
   fix is a single file called `bootia32.efi`, which is already in
   [`artifacts/`](artifacts/).
2. Back up Windows if you want the option to go back —
   [docs/03-prepare-and-backup.md](docs/03-prepare-and-backup.md).
3. Build the install stick on your computer:
   - [macOS](docs/10-usb-macos.md)
   - [Linux](docs/11-usb-linux.md)
   - [Windows](docs/12-usb-windows.md)

   **Use a USB 2.0 stick if you have one.** The Type-C port is wired for USB 2.0 but
   still negotiates SuperSpeed with USB 3.0 devices, fails to hold the link, and drops
   the stick — sometimes minutes into a working session. If it happens to you,
   [docs/13-split-media.md](docs/13-split-media.md) moves the live filesystem onto the
   microSD card and takes USB out of the picture entirely.
4. Get into the tablet's firmware setup, disable Secure Boot, boot the stick —
   [docs/20-uefi-setup.md](docs/20-uefi-setup.md). **Then wait ten minutes.** This
   tablet sits on the CHUWI logo for 5-10 minutes after you pick the stick, and
   powering off early is the most common way people conclude it does not work.
5. Install:
   - [Lubuntu 26.04 LTS](docs/30-install-lubuntu.md) — **recommended**, this is the
     "latest Ubuntu, user friendly" answer for this hardware
   - [Debian 13](docs/31-install-debian.md) — the most reliable fallback, works fully
     offline
   - [Arch Linux](docs/32-install-arch.md) — its ISO already boots 32-bit firmware
     unmodified; the install is all yours
6. [docs/40-post-install.md](docs/40-post-install.md) — rotation, audio, zram, eMMC
   wear, battery.
7. When something misbehaves: [docs/50-troubleshooting.md](docs/50-troubleshooting.md).

Not part of the install, but read it before you flash anything:
[docs/60-bios-firmware.md](docs/60-bios-firmware.md) — the tablet's BIOS releases,
what the circulating firmware archives actually contain, and why updating does not
fix the Linux problems.

Sources for every technical claim in this repo are collected in
[docs/90-references.md](docs/90-references.md).

---

## Which distribution, and why not plain Ubuntu

With 2 GB of RAM and 32 GB of eMMC, the desktop environment is not a matter of taste.

| Option | Verdict |
|---|---|
| **Lubuntu 26.04 LTS** (LXQt) | **Recommended.** It is Ubuntu, supported to April 2029, and it is the only Ubuntu flavour whose installer detects 32-bit firmware and installs a 32-bit GRUB by itself. It tries to take the package from the ISO's own pool; have Wi-Fi connected anyway, see [docs/30](docs/30-install-lubuntu.md). |
| Xubuntu 26.04 LTS (Xfce) | Fine desktop, but it uses the standard Ubuntu installer, which has no 32-bit-firmware handling. You must repair the bootloader by hand afterwards. |
| Ubuntu 26.04 LTS (GNOME) | GNOME on 2 GB RAM is painful, and the ISO alone is bigger than what is comfortable here. Not recommended. |
| **Debian 13 "trixie"** (LXQt/Xfce) | The most dependable path. The installer detects 32-bit firmware and pulls `grub-efi-ia32` **from the ISO itself**, so it works with no network at all. Pick this if the Lubuntu install fights you. |
| Arch Linux | The **only** ISO here that boots this tablet unmodified — current Arch images ship a 32-bit systemd-boot. Everything after that you write yourself. |

Lubuntu ships Calamares rather than Ubuntu's own installer, and Lubuntu's Calamares
configuration reads `/sys/firmware/efi/fw_platform_size` and installs `grub-efi-ia32`
when it says `32`. Ubuntu's installer backend (curtin) picks the GRUB flavour from the
*target architecture* instead and never looks at the firmware at all, so an amd64
install on this tablet gets a 64-bit bootloader the firmware cannot execute. That one
difference is the entire reason for the recommendation. Both claims are verified
against the respective sources — see [docs/90-references.md](docs/90-references.md).

---

## Hardware support summary

Lubuntu 26.04 has been installed on the reference tablet and runs: it boots from its
own 32-bit GRUB, the desktop is accelerated, and it is online over Wi-Fi. The table
below separates **what the kernel supports** — checked against Ubuntu 26.04's shipping
configuration (Linux 7.0.0-31-generic) and current mainline sources — from **what was
actually observed on that unit**, because on this hardware the two are not the same.

See [docs/01-hardware.md](docs/01-hardware.md) for per-component detail and the exact
kernel symbols.

| Component | In the kernel | On the reference unit |
|---|---|---|
| Graphics (Cherry Trail, `i915`) | Yes | **Works**, accelerated, no `nomodeset` needed |
| eMMC, microSD | Yes | **Works** — installed to eMMC, ran the installer off a card |
| Wi-Fi (BCM43430) | Yes | **Works after a manual NVRAM copy** — see below. 2.4 GHz only, the radio has no 5 GHz |
| Touchscreen (Chipone ICN8505) | Yes | **Does not work out of the box** — the DMI quirk does not match, so the firmware is never extracted. Fixable without a kernel patch: the filename comes from ACPI, and Chuwi's own driver package carries the firmware |
| Audio (RT5651) | Yes | Untested; the quirk does not match, so expect wrong channel mapping |
| Accelerometer / auto-rotation | Partly | **The sensor binds** — `BOSC0200` appears as `iio:device0` — but `iio-sensor-proxy` cannot read it: *"Could not find trigger name"*, then *"Buffer did not have data within 0.5s"*. So orientation is exposed by ACPI `ROTM` as designed, and userspace still does not rotate |
| Battery, charging (AXP288) | Yes | **Works** — `axp288_fuel_gauge` reports capacity, voltage and current; `axp288_charger` reports the USB supply online. Charges at 2 A only from a USB-A charger via an A-to-C cable — no PD, and C-to-C gives 500 mA |
| Backlight | Yes | **Works** — `intel_backlight` present and readable |
| micro-HDMI | Yes | Untested |
| Bluetooth (BCM43430 over UART) | Yes | Untested. Needs an `.hcd` from `bluez-firmware`, **not** `linux-firmware` — and no distribution ships one for an a0 chip |
| Suspend | Partly | Untested here. The maintainer's table scores it as suspending but **not** reaching S0i3, so expect idle drain |
| Cameras | **No** | Cherry Trail ISP has no usable mainline driver. Treat them as absent |

### Why several of those say "does not match"

**Some units ship with their DMI fields unfilled.** The reference tablet reports
`To be filled by O.E.M.` for both `sys_vendor` and `product_name`; only the board
fields are set. Nearly every per-device kernel quirk for this tablet keys off the
system fields, so on such a unit the touchscreen, the Wi-Fi calibration lookup and
the audio routing quirk all silently fail to apply — three unrelated-looking faults
from one placeholder string.

Wi-Fi and the touchscreen have DMI-independent workarounds — in both cases the
driver's second attempt uses a name that comes from ACPI or from the chip itself.
Audio has no such escape hatch and needs a kernel patch. The accelerometer looks
like a fourth victim and is not one: its mount matrix is supposed to come from an
ACPI `ROTM` method rather than from DMI. Check yours before you conclude anything:

```sh
cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name
```

Full explanation and the fixes:
[docs/01-hardware.md](docs/01-hardware.md#some-units-ship-with-the-dmi-fields-unfilled-and-it-breaks-three-things-at-once).

**Do not go looking for a BIOS update to fix it.** The placeholder is baked into
the firmware image Chuwi shipped — verified by parsing the newest published BIOS —
so flashing it changes nothing, and one image circulating as "Vi8 Plus BIOS" is
for a different tablet entirely. [docs/60-bios-firmware.md](docs/60-bios-firmware.md)
covers the firmware history, what each image really is, and what does help.

---

## Repository layout

```
artifacts/    bootia32.efi and its provenance - the file that makes the stick bootable
scripts/      build the stick, inspect ISOs, back up the eMMC, repair GRUB, tune
docs/         the actual guide, split by host OS and by distribution
patches/      kernel patches for a unit with unfilled DMI - prepared, not yet sent
tests/        checks the scripts still behave; see "Tests" below
```

Docs and scripts are MIT. `artifacts/bootia32.efi` is an unmodified Debian GRUB binary
and stays under the GPL v3+ — [`LICENSE`](LICENSE),
[`artifacts/PROVENANCE.md`](artifacts/PROVENANCE.md).

| Script | Runs on | What it does |
|---|---|---|
| `make-media.sh` | macOS, Linux | Builds the install stick: GPT + FAT32, ISO contents, `bootia32.efi` |
| `make-media.ps1` | Windows | The same, via the Storage cmdlets and `robocopy` |
| `check-iso-ia32.sh` | macOS, Linux | Says whether an ISO boots 32-bit firmware as shipped |
| `fetch-bootia32.sh` | macOS, Linux | Re-derives `bootia32.efi` from Debian's archive, checksum-verified |
| `fetch-offline-payload.sh` | macOS, Linux | Downloads `grub-efi-ia32-bin` to carry on the stick |
| `collect-hw-report.sh` | tablet | One file with DMI, firmware bitness, drivers, audio, power |
| `dump-bios.sh` | tablet | Reads the SPI flash twice, verifies, extracts the touchscreen firmware. Never writes |
| `extract-touchscreen-fw.sh` | macOS, Linux | Pulls the ICN8505 firmware out of Chuwi's own driver INF, hash-checked |
| `inspect-bios-image.py` | macOS, Linux | Re-derives every firmware claim in [60-bios-firmware.md](docs/60-bios-firmware.md) from a BIOS image. Read-only |
| `backup-emmc.sh` | tablet | Compressed image of the eMMC to an external disk, before wiping |
| `restore-emmc.sh` | tablet | Writes that image back, checksum-verified, to get Windows back |
| `postinstall-grub-ia32.sh` | tablet | Installs a 32-bit GRUB into the installed system's ESP |
| `postinstall-tune.sh` | tablet | zram, TRIM, rotation daemon, journal cap — reports before it acts |

Shell scripts are `bash`, pass `shellcheck` cleanly, and depend only on what the OS
ships. Every script that can destroy data prints what it found and refuses to continue
until you type the target device back — including the restore path, which is why it is
a script and not a `dd` line to copy out of a document.

Each of them also does its checking **before** the destructive step, never after:
`make-media.sh` verifies the ISO and confirms the image can even fit on FAT32 while the
stick is still untouched, and `restore-emmc.sh` verifies the image against its checksum
and refuses a target it would not fit on before it writes a byte.

### Tests

```sh
./tests/run-tests.sh          # static analysis, argument handling, artifact integrity
sudo ./tests/run-tests.sh     # the above, plus an end-to-end make-media.sh run
```

The end-to-end test builds a synthetic ISO, attaches a **virtual** disk (a disk image
on macOS, a loop device on Linux), runs `make-media.sh` against it and checks the
resulting stick really carries `EFI/BOOT/bootia32.efi` and the ISO's tree. It never
touches a real device.

---

## Reality check before you start

- **This wipes Windows.** 32 GB is not enough for a sane dual boot; Windows 10 alone
  leaves under 18 GB free. Back it up first if you might want it back.
- **You cannot charge during the install.** One USB-C port, and it is occupied by the
  OTG hub. Start at 100 %; the install takes 20-40 minutes.
- **Secure Boot must stay off.** No distribution publishes a Microsoft-signed 32-bit
  x86 shim, so there is nothing to start a signed chain from —
  [details](docs/02-boot-problem.md#secure-boot).
- **This tablet is from 2016.** Cherry Trail is slow and its Linux support, while
  complete, is maintained by very few people. Expect a usable browsing/media/terminal
  machine, not a fast one.

---

## How much of this has actually been done

Individual claims carry their own markers — **verified on the unit** means someone
watched it happen, **verified** on its own means a file, image or source tree was
read. This is the summary, because the rest of the document reads with one voice and
that voice is not uniformly earned.

**Done on the tablet, start to finish.** One unit. Built the install medium, booted
it, installed Lubuntu 26.04 to the eMMC, and it runs: graphics, eMMC, microSD,
network. Wi-Fi was brought up by hand and the fix is recorded. The firmware setup
menu was walked through and photographed. The failure modes in the touchscreen and
Wi-Fi sections are copied out of that unit's own `dmesg`.

**Derived from sources, never executed here.**

| Thing | What it rests on |
|---|---|
| [Debian](docs/31-install-debian.md) and [Arch](docs/32-install-arch.md) guides | ISO contents and installer source, read. **Neither was installed on this tablet** |
| [`make-media.ps1`](scripts/make-media.ps1) | Never run — no Windows machine was involved |
| `restore-emmc.sh`, `postinstall-*.sh`, `dump-bios.sh` | Argument handling is unit-tested; none has run on the tablet |
| `extract-touchscreen-fw.sh` | Every path exercised except `--install`, which needs the tablet |
| The three [`patches/`](patches/) | Apply cleanly to mainline. Never compiled, never booted |
| Suspend, HDMI, Bluetooth, audio, cameras | Not exercised on the installed system |

**The date all three patches depend on.** They hard-code BIOS date
`12/11/2015`. That was a photograph of the setup screen, then the `P03_C806.108`
image was obtained carrying the same string —
`BIOS Date: 12/11/2015 21:15:52 Ver: 1ATFG007` — timestamp and all, and it has
now been read off the running kernel as `/sys/class/dmi/id/bios_date`. Not three
independent sources — all three trace back to the same firmware build — but three
ways of reading it that could each have disagreed, and did not. The third is the
one that counts, because it is the string `DMI_MATCH` is handed. The full DMI
capture is in [patches/README.md](patches/README.md).

**Everything is n=1.** One tablet, one BIOS build, one chip revision (a0). Where
this repo says "some units", that is other owners' reports, marked as such.
