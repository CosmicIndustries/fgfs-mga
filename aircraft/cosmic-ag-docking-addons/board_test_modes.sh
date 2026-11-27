#!/usr/bin/env bash
# Sim test of the formation modes: waits for a free board (no lock, no fgfs),
# takes /tmp/fgfs-board.lock ("formation-modes"), starts the mothership demo
# with the test-only level hold (70 kt, 15 flaps, 50 ft AGL), releases both
# drones, steps Ctrl-F through the four formations (logging each drone and
# taking screenshots), recalls both and waits for the latch. Closes only its
# own sim and frees the lock.
# Log: /tmp/cosmic-modes-sim.log, sim log: /tmp/cosmic-modes-fg.log,
# screenshots /tmp/cosmic-modes-*.jpg
DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOCK=/tmp/fgfs-board.lock
LOG=/tmp/cosmic-modes-sim.log
FGLOG=/tmp/cosmic-modes-fg.log
FGPID=""
say() { echo "$(date +%T) $*" | tee -a "$LOG"; }
run_nasal() { timeout 30 python3 "$DIR/fgrun.py" "$1" >/dev/null 2>&1; }
shot() { DISPLAY=:0 timeout 15 import -window root -crop 1920x1080+0+0 -resize 60% -quality 75 "/tmp/cosmic-modes-$1.jpg" 2>/dev/null; }
cleanup() {
    if [[ -n "$FGPID" ]]; then kill "$FGPID" 2>/dev/null; sleep 3; fi
    if grep -qx formation-modes "$LOCK" 2>/dev/null; then rm -f "$LOCK"; fi
    say "sim closed, lock freed"
}
: > "$LOG"; rm -f /tmp/cosmic-modes-*.jpg
end=$((SECONDS + 3600))
until ! pgrep -x fgfs >/dev/null && ( set -o noclobber; echo formation-modes > "$LOCK" ) 2>/dev/null; do
    if (( SECONDS > end )); then say "gave up waiting for the board"; exit 1; fi
    sleep 3
done
trap cleanup EXIT
say "board free, starting the sim"
DISPLAY=:0 COSMIC_ALT_FT=450 "$DIR/launch-fixed.sh" --telnet=5502 --prop:/cosmic/test-hold=1 \
    --prop:/cosmic/test-hold-agl=50 --prop:/cosmic/test-hold-kt=70 --prop:/controls/flight/flaps=0.5 > "$FGLOG" 2>&1 &
FGPID=$!
for i in $(seq 1 120); do grep -q "Remora drones engaged" "$FGLOG" && break; sleep 3; done
grep -q "Remora drones engaged" "$FGLOG" || { say "drones never engaged"; exit 1; }
grep -q "formation modes ready" "$FGLOG" && say "formation modes hooked" || say "formation modes NOT hooked"
run_nasal "setprop('/sim/current-view/view-number',2);"
sleep 20
shot start
say "release both"; run_nasal "cosmic_formation.key_drone(0);"; sleep 1; run_nasal "cosmic_formation.key_drone(1);"
sleep 20; run_nasal "cosmic_modes.report();"; shot escort
for p in 1 2 3 4; do
    say "formation $p"; run_nasal "cosmic_modes.key_formation();"
    sleep 30; run_nasal "cosmic_modes.report();"; shot "formation$p"
    sleep 5; run_nasal "cosmic_modes.report();"
done
say "recall both"; run_nasal "cosmic_formation.key_drone(0);"; sleep 1; run_nasal "cosmic_formation.key_drone(1);"
for i in $(seq 1 90); do
    grep -q "Port drone latched:" "$FGLOG" && grep -q "Starboard drone latched:" "$FGLOG" && break
    (( i % 10 == 0 )) && run_nasal "cosmic_modes.report();"
    sleep 2
done
grep -q "Port drone latched:" "$FGLOG" && say "port latched" || say "port did NOT latch"
grep -q "Starboard drone latched:" "$FGLOG" && say "starboard latched" || say "starboard did NOT latch"
shot end
grep -iE "nasal|error|particle|remora-modes|retardant" "$FGLOG" | grep -v "^\[COSMIC\] status" | head -30 >> "$LOG"
grep -E "COSMIC|\[AGL\]" "$FGLOG" | grep -v "\[COSMIC\] status" | tail -80 >> "$LOG"
