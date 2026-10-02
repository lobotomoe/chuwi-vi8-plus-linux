"""Run the scroll benchmark against any browser that speaks CDP."""

import json
import sys
import time

sys.path.insert(0, "/tmp")
import benchkit
from cdp import Debugger

port = int(sys.argv[1])
label = sys.argv[2]

benchkit.swipe(0.1).join()
time.sleep(3)

page = Debugger(port, match=sys.argv[3] if len(sys.argv) > 3 else "")
tag, height, visible = json.loads(page.evaluate(benchkit.FIND_SCROLLER))
print(f"{label}: <{tag}> {height}px in a {visible}px window")
if height - visible < 200:
    print("nothing to scroll; the rest would be meaningless")
    raise SystemExit(1)

benchkit.score(f"{label} idle",
               page.evaluate(benchkit.record_frames(3000), await_promise=True), False)

thread = benchkit.swipe(7)
measured = page.evaluate(benchkit.record_frames(6000), await_promise=True)
thread.join()
benchkit.score(f"{label} scrolling", measured, True)
