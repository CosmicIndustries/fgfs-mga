#!/bin/bash
# test_start2.sh NAME [attach PGID]
# Ground start at KEZM through fgfs-mga: wait until scenery has loaded (up to 6 min), let it sit 30 s,
# read the attitude/gear/engine properties twice, then stop only our own FlightGear process group.
# Aborts if the board's available memory drops under ~450 MB.
name="$1"; port=5511
log=~/cosmic-fleet/build/test-$name.log; res=~/cosmic-fleet/build/test-$name.result
P=~/cosmic-fleet/tools/probe.py
if [ "$2" = attach ]; then lp=$3; else
  if pgrep -x fgfs >/dev/null; then echo "BUSY: another fgfs is running" > "$res"; exit 1; fi
  rm -f "$res"
  setsid ~/.local/bin/fgfs-mga "$name" fast --no-ffb --no-terrasync --no-photoscenery --input off -- \
    --telnet=$port --timeofday=noon --disable-real-weather-fetch > "$log" 2>&1 &
  lp=$!
fi
t0=$(date +%s); loaded=0
while true; do
  sleep 5; el=$(( $(date +%s) - t0 ))
  if ! pgrep -g $lp -x fgfs >/dev/null; then echo "EXITED early after ${el}s" >> "$res"; break; fi
  ma=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
  if [ "$ma" -lt 450000 ]; then echo "ABORTED at ${el}s: board memory low (MemAvailable ${ma} kB)" >> "$res"; break; fi
  if [ $loaded -eq 0 ]; then
    s=$(timeout 30 python3 ~/cosmic-fleet/tools/probe1.py $port /sim/sceneryloaded 2>/dev/null)
    if [ "$s" = "true" ] || [ "$s" = "1" ]; then loaded=$(date +%s); echo "scenery loaded at ${el}s" >> "$res"; fi
    [ $el -gt 360 ] && { echo "TIMEOUT: scenery not loaded after ${el}s; last: $s" >> "$res"; break; }
  else
    since=$(( $(date +%s) - loaded ))
    if [ $since -ge 15 ] && ! grep -q "^+15s" "$res"; then echo "+15s $(timeout 120 python3 $P $port 2>&1 | tail -1)" >> "$res"; fi
    if [ $since -ge 35 ]; then echo "+35s $(timeout 120 python3 $P $port 2>&1 | tail -1)" >> "$res"; break; fi
  fi
done
kill -TERM -- -$lp 2>/dev/null; sleep 5; kill -KILL -- -$lp 2>/dev/null
echo "--- log errors:" >> "$res"
grep -aiE "error|fail|not found|cannot|could not|unknown" "$log" | grep -viE "sound|openal|joystick|metar|terrasync|dds|osgEarth|texture|shader|fgcom|swift|hid|udev|translation" | sort | uniq -c | sort -rn | head -25 >> "$res"
echo DONE >> "$res"
