#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PREP_SCRIPT=${PREP_SCRIPT:-"$SCRIPT_DIR/prep.sh"}
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

init_pair() {
  local root=$1 project seed bare clone
  mkdir -p "$root/builds" "$root/remotes"
  for project in simgear flightgear; do
    seed="$root/$project-seed"
    bare="$root/remotes/$project.git"
    clone="$root/builds/$project"
    git init -q --bare "$bare"
    git init -q -b release/2024.1 "$seed"
    git -C "$seed" config user.name 'Prep Test'
    git -C "$seed" config user.email 'prep-test@example.invalid'
    printf 'base line\nsecond line\n' > "$seed/tracked.txt"
    printf '\001\002\003\000\377' > "$seed/binary.dat"
    printf 'upstream-owned\n' > "$seed/collision.txt"
    git -C "$seed" add tracked.txt binary.dat collision.txt
    git -C "$seed" commit -qm 'fixture baseline'
    git -C "$seed" tag 2024.1.7
    git -C "$seed" remote add origin "$bare"
    git -C "$seed" push -q origin release/2024.1 --tags
    git --git-dir="$bare" symbolic-ref HEAD refs/heads/release/2024.1
    git clone -q "$bare" "$clone"
    git -C "$clone" config user.name 'Prep Test'
    git -C "$clone" config user.email 'prep-test@example.invalid'
    git -C "$clone" remote set-url origin "https://github.com/flightgear/$project.git"
  done
}

run_prep() {
  local root=$1
  BUILDS_DIR="$root/builds" \
  PREP_WORK_DIR="$root/builds/fg-2024.1.7" \
  SIMGEAR_UPSTREAM_URL="$root/remotes/simgear.git" \
  FLIGHTGEAR_UPSTREAM_URL="$root/remotes/flightgear.git" \
  FETCH_RETRIES=1 FETCH_RETRY_DELAY=0 \
  bash "$PREP_SCRIPT"
}

# Happy path: staged + unstaged + binary + unusual untracked paths and .bak files.
GOOD="$TEST_ROOT/good"
init_pair "$GOOD"
for project in simgear flightgear; do
  repo="$GOOD/builds/$project"
  printf 'staged line\nsecond line\n' > "$repo/tracked.txt"
  git -C "$repo" add tracked.txt
  printf 'staged line\nunstaged line\n' > "$repo/tracked.txt"
  printf '\377\000\003\002\001' > "$repo/binary.dat"
  printf 'space path preserved\n' > "$repo/new file with spaces.txt"
  newline_name=$'new\nline.txt'
  printf 'newline filename preserved\n' > "$repo/$newline_name"
  printf 'backup file preserved\n' > "$repo/important.bak"
  printf 'leading dash preserved\n' > "$repo/-leading-dash.txt"
done
run_prep "$GOOD" > "$GOOD/run.log" 2>&1 || { cat "$GOOD/run.log"; fail 'happy-path prep failed'; }
for project in simgear flightgear; do
  target="$GOOD/builds/$project-2024.1.7"
  [[ "$(cat "$target/tracked.txt")" == $'staged line\nunstaged line' ]] || fail "$project tracked staged/unstaged edits were not restored"
  printf '\377\000\003\002\001' | cmp - "$target/binary.dat" || fail "$project binary edit was not restored"
  [[ -f "$target/new file with spaces.txt" ]] || fail "$project space-containing filename missing"
  newline_name=$'new\nline.txt'
  [[ -f "$target/$newline_name" ]] || fail "$project newline-containing filename missing"
  [[ -f "$target/important.bak" ]] || fail "$project .bak file missing"
  [[ -f "$target/-leading-dash.txt" ]] || fail "$project leading-dash filename missing"
  [[ "$(git -C "$GOOD/builds/$project" remote get-url github-mirror)" == "https://github.com/flightgear/$project.git" ]] || fail "$project GitHub mirror URL was not preserved"
  [[ "$(git -C "$GOOD/builds/$project" remote get-url origin)" == "$GOOD/remotes/$project.git" ]] || fail "$project origin was not pointed to configured upstream"
done
pass 'staged, unstaged, binary, whitespace/newline, .bak, and leading-dash changes restored; GitHub remotes preserved'

# Re-run: existing worktrees must be recognized and left untouched, not patched twice.
run_prep "$GOOD" > "$GOOD/rerun.log" 2>&1 || { cat "$GOOD/rerun.log"; fail 'idempotent rerun failed'; }
grep -q 'Existing simgear worktree found' "$GOOD/rerun.log" || fail 'simgear worktree rerun was not detected'
grep -q 'Existing flightgear worktree found' "$GOOD/rerun.log" || fail 'flightgear worktree rerun was not detected'
pass 'rerun recognized existing target worktrees and skipped patch reapplication'

# Collision: an untracked source path must never overwrite the same path in the tag worktree.
COLLISION="$TEST_ROOT/collision"
init_pair "$COLLISION"
for project in simgear flightgear; do
  repo="$COLLISION/builds/$project"
  git -C "$repo" rm -q collision.txt
  git -C "$repo" commit -qm 'remove collision fixture from current source branch'
  printf 'untracked local data\n' > "$repo/collision.txt"
done
if run_prep "$COLLISION" > "$COLLISION/run.log" 2>&1; then
  fail 'collision case unexpectedly succeeded'
else
  rc=$?
  [[ $rc -eq 6 ]] || { cat "$COLLISION/run.log"; fail "collision case returned $rc instead of 6"; }
fi
[[ "$(cat "$COLLISION/builds/simgear-2024.1.7/collision.txt")" == 'upstream-owned' ]] || fail 'collision handling overwrote target data'
grep -q 'destination already exists' "$COLLISION/run.log" || fail 'collision diagnostic missing'
pass 'untracked-file collision failed closed without overwriting target data'

# Patch conflict: a dirty patch based on a newer source commit must stop the run.
CONFLICT="$TEST_ROOT/conflict"
init_pair "$CONFLICT"
for project in simgear flightgear; do
  repo="$CONFLICT/builds/$project"
  printf 'newer committed line\nsecond line\n' > "$repo/tracked.txt"
  git -C "$repo" add tracked.txt
  git -C "$repo" commit -qm 'diverge source tree from release tag'
  printf 'dirty local line\nsecond line\n' > "$repo/tracked.txt"
done
if run_prep "$CONFLICT" > "$CONFLICT/run.log" 2>&1; then
  fail 'patch-conflict case unexpectedly succeeded'
else
  rc=$?
  [[ $rc -eq 7 ]] || { cat "$CONFLICT/run.log"; fail "patch-conflict case returned $rc instead of 7"; }
fi
grep -q 'PATCH CONFLICT' "$CONFLICT/run.log" || fail 'patch conflict diagnostic missing'
if grep -q '^DONE ' "$CONFLICT/run.log"; then fail 'script printed DONE after a patch conflict'; fi
pass 'patch conflicts stop preparation, retain the worktree and never print DONE'

printf 'All prep.sh regression tests passed.\n'
