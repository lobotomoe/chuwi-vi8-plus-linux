#!/usr/bin/env python3
"""Inspect a Chuwi Vi8 Plus BIOS image and answer the questions docs/60-bios-firmware.md makes claims about.

Read-only. Never touches a device. Works on macOS and Linux.

Every finding this prints is something the documentation asserts, so it doubles
as a way to re-derive those claims instead of trusting them:

  - which BIOS vendor and SoC generation the image is for
  - the Intel flash descriptor's region map
  - whether the SMBIOS defaults carry the "To be filled by O.E.M." placeholder
  - whether the ICN8505 touchscreen firmware is present
  - the ACPI objects the kernel's quirks depend on (BOSC0200/ROTM, CHPN0001/_SUB)

The last two need the UEFI volumes unpacked. That requires uefi-firmware-parser
with its bundled Tiano decompressor:

    python3 -m venv venv && venv/bin/pip install uefi-firmware
    venv/bin/python scripts/inspect-bios-image.py IMAGE

Without it the descriptor and string checks still run, and the ACPI section says
so rather than reporting a false negative.
"""
from __future__ import annotations

import argparse
import hashlib
import lzma
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

DESCRIPTOR_SIGNATURE = bytes.fromhex("5AA5F00F")
SIGNATURE_OFFSET = 0x10
FLMAP0_OFFSET = 0x14
REGION_NAMES = ["Descriptor", "BIOS", "ME/TXE", "GbE", "PDR"]

# What drivers/platform/x86/touchscreen_dmi.c pins for the Vi8 Plus.
TS_PREFIX = bytes.fromhex("b0070000e4070000")
TS_LENGTH = 35012
TS_SHA256 = "93e549e0b6a2b4b3889634975ea81378729b8b829eb5ca7f125134f4307cfc7c"

PLACEHOLDER = b"To be filled by O.E.M."
ACPI_IDS = [b"BOSC0200", b"ROTM", b"CHPN0001", b"_SUB", b"DSDT"]

# LZMA sections in EFI images use these properties; the 13-byte "alone" header
# is props + 4-byte dictionary size + 8-byte uncompressed size.
LZMA_PROPS = 0x5D
LZMA_HEADER = 13
MIN_STREAM = 4096
MAX_DECLARED = 64 * 1024 * 1024


def rule(title: str) -> None:
    print(f"\n=== {title} ===")


def read_u32(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset:offset + 4], "little")


def count_word(data: bytes, word: bytes) -> int:
    return len(re.findall(rb"\b" + re.escape(word) + rb"\b", data))


def report_identity(blobs: list[Path]) -> None:
    """Runs over the *unpacked* blobs: these strings live inside compressed sections."""
    rule("Identity")
    vendors = {"AMI Aptio": 0, "Insyde H2O": 0}
    cherry = valley = 0
    seen = {b"Hampoo": False, b"Cherry Trail CR": False}

    for path in blobs:
        data = path.read_bytes()
        vendors["AMI Aptio"] += data.count(b"American Megatrends")
        vendors["Insyde H2O"] += data.count(b"InsydeH2O") + data.count(b"Insyde")
        cherry += count_word(data, b"CherryView")
        valley += count_word(data, b"ValleyView")
        for needle in seen:
            seen[needle] = seen[needle] or needle in data

    for vendor, hits in vendors.items():
        if hits:
            print(f"  BIOS vendor    : {vendor} ({hits} string occurrences)")

    print(f"  SoC codename   : CherryView x{cherry}, ValleyView x{valley}")
    if cherry and not valley:
        print("                   -> Cherry Trail. Consistent with a Vi8 Plus.")
    elif valley and not cherry:
        print("                   -> Bay Trail. NOT a Vi8 Plus image.")

    for needle, present in seen.items():
        print(f"  {needle.decode():<15}: {'present' if present else 'absent'}")


def report_descriptor(data: bytes) -> None:
    rule("Intel flash descriptor")
    if data[SIGNATURE_OFFSET:SIGNATURE_OFFSET + 4] != DESCRIPTOR_SIGNATURE:
        print("  no descriptor signature at 0x10 - not a full SPI image")
        return

    flmap0 = read_u32(data, FLMAP0_OFFSET)
    frba = ((flmap0 >> 16) & 0xFF) << 4
    region_count = ((flmap0 >> 24) & 0x7) + 1
    print(f"  FRBA 0x{frba:04x}, {region_count} region entries")

    for index in range(min(region_count, len(REGION_NAMES))):
        value = read_u32(data, frba + 4 * index)
        base = (value & 0x1FFF) << 12
        limit = (((value >> 16) & 0x1FFF) << 12) | 0xFFF
        name = REGION_NAMES[index]
        if limit < base:
            print(f"  {name:<11}: unused")
        else:
            size_kib = (limit - base + 1) // 1024
            print(f"  {name:<11}: 0x{base:06x}-0x{limit:06x}  {size_kib} KiB")


def report_smbios(blobs: list[Path]) -> None:
    """Also unpacked-only: the SMBIOS defaults sit in a compressed FFS section."""
    rule("SMBIOS defaults")
    hits = sum(path.read_bytes().count(PLACEHOLDER) for path in blobs)
    if hits:
        print(f"  {PLACEHOLDER.decode()!r} appears {hits} time(s)")
        print("  -> the placeholder is baked into the firmware; flashing it")
        print("     will not give the kernel the strings its quirks match on")
    else:
        print(f"  {PLACEHOLDER.decode()!r} not found")


def lzma_streams(data: bytes):
    """Yield every decompressible LZMA stream in the image."""
    start = 0
    while True:
        offset = data.find(bytes([LZMA_PROPS]), start)
        if offset < 0 or offset + LZMA_HEADER > len(data):
            return
        start = offset + 1
        declared = int.from_bytes(data[offset + 5:offset + LZMA_HEADER], "little")
        if not 0 < declared < MAX_DECLARED:
            continue
        try:
            blob = lzma.LZMADecompressor(format=lzma.FORMAT_ALONE).decompress(
                data[offset:], declared + 1
            )
        except (lzma.LZMAError, EOFError, MemoryError):
            continue
        if len(blob) >= MIN_STREAM:
            yield offset, blob


def unpack(image: Path, workdir: Path) -> list[Path]:
    """Every byte range worth searching: the image, its UEFI volumes, its LZMA streams."""
    blobs = [image]

    parser = shutil.which("uefi-firmware-parser")
    if parser is None and Path(sys.executable).parent.joinpath("uefi-firmware-parser").exists():
        parser = str(Path(sys.executable).parent / "uefi-firmware-parser")
    if parser:
        out = workdir / "uefi"
        out.mkdir()
        subprocess.run(
            [parser, "-e", "-O", str(out), str(image)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
        )
        blobs += [p for p in out.rglob("*") if p.is_file()]
    else:
        print("  note: uefi-firmware-parser not found; UEFI volumes not unpacked")

    data = image.read_bytes()
    lzma_dir = workdir / "lzma"
    lzma_dir.mkdir()
    for offset, blob in lzma_streams(data):
        path = lzma_dir / f"{offset:08x}.bin"
        path.write_bytes(blob)
        blobs.append(path)

    return blobs


def report_touchscreen_fw(blobs: list[Path]) -> None:
    rule("ICN8505 touchscreen firmware")
    found = False
    for path in blobs:
        data = path.read_bytes()
        offset = data.find(TS_PREFIX)
        while offset >= 0:
            found = True
            blob = data[offset:offset + TS_LENGTH]
            digest = hashlib.sha256(blob).hexdigest()
            print(f"  FOUND in {path.name} at 0x{offset:x}, {len(blob)} bytes available")
            print(f"    sha256 {digest}")
            print(f"    matches the kernel's pinned hash: {digest == TS_SHA256}")
            offset = data.find(TS_PREFIX, offset + 1)
    if not found:
        print(f"  absent - prefix {TS_PREFIX.hex()} not found in {len(blobs)} extracted blobs")
        print("  (a driver storing it compressed inside its own data section would")
        print("   not be found by this; nothing else would hide it)")


def report_acpi(blobs: list[Path]) -> None:
    rule("ACPI objects the kernel quirks rely on")
    carrier = None
    for path in blobs:
        data = path.read_bytes()
        if b"DSDT" in data and b"BOSC0200" in data:
            carrier = (path, data)
            break

    if carrier is None:
        print("  no DSDT carrying BOSC0200 was recovered")
        print("  -> this is inconclusive, not a negative result, unless the")
        print("     extraction above produced a DSDT at all")
        return

    path, data = carrier
    print(f"  DSDT found in {path.name}")
    for identifier in ACPI_IDS:
        offsets = [m.start() for m in re.finditer(re.escape(identifier), data)]
        shown = ", ".join(str(o) for o in offsets[:4]) or "-"
        print(f"    {identifier.decode():<10} x{len(offsets):<3} at {shown}")

    rotm = data.find(b"ROTM")
    if rotm >= 0:
        window = data[rotm:rotm + 80]
        matrix = re.findall(rb"-?[01] -?[01] -?[01]", window)
        if matrix:
            print(f"    mount matrix: {b' / '.join(matrix).decode()}")

    # The touchscreen's _SUB, not the first _SUB in the table - a DSDT has many,
    # and taking the wrong one names the wrong firmware file.
    hid = data.find(b"CHPN0001")
    if hid >= 0:
        scope = data[hid:hid + 128]
        sub = scope.find(b"_SUB")
        name = re.search(rb"HAMP[0-9]{4}", scope[sub:]) if sub >= 0 else None
        if name:
            value = name.group().decode()
            print(f"    CHPN0001 _SUB -> {value}")
            print(f"    kernel will request chipone/icn8505-{value}.fw")
        else:
            print("    CHPN0001 found but no HAMP _SUB within its scope")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("image", type=Path, help="BIOS image (full SPI dump or BIOS region)")
    parser.add_argument("--keep", type=Path, help="keep the unpacked blobs in this directory")
    args = parser.parse_args()

    if not args.image.is_file():
        print(f"error: no such file: {args.image}", file=sys.stderr)
        return 1

    data = args.image.read_bytes()
    print(f"{args.image}  {len(data)} bytes")
    print(f"sha256 {hashlib.sha256(data).hexdigest()}")

    report_descriptor(data)

    def run(workdir: Path) -> None:
        blobs = unpack(args.image, workdir)
        print(f"\n({len(blobs)} blobs to search, including the image itself)")
        report_identity(blobs)
        report_smbios(blobs)
        report_touchscreen_fw(blobs)
        report_acpi(blobs)

    if args.keep:
        args.keep.mkdir(parents=True, exist_ok=True)
        run(args.keep)
    else:
        with tempfile.TemporaryDirectory() as tmp:
            run(Path(tmp))

    return 0


if __name__ == "__main__":
    sys.exit(main())
