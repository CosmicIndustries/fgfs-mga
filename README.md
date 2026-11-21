# fgfs-mga

FlightGear 2024.1.7 set up for flight-training practice on a ROCK 5B+ (RK3588, aarch64, Debian/Armbian), flying the Middle Georgia State aviation fleet out of KEZM.

## What's here

| Folder | What it holds |
|---|---|
| `launcher/` | `fgfs-mga`, one launcher for every aircraft, preset and build. It handles the Saitek sticks and force feedback, sound routing and add-ons, and tunes COM1/COM2 for the start airport. Also `fgfs-mga controls gui` (the Qt controls window), its tests and the paste-able installer `install-fgfs-mga.sh`. See `launcher/README.md`. |
| `flightgear-2024.1.7/` | The script that builds SimGear and FlightGear 2024.1.7 twice, once with OpenAL and once with AeonWave sound. Also the local patches on top of the 2024.1.7 tags (the MGA training page and region map in the Qt launcher, and the sound fixes), and the same changes against 2024.1.1. |
| `aeonwave/` | Fixes to the AeonWave sound library (adalinbv/aax): the NEON mixer that muted 3D sounds, the WAV reader that crashed on tagged files, voice clips that played 2.4x slow (ring buffer kept at 20 kHz), and the C++ buffer cache that destroyed each buffer twice. |
| `simgear/` | SimGear AeonWave sound-manager fixes for Red Griffin ATC voices: a released source counts as stopped, so there's no "unknown source id" flood, and the mixer stops cleanly at exit. |
| `ffb-driver/` | Force feedback for the Saitek Cyborg Evo Force on a kernel without `CONFIG_HID_PID`. The scripts build a patched [universal-pidff](https://github.com/JacKeTUs/universal-pidff) module and load it at boot, plus stick and effect tests. |

## Quick start (on the board)

```
bash launcher/install-fgfs-mga.sh
fgfs-mga --aeonwave          # FlightGear 2024.1.7 with AeonWave sound, PA28-161 Warrior at KEZM
fgfs-mga --old               # the older 2024.1.1 build, if the new one misbehaves
fgfs-mga controls gui        # stick setup: dead zones, curves, limits, force feedback
```

## Release binaries

The release has `fgfs` 2024.1.7 built on the board, an OpenAL build and an AeonWave build, plus the fixed `libaax.so.4.0.0`. They need the same Debian/Armbian aarch64 libraries as the board: OpenSceneGraph 3.6, Qt 5 and the system OpenAL. Run the AeonWave build with the fixed `libaax` on `LD_LIBRARY_PATH`; `fgfs-mga` does this for you.

## License

GPL-2.0-or-later (see `LICENSE`). FlightGear and SimGear are GPL-licensed, as is the Linux HID force-feedback code the driver patch builds on. AeonWave keeps its own licence (see the COPYING files in its source). The patches here, plus the upstream commits named in each folder's `UPSTREAM.txt`, are the source for the release binaries.
