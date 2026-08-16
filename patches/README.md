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

This used to be the one place where the patch loaded data nobody had tested on
this tablet. It is not any more: the two files carry **identical parameters**.
Strip the comments and both are the same 35 lines, same SHA-256:

```sh
strip() { grep -v '^#' "$1" | grep -v '^[[:space:]]*$' | sort; }
diff <(strip brcmfmac43430-sdio.Hampoo-D2D3_Vi8A1.txt) \
     <(strip brcmfmac43430a0-sdio.ilife-S806.txt)      # no output
strip brcmfmac43430-sdio.Hampoo-D2D3_Vi8A1.txt | sha256sum
# b852086122b09010b6c5c9c7bbdfda87365a089e7f7f3985aed306a1525a3f9e
```

— **verified** against both files as `linux-firmware` ships them. The only
difference between them is one comment line naming the tablet.

Since the tablet's own nvram is confirmed working on an a0 radio — copied to
`brcmfmac43430a0-sdio.txt` by hand — pointing the quirk at `ilife-S806` loads
byte-for-byte the same calibration. The remaining risk is not the data but
whether the *filename* resolves as expected on a real boot.

The choice had one piece of outside support: Chuwi's own driver package for the
Vi8 Plus is distributed as `Hi8_Pro_drivers_C806_X64.zip`, so the vendor treats
the two tablets as a single `C806` platform — the premise the kernel's existing
Hi8 Pro entry rests on.

**That support is weaker than it looks, now that the package has been opened.**
Its Wi-Fi driver is `netrtwlans.inf` / `rtwlans.sys`, *"Realtek Wireless
802.11b/g/n SDIO"* — not Broadcom at all. So a single `C806` driver bundle covers
units with at least two different radios, and "same platform code" does not imply
"same Wi-Fi module". The dual-boot BIOS says the same thing from the other side:
its DSDT declares `OBDA8723`, a Realtek part, where the single-OS image does not.

Which leaves the `ilife-S806` choice resting on the module identification alone —
still reasonable, since `brcmfmac/dmi.c` states outright that *"The Chuwi Hi8 Pro
uses the same Ampak AP6212 module as the Chuwi Vi8 Plus"*, but it is one source,
not two. Prove it before sending:

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

All three patches hard-code `12/11/2015`. That is now **confirmed from the
firmware image itself**, not only from a photograph: `P03_C806.108`, the build
the reference tablet shipped with, contains the signon string

```
BIOS Date: 12/11/2015 21:15:52 Ver: 1ATFG007
```

— **verified** by extracting strings from the image
([60-bios-firmware.md](../docs/60-bios-firmware.md#the-ver-string-is-not-a-version-number)).

Still read it off the running kernel before sending. The image proves what the
firmware was built with; `/sys/class/dmi/id/bios_date` is what `DMI_MATCH`
actually compares against, and only the second one can rule out a stray space or
a different formatting.

Run this on the tablet. The brackets are not decoration — see below.

```sh
for f in bios_version bios_date sys_vendor product_name product_sku \
         board_vendor board_name; do
  printf '%-14s [%s]\n' "$f" "$(cat "/sys/class/dmi/id/$f" 2>/dev/null)"
done
```

What the tablet actually returns:

```
bios_version   [P03_C806.108]
bios_date      [12/11/2015]
sys_vendor     [To be filled by O.E.M.]
product_name   [To be filled by O.E.M.]
product_sku    [MRD]
board_vendor   [Hampoo]
board_name     [Cherry Trail CR]
```

— **verified on the unit**, and it matches the prediction from the BIOS image
field for field.

That settles the two things these patches were waiting on.

**No trailing spaces.** DMI strings routinely carry them — the BIOS image parsed
for this repo has a system serial that is a single space — and they are invisible
in ordinary output. `DMI_MATCH` is a substring test and tolerates them, but patch
0002 uses `DMI_EXACT_MATCH` on `board_vendor` and `board_name`, which does not.
Every bracket above closes flush against its value, so `DMI_EXACT_MATCH` is safe
and patch 0002 needs no change. This is also the right test to have run: sysfs
and `DMI_MATCH` both read the same stored `dmi_ident[]` strings, so what the
brackets show is exactly what the match sees.

**The existing upstream entry cannot fire on this unit, and now that is
observed rather than argued.** Mainline matches `DMI_SYS_VENDOR` `Hampoo` and
`DMI_PRODUCT_NAME` `D2D3_Vi8A1`; both fields hold the placeholder here. Note
that `Hampoo` *is* present — in `board_vendor`, which upstream does not look at.
The new entry keys on the three fields that are populated, and all three match:
`board_vendor` `Hampoo`, `board_name` `Cherry Trail CR`, `bios_date`
`12/11/2015`.

Copy the output rather than retyping it. `Cherry Trail CR` and `CherryTrail CR`
both exist on this hardware — the first is the board name, the second is the
SMBIOS family in the same BIOS image — and one space is the whole difference
between a patch that matches and one that silently does nothing.

`sudo ./scripts/collect-hw-report.sh` captures all of these in one file, along
with everything else worth having.

`bios_version` reads `P03_C806.108` on this unit — **verified**. Adding
`DMI_MATCH(DMI_BIOS_VERSION, "P03_C806.108")` to each entry is therefore an
option now that it is no longer a guess: it is far more specific than the date
and would remove any risk of catching another Hampoo board built the same day.
It is still left out deliberately, because it would also stop the entries
matching a unit running `.109`, and nothing suggests that build behaves
differently — the two images carry the same placeholder SMBIOS defaults
([60-bios-firmware.md](../docs/60-bios-firmware.md#what-changed-between-108-and-109)).
The date is the looser key on purpose.

## Testing

### Audio, without building anything

The RT5651 machine driver takes a quirk override on the command line, so the
flags can be proven before the patch exists:

```sh
sudo modprobe -r snd_soc_sst_bytcr_rt5651
sudo modprobe snd_soc_sst_bytcr_rt5651 quirk=0xC23412
dmesg | grep -iA6 'quirk'
```

**The driver prints what it applied, and on this tablet it prints the fallback**
— which is the other half of the proof. Untouched, with no DMI match, it logs:

```
bytcr_rt5651: quirk IN2_MAP enabled
bytcr_rt5651: quirk realtek,jack-detect-source 1
bytcr_rt5651: quirk realtek,over-current-threshold-microamp 2000
bytcr_rt5651: quirk realtek,over-current-scale-factor 1
bytcr_rt5651: quirk MCLK_EN enabled
```

— **verified on the unit**. That is `DEFAULT_QUIRKS | IN2_MAP` = `0x23412`,
term for term, decoded by the driver itself rather than by the table below.
`MONO_SPEAKER` and `HP_LR_SWAPPED` are the two that do not appear, and they are
exactly what this patch adds: `0x23412 | 0x800000 | 0x400000` = **`0xC23412`**.
So the target value is confirmed from the running driver, and the audio symptoms
to expect until the patch lands are stereo routing on a mono speaker and swapped
headphone channels.

`0xC23412` is `BYT_RT5651_DEFAULT_QUIRKS | IN2_MAP | HP_LR_SWAPPED |
MONO_SPEAKER`, and every term is read from a header rather than inferred:

| Term | Value | Source |
|---|---|---|
| `IN2_MAP` | `0x000002` | third member of the map enum, bits 3:0 |
| `JD1_1` | `0x000010` | `RT5651_JD1_1` = 1, shifted into bits 7:4 |
| `OVCD_TH_2000UA` | `0x001400` | `20 << 8` |
| `OVCD_SF_0P75` | `0x002000` | `RT5651_OVCD_SF_0P75` = 1, shifted into bits 14:13 |
| `MCLK_EN` | `0x020000` | `BIT(17)` |
| `HP_LR_SWAPPED` | `0x400000` | `BIT(22)` |
| `MONO_SPEAKER` | `0x800000` | `BIT(23)` |

The four codec-side constants come from `include/dt-bindings/sound/rt5651.h`,
the rest from `bytcr_rt5651.c` itself. `DEFAULT_QUIRKS` is `0x23410`; OR the
other three in and the total is `0xC23412`. — **verified**

The driver still decodes and logs whatever it applied, which is the real
confirmation.

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

**Patch 0001 may well be a no-op on the unit it was written for, and that has to
be said when sending it.** The quirk entry's entire payload is an `embedded_fw`
descriptor, so it does something only if the ICN8505 firmware really is in that
unit's UEFI image. It is not in either published BIOS image, and it is not in the
flash read off the reference tablet either — `inspect-bios-image.py`, which
unpacks the UEFI volumes and every LZMA stream rather than grepping raw bytes,
reports it absent from all of them ([60-bios-firmware.md](../docs/60-bios-firmware.md)).
So on that tablet the DMI match would fire, the EFI scan would find nothing, and
the touchscreen would still not come up.

That is evidence about one firmware build, not proof about the model. The
driver's maintainer records `fw in EFI` for this tablet and his unit is an a1, so
the likeliest reading is that an earlier BIOS build carried the blob and `.108`
and `.109` do not. Worth stating in the submission and letting him judge — he
wrote both the driver and the EFI extraction mechanism.

`sudo ./scripts/dump-bios.sh` checks your own unit, but note it searches the raw
dump only; a negative from it is weaker than one from the inspector.

**Patch 0001 is a convenience, not the only route to a working touchscreen.** The
driver derives `chipone/icn8505-HAMP0002.fw` from ACPI `_SUB`, not from DMI, and
`firmware_request_platform()` checks the filesystem before the UEFI copy. A file
dropped into `/lib/firmware/chipone/` therefore works on an unpatched kernel with
the DMI still unfilled. What the patch buys is not needing the file at all. Try
the file first — it is the faster way to learn whether the rest of the touchscreen
stack is healthy, and it makes a good bisection point if the patched kernel still
does not work.

That route is no longer theoretical: on the reference unit
`extract-touchscreen-fw.sh --download --install` plus a `modprobe -r` / `modprobe`
brought the touchscreen up on a stock Ubuntu kernel with the DMI still unfilled —
tracking the finger, though with both axes rotated 180°, which a libinput
calibration matrix corrects ([01-hardware.md](../docs/01-hardware.md)). Which is
also what makes the paragraph above worth taking seriously: the working fix
bypasses UEFI entirely, so it says nothing about whether the blob is in there.

That rotation is **not** an argument for adding axis properties to patch 0001.
`chuwi_vi8_plus_data` has no `.properties` at all, so a missed DMI match costs
the firmware and nothing else, and the likeliest cause is the substitute firmware
build rather than the hardware. Quirking it upstream would break the units that
get the blob out of EFI as intended.

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

Read `Documentation/process/submitting-patches.rst` before the first send.

`scripts/checkpatch.pl --strict` has been run on all three:

```
total: 1 errors, 0 warnings, 0 checks
```

The one error in each is `Missing Signed-off-by: line by nominal patch author ''`,
which is the placeholder above doing its job — checkpatch compares the sign-off
against the `From:` author, and these files have neither filled in. Replace the
sign-off with your own name and that error goes away.

It found real problems the first time round: over-long commit-description lines
in 0002 and 0003, and an 80-character subject on 0001. Those are fixed. Re-run it
after any edit — the limit is 75 columns for both subject and body, and a wrapped
line is one of the more common reasons a first patch gets bounced.

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

For a `BOSC0200` device the ACPI path looks for a `ROTM` method, and this tablet's
DSDT has one — extracted from the published `P03_C806.109` image and read
directly. It sits in the `ACC2` device scope and spells the matrix out:
`"0 -1 0" "-1 0 0" "0 0 1"`. The driver's comment lists "Chuwi Vi8 Plus (CWI519)"
among exactly these devices.

So no hwdb entry is needed and no `modalias` has to be captured for one. If
auto-rotation still does not happen, that is LXQt not acting on the sensor,
which is a desktop-side problem and not a quirk to submit anywhere.

## Provenance

Generated against `torvalds/linux` master
`3eb40771c00a8488fa6ed2cc1fe203477908bf38` (2026-08-15) and verified to apply
with `patch -p1 --dry-run`. Regenerate them if upstream moves the surrounding
entries.
