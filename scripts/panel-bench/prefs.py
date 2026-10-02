"""Read Firefox's live prefs and platform state through Marionette's chrome context.

Reading the real value beats reading a blog post about the default: several of
these differ by build and by platform.
"""

import sys

sys.path.insert(0, "/tmp")
from marionette import Marionette

READ = """
const names = arguments[0];
const out = {};
for (const name of names) {
    try {
        switch (Services.prefs.getPrefType(name)) {
            case Services.prefs.PREF_BOOL:   out[name] = String(Services.prefs.getBoolPref(name)); break;
            case Services.prefs.PREF_INT:    out[name] = String(Services.prefs.getIntPref(name)); break;
            case Services.prefs.PREF_STRING: out[name] = Services.prefs.getCharPref(name); break;
            default: out[name] = "(unset)";
        }
        if (out[name] !== "(unset)" && Services.prefs.prefHasUserValue(name))
            out[name] += "  [user set]";
    } catch (error) { out[name] = "(error) " + error; }
}
return out;
"""

STATE = """
const gfx = Cc["@mozilla.org/gfx/info;1"].getService(Ci.nsIGfxInfo);
return {
    accessibility: String(Services.appinfo.accessibilityEnabled),
    compositor: gfx.getFeatureStatusStr ? gfx.getFeatureStatusStr(Ci.nsIGfxInfo.FEATURE_WEBRENDER)
                                        : "unknown",
    webgl: gfx.getFeatureStatusStr ? gfx.getFeatureStatusStr(Ci.nsIGfxInfo.FEATURE_WEBGL_OPENGL)
                                   : "unknown",
    processes: String(Services.ppmm.childCount),
    memory: String(Services.appinfo.OS),
};
"""

NAMES = [
    "dom.w3c_touch_events.enabled",
    "apz.content_response_timeout",
    "apz.touch_start_tolerance",
    "apz.x_skate_size_multiplier",
    "apz.y_skate_size_multiplier",
    "apz.x_stationary_size_multiplier",
    "apz.y_stationary_size_multiplier",
    "apz.paint_skipping.enabled",
    "apz.frame_delay.enabled",
    "layout.frame_rate",
    "gfx.webrender.all",
    "gfx.webrender.software",
    "gfx.canvas.accelerated",
    "network.process.enabled",
    "media.rdd-process.enabled",
    "media.utility-process.enabled",
    "browser.sessionstore.interval",
    "browser.cache.disk.enable",
    "accessibility.force_disabled",
    "image.mem.shared.unmap.min_expiration_ms",
    "javascript.options.baselinejit",
    "javascript.options.ion",
]

client = Marionette()
try:
    client.command("Marionette:SetContext", {"value": "chrome"})
    for name, value in client.script(READ, args=[NAMES]).items():
        print(f"{name:46} {value}")
    print("--- platform ---")
    for name, value in client.script(STATE).items():
        print(f"{name:46} {value}")
finally:
    client.close()
