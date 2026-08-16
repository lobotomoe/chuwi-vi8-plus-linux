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
module. Prove it before sending:

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

Run this on the tablet and check it against the patches:

```sh
cat /sys/class/dmi/id/bios_date        # expected: 12/11/2015
cat /sys/class/dmi/id/bios_version     # expected: P03_C806.108
cat /sys/class/dmi/id/board_vendor     # expected: Hampoo
cat /sys/class/dmi/id/board_name       # expected: Cherry Trail CR
cat /sys/class/dmi/id/modalias         # needed verbatim for the hwdb entry
```

`sudo ./scripts/collect-hw-report.sh` captures all of these in one file.

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
separate problem.

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

## The accelerometer is not a kernel patch

Auto-rotation orientation lives in systemd's hwdb, which already has this
tablet under its good DMI strings:

```
sensor:modalias:acpi:BOSC0200:*:dmi:*:svnHampoo:pnD2D3_Vi8A1:*   # Vi8 Plus (CWI519)
```

`60-sensor.hwdb` also carries entries matching on BIOS date and board fields for
tablets with generic system strings, so the same fix applies — but the entry has
to be written against this unit's exact `modalias`, which is why it is on the
checklist above and not in this directory yet. It goes to
<https://github.com/systemd/systemd>, not to the kernel.

## Provenance

Generated against `torvalds/linux` master
`3eb40771c00a8488fa6ed2cc1fe203477908bf38` (2026-08-15) and verified to apply
with `patch -p1 --dry-run`. Regenerate them if upstream moves the surrounding
entries.
