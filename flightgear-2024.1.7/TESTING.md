# Optional upstream test suites

The default build remains optimized for the memory-constrained ROCK 5B+ and does not build or run the upstream SimGear/FlightGear test suites.

To opt in, supply a FlightGear data directory and set `MGA_ENABLE_TESTS=1`:

```bash
MGA_ENABLE_TESTS=1 \
FG_ROOT="$HOME/.fgfs/fgdata_2024_1" \
JOBS=2 bash ~/builds/fg-2024.1.7/build.sh
```

- SimGear is configured with `ENABLE_TESTS=ON`; CTest runs after each SimGear variant builds.
- FlightGear's separate `test_suite` target is built explicitly, then CTest runs with `FG_ROOT` set.
- `FG_ROOT` must identify a FlightGear data tree containing a `version` file. Override the default path when your data is installed elsewhere.
- `ENABLE_AUTOTESTING` remains OFF in generated FlightGear init caches so test execution happens explicitly through CTest rather than being hidden inside a build target.
- The default `MGA_ENABLE_TESTS=0` path does not invoke CTest or build the FlightGear test suite.

Tests increase build time, disk use, and memory pressure. Run them when the board has adequate free storage and swap headroom.
