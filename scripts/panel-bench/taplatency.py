"""How long Home Assistant takes to answer a tap on a card.

Scroll smoothness is only half of "reactive"; the other half is the wait after
touching a tile. Earlier work put that at 0.6-1.0 s of saturated main thread
and concluded no browser pref can move it, so it is worth a number.

What is measured is Home Assistant's own response, which is the part that
dominates: the input path adds a fixed 28 ms that no software can remove.

Two earlier approaches failed and are recorded so they are not retried. Tapping
by screen coordinate opened nothing - the panel is rotated 180 degrees and the
cards live in shadow DOM. Calling .click() on the tile opened nothing either:
Home Assistant does not listen for clicks, it runs its own action-handler over
pointerdown and pointerup. So the dialog is asked for the way the card itself
asks for it, with a hass-more-info event.
"""

import json
import statistics
import subprocess
import sys
import time

sys.path.insert(0, "/tmp")
from marionette import Marionette

DEEP = """
function deepFind(test, root, found) {
    found = found || [];
    root = root || document;
    for (const node of root.querySelectorAll('*')) {
        if (test(node)) found.push(node);
        if (node.shadowRoot) deepFind(test, node.shadowRoot, found);
    }
    return found;
}
function openDialog() {
    return deepFind(n => /MORE-INFO|DIALOG/.test(n.tagName) && n.offsetHeight > 80)[0];
}
"""

SURVEY = DEEP + """
const tiles = deepFind(n => /^(HUI-TILE-CARD|HA-TILE-CARD|HUI-[A-Z-]*ENTITY-ROW)$/.test(n.tagName));
return JSON.stringify({
    tiles: tiles.length,
    withEntity: tiles.filter(n => (n._config || n.config || {}).entity).length,
    dialogAlready: !!openDialog(),
    nodes: deepFind(() => true).length,
});
"""

CLICK_AND_WAIT = DEEP + """
const done = arguments[arguments.length - 1];
const tiles = deepFind(n => /^(HUI-TILE-CARD|HA-TILE-CARD|HUI-[A-Z-]*ENTITY-ROW)$/.test(n.tagName));
const withEntity = tiles.filter(n => (n._config || n.config || {}).entity);
const tile = withEntity[arguments[0] % Math.max(withEntity.length, 1)];
if (!tile) { done({opened: -2}); } else {
    const entityId = (tile._config || tile.config).entity;
    const started = performance.now();
    const intervals = [];
    let previous = null;
    // The card does not handle a click; it raises this, and so do we.
    document.querySelector('home-assistant').dispatchEvent(new CustomEvent(
        'hass-more-info', {detail: {entityId: entityId}, bubbles: true, composed: true}));
    function look(now) {
        if (previous !== null) intervals.push(now - previous);
        previous = now;
        if (openDialog()) { done({opened: performance.now() - started, intervals: intervals,
                                  tag: tile.tagName.toLowerCase()}); return; }
        if (now - started > 8000) { done({opened: -1, intervals: intervals,
                                          tag: entityId}); return; }
        requestAnimationFrame(look);
    }
    requestAnimationFrame(look);
}
"""

CLOSE = DEEP + """
const dialog = deepFind(n => /MORE-INFO|DIALOG/.test(n.tagName) && n.close)[0];
if (dialog) dialog.close();
return !!dialog;
"""


def main():
    label = sys.argv[1] if len(sys.argv) > 1 else "tap"
    subprocess.run(["python3", "/tmp/swipe.py", "0.1"], stdout=subprocess.DEVNULL)
    time.sleep(3)

    client = Marionette()
    try:
        survey = json.loads(client.script(SURVEY))
        print(f"{label}: {survey['tiles']} tiles ({survey['withEntity']} with an entity), "
              f"{survey['nodes']} DOM nodes, dialog already open: {survey['dialogAlready']}")
        if not survey["tiles"]:
            print("no tiles found even through shadow DOM; cannot measure")
            return

        delays = []
        for attempt in range(4):
            measured = client.script(CLICK_AND_WAIT, asynchronous=True, args=[attempt])
            if measured["opened"] < 0:
                print(f"  {attempt + 1}: <{measured.get('tag')}> opened nothing in 8 s")
            else:
                worst = max(measured["intervals"]) if measured["intervals"] else 0
                delays.append(measured["opened"])
                print(f"  {attempt + 1}: <{measured['tag']}> dialog after "
                      f"{measured['opened']:6.0f} ms, worst frame while opening {worst:5.0f} ms")
            client.script(CLOSE)
            time.sleep(2.5)

        if delays:
            print(f"{label}: median tap-to-dialog {statistics.median(delays):.0f} ms "
                  f"over {len(delays)} opens")
    finally:
        client.close()


if __name__ == "__main__":
    main()
