#!/bin/bash
# Build FlightGear 2024.1.7 twice (OpenAL and AeonWave) next to the old 2024.1.1 builds, which stay as they are.
# Usage: build.sh [stage...]   stages: sg-openal fg-openal sg-aw fg-aw   (default: all, in order)
set -u
W=~/builds/fg-2024.1.7
SG=~/builds/simgear-2024.1.7; FG=~/builds/flightgear-2024.1.7
P1=$W/prefix-openal; P2=$W/prefix-aeonwave; AAX=~/builds/aeonwave-prefix
FLAGS="-O3 -march=armv8.2-a+fp16+dotprod -mtune=cortex-a76"
JOBS=${JOBS:-3}            # the board is short on memory; more jobs swap
LOG=$W/build.log
exec >>$LOG 2>&1
st() { echo "$1 $(date '+%F %T')" >> $W/status; echo "######## $1 $(date +%T)"; }
initcache() {  # the ENABLE_* choices of an old FG build, as a cmake -C file
  grep -E '^(ENABLE_[A-Z_]+|OSG_FSTREAM_EXPORT_FIXED):BOOL=' "$1" | grep -v -E '^ENABLE_(TESTS|AUTOTESTING)' |
    sed -E 's/^([A-Z_]+):BOOL=(.*)$/set(\1 \2 CACHE BOOL "")/' > "$2"
  echo 'set(ENABLE_TESTS OFF CACHE BOOL "")' >> "$2"; echo 'set(ENABLE_AUTOTESTING OFF CACHE BOOL "")' >> "$2"
}
run_ninja() { nice -n 10 ninja -C "$1" -j "$JOBS" -l 7 || { st "FAILED ninja $1"; exit 1; }; }
stage() {
  case "$1" in
  sg-openal)
    st "start sg-openal"
    cmake -S $SG -B $SG/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$P1 \
      -DCMAKE_PREFIX_PATH=/usr/local "-DCMAKE_C_FLAGS=$FLAGS" "-DCMAKE_CXX_FLAGS=$FLAGS" \
      -DSIMGEAR_SHARED=OFF -DENABLE_SIMD=ON -DENABLE_TESTS=OFF -DUSE_AEONWAVE=OFF || { st "FAILED cmake sg-openal"; exit 1; }
    run_ninja $SG/build; ninja -C $SG/build install >/dev/null || { st "FAILED install sg-openal"; exit 1; }
    st "done sg-openal" ;;
  fg-openal)
    st "start fg-openal"
    initcache ~/builds/flightgear/build/CMakeCache.txt $W/fg-openal-init.cmake
    cmake -C $W/fg-openal-init.cmake -S $FG -B $FG/build -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=$P1 "-DCMAKE_PREFIX_PATH=$P1;/usr/local" -DSimGear_DIR=$P1/lib/cmake/SimGear \
      "-DCMAKE_C_FLAGS=$FLAGS" "-DCMAKE_CXX_FLAGS=$FLAGS" || { st "FAILED cmake fg-openal"; exit 1; }
    run_ninja $FG/build
    st "done fg-openal" ;;
  sg-aw)
    st "start sg-aw"
    cmake -S $SG -B $SG/build-aeonwave -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$P2 \
      -DCMAKE_PREFIX_PATH=$AAX "-DCMAKE_C_FLAGS=$FLAGS" "-DCMAKE_CXX_FLAGS=$FLAGS" \
      -DSIMGEAR_SHARED=OFF -DENABLE_SIMD=ON -DENABLE_TESTS=OFF -DUSE_AEONWAVE=ON \
      -DAAX_INCLUDE_DIR=$AAX/include -DAAX_LIBRARY=$AAX/lib/aarch64-linux-gnu/libaax.so || { st "FAILED cmake sg-aw"; exit 1; }
    run_ninja $SG/build-aeonwave; ninja -C $SG/build-aeonwave install >/dev/null || { st "FAILED install sg-aw"; exit 1; }
    st "done sg-aw" ;;
  fg-aw)
    st "start fg-aw"
    initcache ~/builds/flightgear/build-aeonwave/CMakeCache.txt $W/fg-aw-init.cmake
    cmake -C $W/fg-aw-init.cmake -S $FG -B $FG/build-aeonwave -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=$P2 "-DCMAKE_PREFIX_PATH=$P2;$AAX" -DSimGear_DIR=$P2/lib/cmake/SimGear \
      -DAAX_INCLUDE_DIR=$AAX/include -DAAX_LIBRARY=$AAX/lib/aarch64-linux-gnu/libaax.so \
      -DCMAKE_BUILD_RPATH=$AAX/lib/aarch64-linux-gnu "-DCMAKE_C_FLAGS=$FLAGS" "-DCMAKE_CXX_FLAGS=$FLAGS" || { st "FAILED cmake fg-aw"; exit 1; }
    run_ninja $FG/build-aeonwave
    st "done fg-aw" ;;
  *) st "FAILED unknown stage $1"; exit 1 ;;
  esac
}
[ $# -eq 0 ] && set -- sg-openal fg-openal sg-aw fg-aw
for s in "$@"; do stage "$s"; done
st "ALL DONE"
