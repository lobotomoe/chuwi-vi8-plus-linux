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

If Esc does nothing, on Chuwi tablets the volume rocker is the other route:
hold **Volume +** (or **Volume -**, they differ by model) while pressing power,
and keep holding until a menu appears. The volume keys navigate and power
selects.

This tablet's exact key was not verified for this guide — reports for Chuwi
Cherry Trail tablets cover Esc, Del, F7, Volume + and Volume -. Use the Windows
route above if you can; it removes the guesswork entirely.

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
came for. Change Secure Boot and nothing else. `F3` (Optimized Defaults) undoes
an accident.

## What to change

**1. Secure Boot -> Disabled.** This is not optional: no distribution publishes
a Microsoft-signed 32-bit x86 shim, so with Secure Boot on, nothing you build
will start. See [02-boot-problem.md](02-boot-problem.md#secure-boot).

If it appears but is greyed out, that is the AMI Aptio behaviour where the
setting is locked until a supervisor password exists:

1. `Security` -> `Administrator Password` -> set one
2. `Secure Boot` -> `Disabled`
3. `Security` -> `Administrator Password` -> enter the current one, leave the new
   one **empty** — this clears it again

Do not skip step 3. The only input this tablet has is a USB keyboard on the OTG
hub, and a tablet has no CMOS jumper or coin cell to clear a forgotten password
with. Treat the password as a temporary key, write it down while it is set, and
remove it as soon as Secure Boot is off.

**2. Boot order — nothing to do.** The shipped order already puts USB first:

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
