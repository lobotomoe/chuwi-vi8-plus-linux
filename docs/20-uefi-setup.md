# Getting into the firmware and booting the stick

## Wire it up first

Tablet off, then: USB-C OTG hub into the tablet, keyboard and the install stick
into the hub. Do this before powering on — some firmware only enumerates USB
devices present at power-up.

## Turn off Windows Fast Startup, or "shut down" will not shut down

This bites people constantly. With Fast Startup enabled, choosing "Shut down"
in Windows hibernates the kernel instead of powering off, and the firmware setup
key never gets a chance to register.

In Windows, as administrator:

```
powercfg /h off
```

Then shut down normally.

## Two ways into the firmware setup

### The reliable way: ask Windows to reboot into it

While you still have Windows:

**Settings -> Update & Security -> Recovery -> Advanced startup -> Restart now
-> Troubleshoot -> Advanced options -> UEFI Firmware Settings -> Restart**

Or from an administrator command prompt:

```
shutdown /r /fw /t 0
```

This lands in the firmware setup without any key timing.

### The key way

With the tablet fully off and the keyboard attached through the hub: hold the
power button to switch on and tap **Esc** repeatedly on the USB keyboard from
the moment the screen lights up.

**Esc is the right key on this tablet** — confirmed on the unit this guide was
written against, and independently by several owners on the 4PDA thread
(post #636: *"заходим в биос (при включении зажать кнопку ESC)"*, post #990).
Two alternatives are also confirmed there:

| Key | What it does |
|---|---|
| **Esc** | Firmware setup. The one to use. |
| **F7** | One-off boot menu — goes straight to the device list |
| **Del** | Setup, on some units |
| **Volume +** | Setup, without a keyboard. Also the documented way back in when a bad setting leaves the tablet stuck on the logo — see [50-troubleshooting.md](50-troubleshooting.md#a-setting-you-changed-left-it-stuck-on-the-chuwi-logo) |

`F7` is worth knowing: it skips the setup menu entirely, which is what you want
once Secure Boot is already sorted and you just need to pick the stick.

## The firmware you will see

**AMI Aptio Setup Utility, version 2.17.1249 (American Megatrends, 2015).** Not
Insyde. Six tabs, in this order:

```
Main   Advanced   Chipset   Security   Boot   Save & Exit
```

The key legend is printed down the right-hand side of every page:

| Key | Action |
|---|---|
| ← → | Move between tabs |
| ↑ ↓ | Move between items |
| Enter | Open the selected item |
| **+ / −** | **Change the value** — not Enter, on value fields |
| F1 | General help |
| F2 | Previous values |
| F3 | Optimized defaults |
| **F4** | **Save & Exit** |
| Esc | Back / exit |

**Saving is F4, not F10.** F10 does nothing here.

## Most of this menu is hidden — turn it on first

**Do not go looking for Secure Boot tab by tab. It is not displayed at all until
you unhide it.** Chuwi ships this firmware with most of its settings suppressed,
and the switch is in an unexpected place:

`Save & Exit` -> **`SHOW ALL ITEM`** -> `Enabled` (change it with `+`, not Enter)

The on-screen help for it reads *"Enable or Disable show all setup item"*. Its
default is `Disabled`. Then pick `Save Changes and Reset` and re-enter setup:
every tab now carries considerably more than before.

This is why a stock walkthrough of these tablets is so often wrong about where
Secure Boot lives. In the default, truncated menu it is nowhere:

- `Security` holds only `Administrator Password` and `User Password` (3–20 chars)
- `Boot` holds only `Bootup NumLock State`, `Quiet Boot`, `Fast Boot`, the fixed
  boot order and `UEFI Hard Disk Drive BBS Priorities`

Once `SHOW ALL ITEM` is on, treat the rest of the menu with care — memory
timings, voltages and chipset internals become visible along with the setting you
came for. **Change Secure Boot and nothing else.**

This is not boilerplate caution. On the 4PDA thread, changing the wrong item in
this menu is the single most common way owners have bricked these tablets — not
flashing firmware, just saving a bad setting:

> *"стоит что-то одно не верно поменять/включить/выключить/наковырять и
> получится кирпич, с которым прямая дорога в СЦ и перепрошивка микрухи
> программатором"* — post #1270

`F3` (Optimized Defaults) undoes an accident **while you can still see the
screen**. If a setting kills video output, you are navigating blind, and the
recovery is in
[50-troubleshooting.md](50-troubleshooting.md#a-setting-you-changed-left-it-stuck-on-the-chuwi-logo).
There is no CMOS jumper and no coin cell on this board.

**Never flash firmware from another Chuwi model.** Several people tried a Hi10
or a 64-bit image and got an unrecoverable brick; there is no way to convert a
32-bit UEFI unit to 64-bit in software (post #2626). Recovery from that point
means disassembly and a CH341A programmer running at **1.8 V**, not the 3.3 V the
common ones ship with. Nothing in this repository requires touching the firmware
image, and you should not.

## What to change

**1. Secure Boot -> Disabled.** This is not optional: no distribution publishes
a Microsoft-signed 32-bit x86 shim, so with Secure Boot on, nothing you build
will start. See [02-boot-problem.md](02-boot-problem.md#secure-boot).

With `SHOW ALL ITEM` enabled, the `Security` tab gains two submenus:

```
Administrator Password
User Password
▶ Secure Boot menu        <- this one
▶ Secure Flash update
```

Open **`Secure Boot menu`** with **Enter** — the `▶` marks a submenu, so `+/-`
does nothing on it. The `Secure Boot` value lives inside.

**On the unit this guide was written against there was nothing to change.** The
submenu read:

```
System Mode        Setup
Secure Boot        Not Active
Vendor Keys        Not Active

Secure Boot        [Disabled]
Secure Boot Mode   [Custom]
▶ Key Management
```

`System Mode: Setup` means no Platform Key is enrolled, and the submenu's own
help spells out the consequence: Secure Boot can only be enabled with a PK
enrolled and CSM disabled. With no keys in the firmware it cannot engage at all,
whatever the setting says. This tablet appears to ship that way, so treat this
step as *confirm*, not *change*.

Stay out of `Key Management`. Enrolling keys is the one action on this screen
that can make the machine harder to boot, and nothing here needs it.

`Secure Flash update` is the neighbouring trap: it is a read-only report on the
firmware's own update policy (`Signed BIOS update`, `Public Key store`,
`Signature algorithm`, `BIOS flash method`, `Flash write-protection`). Nothing in
it is editable and nothing in it concerns booting Linux. Landing there and
concluding that Secure Boot cannot be changed is an easy mistake to make.

If the setting inside is greyed out, that is the AMI Aptio behaviour where it is
locked until a supervisor password exists:

1. `Security` -> `Administrator Password` -> set one
2. `Secure Boot` -> `Disabled`
3. `Security` -> `Administrator Password` -> enter the current one, leave the new
   one **empty** — this clears it again

Do not skip step 3. The only input this tablet has is a USB keyboard on the OTG
hub, and a tablet has no CMOS jumper or coin cell to clear a forgotten password
with. Treat the password as a temporary key, write it down while it is set, and
remove it as soon as Secure Boot is off.

**2. Boot order — nothing to do, and do not rely on it anyway.** Use
`Boot Override` (below) to pick the stick. Reordering the boot list is reported
not to take effect on this tablet — *"it seems like 'windows boot manager' is
overriding the settings"* (techtablets post #23272) — while `Boot Override` works.
The shipped order already puts USB first regardless:

```
Boot Option #1   [USB Lan]
Boot Option #2   [USB Key]
Boot Option #3   [USB Hard Disk]
Boot Option #4   [Hard Disk: Windows Boot Manager]
```

`Fast Boot` is `Disabled` out of the box too, which is what you want — USB gets
enumerated fully at power-on.

**3. Optional: CPU C-states.** Setting C-States to `C1` is a long-standing
workaround for random freezes on Chuwi's Atom tablets. It costs battery life, so
leave it alone unless you actually see freezes — and if you do, see
[50-troubleshooting.md](50-troubleshooting.md#random-freezes). There is no
`Power` tab on this firmware; look under `Advanced` or `Chipset` after enabling
`SHOW ALL ITEM`. Its exact location here has not been confirmed.

Save with **F4** and let it reboot.

## Booting the stick

Go to the last tab, `Save & Exit`, and pick the stick under **`Boot Override`**.
There is no separate `Boot Manager` tab on this firmware. The stick usually
appears under its own product name rather than as "UEFI: USB".

Whether the stick is listed there is the single most informative thing in this
whole menu, and it costs nothing to look. The firmware only offers a removable
device it could actually start, so if the stick appears, a 32-bit loader was
found at `\EFI\BOOT\BOOTIA32.EFI` — the entire problem this repository exists to
solve, answered without leaving setup. With no stick attached the list shows just
`Windows Boot Manager`, so make sure it is plugged in before reading anything
into its absence.

A matching `UEFI USB Key Drive BBS Priorities` submenu appearing on the `Boot`
tab is the same signal: those submenus exist only for device classes the firmware
actually found something bootable in.

If the stick is absent while a keyboard on the same hub works, the missing piece
is the loader, not the hub — USB itself is plainly being serviced.

### The Chuwi logo will sit there for minutes. That is normal.

**Do not power off early.** After you pick the stick, this tablet redraws the
CHUWI splash screen and stays on it for a long time before the loader paints
anything. Owners installing Windows from USB describe exactly the same thing and
put the normal range at **5-10 minutes**:

> *"Включаешь планшет и жмешь F7. Далее выбираем загрузку с флешки. Появится
> логотип Chuwi. Ждем не больше 5-10 минут. Появится установщик Windows 10."*
> — 4PDA post #2719

`Quiet Boot` is `Enabled` out of the box, and the splash stays up until
something replaces it, so a logo on screen tells you nothing about whether the
loader is running. Give it **a full 10 minutes** before concluding anything.
Turning `Quiet Boot` off (`Boot` tab) replaces the logo with POST text and makes
this far less nerve-wracking — it does not make the stick boot any sooner.

Only after 10 minutes of no change is it worth treating as a real hang.

What should happen next: a GRUB menu with the distribution's usual entries.
That means `bootia32.efi` started, found `/boot/grub/grub.cfg` on the stick and
handed over. From here the 32-bit part of the job is done — everything after
this is a 64-bit Linux running through EFI mixed mode.

## If the stick is not in the list at all

In order of likelihood:

1. **`bootia32.efi` is missing from the stick.** Put it back in the computer and
   confirm `EFI/BOOT/bootia32.efi` exists. This is the cause nine times out of
   ten.
2. **Secure Boot is still on.** Check the setting actually saved.
3. **The stick was written with `dd`/Rufus DD mode.** You cannot add files to it
   afterwards; rebuild it. See [02-boot-problem.md](02-boot-problem.md#why-the-stick-cannot-simply-be-dd-ed).
4. **The hub was plugged in after power-on.** Power off completely and retry.
5. **The firmware wants a differently typed partition.** Rebuild the stick from
   Linux or with Rufus (GPT / UEFI non-CSM).
6. **Re-seat the stick.** One owner reports the firmware missing a stick at
   power-on but picking it up immediately after unplugging and replugging it
   (4PDA post #2214). Cheap to try before rebuilding anything.

### The one recipe known to have worked on this exact tablet

A 4PDA owner installed **Ubuntu 20.04** successfully in May 2020 (post #3875)
and described what it took:

> *"Понадобилось bootia32.efi в /efi/boot (оттуда все удалить обязательно и
> оставить только этот файл), пишем флешку через руфус. Установку производим
> автоматом. ОБЯЗАТЕЛЬНО иметь интернет (свисток, юсб модем), без интернета
> будет давать ошибку в конце установки."*

Three things in that are worth taking seriously:

- **`\EFI\BOOT\` contained only `bootia32.efi`** — everything else, including
  `bootx64.efi`, was deleted. Treat this as a thing to try, not a rule:
  - *For it:* Dell published a knowledge-base article, "Systems with 32 bit
    processor will not boot to USB key if both 32 bit and 64 bit images are
    present" (KB 000141299), describing exactly this failure and prescribing a
    key carrying only the 32-bit loader. Dell has since retired the article, and
    its stated mechanism — that the firmware "will not boot past the bootx64.efi
    boot file" — contradicts the UEFI specification, under which IA32 firmware
    looks for `\EFI\BOOT\BOOTIA32.EFI` and never considers the x64 path at all.
  - *Against it:* a Vi8 Plus owner reached the GRUB menu in January 2016 with a
    stock Ubuntu ISO that still had `bootx64.efi` on it, having only *added*
    `bootia32.efi` (techtablets post #23355). On this tablet, both files present
    demonstrably did not prevent booting.

  So the scripts here leave `bootx64.efi` in place. If a stick that looks correct
  will not start, deleting it is a cheap thing to test before rebuilding
  anything.
- **The installer needs a working network connection**, or it fails at the very
  end. This tablet's Wi-Fi does work in a live session, but if you are installing
  somewhere without Wi-Fi, plan for a USB Ethernet adapter on the hub.
- Sound, graphics, brightness, **screen orientation** and the physical buttons
  worked out of the box for them; Wi-Fi and touch did not. That report predates
  the `chipone_icn8505` driver reaching a released Ubuntu kernel, which is why
  [01-hardware.md](01-hardware.md) expects touch to work on anything current —
  but it is the reason to verify touch in the live session rather than assume.

More in [50-troubleshooting.md](50-troubleshooting.md).

## Before you install: check the hardware report

At the live session's desktop or shell, with this repository copied over (or
just cloned again over Wi-Fi):

```sh
sudo ./scripts/collect-hw-report.sh
```

Confirm two lines in the report:

- `product_name` is `D2D3_Vi8A1`
- `fw_platform_size` is `32`

If both hold, everything else in this repo applies to your unit.

## Next

- [30-install-lubuntu.md](30-install-lubuntu.md) (recommended)
- [31-install-debian.md](31-install-debian.md)
- [32-install-arch.md](32-install-arch.md)
