# fgfs-mga: one FlightGear launcher (ROCK 5B+, FG 2024.1, MGA at KEZM)

| File | What it is |
|---|---|
| `install-fgfs-mga.sh` | Paste-able installer. Installs `~/.local/bin/fgfs-mga`, turns old launchers and tools into shims, writes `~/.config/fgfs-mga/config` and a menu entry. `--dry-run`, `--keep-old`, `--tidy`, `--undo`. |
| `fgfs-audit.sh` | Paste-able, read-only. Lists every FlightGear launcher, alias, `.desktop` shortcut and fgfs build. Same as `fgfs-mga audit`. |
| `archive-downloads.sh` | Paste-able. Moves stale one-off FG files in `~/Downloads` into `~/Downloads/fg-archive-<date>/`. Deletes nothing. |
| `src/`, `build.sh`, `tests/test.sh` | Sources, build step, mock-board test (board layout from the Nov 21 audit; 116 checks pass). |

## Use

```
fgfs-mga                          # PA28-161-160 Warrior, balanced, KEZM, six add-ons
fgfs-mga seminole fast            # any fleet name + any preset, any order
fgfs-mga r44 training --aeonwave
fgfs-mga --build system           # /usr/local/bin/fgfs instead of the source build
fgfs-mga --telemetry --weather-in # UDP 5620 out / 5610 in (protocol XMLs must be in fgdata/Protocol)
fgfs-mga gui visual               # FlightGear's own launcher window (your fg-rock5b)
fgfs-mga list                     # aircraft, builds, tools, what's installed
fgfs-mga --dry-run                # print the full command, start nothing
```

Presets: fast, balanced, training (balanced + fixed calm noon VFR weather), high. Old names low, performance, medium, visual, quality also work.
Builds: source (`~/builds/flightgear/build`), aeonwave (`~/builds/flightgear-aeonwave-prefix`, then `build-aeonwave`), system (`/usr/local/bin/fgfs`).

## What each old name runs now

| Old name | Now |
|---|---|
| `fgfs-mga-training` | `fgfs-mga` |
| `fgfs-mga-training-aeonwave` | `fgfs-mga --build aeonwave` |
| `fgfs-mga-fleet` | `fgfs-mga` |
| `fg-rock5b` | `fgfs-mga gui` |
| `flightgear-edited-openal` | `fgfs-mga openal` |
| `fgfs-mga-controller-setup` | `fgfs-mga controller` |
| `fgfs-mga-joystick-test` | `fgfs-mga joystick-test` |
| `fgfs-mga-training-event-input` | `fgfs-mga event-input` |
| `fgfs-mga-update` | `fgfs-mga update` |
| `fgfs-mga-scenery-fleet-audit` | `fgfs-mga scenery-audit` |
| `aeonwave-output-test` | `fgfs-mga aeonwave-test` |

The training and fleet launchers are rebuilt inside fgfs-mga. The other eight are your own scripts: they're kept unchanged in `~/.local/share/fgfs-mga/tools/` and fgfs-mga runs them. Every original is also copied to `~/.local/share/fgfs-mga/backup-<time>/` first.

`--tidy` (optional, after you've used it a bit): points the `.desktop` shortcuts at fgfs-mga, moves the old-name shims and the three `fgfs-mga-training.bak*` files out of `~/.local/bin`. A name is kept if another script still calls it. `--undo` reverses the last step; run it again to go back further.

Left alone: `/usr/local/bin/fgfs` and the three system FlightGear menu entries (from the FlightGear install).

## Downloads

Archived by `archive-downloads.sh`: the old `fgfs-mga-training` copy (KCON + R44), `fg_aeonwave_3124_compat_build.sh`, `fg_aeonwave_3124_zeroxml_fix.sh`, `fg_aeonwave_audio_triage.sh` (all aimed at a `build-aeonwave-3124` folder that's no longer on the board), `fg_aircraft_launcher_cleanup.py`, `fg_aircraft_search_path_dedup.py`, `fg_aircraft_sweeper.py`, and the `cosmicindustries.github.io-*.log`.
Kept: the four `patch_launcher_*.py` (needed again if the FG source is reset), and `FG_INTEGRATION_README.md`, `fg_telemetry_out.xml`, `fg_weather_in.xml`.

## 1.2.0 (Nov 21)

- Add-ons: searched in `~/.fgfs/Addons`, `fgdata/Addons`, `~/.fgfs/FlightGear-2024.1-Addons-MGA` (so Logbook = v2.1.0, plus landing_rate and which-runway). One add-on per id. With `--launcher`, add-ons the launcher window already loads (its ini `[addon-modules]`) are skipped: that double load was the launcher crash, not FlightGear auto-loading.
- Photoscenery: `~/.fgfs/Scenery-Addons` goes first in the scenery path when it exists, and the overlay is switched on.
- Controls: `--input event` by default (this kernel has no joydev). `fgfs-mga controls wizard|scan|test|show|defaults` (src/fgfs-mga-controls, python3-evdev) writes `~/.fgfs/Input/Event/Saitek/fgfs-mga-<device>.xml` with the real FlightGear event names.
- Sound: ES8316 codec and fgfs stream unmuted once fgfs starts (from the old aeonwave launcher). AeonWave build gets its lib dir, PIPEWIRE_LATENCY and sound device; other builds reset the saved device name.
- Installer keeps an existing `fgfs-mga.desktop` (new ones open `--launcher`) and comments out the 1.1 `ADDONS=""` workaround.

## Sound fix (Nov 21, after 1.2.0)
- The desktop's default output is the Virtual Surround (KEMAR) sink, which feeds HDMI-1. FlightGear (AeonWave and OpenAL) opened 8 channels into it, at PipeWire's 256-frame buffer, and PipeWire runs without realtime priority here: hundreds of underruns a minute (the "timing errors").
- `AUDIO_SINK="auto"` now sends fgfs straight to the output a virtual-surround default feeds (`PULSE_SINK`). Set a sink name to pick one, or "" for the plain default.
- `AUDIO_QUANTUM=1024` raises the buffer only while fgfs plays (`PULSE_PROP=node.force-quantum`); PIPEWIRE_LATENCY never reached the PulseAudio stream.
- Still open: PipeWire realtime (add the user to the `pipewire` group, needs sudo), AeonWave 4.2.0 (board has a June 2025 4.1.0 snapshot).

## Not checked yet

- Not run on the board. The eight tools and the cleanup .py files weren't read, only seen in the audit list.
- Preset flags are standard FG 2024.1 options; their speed on the Mali GPU is untested. `fgfs-mga legacy` runs the original training launcher.
