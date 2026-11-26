#!/bin/bash
# test_start.sh NAME  -- one ~60 s ground start at KEZM through fgfs-mga, then quit.
# Refuses to start if any fgfs is already running (one FlightGear at a time on this board).
name="$1"; port=5511
log=~/cosmic-fleet/build/test-$name.log; res=~/cosmic-fleet/build/test-$name.result
if pgrep -x fgfs >/dev/null; then echo "BUSY: another fgfs is running" > "$res"; exit 1; fi
rm -f "$res"
setsid ~/.local/bin/fgfs-mga "$name" fast --no-ffb --no-terrasync --no-photoscenery --input off -- \
  --telnet=$port --timeofday=noon --disable-real-weather-fetch > "$log" 2>&1 &
lp=$!
for i in $(seq 1 140); do
  sleep 1
  if ! kill -0 $lp 2>/dev/null; then echo "EXITED early after ${i}s" >> "$res"; break; fi
  ma=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
  if [ "$ma" -lt 450000 ]; then echo "ABORTED at ${i}s: board memory low (MemAvailable ${ma} kB)" >> "$res"; break; fi
  if [ $i -eq 100 ] || [ $i -eq 125 ]; then
    echo "t=${i}s $(python3 ~/cosmic-fleet/tools/probe.py $port 2>&1)" >> "$res"
  fi
  [ $i -eq 126 ] && break
done
# stop only our own FlightGear (its process group)
pk=$(pgrep -g $lp -x fgfs | head -1)
[ -n "$pk" ] && kill -TERM -- -$lp 2>/dev/null
sleep 4; kill -KILL -- -$lp 2>/dev/null
echo "--- log errors:" >> "$res"
grep -aiE "error|fail|not found|cannot|could not|unknown" "$log" | grep -viE "sound|openal|joystick|metar|terrasync|dds|osgEarth|texture|shader|fgcom|swift|hid|udev" | sort | uniq -c | sort -rn | head -25 >> "$res"
echo DONE >> "$res"
