#!/usr/bin/env python3
"""Counts input events (without grabbing) from each Saitek event node for a few seconds, and prints
each node's current axis values, to see which nodes are alive. Usage: listen-sticks.py [seconds]"""
import select, sys, time
import evdev
from evdev import ecodes as E
secs = float(sys.argv[1]) if len(sys.argv) > 1 else 4
devs = [evdev.InputDevice(p) for p in evdev.list_devices()]
devs = [d for d in devs if "saitek" in d.name.lower()]
count = {d.path: {} for d in devs}
for d in devs:
    abs_now = {E.ABS[c] if not isinstance(E.ABS[c], list) else E.ABS[c][0]: i.value
               for c, i in d.capabilities(absinfo=True).get(E.EV_ABS, [])}
    print("%-18s %-26s axes now %s" % (d.path, d.name, abs_now))
end = time.time() + secs
while time.time() < end:
    r, _, _ = select.select(devs, [], [], 0.2)
    for d in r:
        for ev in d.read():
            if ev.type in (E.EV_ABS, E.EV_KEY):
                k = E.bytype[ev.type].get(ev.code, ev.code)
                k = k[0] if isinstance(k, list) else k
                count[d.path][k] = count[d.path].get(k, 0) + 1
for d in devs:
    print("%-18s events in %.0f s: %s" % (d.path, secs, count[d.path] or "none"))
