#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BUILD_SCRIPT=${BUILD_SCRIPT:-"$SCRIPT_DIR/../build.sh"}
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

make_fakes() {
  local bin=$1
  mkdir -p "$bin"
  cat > "$bin/cmake" <<'EOF'
#!/usr/bin/env bash
printf 'cmake %s\n' "$*" >> "$MOCK_LOG"
EOF
  cat > "$bin/ninja" <<'EOF'
#!/usr/bin/env bash
printf 'ninja %s\n' "$*" >> "$MOCK_LOG"
EOF
  cat > "$bin/ctest" <<'EOF'
#!/usr/bin/env bash
printf 'ctest %s FG_ROOT=%s\n' "$*" "${FG_ROOT:-}" >> "$MOCK_LOG"
EOF
  cat > "$bin/nice" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == -n && "$2" == 10 ]] || exit 90
shift 2
exec "$@"
EOF
  chmod +x "$bin/"*
}

make_home() {
  local home=$1
  mkdir -p "$home/builds/fg-2024.1.7" \
    "$home/builds/simgear-2024.1.7" \
    "$home/builds/flightgear-2024.1.7" \
    "$home/builds/flightgear/build"
  printf 'ENABLE_LOGGING:BOOL=ON\nENABLE_TESTS:BOOL=ON\nENABLE_AUTOTESTING:BOOL=ON\n' \
    > "$home/builds/flightgear/build/CMakeCache.txt"
}

# Default path: tests must remain disabled and must not invoke CTest.
OFF_HOME="$ROOT/off-home"
OFF_BIN="$ROOT/off-bin"
make_home "$OFF_HOME"
make_fakes "$OFF_BIN"
MOCK_LOG="$ROOT/off.log" HOME="$OFF_HOME" PATH="$OFF_BIN:$PATH" JOBS=1 \
  bash "$BUILD_SCRIPT" sg-openal fg-openal
grep -q -- '-DENABLE_TESTS=OFF' "$MOCK_LOG" || fail 'default SimGear test option was not OFF'
! grep -q '^ctest ' "$MOCK_LOG" || fail 'default build unexpectedly ran CTest'
! grep -q 'test_suite' "$MOCK_LOG" || fail 'default build unexpectedly built the FlightGear test suite'
pass 'default build keeps both upstream test suites disabled'

# Opt-in path: SimGear tests are enabled and CTest is run for both projects.
ON_HOME="$ROOT/on-home"
ON_BIN="$ROOT/on-bin"
make_home "$ON_HOME"
make_fakes "$ON_BIN"
mkdir -p "$ON_HOME/data"
printf 'FlightGear data fixture\n' > "$ON_HOME/data/version"
MOCK_LOG="$ROOT/on.log" HOME="$ON_HOME" PATH="$ON_BIN:$PATH" JOBS=1 \
  MGA_ENABLE_TESTS=1 FG_ROOT="$ON_HOME/data" \
  bash "$BUILD_SCRIPT" sg-openal fg-openal
grep -q -- '-DENABLE_TESTS=ON' "$MOCK_LOG" || fail 'opt-in did not enable SimGear test apps'
grep -q '^ctest --test-dir .*simgear-2024.1.7/build ' "$MOCK_LOG" || fail 'SimGear CTest was not run'
grep -q 'ninja .* test_suite' "$MOCK_LOG" || fail 'FlightGear test_suite target was not built'
grep -q '^ctest --test-dir .*flightgear-2024.1.7/build .*FG_ROOT=' "$MOCK_LOG" || fail 'FlightGear CTest was not run'
pass 'opt-in enables SimGear tests and explicitly builds/runs FlightGear tests with FG_ROOT'

# Test mode must refuse to run FlightGear tests without a usable FG_ROOT.
MISSING_HOME="$ROOT/missing-home"
MISSING_BIN="$ROOT/missing-bin"
make_home "$MISSING_HOME"
make_fakes "$MISSING_BIN"
if MOCK_LOG="$ROOT/missing.log" HOME="$MISSING_HOME" PATH="$MISSING_BIN:$PATH" JOBS=1 \
  MGA_ENABLE_TESTS=1 FG_ROOT="$MISSING_HOME/no-data" \
  bash "$BUILD_SCRIPT" fg-openal; then
  fail 'FlightGear tests ran without a valid FG_ROOT'
fi
grep -q 'FG_ROOT must point to a FlightGear data tree' "$MISSING_HOME/builds/fg-2024.1.7/build.log" || fail 'missing FG_ROOT diagnostic absent'
! grep -q '^ctest ' "$ROOT/missing.log" || fail 'CTest ran despite missing FG_ROOT'
pass 'test mode fails clearly when FlightGear data is missing'

# Reject invalid toggle values before any build command.
if HOME="$OFF_HOME" PATH="$OFF_BIN:$PATH" MGA_ENABLE_TESTS=yes bash "$BUILD_SCRIPT" sg-openal; then
  fail 'invalid MGA_ENABLE_TESTS value was accepted'
fi
pass 'invalid test toggle is rejected'

printf 'All optional build-test regression tests passed.\n'
