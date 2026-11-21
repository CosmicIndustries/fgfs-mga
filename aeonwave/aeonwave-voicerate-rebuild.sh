#!/bin/bash
# Rebuilds the AeonWave FlightGear against the patched aeonwave C++ header (buffer cache destroys each
# voice buffer once). The libaax rate fix needs no rebuild here: fgfs-mga loads aeonwave-fixed-prefix.
# Undo: copy fgfs.before-voicerate and libSimGearScene.a.before-voicerate back, and the files in
# ~/builds/voicerate-backup-20261121 to where they came from.
set -e
exec > $HOME/builds/aeonwave-voicerate-rebuild.log 2>&1
pgrep -x fgfs >/dev/null && { echo "fgfs running; not rebuilding"; exit 1; }
SG=$HOME/builds/simgear; FG=$HOME/builds/flightgear; P=$HOME/builds/aeonwave-prefix; FP=$HOME/builds/flightgear-aeonwave-prefix
[ -f $P/lib/libSimGearScene.a.before-voicerate ] || cp -p $P/lib/libSimGearScene.a $P/lib/libSimGearScene.a.before-voicerate
[ -f $FP/bin/fgfs.before-voicerate ] || cp -p $FP/bin/fgfs $FP/bin/fgfs.before-voicerate
touch $SG/simgear/sound/soundmgr_aeonwave.cxx
nice -n 10 cmake --build $SG/build-aeonwave --target SimGearScene -j4
cp -p $SG/build-aeonwave/simgear/libSimGearScene.a $P/lib/libSimGearScene.a
nice -n 10 cmake --build $FG/build-aeonwave --target fgfs -j4
cp $FG/build-aeonwave/src/Main/fgfs $FP/bin/.fgfs.new && mv -f $FP/bin/.fgfs.new $FP/bin/fgfs
md5sum $FP/bin/fgfs $FP/bin/fgfs.before-voicerate
echo VOICERATE-DONE
