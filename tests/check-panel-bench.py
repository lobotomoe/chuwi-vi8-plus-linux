#!/usr/bin/env python3
"""Check the parts of scripts/panel-bench that can be checked without a tablet.

Two things. Every module compiles, which catches the usual editing damage. And
`touchdevice.py` builds the right ioctl request: that number is assembled by
hand, because Python has no kernel header to read it from, and a wrong one fails
by quietly matching no device at all - indistinguishable from a machine with no
touchscreen. 0x80084523 is EVIOCGBIT(EV_ABS, 8) on Linux.

The rest of the kit only means anything against a running browser and a real
panel, so it is not tested here.
"""
import importlib.util
import pathlib
import sys

BENCH = pathlib.Path(__file__).resolve().parent.parent / "scripts" / "panel-bench"
EXPECTED_EVIOCGBIT_ABS = 0x80084523


def load(name):
    spec = importlib.util.spec_from_file_location(name, BENCH / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    failures = []

    for script in sorted(BENCH.glob("*.py")):
        # compile() rather than py_compile, which insists on writing a .pyc
        # somewhere; nothing here needs a build artifact left behind.
        try:
            compile(script.read_text(), str(script), "exec")
        except SyntaxError as error:
            failures.append("%s does not compile: %s" % (script.name, error))

    touchdevice = load("touchdevice")
    actual = touchdevice._eviocgbit(touchdevice.EV_ABS, 8)
    if actual != EXPECTED_EVIOCGBIT_ABS:
        failures.append(
            "EVIOCGBIT(EV_ABS, 8) came out as 0x%08x, expected 0x%08x"
            % (actual, EXPECTED_EVIOCGBIT_ABS)
        )
    if touchdevice.ABS_MT_POSITION_X != 0x35:
        failures.append("ABS_MT_POSITION_X is not 0x35")

    for failure in failures:
        print(failure)
    print("%d python files checked, %d problems" % (
        len(list(BENCH.glob("*.py"))), len(failures)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
