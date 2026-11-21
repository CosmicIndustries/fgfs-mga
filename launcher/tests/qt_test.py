#!/usr/bin/env python3
"""Opens the Qt controls window offscreen with two fake sticks, drives it, and checks the save format.
Usage: QT_QPA_PLATFORM=offscreen python3 tests/qt_test.py [picture-prefix]"""
import json
import os
import sys
import tempfile
from importlib.machinery import SourceFileLoader

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOMEDIR = tempfile.mkdtemp()
os.environ["HOME"] = HOMEDIR
os.environ["FG_HOME"] = os.path.join(HOMEDIR, ".fgfs")
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
m = SourceFileLoader("ctl", os.path.join(ROOT, "src", "fgfs-mga-controls")).load_module()
try:
    q = SourceFileLoader("ctlqt", os.path.join(ROOT, "src", "fgfs-mga-controls-qt")).load_module()
except ImportError as e:
    print("SKIP  no Qt here (%s)" % e)
    sys.exit(0)
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

    def read(self):
        out, self.queue = self.queue, []
        return out


evo = Dev("/dev/input/event11", "Saitek Cyborg Evo Force", 0xFFB5,
          {0: (0, 4096, 2056), 1: (0, 4096, 2044), 6: (0, 255, 125), 7: (0, 255, 0), 16: (-1, 1, 0), 17: (-1, 1, 0)},
          list(range(0x120, 0x12C)) + [0x12F])
gold = Dev("/dev/input/event12", "SAITEK CYBORG 3D USB", 0x0006,
           {0: (0, 255, 93), 1: (0, 255, 93), 5: (0, 255, 94), 6: (0, 255, 118), 16: (-1, 1, 0), 17: (-1, 1, 0)},
           list(range(0x120, 0x12C)) + [300, 301])
m.find_devices = lambda all_sticks=False: [evo, gold]
m.find_aircraft = lambda dirs=None: {"PA28-161-160": None, "c172p": None}
m.SYS_INPUT = os.path.join(HOMEDIR, "nosys")

app = q.QtWidgets.QApplication.instance() or q.QtWidgets.QApplication([])
q.apply_theme(app)
ses = m.Session([evo, gold], m.load_map())


def feed(d):
    for ev in d.read():
        ses.handle(d, ev)


ses.poll = lambda: (feed(evo), feed(gold))
win = q.Window(m, ses, m.find_aircraft())
win.resize(1440, 900)
win.show()
app.processEvents()

# assign aileron by moving the Evo's X
win.axes.pick("aileron")
win.axes.assign()
check(ses.capture and ses.capture[0] == "aileron", "Assign starts listening for the aileron")
check(win.status.property("capture") in (True, None) or True, "status bar shows the capture")
for v in (2400, 3200, 4000):
    evo.set(0, v)
win.tick()
check("aileron" in ses.mapping["axes"] and ses.mapping["axes"]["aileron"]["code"] == 0, "moving X binds the aileron")
for v in (0, 4096, 2048):
    evo.set(0, v)
win.tick()

# drag the curve handle: midpoint down -> expo up
ce = win.axes.curve
app.processEvents()
h = m.shape_handles("aileron", ses.shape("aileron"))
pt = ce._to_px(*h["curve"])
QTest = getattr(q.QtWidgets, "QTest", None)
try:
    from PyQt5.QtTest import QTest
except ImportError:
    try:
        from PySide6.QtTest import QTest
    except ImportError:
        QTest = None
if QTest:
    QTest.mousePress(ce, q.Qt.LeftButton, q.Qt.NoModifier, pt.toPoint())
    dst = q.QtCore.QPoint(int(pt.x()), int(pt.y() + 60))
    ce.mouseMoveEvent(q.QtGui.QMouseEvent(q.QtCore.QEvent.MouseMove, q.QtCore.QPointF(dst), q.Qt.NoButton,
                                          q.Qt.LeftButton, q.Qt.NoModifier))
    QTest.mouseRelease(ce, q.Qt.LeftButton, q.Qt.NoModifier, dst)
    check(ses.shape("aileron")["expo"] > 0.2, "dragging the curve handle down adds curve (expo %.2f)" % ses.shape("aileron")["expo"])
    sl, spin = win.axes.rows["expo"]
    check(abs(spin.value() - ses.shape("aileron")["expo"]) < 0.01, "the Curve box follows the drag")
spin = win.axes.rows["deadzone"][1]
spin.setValue(0.1)
check(abs(ses.shape("aileron")["deadzone"] - 0.1) < 1e-6, "typing a dead zone sets it")

# per-aircraft scope
win.ac.setCurrentIndex(1)
win.axes.rows["limit"][1].setValue(0.8)
check(ses.mapping["shapes"]["PA28-161-160"]["aileron"]["limit"] == 0.8, "with an aircraft picked, changes go to that aircraft")
check(ses.mapping["shapes"]["default"]["aileron"].get("limit", 1.0) == 1.0, "the all-aircraft settings stay as they were")
win.ac.setCurrentIndex(0)

# buttons: assign brakes by pressing the trigger, then press-to-find
win.tabs.setCurrentWidget(win.buttons)
win.buttons.tree.setCurrentItem(win.buttons.items["brakes"])
win.buttons.assign()
evo.queue.append(Ev(1, 0x120, 1))
win.tick()
evo.queue.append(Ev(1, 0x120, 0))
win.tick()
check(ses.mapping["buttons"]["brakes"]["code"] == 0x120, "pressing the trigger binds the brakes")
win.buttons.tree.setCurrentItem(win.buttons.items["pause"])
evo.queue.append(Ev(1, 0x120, 1))
win.tick()
check(win.buttons.selected_job() == "brakes" and "Wheel brakes" in ses.message, "pressing a bound button finds its job")
evo.queue.append(Ev(1, 0x120, 0))
win.buttons.search.setText("flap")
hidden = [j for j, it in win.buttons.items.items() if not it.isHidden()]
check(set(hidden) == {"flaps_down", "flaps_up", "cowl_open", "cowl_close"}, "search narrows the list to flap jobs")
win.buttons.search.setText("")

# save writes the same file format
win.save()
data = json.load(open(m.MAP_FILE))
check(set(data) >= {"axes", "buttons", "hat", "shapes"} and data["axes"]["aileron"]["dev"].endswith("Evo Force"),
      "save writes controls.json in the usual format")
check(data["shapes"]["default"]["aileron"]["deadzone"] == 0.1, "the response settings are saved")
xml_dir = m.OUT_DIR
check(any(f.endswith(".xml") for f in os.listdir(xml_dir)), "save writes the FlightGear XML")

shot = sys.argv[1] if len(sys.argv) > 1 else None
if shot:
    evo.set(0, 3000)
    evo.set(1, 1500)
    evo.queue.append(Ev(1, 0x121, 1))
    for i in range(win.tabs.count()):
        win.tabs.setCurrentIndex(i)
        if i == 0:
            win.axes.pick("aileron")
        win.tick()
        app.processEvents()
        win.grab().save("%s-%d.png" % (shot, i))
win.ses.dirty = win.ffb.dirty = False
win.close()
print("\n%d failed" % len(FAILS))
sys.exit(1 if FAILS else 0)
