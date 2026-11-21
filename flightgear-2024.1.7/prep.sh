#!/bin/bash
# FlightGear 2024.1.7 prep: save local edits, point origin at the official GitLab, fetch the tag,
# make side-by-side worktrees (old trees and builds untouched), re-apply the local edits there.
set -u
W=~/builds/fg-2024.1.7
exec > $W/prep.log 2>&1
TAG=2024.1.7
mkdir -p $W/patches
for p in simgear flightgear; do
  cd ~/builds/$p || exit 1
  echo "===== $p $(date +%T)"
  git diff > $W/patches/$p-local-on-2024.1.1.patch
  git status --porcelain | awk '/^\?\? / && $2 !~ /\.bak/ {print $2}' > $W/patches/$p-new-files.txt
  [ -s $W/patches/$p-new-files.txt ] && tar czf $W/patches/$p-new-files.tgz -T $W/patches/$p-new-files.txt
  # remotes: origin -> official GitLab, keep the old GitHub mirror as github-mirror
  if git remote get-url origin | grep -q github.com; then
    git remote rename origin github-mirror && git remote add origin https://gitlab.com/flightgear/$p.git
  fi
  git remote -v
  ok=0
  for t in 1 2 3 4 5; do
    git fetch --no-tags origin "refs/tags/$TAG:refs/tags/$TAG" release/2024.1:refs/remotes/origin/release/2024.1 && { ok=1; break; }
    echo "fetch try $t failed"; sleep 10
  done
  [ $ok = 1 ] || { echo "FETCH FAILED $p"; exit 2; }
  git log -1 --format='%h %ci %s' $TAG
  git worktree add -b mga-$TAG ~/builds/$p-$TAG $TAG || exit 3
  cd ~/builds/$p-$TAG
  if git apply --3way $W/patches/$p-local-on-2024.1.1.patch; then echo "PATCH APPLIED $p"; else echo "PATCH CONFLICT $p"; git status --short; fi
  [ -f $W/patches/$p-new-files.tgz ] && tar xzf $W/patches/$p-new-files.tgz && echo "new files restored: $(wc -l < $W/patches/$p-new-files.txt)"
done
echo DONE $(date +%T)
