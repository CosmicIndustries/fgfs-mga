"""Drop the per-frame AAX_UPDATE from SimGear's AeonWave sound manager.

AAX_UPDATE runs one synchronous mixer batch and waits for it to finish. With the mixer already
playing on its own thread it can wait forever (seen: update() stuck in aaxMixerSetState after a
suspend/resume). The silence it was added for was the NEON mixing bug, fixed in libaax itself.
Usage: python3 noupdate-patch.py soundmgr_aeonwave.cxx
"""
import sys
p = sys.argv[1]
s = open(p).read()
if "TRY( d->_aax.set(AAX_UPDATE) );" not in s:
    print("already patched"); sys.exit(0)
old = '''        // AeonWave requires an explicit mixer update to advance emitters and
        // submit their mixed PCM to the output device. Without this call,
        // FlightGear reports samples as playing but the sink receives silence.
        TRY( d->_aax.set(AAX_UPDATE) );
'''
new = '''        // No AAX_UPDATE here: the mixer runs on its own thread, and a synchronous batch update
        // from this thread can wait forever (a hang after pause/resume and at exit).
'''
assert s.count(old) == 1, "update anchor"
s = s.replace(old, new)
open(p, "w").write(s)
print("patched")
