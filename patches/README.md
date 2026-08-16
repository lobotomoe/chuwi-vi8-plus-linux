# Kernel patches for a Vi8 Plus with unfilled DMI

Three patches that make the kernel recognise a Chuwi Vi8 Plus whose firmware
left `sys_vendor` and `product_name` at `To be filled by O.E.M.`. Between them
they fix the touchscreen, Wi-Fi and audio on such a unit.

**Status: prepared, not submitted, not yet tested on hardware.** They apply
cleanly and are modelled on entries already upstream, but nobody has booted a
kernel built with them. Do not send them anywhere until the checklist below is
done.

| Patch | Subsystem | Fixes |
|---|---|---|
| `0001-…touchscreen_dmi…` | `platform/x86` | ICN8505 firmware extraction from UEFI |
| `0002-…brcmfmac…` | `wifi` | NVRAM lookup for the BCM43430 |
| `0003-…bytcr_rt5651…` | `ASoC/Intel` | mono speaker, swapped headphones, IN2 mic |

The accelerometer needs a systemd hwdb entry rather than a kernel patch; see
below.

## Why this shape

The tablet's system DMI fields are placeholders, so every existing quirk that
keys on them misses. The board fields are correct (`Hampoo` / `Cherry Trail CR`)
but far too generic on their own — they are shared across Hampoo's whole Cherry
Trail line. Upstream's established answer is to match the board fields **plus
the BIOS date**, and there is already an entry doing exactly that for a sibling
tablet in the very file patch 0001 touches:

```c
/* Chuwi HiBook (CWI514) */
DMI_MATCH(DMI_BOARD_VENDOR, "Hampoo"),
DMI_MATCH(DMI_BOARD_NAME, "Cherry Trail CR"),
/* Above matches are too generic, add bios-date match */
DMI_MATCH(DMI_BIOS_DATE, "05/07/2016"),
```

`To be filled by O.E.M.` is likewise already used as a legitimate match value in
both `touchscreen_dmi.c` and `brcmfmac/dmi.c`, so none of this is novel.

### The Wi-Fi patch is not symmetric with the others

Worth understanding before sending it, because it looks wrong at first glance.

`linux-firmware` ships this tablet's own calibration data as
`brcmfmac43430-sdio.Hampoo-D2D3_Vi8A1.txt` — with no `a0` in the name, so it is
only reachable by chip-revision **a1** units. Both revisions shipped in this
model, and the reference tablet is **a0**, which looks for
`brcmfmac43430a0-sdio.*` and therefore cannot see that file at all.

So the quirk points at `ilife-S806`, which *is* present as an a0 build and comes
from the same AmPak AP6212 module — precisely what the existing Chuwi Hi8 Pro
entry does. The `chiprev` field in `brcmf_dmi_data` means a1 units never hit this
entry and keep their current behaviour.

**This is the one place where the patch loads data nobody has tested on this
tablet.** What was verified here is that the tablet's *own* nvram works on an a0
radio, by copying it to `brcmfmac43430a0-sdio.txt` by hand. `ilife-S806` is a
different file, chosen because it is the only a0-named candidate from the same
module.

The choice has one piece of outside support: Chuwi's own driver package for the
Vi8 Plus is distributed as `Hi8_Pro_drivers_C806_X64.zip` — the vendor treats
the two tablets as a single `C806` platform, which is the premise the kernel's
existing Hi8 Pro entry rests on. That is corroboration, not a test. Prove it
before sending:

```sh
sudo cp /lib/firmware/brcm/brcmfmac43430a0-sdio.ilife-S806.txt \
        /lib/firmware/brcm/brcmfmac43430a0-sdio.txt
sudo reboot
ip -br link          # wlan0 must appear, and must associate
```

Reboot rather than reloading the module — after a failed attempt the chip is
left wedged and returns `-16 EBUSY`, which looks like an unrelated fault.

If `ilife-S806` does **not** bring the radio up, do not send patch 0002 as
written. The alternative is to set `board_type` to `"Hampoo-D2D3_Vi8A1"` and
submit a one-line `linux-firmware` change adding
`brcmfmac43430a0-sdio.Hampoo-D2D3_Vi8A1.txt` as a link to the existing file.
That uses the data actually known to work, at the cost of two submissions to
two projects, and the kernel half is useless until the firmware half lands.

One style point a reviewer may raise either way: `chuwi_vi8_plus_data` is
byte-identical to `chuwi_hi8_pro_data`. Keeping the separate name documents
which tablet the entry is for; be ready to be asked to reuse the existing
struct instead.

## Before submitting: confirm the BIOS date

All three patches hard-code `12/11/2015`. That came from a **photograph of the
setup screen**, not from the kernel's own view of DMI, and if the string in
`/sys` differs by so much as a leading zero the patches match nothing.

Run this on the tablet. The brackets are not decoration — see below.

```sh
for f in bios_version bios_date sys_vendor product_name product_sku \
         board_vendor board_name; do
  printf '%-14s [%s]\n' "$f" "$(cat "/sys/class/dmi/id/$f" 2>/dev/null)"
done
```

Expected, from what has been verified so far:

```
bios_version   [P03_C806.108]
bios_date      [12/11/2015]
sys_vendor     [To be filled by O.E.M.]
product_name   [To be filled by O.E.M.]
product_sku    [MRD]
board_vendor   [Hampoo]
board_name     [Cherry Trail CR]
```

**Trailing spaces decide whether patch 0002 works.** DMI strings routinely carry
them — the BIOS image parsed for this repo has a system serial that is a single
space — and they are invisible in ordinary output. `DMI_MATCH` is a substring
test and tolerates them, but patch 0002 uses `DMI_EXACT_MATCH` on
`board_vendor` and `board_name`, which does not. If either bracket shows
`[Hampoo ]` rather than `[Hampoo]`, the entry must either include the space or
switch to `DMI_MATCH`.

Copy the output rather than retyping it. `Cherry Trail CR` and `CherryTrail CR`
both exist on this hardware — the first is the board name, the second is the
SMBIOS family in the same BIOS image — and one space is the whole difference
between a patch that matches and one that silently does nothing.

`sudo ./scripts/collect-hw-report.sh` captures all of these in one file, along
with everything else worth having.

If `bios_version` reads `P03_C806.108`, consider adding
`DMI_MATCH(DMI_BIOS_VERSION, "P03_C806.108")` to each entry — it is far more
specific than the date and would remove any risk of catching another Hampoo
board built the same day. It was left out only because it is unverified.

## Testing

### Audio, without building anything

The RT5651 machine driver takes a quirk override on the command line, so the
flags can be proven before the patch exists:

```sh
sudo modprobe -r snd_soc_sst_bytcr_rt5651
sudo modprobe snd_soc_sst_bytcr_rt5651 quirk=0xC23412
dmesg | grep -iA6 'quirk'
```

`0xC23412` is `BYT_RT5651_DEFAULT_QUIRKS | IN2_MAP | HP_LR_SWAPPED |
MONO_SPEAKER`. Two of its components (`JD1_1`, `OVCD_SF_0P75`) were derived from
the enum ordering rather than read from a header, so treat the number as a
starting point — the driver decodes and logs whatever it applied, which tells
you immediately whether it is right.

The flags themselves are on firmer ground than the encoding. The patch copies the
existing upstream `Chuwi Vi8 Plus (CWI519)` entry verbatim and changes only the
`.matches`, and the driver maintainer's own per-tablet audio table lists this
model as `mono / mono in2 / JD1_1` — an independent confirmation of the mono
speaker, the IN2 microphone mapping and the jack-detect source
([90-references.md](../docs/90-references.md#three-more-files-in-the-same-repository)).
`HP_LR_SWAPPED` is the one flag not corroborated outside the kernel entry itself,
and it is also the one you can hear: swapped left and right in headphones.

### The rest

There is no shortcut: build a kernel with the patches and boot it. On this
hardware, build on another machine.

```sh
# touchscreen: the firmware should now be pulled out of UEFI by itself
dmesg | grep -i icn8505
# wifi: the board_type should no longer contain the placeholder
dmesg | grep -i brcmf_fw_alloc_request
```

Note that patch 0001 can only work if the ICN8505 firmware really is in this
unit's UEFI image. It was **not** found in either published BIOS image
([60-bios-firmware.md](../docs/60-bios-firmware.md)), so run
`sudo ./scripts/dump-bios.sh` first — if that does not find it either, the DMI
match is correct but the touchscreen still will not come up, and that is a
separate problem. The maintainer's notes do say `fw in EFI` for this model, so
absence in the published images is more likely an extraction limit than proof.

**Patch 0001 is a convenience, not the only route to a working touchscreen.** The
driver derives `chipone/icn8505-HAMP0002.fw` from ACPI `_SUB`, not from DMI, and
`firmware_request_platform()` checks the filesystem before the UEFI copy. A file
dropped into `/lib/firmware/chipone/` therefore works on an unpatched kernel with
the DMI still unfilled. What the patch buys is not needing the file at all. Try
the file first — it is the faster way to learn whether the rest of the touchscreen
stack is healthy, and it makes a good bisection point if the patched kernel still
does not work.

## Where to send them

Verified against `MAINTAINERS` at the base commit below.

| Patch | To | Cc |
|---|---|---|
| 0001 | Hans de Goede `<hansg@kernel.org>` | `linux-input@vger.kernel.org`, `platform-driver-x86@vger.kernel.org` |
| 0002 | Arend van Spriel `<arend.vanspriel@broadcom.com>` | `linux-wireless@vger.kernel.org`, `brcm80211@lists.linux.dev` |
| 0003 | Cezary Rojewski `<cezary.rojewski@intel.com>` and the other Intel ASoC maintainers | `linux-sound@vger.kernel.org` |

Send them as three independent patches, not a series — they touch unrelated
subsystems and will be applied by different trees.

Each file carries a placeholder:

```
Signed-off-by: Your Name <your.email@example.com>
```

Replace it with your own name and address. That line is the Developer
Certificate of Origin — a real legal statement that you wrote the patch and may
submit it — so it is deliberately not pre-filled.

Read `Documentation/process/submitting-patches.rst` before the first send, and
run `scripts/checkpatch.pl` on each file from inside a kernel tree.

You do not need a company behind you. Roughly half the commits to
`touchscreen_dmi.c` come from personal addresses — gmail, yandex, protonmail,
hotmail — because a quirk table for discontinued Chinese tablets can only be
maintained by the people who own them. Patches get rejected for format, not for
who sent them.

### Do not send these from a Proton address

Proton looks up recipient keys over WKD and **encrypts automatically to any
address it finds a key for**, which includes `@kernel.org`. There is no setting
to turn it off, so the patch arrives encrypted and unreadable to the list. This
was raised on LKML in 2022 in a patch proposing to document Proton as unsuitable
for kernel development; verify whether anything has changed before relying on
it. Proton's SMTP also needs the paid Bridge before `git send-email` can talk to
it at all.

The usual workaround is a separate free account elsewhere used only for kernel
mail, with an app password. Whatever you use, send the patch to yourself first
and check that what arrives still applies with `git am`.

## The accelerometer needs no patch at all

It looks like a fourth casualty of the unfilled DMI — systemd's hwdb carries
this tablet only under its good strings:

```
sensor:modalias:acpi:BOSC0200:*:dmi:*:svnHampoo:pnD2D3_Vi8A1:*   # Vi8 Plus (CWI519)
```

But that entry is a fallback the kernel never reaches here. `bmc150_accel` tries
ACPI first and only reads the hwdb-supplied property if that fails:

```c
if (!bmc150_apply_acpi_orientation(dev, &data->orientation)) {
	ret = iio_read_mount_matrix(dev, &data->orientation);
```

For a `BOSC0200` device the ACPI path looks for a `ROTM` method. The driver's
comment lists "Chuwi Vi8 Plus (CWI519)" among exactly these devices, and the
driver's maintainer, who owns one, records `mount-matrix ok` for it in his own
hardware notes. Neither is a reading of the tablet's actual DSDT — the ACPI
tables are compressed inside the BIOS image and were not unpacked here — so
treat the `in_accel_mount_matrix` check as the real evidence.

So no hwdb entry is needed and no `modalias` has to be captured for one. If
auto-rotation still does not happen, that is LXQt not acting on the sensor,
which is a desktop-side problem and not a quirk to submit anywhere.

## Provenance

Generated against `torvalds/linux` master
`3eb40771c00a8488fa6ed2cc1fe203477908bf38` (2026-08-15) and verified to apply
with `patch -p1 --dry-run`. Regenerate them if upstream moves the surrounding
entries.
