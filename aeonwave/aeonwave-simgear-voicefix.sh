#!/bin/bash
# Rebuilds the AeonWave FlightGear with the SimGear sound-manager fixes:
#  - a released source counts as stopped (no "unknown source id" flood after ATC voice messages)
#  (the per-frame AAX_UPDATE stays: without it the mixer was silent here)
#  - the mixer is stopped with AAX_STOPPED at exit (AAX_PROCESSED was an invalid mixer state)
# Backs up the source, the static library and the fgfs binary first. Undo: copy the .before-voicefix files back.
set -e
exec > $HOME/builds/aeonwave-simgear-voicefix.log 2>&1
pgrep -x fgfs >/dev/null && { echo "fgfs running; not rebuilding"; exit 1; }
SG=$HOME/builds/simgear; FG=$HOME/builds/flightgear; P=$HOME/builds/aeonwave-prefix; FP=$HOME/builds/flightgear-aeonwave-prefix
T=$HOME/builds/fg-2024.1.7/sndtest
SRC=$SG/simgear/sound/soundmgr_aeonwave.cxx
[ -f $SRC.before-voicefix ] || cp -p $SRC $SRC.before-voicefix
[ -f $P/lib/libSimGearScene.a.before-voicefix ] || cp -p $P/lib/libSimGearScene.a $P/lib/libSimGearScene.a.before-voicefix
[ -f $FP/bin/fgfs.before-voicefix ] || cp -p $FP/bin/fgfs $FP/bin/fgfs.before-voicefix
python3 $T/ttsfix-patch.py $SRC
nice -n 10 cmake --build $SG/build-aeonwave --target SimGearScene -j4
cp -p $SG/build-aeonwave/simgear/libSimGearScene.a $P/lib/libSimGearScene.a
nice -n 10 cmake --build $FG/build-aeonwave --target fgfs -j4
cp $FG/build-aeonwave/src/Main/fgfs $FP/bin/.fgfs.new && mv -f $FP/bin/.fgfs.new $FP/bin/fgfs
md5sum $FP/bin/fgfs $FP/bin/fgfs.before-voicefix
echo VOICEFIX-DONE
