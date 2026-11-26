# MGA fleet round: Arrow, Seminole, Decathlon, Citabria, AT-502B, AT-802

Rough FlightGear models for the MGA training fleet, built 2026-11-26 on the ROCK 5B+.
They are sized from published specs and tuned to book numbers, not detailed replicas.

| Launcher name | Aircraft | Folder / id | Flight model |
|---|---|---|---|
| `arrow` | Piper Arrow (PA-28R-201) | `PA28/PA28R-201` | JSBSim, PA28 FDM + IO-360 200 hp, constant-speed prop, retractable gear |
| `seminole` | Piper Seminole (PA-44-180) | `SenecaII/PA44-180` | JSBSim, Seneca FDM resized + O-360 180 hp x2, T-tail overlay |
| `decathlon` | American Champion 8KCAB Decathlon | `Cosmic-Decathlon/decathlon` | YASim, 180 hp, constant-speed |
| `citabria` | American Champion 7GCAA Citabria | `Cosmic-Citabria/citabria` | YASim, 150 hp, fixed pitch |
| `at502b` | Air Tractor AT-502B | `Cosmic-AT502B/at502b` | YASim, PT6A-34AG 750 shp |
| `at802` | Air Tractor AT-802 | `Cosmic-AT802/at802` | YASim, PT6A-67AG 1350 shp |

The Arrow and Seminole reuse the PA28 and SenecaII packages already on the board (cockpit, panel, sounds).
Their new files sit beside the originals; nothing in those packages is overwritten.

## Layout

- `src/` generators and the Arrow/Seminole XML. `build_round.py PA28_DIR SENECA_DIR STAGE` rebuilds all six into STAGE.
- `built/` the output of that build, ready to copy into `~/.fgfs/Aircraft`.
- `tools/` checks: `ac_info.py` (part bounding boxes), `ac_points.py` (point cloud), `fleetview.py`
  (three-view and the ground-clearance pitch sweep plots, needs matplotlib), `cg_tune.py` (YASim nose ballast
  to a target % MAC), `probe.py` + `test_start.sh` (60 s ground start at KEZM through fgfs-mga, one fgfs at a time).

## Install

    cp -rn built/* ~/.fgfs/Aircraft/

`-n` keeps any existing file. The launcher's fleet table (launcher/src/fgfs-mga) maps the short names above.

## How the planes were checked

- Axes: FlightGear reads AC files Y-up, so model (x aft, y right, z up) is written to AC as (x, z, -y).
- Ground-clearance pitch sweep: each model is pitched nose-up about the main wheels from 0 deg past the
  tail-down attitude, every part's height above ground checked at each step, side views plotted with any
  part below ground in red. Taildraggers sit on their tailwheel at 11-12.5 deg with the rudder clear;
  the rudder or tail cone reaches the ground only at about 14-16 deg. Arrow is clear to 16 deg; Seminole's
  tail cone reaches the ground at about 13-14 deg.
- JSBSim (Arrow, Seminole) flown offline in python-jsbsim 1.3.3:
  Arrow 2720 lb: 138 KTAS gear up at 6000 ft and 71% power, 124 KTAS gear down, about 710 fpm climb at Vy.
  Seminole 3730 lb: 155 KTAS at 5500 ft, about 1,070 fpm two-engine climb, 229 fpm single-engine with
  the dead prop feathered (book 212).
- YASim (four new planes): solved with the yasim tool from 2024.1.7. Wing and tail positions are mid-chord
  root points; nose ballast tuned so the CG sits at 27-28% MAC; approach elevator -0.3 to -0.5.
  YASim prints its "possible convergence problem" note for all four; that is its oscillation-damping
  heuristic kicking in, and each solution finished with sane numbers.

## Known gaps

- Seminole keeps the Seneca II cockpit, panel and airspeed markings.
- Arrow has no gear auto-extend system.
- The four YASim planes have simple cockpits (3D gauges from fgdata), no spray system, and were not
  flown against book climb or cruise numbers beyond the YASim solve.

## In-sim start at KEZM (2026-11-26, ROCK 5B+, fgfs-mga fast preset, 2024.1.7 build)

Each plane was started on the ground at KEZM through `fgfs-mga NAME fast`, one FlightGear at a time.
`tools/test_start2.sh` waits for scenery to load, then reads the properties 15 s and 35 s later.
The KEZM start spot has about 1.8 deg of roll in every aircraft, so that comes from the ground there.

| Plane | Pitch on ground | Wheels on ground | Engine at start | Notes |
|---|---|---|---|---|
| Arrow | 1.8 deg | all three, gear down and locked | off (cold start) | 2,280 lb loaded |
| Seminole | 0.8 deg | all three | off (cold start) | 3,168 lb loaded |
| Decathlon | 12.8 deg tail-down (design 12.5) | mains + tailwheel | off | 1,654 lb |
| Citabria | 12.5 deg tail-down (design 12) | mains + tailwheel | off | 1,347 lb |
| AT-502B | 12.0 deg tail-down (design 11.5) | mains + tailwheel | turbine running at idle, N2 70% | 5,710 lb |
| AT-802 | 11.5 deg tail-down (design 11) | mains + tailwheel | turbine running at idle, N2 70% | 7,715 lb |

No aircraft errors in the logs. Every start except the Arrow's also logged a canvas GUI error from fgdata
(`Nasal/canvas/gui/Widget.nas` line 153). It comes from the GUI layer, not from these aircraft files.
Not done yet: flying each plane against book climb and cruise numbers in the sim.
