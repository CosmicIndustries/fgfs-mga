#!/usr/bin/env python3
"""Walker check in a running FlightGear (telnet props server).
usage: walker_probe.py PORT [shot]
Sends the walker outside, reports where he stands relative to the aircraft (x aft,
y right, metres) and his outfit, switches to the Walker Orbit View and saves a screenshot."""
import socket, sys, time, math

port = int(sys.argv[1]); shot = len(sys.argv) > 2
s = socket.create_connection(("127.0.0.1", port), timeout=60)
f = s.makefile("rwb", buffering=0)
s.sendall(b"data\r\n")


def get(p):
    s.sendall(("get %s\r\n" % p).encode())
    return f.readline().decode(errors="replace").strip()


def put(p, v):
    s.sendall(("set %s %s\r\n" % (p, v)).encode())


def run(cmd):
    # in data mode the props server sends nothing back for a command that worked
    s.sendall(("run %s\r\n" % cmd).encode())


out = {}
try:
    for k in ["/sim/aircraft", "/sim/walker/outfit", "/sim/walker/theme-name",
              "/sim/model/map/default_exit/x-offset-m", "/sim/model/map/default_exit/y-offset-m",
              "/sim/walker/outside"]:
        out[k] = get(k)
    if out["/sim/walker/outside"] not in ("true", "1"):
        cur = get("/sim/walker/key-triggers/outside-toggle")
        put("/sim/walker/key-triggers/outside-toggle", "false" if cur in ("true", "1") else "true")
    time.sleep(5)
    out["outside_after"] = get("/sim/walker/outside")
    la, lo = float(get("/position/latitude-deg") or 0), float(get("/position/longitude-deg") or 0)
    wla, wlo = float(get("/sim/walker/latitude-deg") or 0), float(get("/sim/walker/longitude-deg") or 0)
    hdg = math.radians(float(get("/orientation/heading-deg") or 0))
    dn = (wla - la) * 111320.0; de = (wlo - lo) * 111320.0 * math.cos(math.radians(la))
    fwd = dn * math.cos(hdg) + de * math.sin(hdg); right = -dn * math.sin(hdg) + de * math.cos(hdg)
    out["walker_x_aft_m"] = round(-fwd, 2); out["walker_y_right_m"] = round(right, 2)
    out["walker_alt_ft"] = get("/sim/walker/altitude-ft"); out["ground_ft"] = get("/position/ground-elev-ft")
    put("/sim/current-view/view-number-raw", "111")
    time.sleep(2)
    out["view"] = get("/sim/current-view/name")
    out["groundspeed_kt"] = get("/velocities/groundspeed-kt"); out["airspeed_kt"] = get("/velocities/airspeed-kt")
    H = math.degrees(hdg)
    put("/sim/current-view/pitch-offset-deg", "-32"); put("/sim/current-view/field-of-view", "60"); put("/sim/current-view/z-offset-m", "10")
    shots = []
    for k, off in enumerate((H + 60, H + 240) if shot else ()):
        put("/sim/current-view/heading-offset-deg", "%.0f" % (off % 360))
        time.sleep(6)
        run("screen-capture")
        time.sleep(6)
        shots.append(get("/sim/paths/screenshot-last"))
    out["shot"] = ",".join(shots)
    out["fps"] = get("/sim/frame-rate")
except Exception as e:
    out["error"] = repr(e)
print(" | ".join("%s=%s" % kv for kv in out.items()))
try:
    s.sendall(b"quit\r\n")
except Exception:
    pass
