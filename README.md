# fgfs-mga

FlightGear 2024.1.7 set up for flight-training practice on a ROCK 5B+ (RK3588, aarch64, Debian/Armbian), flying the Middle Georgia State aviation fleet out of KEZM.

## What's here

| Folder | What it holds |
|---|---|
| `launcher/` | `fgfs-mga`, one launcher for every aircraft, preset and build. It handles the Saitek sticks and force feedback, sound routing and add-ons, and tunes COM1/COM2 for the start airport. Also `fgfs-mga controls gui` (the Qt controls window), its tests and the paste-able installer `install-fgfs-mga.sh`. See `launcher/README.md`. |
| `flightgear-2024.1.7/` | The script that builds SimGear and FlightGear 2024.1.7 twice, once with OpenAL and once with AeonWave sound. Also the local patches on top of the 2024.1.7 tags (the MGA training page and region map in the Qt launcher, the Controls page, full Settings and Environment pages, the Location map overlay and the Before you fly panel, and the sound fixes), and the same changes against 2024.1.1. |
| `aeonwave/` | Fixes to the AeonWave sound library (adalinbv/aax): the NEON mixer that muted 3D sounds, and the WAV reader that crashed on tagged files. (A first fix for Red Griffin voices playing 2.4x slow left FlightGear silent and was withdrawn; the slow voice is still open.) |
| `simgear/` | SimGear AeonWave sound-manager fixes for Red Griffin ATC voices: a released source counts as stopped, so there's no "unknown source id" flood, and the mixer stops cleanly at exit. |
| `ffb-driver/` | Force feedback for the Saitek Cyborg Evo Force on a kernel without `CONFIG_HID_PID`. The scripts build a patched [universal-pidff](https://github.com/JacKeTUs/universal-pidff) module and load it at boot, plus stick and effect tests. |

## Quick start: a fresh board

On a ROCK 5B / RK3588 running Debian 12 or Armbian bookworm (aarch64):

```
git clone https://github.com/CosmicIndustries/fgfs-mga.git
bash fgfs-mga/install.sh --all
```

That's the whole install, and it needs no sudo. It puts in the `fgfs-mga` launcher and a "FlightGear MGA" menu entry, the stick, sound and scenery tools, the launcher add-on (start state, crash reset, auto mixture) and the ROCK 5B performance profiles. `--all` also downloads the FlightGear 2024.1.7 MGA builds from this repo's release (checked against `SHA256SUMS`) and the official FlightGear 2024.1.7 data (1.9 GB). Anything it replaces is backed up first, and `bash fgfs-mga/install.sh --undo` puts it back. `--dry-run` shows what it would do.

If system libraries are missing, it ends by printing one `sudo apt install ...` line to run. Aircraft beyond FlightGear's defaults, like the MGA fleet, are installed from the launcher's Aircraft page. Your own builds in `~/builds/flightgear-2024.1.7` always win over the release ones.

What's where once it's installed:

| Path | What |
|---|---|
| `~/.local/bin/fgfs-mga` | the launcher (`fgfs-mga --launcher` opens FlightGear's launcher window with the MGA pages) |
| `~/.local/share/fgfs-mga/tools/` | the tools behind `fgfs-mga gui`, `controller`, `controls`, `ffb`, `joystick-test`, `event-input`, `update`, `scenery-audit`, `aeonwave-test`, plus the TerraSync and ArcGIS scenery downloaders and `fgfs-mga-photo-dds` (compressed photo scenery) |
| `~/.fgfs/fgfs-mga-addons/mga-launcher-extras/` | the add-on the launcher's Assists & start state options use |
| `~/.fgfs/FlightGear-2024.1-Addons-MGA/mga-checklist/` | the in-flight checklist (Ctrl-K, or the Checklist menu): lines go green as you set each control |
| `~/.config/fgfs-mga/config` | your settings (never overwritten) |
| `~/.config/flightgear-rock5b/` | the low / balanced / visual / performance profiles for `fgfs-mga gui` |

## Everyday use

```
bash install.sh              # or just the launcher: bash launcher/install-fgfs-mga.sh
fgfs-mga --aeonwave          # FlightGear 2024.1.7 with AeonWave sound, PA28-161 Warrior at KEZM
fgfs-mga --old               # the older 2024.1.1 build, if the new one misbehaves
fgfs-mga controls gui        # stick setup: dead zones, curves, limits, force feedback
```

## Release binaries

The release has `fgfs` 2024.1.7 built on the board, an OpenAL build and an AeonWave build, plus the fixed `libaax.so.4.0.0`. They need the same Debian/Armbian aarch64 libraries as the board: OpenSceneGraph 3.6, Qt 6 and the system OpenAL. Run the AeonWave build with the fixed `libaax` on `LD_LIBRARY_PATH`; `fgfs-mga` does this for you.

## License

GPL-2.0-or-later (see `LICENSE`). FlightGear and SimGear are GPL-licensed, as is the Linux HID force-feedback code the driver patch builds on. AeonWave keeps its own licence (see the COPYING files in its source). The patches here, plus the upstream commits named in each folder's `UPSTREAM.txt`, are the source for the release binaries.
