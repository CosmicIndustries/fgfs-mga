#!/bin/bash
# Pause the 2024.1.7 build while any fgfs runs; resume it 60 s after the last fgfs exits.
# Stops by itself once the build says ALL DONE or FAILED. Log: pause.log
W=$HOME/builds/fg-2024.1.7
exec >> $W/pause.log 2>&1
tree() { local p; for p in "$@"; do echo "$p"; tree $(pgrep -P "$p"); done; }
build_pids() {  # build.sh (started as "bash build.sh" in $W) and everything under it
  local p
  for p in $(pgrep -x bash); do
    [ "$(readlink /proc/$p/cwd 2>/dev/null)" = "$W" ] && tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null | grep -q 'build\.sh' && tree "$p"
  done
}
state=""; quiet=0
echo "$(date +%T) watcher start, build pids: $(build_pids | tr '\n' ' ')"
while :; do
  grep -q -E 'ALL DONE|FAILED' $W/status 2>/dev/null && { echo "$(date +%T) build finished, watcher exits"; kill -CONT $(build_pids) 2>/dev/null; exit 0; }
  if pgrep -x fgfs >/dev/null; then
    quiet=0
    if [ "$state" != paused ]; then kill -STOP $(build_pids) 2>/dev/null; state=paused; echo "$(date +%T) fgfs running: build paused"; fi
  else
    quiet=$((quiet + 10))
    if [ "$state" != running ] && [ $quiet -ge 60 ]; then kill -CONT $(build_pids) 2>/dev/null; state=running; echo "$(date +%T) no fgfs for 60 s: build resumed"; fi
  fi
  sleep 10
done
