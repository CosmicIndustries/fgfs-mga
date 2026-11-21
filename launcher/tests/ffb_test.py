#!/usr/bin/env python3
"""Tests fgfs-mga-ffb without a stick or FlightGear: real UDP packets in, a fake stick out."""
import json
import os
import socket
import sys
import tempfile
from importlib.machinery import SourceFileLoader

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.environ["HOME"] = tempfile.mkdtemp()
m = SourceFileLoader("ffb", os.path.join(ROOT, "src", "fgfs-mga-ffb")).load_module()
m.CONF = os.path.join(os.environ["HOME"], ".config", "fgfs-mga", "ffb.json")
FAILS = []


def check(cond, what):
    print(("PASS  " if cond else "FAIL  ") + what)
    if not cond:
        FAILS.append(what)


def line(**kw):
    s = dict(ias=0, gs=0, alpha=0, stall=0, wow0=0, wow1=0, wow2=0, trim=0, frozen=0)
    s.update(kw)
    return ",".join(str(s[f]) for f in m.FIELDS)


c = m.load_conf()
check(c["master"] < 100 and c["spring"] < 100, "defaults are moderate, not 100%")
check(m.parse("1,2,3") is None and m.parse(line(ias=90))["ias"] == 90.0, "parses FlightGear's line, rejects junk")

t_slow = m.targets(m.parse(line(ias=20)), c)
t_fast = m.targets(m.parse(line(ias=c["vref_kt"])), c)
check(t_fast["spring"][0] > t_slow["spring"][0] > 0, "spring stiffens with airspeed")
check(abs(t_fast["spring"][0] - c["spring"] / 100) < 1e-3, "full stiffness at vref = spring slider")
check(m.targets(m.parse(line(ias=90, trim=0.4)), c)["spring"][1] < 0, "spring centre follows elevator trim")
check(m.targets(m.parse(line(ias=60, alpha=5)), c)["buffet"][0] == 0, "no buffet in normal flight")
b = m.targets(m.parse(line(ias=50, alpha=c["buffet_alpha"] + 3)), c)["buffet"][0]
check(0 < b <= c["buffet"] / 100, "buffet near the stall, capped by its slider")
check(m.targets(m.parse(line(ias=50, stall=1)), c)["buffet"][0] > 0, "stall warning alone starts the buffet")
check(m.targets(m.parse(line(ias=50, alpha=30, wow0=1)), c)["buffet"][0] == 0, "no buffet on the ground")
r0 = m.targets(m.parse(line(gs=1, wow0=1)), c)["rumble"][0]
r1 = m.targets(m.parse(line(gs=20, wow0=1, wow1=1)), c)["rumble"][0]
r2 = m.targets(m.parse(line(gs=60, wow1=1)), c)["rumble"][0]
check(r0 == 0 and 0 < r1 < r2 <= c["rumble"] / 100, "ground rumble grows with ground speed")
check(m.targets(m.parse(line(gs=60, wow1=1)), dict(c, rumble=0))["rumble"][0] == 0, "slider at 0 turns an effect off")
check(m.targets(m.parse(line(gs=30, wow0=1, frozen=1)), c)["rumble"][0] == 0, "paused sim: no shaking")


class FakeStick:
    made = []

    def __init__(self):
        self.calls, self.gains, self.closed = [], [], False
        FakeStick.made.append(self)

    def gain(self, p):
        self.gains.append(p)

    def set(self, kind, value):
        self.calls.append((kind, value))

    def stop(self):
        self.calls.append(("stop", None))

    def close(self):
        self.closed = True


rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
rx.bind(("127.0.0.1", 0))
tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
port = rx.getsockname()[1]
for ln in [line(ias=90), line(ias=90), line(ias=40, alpha=c["buffet_alpha"] + 5, stall=1), "garbage"]:
    tx.sendto((ln + "\n").encode(), ("127.0.0.1", port))
m.save_conf(dict(c, master=55))
m.run([], stick_factory=FakeStick, sock=rx, max_loops=6)
st = FakeStick.made[-1]
check(st.gains == [55], "master strength from the settings file sets the stick gain once")
kinds = [k for k, _v in st.calls]
check(kinds[:3] == ["spring", "buffet", "rumble"], "all three effects set on the first packet")
check(any(k == "buffet" and v[0] > 0 for k, v in st.calls), "buffet turned on by the stall packet")
check(st.closed, "effects erased when the bridge stops")

# lost data -> stop; disabled -> stop
clock = iter([0, 0.1, 0.2, 5.0, 5.1, 5.2, 5.3]).__next__
tx.sendto((line(ias=90) + "\n").encode(), ("127.0.0.1", port))
m.run([], stick_factory=FakeStick, sock=rx, clock=clock, max_loops=6)
check(("stop", None) in FakeStick.made[-1].calls, "effects stop when FlightGear stops sending")
m.save_conf(dict(c, enabled=False))
tx.sendto((line(ias=90) + "\n").encode(), ("127.0.0.1", port))
m.run([], stick_factory=FakeStick, sock=rx, max_loops=3)
check(FakeStick.made[-1].calls[:1] == [("stop", None)], "switched off in settings: nothing plays")


def no_stick():
    raise OSError("no such device")


check(m.run([], stick_factory=no_stick, sock=rx, max_loops=2) == 0, "keeps running (waiting) without the stick")
saved = json.load(open(m.CONF))
check(set(saved) == set(m.DEFAULTS), "settings file holds every setting")
print("\n%d failed" % len(FAILS))
sys.exit(1 if FAILS else 0)
