#!/bin/bash
# Builds AeonWave with the NEON fmadd fix and the WAV tag-parser fix into ~/builds/aeonwave-fixed (a copy of ~/builds/aeonwave) and puts
# the library in ~/builds/aeonwave-fixed-prefix/lib/aarch64-linux-gnu. The original tree and prefix stay as they are.
exec > ~/builds/aeonwave-fixed-build.log 2>&1
set -e
cd ~/builds
rm -rf aeonwave-fixed                            # only ever this script's own copy
mkdir aeonwave-fixed
tar -C aeonwave --exclude=./build -cf - . | tar -C aeonwave-fixed -xf -
python3 aeonwave-fmadd-fix.py aeonwave-fixed
python3 aeonwave-wavlist-fix.py aeonwave-fixed
python3 aeonwave-wavlist-fix2.py aeonwave-fixed
python3 aeonwave-wavlist-fix3.py aeonwave-fixed
python3 aeonwave-meta-fix.py aeonwave-fixed
python3 aeonwave-voicerate-fix.py aeonwave-fixed
cd aeonwave-fixed
nice -n 19 cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$HOME/builds/aeonwave-fixed-prefix \
  -DXML_INCLUDE_DIR=$HOME/builds/aeonwave-prefix/include -DXML_LIBRARY=$HOME/builds/aeonwave-prefix/lib64/libzeroxml.a
nice -n 19 cmake --build build -j3 --target aax
L=$HOME/builds/aeonwave-fixed-prefix/lib/aarch64-linux-gnu
mkdir -p "$L"
cp -P build/libaax.so build/libaax.so.4 build/libaax.so.4.0.0 "$L"/
ls -la "$L"
echo BUILT
