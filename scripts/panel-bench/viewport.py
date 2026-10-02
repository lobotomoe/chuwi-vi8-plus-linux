"""Does the kiosk still own the whole panel once Marionette is enabled?

A permanently enabled remote-control port is only acceptable on a wall display
if nothing about the display changes. Firefox shows an infobar for some remote
sessions, and an infobar would eat the top of the dashboard. Compare the page's
viewport against the screen instead of guessing: 800x1280 means nothing was
taken away.
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from marionette import Marionette

screen = subprocess.run(
    ["xdpyinfo"], capture_output=True, text=True
).stdout
dimensions = [line.split()[1] for line in screen.splitlines() if "dimensions:" in line]

# A short timeout, because this runs on a machine whose only shell is a shared
# terminal: a client that blocks forever there wedges the channel itself.
client = Marionette(timeout=15)
try:
    size = client.script(
        "return [window.innerWidth, window.innerHeight,"
        " window.outerHeight, navigator.webdriver, document.title];"
    )
finally:
    client.close()

print("screen          :", dimensions[0] if dimensions else "unknown")
print("page viewport   : %sx%s" % (size[0], size[1]))
print("window outer h  :", size[2])
print("navigator.webdriver:", size[3])
print("title           :", size[4])
