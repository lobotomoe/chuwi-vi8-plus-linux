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

## What to change

The firmware is an InsydeH2O/AMI tablet build. Menu names vary slightly between
BIOS versions; the settings you want are:

**1. Secure Boot -> Disabled.** Usually under `Security`, sometimes
`Boot -> Secure Boot Option`. This is not optional: no distribution publishes a
Microsoft-signed 32-bit x86 shim, so with Secure Boot on, nothing you build will
start. See [02-boot-problem.md](02-boot-problem.md#secure-boot).

**2. Boot order.** Put USB ahead of the internal eMMC, or plan on using the
one-off boot menu (`Boot Manager` in the setup, or F7/F12 at power-on) each
time.

**3. Optional: CPU C-states.** Under `Power -> Advanced CPU Control`, setting
C-States to `C1` is a long-standing workaround for random freezes on Chuwi's
Atom tablets. It costs battery life, so leave it alone unless you actually see
freezes — and if you do, see
[50-troubleshooting.md](50-troubleshooting.md#random-freezes).

Save with **F10** and let it reboot.

## Booting the stick

From the setup menu choose `Boot Manager` (or `Save & Exit -> Boot Override`)
and pick the USB device. It usually appears under its own product name rather
than as "UEFI: USB".

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
