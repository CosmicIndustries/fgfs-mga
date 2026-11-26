#!/bin/bash
# walker_test.sh NAME
# Ground start at KEZM through fgfs-mga, wait for scenery, send the walker out, report where he
# stands and his outfit, take a screenshot from the Walker Orbit View, then stop only our own
# FlightGear process group. Aborts if board memory drops under ~450 MB.
name="$1"; port=5512
HERE="$(cd "$(dirname "$0")" && pwd)"; W=${WALKER_TEST_DIR:-$HOME/aquila-walker-tests}; mkdir -p $W/tests
log=$W/tests/$name.log; res=$W/tests/$name.result
if pgrep -x fgfs >/dev/null; then echo "BUSY: another fgfs is running" > "$res"; exit 1; fi
rm -f "$res"
setsid ~/.local/bin/fgfs-mga "$name" fast --no-ffb --no-terrasync --no-photoscenery --input off -- \
  --telnet=$port --timeofday=noon --disable-real-weather-fetch > "$log" 2>&1 &
lp=$!
t0=$(date +%s); loaded=0
while true; do
  sleep 5; el=$(( $(date +%s) - t0 ))
  if ! pgrep -g $lp -x fgfs >/dev/null; then echo "EXITED early after ${el}s" >> "$res"; break; fi
  ma=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
  if [ "$ma" -lt 450000 ]; then echo "ABORTED at ${el}s: board memory low (MemAvailable ${ma} kB)" >> "$res"; break; fi
  if [ $loaded -eq 0 ]; then
    s=$(timeout 30 python3 $HERE/../../fleet-round/tools/probe1.py $port /sim/sceneryloaded 2>/dev/null)
    if [ "$s" = "true" ] || [ "$s" = "1" ]; then loaded=$(date +%s); echo "scenery loaded at ${el}s" >> "$res"; fi
    [ $el -gt 420 ] && { echo "TIMEOUT: scenery not loaded after ${el}s; last: $s" >> "$res"; break; }
  else
    if [ $(( $(date +%s) - loaded )) -ge 20 ]; then
      echo "walker: $(timeout 150 python3 $HERE/walker_probe.py $port shot 2>&1 | tail -1)" >> "$res"; break
    fi
  fi
done
kill -TERM -- -$lp 2>/dev/null; sleep 5; kill -KILL -- -$lp 2>/dev/null
echo "--- log lines about the walker / nasal errors:" >> "$res"
grep -aiE "walk|outfit|aquila|nasal.*error|runtime error|failed to load|Human" "$log" | grep -viE "sound|joystick" | sort | uniq -c | sort -rn | head -20 >> "$res"
echo DONE >> "$res"
