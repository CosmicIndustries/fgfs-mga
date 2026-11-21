#!/usr/bin/env python3
# Checks that the Evo Force accepts force-feedback effects, WITHOUT playing any (nothing moves).
import evdev, sys
from evdev import ecodes, ff
path = sys.argv[1] if len(sys.argv) > 1 else "/dev/input/by-id/usb-Saitek_Cyborg_Evo_Force-event-joystick"
d = evdev.InputDevice(path)
caps = d.capabilities().get(ecodes.EV_FF, [])
names = [ecodes.FF.get(c, c) for c in caps]
print(d.path, d.name, "effects:", names, "max at once:", getattr(d, "ff_effects_count", "?"))
tests = {
    "constant": ff.Effect(ecodes.FF_CONSTANT, -1, 0x4000, ff.Trigger(0, 0), ff.Replay(500, 0),
                          ff.EffectType(ff_constant_effect=ff.Constant(0, ff.Envelope(0, 0, 0, 0)))),
    "spring": ff.Effect(ecodes.FF_SPRING, -1, 0, ff.Trigger(0, 0), ff.Replay(500, 0),
                        ff.EffectType(ff_condition_effect=(ff.Condition(0x4000, 0x4000, 0x4000, 0x4000, 0, 0),
                                                           ff.Condition(0x4000, 0x4000, 0x4000, 0x4000, 0, 0)))),
    "sine": ff.Effect(ecodes.FF_PERIODIC, -1, 0, ff.Trigger(0, 0), ff.Replay(500, 0),
                      ff.EffectType(ff_periodic_effect=ff.Periodic(ecodes.FF_SINE, 50, 0, 0, 0, ff.Envelope(0, 0, 0, 0)))),
}
for name, eff in tests.items():
    try:
        i = d.upload_effect(eff)
        print("  upload %-8s ok (id %d), erased without playing" % (name, i))
        d.erase_effect(i)
    except OSError as e:
        print("  upload %-8s FAILED: %s" % (name, e))
