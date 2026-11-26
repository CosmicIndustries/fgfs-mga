#!/usr/bin/env python3
"""Read a few FlightGear properties over the telnet props server.  probe.py PORT"""
import socket, sys, time
port = int(sys.argv[1])
props = ["/sim/aircraft", "/sim/sceneryloaded", "/sim/aero", "/sim/flight-model",
         "/orientation/pitch-deg", "/orientation/roll-deg", "/position/altitude-agl-ft",
         "/velocities/groundspeed-kt",
         "/gear/gear[0]/wow", "/gear/gear[1]/wow", "/gear/gear[2]/wow",
         "/gear/gear[0]/compression-norm", "/gear/gear[1]/compression-norm", "/gear/gear[2]/compression-norm",
         "/gear/gear[0]/position-norm",
         "/engines/engine[0]/running", "/engines/engine[0]/rpm", "/engines/engine[0]/n2",
         "/engines/engine[1]/running", "/engines/engine[1]/rpm",
         "/sim/frame-rate", "/consumables/fuel/total-fuel-lbs", "/fdm/yasim/gross-weight-lbs",
         "/fdm/jsbsim/inertia/weight-lbs"]
s = socket.create_connection(("127.0.0.1", port), timeout=40)
f = s.makefile("rwb", buffering=0)
s.sendall(b"data\r\n")
out = []
for p in props:
    s.sendall(("get %s\r\n" % p).encode())
    v = f.readline().decode(errors="replace").strip()
    out.append("%s=%s" % (p.split("/")[-2] + "/" + p.split("/")[-1] if p.count("/") > 2 else p.strip("/"), v))
print(" | ".join(out))
s.sendall(b"quit\r\n")
