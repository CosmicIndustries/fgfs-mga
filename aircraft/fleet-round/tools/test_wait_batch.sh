#!/bin/bash
# test_wait_batch.sh NAME...  Wait until the board is free (no lock, no fgfs for 15 s), take
# /tmp/fgfs-board.lock with noclobber, run test_start2.sh for each NAME one at a time, free the lock.
L=/tmp/fgfs-board.lock; S=~/cosmic-fleet/build/batch.status
echo "wait-batch $* queued $(date +%T)" > $S
while true; do
  q=0
  while [ $q -lt 15 ]; do
    if [ -e $L ] || pgrep -x fgfs >/dev/null; then q=0; else q=$((q+1)); fi
    sleep 1
  done
  if ( set -o noclobber; echo "fleet-models $(date +%T)" > $L ) 2>/dev/null; then break; fi
done
echo "lock taken $(date +%T)" >> $S
for n in "$@"; do
  echo "start $n $(date +%T)" >> $S
  ~/cosmic-fleet/tools/test_start2.sh $n
  grep -q ABORTED ~/cosmic-fleet/build/test-$n.result && { echo "stopped: low memory on $n" >> $S; break; }
  sleep 5
done
grep -q fleet-models $L && rm -f $L
echo "all done $(date +%T)" >> $S
