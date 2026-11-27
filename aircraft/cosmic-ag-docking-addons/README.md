# Cosmic Ag docking demo: drone formations, sprayer / scout modes, retardant bag

Add-ons for the Cosmic Ag docking demo (mothership with two Remora drones,
FlightGear 2024.1). They hook into the demo's own drone script at run time and
do not change it.

## Formations (Ctrl-F while flying the mothership)

Ctrl-F steps through five formations for the drones that are out (release
them with Ctrl-K port / Ctrl-Y starboard). Either drone or both can lead or
follow:

| # | Port drone | Starboard drone |
|---|------------|-----------------|
| 0 | escort (beside you) | escort |
| 1 | scouts ahead | sprays behind |
| 2 | sprays behind | scouts ahead |
| 3 | scouts ahead | scouts ahead |
| 4 | sprays behind | sprays behind |

- **Scout (leading):** 40 m ahead of its latch, 10 m outboard, 5 m above it.
  No spray; the camera gimbal under the nose sweeps side to side and a green
  light blinks.
- **Spray (following):** 22 m behind its latch, 16 m outboard, level with it,
  clear of the mothership's wingtip vortex. Spray mist comes from a spray bar
  under the wing and the pod nozzle once the drone is within 8 m of its slot.
- The drones top out near 82 kt, so scouts can only stay ahead up to about
  75 kt. Fly formations at about 70 kt with 15 flaps.
- Recall (Ctrl-K / Ctrl-Y) from a scout or spray slot first brings the drone
  back alongside, then it docks as before.

## Retardant bag

A fabric bag of fire retardant cradled in the belly capture ring: about
1,060 L, roughly 1,150 kg full. It is drawn only; the flight model does not
carry its weight. Sitting on the tailwheel (11 deg nose-up) the dump valve
clears the ground by 0.17 m (the demo's `ground_test.py`; at 13 deg, which
the tailwheel doesn't allow, it would still clear by 0.08 m). Hide it with
`/cosmic/no-bag=1`.

## Files

- `cosmic_modes.nas`: formation modes (goes in `$FG_ROOT/Nasal/`).
- `gen_formation_addons.py`: builds `remora-modes.ac` and `retardant-bag.ac`
  with the primitives of the demo's `generate_models_v2.py`.
- `remora-modes.xml`, `retardant-bag.xml`: model wrappers (spray particles,
  gimbal sweep, bag).
- `install-formation-modes.sh`: installs into the demo project
  (`Scripts/formation-addons/`) and fgdata, adds one-line hooks to the drone
  wrappers, `mothership.xml` and the Ctrl-F key, with backups. Idempotent.
- `test_formation_modes.sh`, `test_modes_run.nas`: offline test in the
  standalone `nasal` interpreter, with the real drone script.
- `board_test_modes.sh`: sim test on the board (screenshots and logs in /tmp).

The docking demo itself (mothership, drones, drone script) is not in this
repository yet; these files need it installed.

## Sim test (2026-11-26, ROCK 5B+, 70 kt, 15 flaps, 50 ft AGL)

All four formations held their slots within about 1 m; spray and scout
switched on as they should. Recall: both drones latched (port on its 2nd try,
starboard on its 4th; the hook retries at 70 kt also happen without these
add-ons). Screenshots in `screenshots/`.
