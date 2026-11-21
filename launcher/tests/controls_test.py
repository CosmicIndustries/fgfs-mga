#!/usr/bin/env python3
"""Walks the whole `fgfs-mga controls wizard` with two fake Saitek sticks.

The fake sticks change their axis values when the wizard asks for a move, so the
wizard's real code paths (calibration, centre, axis picking, levers, buttons,
saving progress, resuming, writing XML) all run. Usage: python3 tests/controls_test.py
"""
import json
import os
import sys
import tempfile
import xml.etree.ElementTree as ET
from importlib.machinery import SourceFileLoader

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOMEDIR = tempfile.mkdtemp()
os.environ["HOME"] = HOMEDIR
os.environ["FG_HOME"] = os.path.join(HOMEDIR, ".fgfs")
m = SourceFileLoader("ctl", os.path.join(ROOT, "src", "fgfs-mga-controls")).load_module()

FAILS = []


def check(cond, what):
    print(("PASS  " if cond else "FAIL  ") + what)
    if not cond:
        FAILS.append(what)


class AI:
    def __init__(self, lo, hi, v):
        self.min, self.max, self.value = lo, hi, v


class Ev:
    def __init__(self, t, c, v):
        self.type, self.code, self.value = t, c, v


class Info:
    def __init__(self, product):
        self.vendor, self.product = 0x06A3, product


class Dev:
    """Fake evdev.InputDevice: axes in raw units, a queue of pending events."""

    def __init__(self, path, name, product, axes, keys):
        self.path, self.name, self.info = path, name, Info(product)
        self.ab = {c: AI(lo, hi, v) for c, (lo, hi, v) in axes.items()}
        self.keys, self.queue = keys, []

    def capabilities(self, absinfo=False):
        return {3: [(c, a) if absinfo else c for c, a in self.ab.items()], 1: list(self.keys)}

    def absinfo(self, c):
        return self.ab[c]

    def set(self, c, v):
        self.ab[c].value = v
        self.queue.append(Ev(3, c, v))

    def read_one(self):
        return self.queue.pop(0) if self.queue else None

    def read(self):
        q, self.queue = self.queue, []
        return q

    def fileno(self):
        return 99


evo = Dev("/dev/input/event11", "Saitek Cyborg Evo Force", 0xFFB5,
          {0: (0, 4096, 2056), 1: (0, 4096, 2044), 6: (0, 255, 125), 7: (0, 255, 0), 16: (-1, 1, 0), 17: (-1, 1, 0)},
          list(range(0x120, 0x12C)) + [0x12F])
gold = Dev("/dev/input/event12", "SAITEK CYBORG 3D USB", 0x0006,
           {0: (0, 255, 93), 1: (0, 255, 93), 5: (0, 255, 94), 6: (0, 255, 118), 16: (-1, 1, 0), 17: (-1, 1, 0)},
           list(range(0x120, 0x12C)) + [300, 301])
DEVS = [evo, gold]
m.find_devices = lambda all_sticks=False: list(DEVS)


def centre_all():
    for c, v in ((0, 2048), (1, 2048), (7, 128)):
        evo.set(c, v)
    for c, v in ((0, 93), (1, 93), (5, 94)):
        gold.set(c, v)
    evo.queue.clear()
    gold.queue.clear()


def fake_calibrate(devs):
    """Run the real calibrate(): the sticks swing end to end, then Enter."""
    class Stdin:
        def readline(self):
            return "\n"
    swings = [(evo, 0, 0), (evo, 0, 4096), (evo, 1, 0), (evo, 1, 4096), (evo, 6, 3), (evo, 6, 250),
              (evo, 7, 40), (evo, 7, 215), (gold, 0, 0), (gold, 0, 186), (gold, 1, 0), (gold, 1, 186),
              (gold, 5, 10), (gold, 5, 180), (gold, 6, 0), (gold, 6, 255)]
    stdin = Stdin()
    calls = {"n": 0}
    real_select, real_stdin = m.select.select, m.sys.stdin

    def sel(r, w, x, t):
        calls["n"] += 1
        if calls["n"] == 1:
            for d, c, v in swings:
                d.set(c, v)
            return ([evo, gold], [], [])
        return ([stdin], [], [])
    m.select.select, m.sys.stdin = sel, stdin
    try:
        return real_calibrate(devs)
    finally:
        m.select.select, m.sys.stdin = real_select, real_stdin
        centre_all()


real_calibrate = m.calibrate
m.calibrate = fake_calibrate

# What the person does at each prompt (matched on the prompt text), and what they type.
ACTIONS = [
    ("let go of everything", lambda: centre_all(), ""),
    ("ROLL", lambda: evo.set(0, 4000), ""),
    ("PITCH", lambda: (centre_all(), evo.set(1, 80)), ""),
    ("RUDDER", lambda: (centre_all(), evo.set(7, 160)), ""),     # small twist (the one that needed two tries)
    ("THROTTLE: set it to IDLE", lambda: (centre_all(), evo.set(6, 250)), ""),
    ("now move it to FULL power", lambda: evo.set(6, 3), ""),
    ("MIXTURE", lambda: gold.set(6, 0), ""),
    ("now move it to FULL RICH", lambda: gold.set(6, 255), ""),
    ("PROPELLER", None, "s"),
    ("glance", None, ""),
]
script = list(ACTIONS)


def fake_ask(prompt):
    for i, (needle, act, typed) in enumerate(script):
        if needle.lower() in prompt.lower():
            script.pop(i)
            if act:
                act()
            return typed
    raise AssertionError("unexpected prompt: " + prompt)


m.ask = fake_ask
BUTTON_PRESSES = [(evo.path, 0x121), (evo.path, 0x120), (evo.path, 0x124), (evo.path, 0x123),
                  (evo.path, 0x126), (evo.path, 0x127), None, (gold.path, 300), (gold.path, 0x120), None]
presses = list(BUTTON_PRESSES)
m.wait_button = lambda devs, used, timeout=20: presses.pop(0)

# ---- run 1: stop at the throttle step (q), like the crash happened there ----
centre_all()
script.insert(4, ("THROTTLE: set it to IDLE", None, "q"))
rc = m.cmd_wizard([])
check(rc == 1, "wizard stops on q")
part = json.load(open(m.PARTIAL))
check(part["axes_done"] == ["aileron", "elevator", "rudder"], "progress saved after roll, pitch, rudder")
check(part["mapping"]["axes"]["rudder"]["code"] == 7, "small twist picked as rudder (ABS_RUDDER)")

# ---- run 2: resumes at the throttle, no calibration, no roll/pitch/rudder ----
m.calibrate = lambda devs: (_ for _ in ()).throw(AssertionError("calibration asked again"))
script[:] = [("Picking up where you stopped", None, "")] + ACTIONS[4:]
rc = m.cmd_wizard([])
check(rc == 0, "resumed wizard finishes")
check(not script, "every remaining step was asked once")
check(not os.path.exists(m.PARTIAL), "progress file removed when done")
mp = json.load(open(m.MAP_FILE))
ax = mp["axes"]
check(ax["aileron"]["dir"] == 1 and ax["elevator"]["dir"] == -1, "roll right +, forward = nose down")
check(ax["throttle"]["dir"] == -1 and ax["throttle"]["dev"].endswith("Evo Force"), "throttle on Evo, reversed")
check(ax["mixture"]["dev"].endswith("3D USB") and ax["mixture"]["dir"] == 1, "mixture on the Cyborg 3D")
check("propeller" not in ax, "propeller skipped")
check(all(ax[f]["cal"] for f in ("aileron", "elevator", "rudder", "throttle", "mixture")), "all axes calibrated")
check(mp["buttons"]["brakes"]["code"] == 0x121 and mp["buttons"]["ptt"]["code"] == 0x120, "buttons recorded")
check("parking_brake" not in mp["buttons"], "free button left free")
evo_xml = open(os.path.join(m.OUT_DIR, "fgfs-mga-Saitek-Cyborg-Evo-Force.xml")).read()
gold_xml = open(os.path.join(m.OUT_DIR, "fgfs-mga-SAITEK-CYBORG-3D-USB.xml")).read()
for name, x in (("Evo", evo_xml), ("3D USB", gold_xml)):
    try:
        ET.fromstring(x.split("?>", 1)[1])
        check(True, name + " XML parses")
    except ET.ParseError:
        check(False, name + " XML parses")
check("<name>abs-rudder</name>" in evo_xml and "<interpolater>" in evo_xml, "Evo rudder with calibration")
check("<name>button-thumb</name>" in evo_xml and "applyBrakes" in evo_xml, "brakes on button-thumb")
check("<name>button-300</name>" in gold_xml and "view.stepView" in gold_xml, "unnamed key 300 used as FlightGear names it")
check("abs-hat0-x" in evo_xml, "hat glance on the Evo")

# ---- the numbers FlightGear will see, off-centre 3D USB stick included ----
a = ax["aileron"]
check(abs(m.fg_value("aileron", a, 2048 / 4096)) < 0.01, "Evo centred -> aileron 0")
check(m.fg_value("aileron", a, 1.0) == 1.0, "Evo full right -> aileron +1")
g = {"dev": "x", "code": 0, "dir": 1, "cal": [0.0, 93 / 255, 186 / 255]}
check(abs(m.fg_value("aileron", g, 93 / 255)) < 0.01, "3D USB resting at 93/255 -> 0, not a pull to one side")
t = ax["throttle"]
check(abs(m.fg_value("throttle", t, 3 / 255) - 1) < 1e-3 and abs(m.fg_value("throttle", t, 250 / 255)) < 1e-3, "throttle ends -> 1 and 0")

# ---- resume ignored when the sticks changed ----
m.save_partial({evo.path: evo, gold.path: gold}, {"lo": {}, "hi": {}, "centre": {}, "mapping":
               {"axes": {"aileron": {"dev": "06a3:9999 Other", "code": 0, "dir": 1}}, "buttons": {}, "hat": {}},
               "axes_done": ["aileron"], "buttons_done": []})
check(m.load_partial(DEVS) is None, "saved progress for other sticks is ignored")

# ---- response shaping: dead zone, curve, sensitivity, limit, offset ----
d = m.shape_default("aileron")
check(m.apply_shape("aileron", 0.0, d) == 0.0 and abs(m.apply_shape("aileron", 1.0, d) - 1) < 1e-9, "default shape leaves 0 and 1 alone")
s = dict(d, deadzone=0.1)
check(m.apply_shape("aileron", 0.05, s) == 0.0 and m.apply_shape("aileron", -0.08, s) == 0.0, "dead zone swallows small moves")
check(abs(m.apply_shape("aileron", 1.0, s) - 1) < 1e-9, "dead zone still reaches full travel")
s = dict(d, expo=0.6)
check(abs(m.apply_shape("aileron", 0.5, s)) < 0.5 and abs(m.apply_shape("aileron", 1.0, s) - 1) < 1e-9, "curve softens the middle, keeps the ends")
check(abs(m.apply_shape("aileron", -0.5, s) + m.apply_shape("aileron", 0.5, s)) < 1e-9, "curve is symmetric")
s = dict(d, limit=0.7)
check(abs(m.apply_shape("aileron", 1.0, s) - 0.7) < 1e-9, "limit caps the output")
s = dict(d, sensitivity=2.0)
check(m.apply_shape("aileron", 0.8, s) == 1.0, "sensitivity above 1 still clamps at +1")
s = dict(d, offset=0.1)
check(abs(m.apply_shape("aileron", 0.0, s) - 0.1) < 1e-9, "offset moves the centre (trim)")
t = m.shape_default("throttle")
check(abs(m.apply_shape("throttle", 0.0, dict(t, offset=0))) < 1e-9 and m.apply_shape("throttle", 1.0, t) == 1.0, "lever 0..1 kept")

# ---- per-aircraft presets ----
mp2 = json.loads(json.dumps(mp))
mp2["shapes"] = {"default": {"aileron": {"expo": 0.3}}, "c172p": {"aileron": {"expo": 0.7, "deadzone": 0.05}}}
check(m.get_shape(mp2, "aileron")["expo"] == 0.3, "default preset used for other aircraft")
g2 = m.get_shape(mp2, "aileron", "c172p")
check(g2["expo"] == 0.7 and g2["deadzone"] == 0.05, "aircraft preset wins for that aircraft")
check(m.get_shape(mp2, "elevator", "c172p") == m.shape_default("elevator"), "untouched job keeps the defaults")

# ---- GUI session: binding any job, response edits, problems ----
centre_all()
ses = m.Session(DEVS, json.loads(json.dumps(mp)))
ses.start_capture("brake_left_axis")
gold.set(5, 180)
ses.poll = None
for ev in gold.read():
    ses.handle(gold, ev)
check(ses.mapping["axes"].get("brake_left_axis", {}).get("code") == 5, "GUI binds a brake lever to the twist")
ses.start_capture("parking_brake")
evo.queue.append(Ev(1, 0x125, 1))
for ev in evo.read():
    ses.handle(evo, ev)
check(ses.mapping["buttons"]["parking_brake"]["code"] == 0x125, "GUI binds a button job")
ses.start_capture("ptt")   # ptt already on 0x120; press 0x125 -> parking brake lets go
evo.queue.append(Ev(1, 0x125, 1))
for ev in evo.read():
    ses.handle(evo, ev)
check("parking_brake" not in ses.mapping["buttons"] and ses.mapping["buttons"]["ptt"]["code"] == 0x125, "one button, one job")
ses.set_aircraft("c172p")
ses.set_shape("aileron", "expo", 0.5)
ses.set_shape("aileron", "deadzone", 9)   # out of range -> clamped
check(ses.mapping["shapes"]["c172p"]["aileron"]["expo"] == 0.5, "response edit saved for that aircraft only")
check(ses.mapping["shapes"]["c172p"]["aileron"]["deadzone"] == m.SHAPE_RANGE["deadzone"][1], "slider value clamped")
check("aileron" not in ses.mapping["shapes"].get("default", {}), "all-aircraft settings untouched")
pts = ses.curve("aileron")
check(pts[0][0] == -1 and pts[-1][0] == 1 and len(pts) == 41, "curve preview spans the stick")
ses.set_aircraft(None)
ses.clear("rudder")
check(any("isn't bound" in p for p in ses.problems()), "unbound rudder reported")

# ---- the XML carries the shaping Nasal ----
rc = m.write_all(DEVS, ses.mapping, False)
evo_xml = open(os.path.join(m.OUT_DIR, "fgfs-mga-Saitek-Cyborg-Evo-Force.xml")).read()
check(rc == 0 and "<open><![CDATA[" in evo_xml and "maketimer(0" in evo_xml, "Evo XML has the per-frame shaping loop")
check('"c172p"' in evo_xml, "aircraft preset written into the XML")
check(m.RAW in evo_xml, "axes feed the raw values the loop shapes")

# ---- before-flight check ----
m.save_map = getattr(m, "save_map", None)
check(m.cmd_check([]) == 3, "check warns when a core job is free")
real_find = m.find_devices
m.find_devices = lambda all_sticks=False: [evo]
gm = json.load(open(m.MAP_FILE))
gm["axes"]["rudder"] = {"dev": m.dev_key(evo), "code": 7, "dir": 1, "cal": [0, 0.5, 1]}
json.dump(gm, open(m.MAP_FILE, "w"))
import io, contextlib
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rc = m.cmd_check([])
check(rc == 3 and "isn't plugged in" in buf.getvalue(), "check spots an unplugged stick")
m.find_devices = real_find
sysin = os.path.join(HOMEDIR, "sys-class-input")
for n in ("event11", "event12", "event17"):
    os.makedirs(os.path.join(sysin, n, "device"), exist_ok=True)
os.makedirs(os.path.join(sysin, "event16"), exist_ok=True)       # a dead copy: its USB device is gone
m.SYS_INPUT = sysin
check(m.stick_health([evo, gold]) == [], "healthy sticks give no stick warning")
ghost = Dev("/dev/input/event16", "Saitek Cyborg Evo Force", 0xFFB5,
            {0: (0, 4096, 0), 1: (0, 4096, 0), 6: (0, 255, 0)}, list(range(0x120, 0x12C)))
check(m.is_dead_copy(ghost.path) and not m.is_dead_copy(evo.path), "a node without a USB device counts as a dead copy")
check(m.stick_health([ghost, evo]) == [], "dead copies beside a working stick give no warning")
stuck = Dev("/dev/input/event17", "Saitek Cyborg Evo Force", 0xFFB5,
            {0: (0, 4096, 0), 1: (0, 4096, 0), 6: (0, 255, 0)}, list(range(0x120, 0x12C)))
w = m.stick_health([stuck])
check(any("isn't sending any movement" in x for x in w), "check spots a plugged-in stick whose X and Y never moved")
check(m.stick_health([gold]) == [], "the other stick alone is fine")

print("\n%d failed" % len(FAILS))
sys.exit(1 if FAILS else 0)
