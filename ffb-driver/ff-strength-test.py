#!/usr/bin/env python3
"""Full-strength force feedback test for the Saitek Cyborg Evo Force (no sudo needed).
   python3 ~/builds/saitek-ffb/ff-strength-test.py [gain-percent]     default 100
Plays, one after another: full push left, full push right, a stiff centring spring, a strong buzz.
Hold the stick loosely. Ctrl+C stops everything at once."""
import sys, time, evdev
from evdev import ecodes as E, ff

NODE = "/dev/input/by-id/usb-Saitek_Cyborg_Evo_Force-event-joystick"
gain = max(0, min(100, int(sys.argv[1]) if len(sys.argv) > 1 else 100))
d = evdev.InputDevice(NODE)
ids = []

def env():
    return ff.Envelope(0, 0, 0, 0)

def up(effect):
    i = d.upload_effect(effect); ids.append(i); return i

def play(i, secs, what):
    print("  %-34s" % what, end="", flush=True)
    d.write(E.EV_FF, i, 1); time.sleep(secs); d.write(E.EV_FF, i, 0); time.sleep(0.4)
    print("done")

try:
    d.write(E.EV_FF, E.FF_GAIN, int(0xFFFF * gain / 100))
    print("%s: master gain %d%%" % (d.name, gain))
    ms = 1500
    left = up(ff.Effect(E.FF_CONSTANT, -1, 0x4000, ff.Trigger(0, 0), ff.Replay(ms, 0),
                        ff.EffectType(ff_constant_effect=ff.Constant(0x7FFF, env()))))
    right = up(ff.Effect(E.FF_CONSTANT, -1, 0xC000, ff.Trigger(0, 0), ff.Replay(ms, 0),
                         ff.EffectType(ff_constant_effect=ff.Constant(0x7FFF, env()))))
    stiff = ff.Condition(0xFFFF, 0xFFFF, 0x7FFF, 0x7FFF, 0, 0)   # saturation, coefficients, no deadband
    spring = up(ff.Effect(E.FF_SPRING, -1, 0, ff.Trigger(0, 0), ff.Replay(4000, 0),
                          ff.EffectType(ff_condition_effect=(stiff, stiff))))
    buzz = up(ff.Effect(E.FF_PERIODIC, -1, 0x4000, ff.Trigger(0, 0), ff.Replay(1500, 0),
                        ff.EffectType(ff_periodic_effect=ff.Periodic(E.FF_SINE, 60, 0x7FFF, 0, 0, env()))))
    play(left, 1.5, "full push one way (1.5 s)")
    play(right, 1.5, "full push the other way (1.5 s)")
    play(spring, 4.0, "stiff spring: move the stick (4 s)")
    play(buzz, 1.5, "strong buzz (1.5 s)")
except KeyboardInterrupt:
    print("\nstopped")
except OSError as e:
    print("\nthe stick refused an effect: %s" % e)
finally:
    for i in ids:
        try:
            d.write(E.EV_FF, i, 0); d.erase_effect(i)
        except OSError:
            pass
