#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016  # test helpers use a && b || c on purpose
# Mock-board test: fake HOME laid out like the board's audit output, fake fgfs that prints its args.
# Usage: bash tests/test.sh   (from the flightgear-launcher folder; run build.sh first)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; export PATH="$HOME/.local/bin:/usr/bin:/bin"
FAIL=0; N=0
ok()   { N=$((N+1)); echo "PASS  $*"; }
bad()  { N=$((N+1)); echo "FAIL  $*"; FAIL=1; }
has()  { grep -qF -- "$2" <<<"$1" && ok "$3" || { bad "$3"; echo "----- output:"; echo "$1" | head -60; }; }
hasnt(){ grep -qF -- "$2" <<<"$1" && { bad "$3"; echo "$1" | head -60; } || ok "$3"; }
snap() { find "$HOME" -exec stat -c '%n %s %Y' {} + 2>/dev/null | sort | md5sum; }

# ---- fake board (from the Nov 21 audit) ----
mk_fgfs() { mkdir -p "$(dirname "$1")"; printf '#!/bin/bash\necho "FGFS(%s) FG_HOME=$FG_HOME LD=${LD_LIBRARY_PATH:-}"; for a in "$@"; do echo "ARG $a"; done\n' "$2" > "$1"; chmod +x "$1"; }
mk_fgfs "$HOME/builds/flightgear/build/src/Main/fgfs" source
mk_fgfs "$HOME/builds/flightgear/build-aeonwave/src/Main/fgfs" aeon-build
mk_fgfs "$HOME/builds/flightgear-aeonwave-prefix/bin/fgfs" aeon-prefix
mkdir -p "$HOME/builds/flightgear-aeonwave-prefix/lib"
mkdir -p "$HOME/builds/aeonwave-fixed-prefix/lib/aarch64-linux-gnu"
mk_fgfs "$T/sys/fgfs" system
R="$HOME/.fgfs/fgdata_2024_1"; mkdir -p "$R/Scenery" "$R/Protocol" "$HOME/.fgfs/TerraSync"
touch "$R/Protocol/fg_telemetry_out.xml"
for a in ATCChatter SpokenATC SpokenGCA PAR Logbook; do mkdir -p "$R/Addons/$a"; printf '<identifier type="string"> org.fg.%s</identifier>\n' "$a" > "$R/Addons/$a/addon-metadata.xml"; done
mkdir -p "$HOME/.fgfs/Addons/Logbook-v2.1.0"; echo '<identifier>org.fg.Logbook</identifier>' > "$HOME/.fgfs/Addons/Logbook-v2.1.0/addon-metadata.xml"
for a in landing_rate which-runway; do mkdir -p "$HOME/.fgfs/FlightGear-2024.1-Addons-MGA/$a"; echo "<identifier>org.fg.$a</identifier>" > "$HOME/.fgfs/FlightGear-2024.1-Addons-MGA/$a/addon-metadata.xml"; done
mkdir -p "$HOME/.fgfs/FlightGear" "$HOME/.fgfs/Scenery-Addons/Orthophotos"
printf '[General]\nx=1\n\n[addon-modules]\n1\\enable=true\n1\\path=%s\n2\\enable=false\n2\\path=%s\nsize=2\n' "$HOME/.fgfs/Addons/Logbook-v2.1.0" "$R/Addons/PAR" > "$HOME/.fgfs/FlightGear/FlightGear_2024.1.ini"
mkdir -p "$R/Addons/RedGriffinATC/trunk"; touch "$R/Addons/RedGriffinATC/trunk/addon-metadata.xml"
A="$HOME/.fgfs/Aircraft"
mkdir -p "$A/PA28" "$A/R44" "$A/R22" "$A/SenecaII" "$A/Cessna337"
touch "$A/PA28/PA28-161-160-set.xml" "$A/PA28/PA28-161-180-set.xml" "$A/R44/raven-set.xml" \
      "$A/R22/R22-set.xml" "$A/SenecaII/SenecaII-set.xml" "$A/Cessna337/Cessna337-set.xml"
# a plane installed from the launcher's Aircraft page (package catalog), with no link in $A
CAT="$A/org.flightgear.fgaddon.stable_2024"; mkdir -p "$CAT/Aircraft/J3Cub"; touch "$CAT/catalog.xml" "$CAT/Aircraft/J3Cub/PA-18-set.xml"
B="$HOME/.local/bin"; AP="$HOME/.local/share/applications"; DT="$HOME/Desktop"; DL="$HOME/Downloads"
mkdir -p "$B" "$AP" "$DT" "$DL"
cat > "$B/fgfs-mga-training" <<'EOF'
#!/usr/bin/env bash
# fgfs-mga-training - MGA training launcher for Rock 5B
# Drop this at ~/.local/bin/fgfs-mga-training and chmod +x
FGFS=/home/radxa/builds/flightgear/build/src/Main/fgfs
ADDONS=/home/radxa/.fgfs/fgdata_2024_1/Addons
ARGS=(
    --airport=KEZM
    --aircraft=PA28-161-160
    --timeofday=noon
    --addon="${ADDONS}/ATCChatter"
)
echo "ORIGINAL TRAINING $*"
EOF
cat > "$B/fgfs-mga-training-aeonwave" <<'EOF'
#!/usr/bin/env bash
BIN="${FG_TEST_BIN:-$HOME/builds/flightgear-aeonwave-prefix/bin/fgfs}"
#  --help|-h) echo 'Usage: fgfs-mga-training [balanced|performance|low] [extra fgfs options]'; exit 0 ;;
echo "ORIGINAL AEONWAVE $*"
EOF
printf '#!/bin/bash\n# fgfs-mga-fleet <type>\nBASE="$HOME/.local/bin/fgfs-mga-training"\necho old fleet\n' > "$B/fgfs-mga-fleet"
for n in fg-rock5b flightgear-edited-openal fgfs-mga-controller-setup fgfs-mga-training-event-input fgfs-mga-update fgfs-mga-scenery-fleet-audit aeonwave-output-test; do
  printf '#!/bin/bash\n# uses fgfs\necho "TOOL %s $*"\n' "$n" > "$B/$n"
done
# the joystick test calls the training launcher by its old name
printf '#!/bin/bash\n# uses fgfs\nfgfs-mga-training fast\necho "TOOL fgfs-mga-joystick-test $*"\n' > "$B/fgfs-mga-joystick-test"
echo old > "$B/fgfs-mga-training.bak"; echo old > "$B/fgfs-mga-training.bak-joystick-20261019-084927"
chmod +x "$B"/*
printf '[Desktop Entry]\nName=FlightGear - Edited OpenAL Build\nExec=%s/flightgear-edited-openal\n' "$B" > "$AP/flightgear-edited-openal.desktop"
printf '[Desktop Entry]\nName=FlightGear MGA Source Updater\nExec=%s/fgfs-mga-update build\n' "$B" > "$AP/flightgear-mga-source-updater.desktop"
printf '[Desktop Entry]\nName=FlightGear MGA Controller Setup\nExec=%s/fgfs-mga-controller-setup\n' "$B" > "$DT/FlightGear MGA Controller Setup.desktop"
printf '#!/bin/bash\n--airport=KCON\n--aircraft=R44\nfgfs\n' > "$DL/fgfs-mga-training"
for n in fg_aeonwave_3124_compat_build.sh fg_aircraft_sweeper.py patch_launcher_live_weather.py fg_weather_in.xml cosmicindustries.github.io-1792846064701.log; do echo x > "$DL/$n"; done

cd "$ROOT" || exit 1
for f in src/fgfs-mga src/install-body.sh install-fgfs-mga.sh fgfs-audit.sh archive-downloads.sh build.sh; do bash -n "$f" && ok "bash -n $f" || bad "bash -n $f"; done
SC="$(PATH="$PATH:/usr/local/bin" command -v shellcheck || true)"
if [[ -n "$SC" ]]; then "$SC" src/fgfs-mga src/install-body.sh build.sh tests/test.sh && "$SC" -s bash archive-downloads.sh && ok "shellcheck clean" || bad "shellcheck"; fi

# ---- audit (read-only) ----
before="$(snap)"
out="$(bash fgfs-audit.sh 2>&1)"
has "$out" "SCRIPT    $B/fg-rock5b" "audit lists fg-rock5b"
has "$out" "fgfs-mga-training.bak-joystick" "audit lists .bak launchers"
has "$out" "flightgear-edited-openal.desktop" "audit lists .desktop entry"
has "$out" "flightgear-aeonwave-prefix/bin/fgfs" "audit lists fgfs builds"
[[ "$before" == "$(snap)" ]] && ok "audit changed nothing" || bad "audit changed files"

# ---- installer dry runs change nothing ----
out="$(bash install-fgfs-mga.sh --dry-run 2>&1)"
has "$out" "aircraft=PA28-161-160 airport=KEZM" "installer reads live launcher defaults"
has "$out" "make it run: fgfs-mga gui" "dry run plans fg-rock5b -> gui"
out="$(bash install-fgfs-mga.sh --dry-run --tidy 2>&1)"; has "$out" "DRY RUN" "tidy dry run"
[[ "$before" == "$(snap)" ]] && ok "dry runs changed nothing" || bad "dry run changed files"

# ---- install, piped the way a paste arrives ----
out="$(bash < install-fgfs-mga.sh 2>&1)"
has "$out" "Installed $B/fgfs-mga" "install"
has "$out" "fgfs-mga-training-aeonwave ; it now runs: fgfs-mga --build aeonwave" "aeonwave launcher shim"
has "$out" "fgfs-mga-update ; it now runs: fgfs-mga update" "tool shim"
bk="$(ls -d "$HOME"/.local/share/fgfs-mga/backup-*)"
[[ -f "$bk/fgfs-mga-training" && -f "$bk/fg-rock5b" && -f "$HOME/.local/share/fgfs-mga/tools/fg-rock5b" ]] && ok "backups and tool copies" || bad "backups"
grep -q 'DEFAULT_AIRCRAFT="PA28-161-160"' "$HOME/.config/fgfs-mga/config" && ok "config default aircraft" || bad "config aircraft"
echo "FGFS_BIN_SYSTEM=\"$T/sys/fgfs\"" >> "$HOME/.config/fgfs-mga/config"

# ---- launcher ----
out="$(fgfs-mga -n 2>&1)"
has "$out" "--aircraft=PA28-161-160" "default aircraft from old launcher"
has "$out" "--airport=KEZM" "airport KEZM"
has "$out" "RedGriffinATC/trunk" "nested add-on found"
has "$out" "Addons/Logbook-v2.1.0" "newer Logbook picked"; hasnt "$out" "fgdata_2024_1/Addons/Logbook" "only one Logbook"
has "$out" "Addons-MGA/which-runway" "MGA add-on loaded"
has "$out" "no-event-input=false" "event input on"; has "$out" "photoscenery/enabled=true" "photoscenery on"
has "$out" "fg-scenery=$HOME/.fgfs/Scenery-Addons:" "photoscenery path first"; hasnt "$out" "sound/device-name=" "no empty device option (fgfs stops at --prop:x=)"
out="$(OPENAL_DEVICE_TEST=1 fgfs-mga --prop:/sim/foo= -n 2>&1)"; has "$out" "left out --prop:/sim/foo" "empty --prop is dropped with a warning"; hasnt "$out" "/sim/foo= " "and not passed"; hasnt "$out" "/sim/foo= \\" "and not passed (line form)"
out="$(fgfs-mga --launcher -n 2>&1)"
hasnt "$out" "Logbook" "launcher window's add-on not doubled"; has "$out" "Addons/PAR" "disabled launcher add-on still passed"
has "$out" "SpokenATC" "other add-ons passed with --launcher"
out="$(fgfs-mga --input off --no-photoscenery -n 2>&1)"; has "$out" "no-event-input=true" "input off"; hasnt "$out" "photoscenery/enabled" "no-photoscenery"
out="$(fgfs-mga -n 2>&1)"; has "$out" "no 2024.1.7 build" "missing 2024.1.7 build: warns"; has "$out" "flightgear/build/src/Main/fgfs" "and falls back to the older build"
mk_fgfs "$HOME/builds/flightgear-2024.1.7/build/src/Main/fgfs" new-source; mk_fgfs "$HOME/builds/flightgear-2024.1.7/build-aeonwave/src/Main/fgfs" new-aeon
out="$(fgfs-mga -n 2>&1)"; has "$out" "flightgear-2024.1.7/build/src/Main/fgfs" "2024.1.7 is the default build"
out="$(fgfs-mga --aeonwave -n 2>&1)"; has "$out" "flightgear-2024.1.7/build-aeonwave/src/Main/fgfs" "2024.1.7 AeonWave is the default AeonWave build"
out="$(fgfs-mga --aeonwave --old -n 2>&1)"; has "$out" "flightgear-aeonwave-prefix/bin/fgfs" "--old goes back to the older AeonWave build"
out="$(fgfs-mga --old -n 2>&1)"; has "$out" "flightgear/build/src/Main/fgfs" "--old goes back to the older build"
# ---- radios tuned from apt.dat (Red Griffin ATC needs a station on COM1/COM2) ----
printf '%s\n' "1000 Version" "1      304 0 1 KEZM HEART OF GEORGIA RGNL" "50 11942 AWOS 3" "51 12300 CTAF/UNICOM" \
  "55 11960 ATLANTA APP/DEP" "55 12420 ATLANTA APP/DEP" "1    1000 1 0 KMCN MIDDLE GEORGIA RGNL" "1050 126575 ATIS" \
  "1054 119300 TWR" "1053 121900 GND" "1055 119600 APP" "99" | gzip > "$R/Airports-apt.tmp"; mkdir -p "$R/Airports"; mv "$R/Airports-apt.tmp" "$R/Airports/apt.dat.gz"
out="$(fgfs-mga -n 2>&1)"; has "$out" "--com1=123.000" "COM1 tuned to KEZM CTAF"; has "$out" "--com2=119.600" "COM2 tuned to KEZM approach"; has "$out" "COM1=123.000 COM2=119.600" "radios in summary"
out="$(fgfs-mga --airport KMCN -n 2>&1)"; has "$out" "--com1=119.300" "new-format apt.dat: tower first"; has "$out" "--com2=119.600" "new-format apt.dat: approach"
out="$(fgfs-mga --no-tune -n 2>&1)"; hasnt "$out" "--com1=" "--no-tune leaves radios alone"
out="$(fgfs-mga --com1=122.8 -n 2>&1)"; hasnt "$out" "--com1=123.000" "own --com1 wins"; has "$out" "--com1=122.8" "own --com1 passed"
before="$(snap)"; fgfs-mga -n >/dev/null 2>&1; [[ "$before" == "$(snap)" ]] && ok "radio lookup in a dry run writes no cache" || bad "dry run wrote the radio cache"
hasnt "$out" "--fg-home" "no --fg-home flag"
out="$(fgfs-mga fast seminole --runway 20 --fps --prop:/foo=1 -n 2>&1)"
has "$out" "--aircraft=SenecaII" "fleet name"; has "$out" "--fog-fastest" "preset fast"; has "$out" "--prop:/foo=1" "pass-through flag"
out="$(fgfs-mga-training-aeonwave performance -n 2>&1)"
has "$out" "flightgear-2024.1.7/build-aeonwave/src/Main/fgfs" "aeonwave picks the 2024.1.7 build first"
has "$out" "flightgear-aeonwave-prefix/lib" "aeonwave library path"; has "$out" "LD_LIBRARY_PATH=$HOME/builds/aeonwave-fixed-prefix/lib/aarch64-linux-gnu" "aeonwave uses the NEON-fixed library first"; hasnt "$out" "AAX_NO_SIMD_SUPPORT" "aeonwave keeps NEON on"; has "$out" "--sound-device=PulseAudio" "aeonwave sound device"; has "$out" "PIPEWIRE_LATENCY=1024" "aeonwave latency"; has "$out" "PULSE_PROP=node.force-quantum=1024" "stream quantum 1024"; has "$out" "preset performance" "old preset name performance"
# ---- sound routing: a virtual-surround default sink is skipped for the output it feeds ----
cat > "$B/pactl" <<'PEOF'
#!/bin/bash
case "$*" in
  get-default-sink) echo "${FAKE_DEFAULT:-effect_input.virtual-surround-kemar}" ;;
  "list sink-inputs") printf 'Sink Input #35\n\tDriver: PipeWire\n\tSink: 68\n\tProperties:\n\t\tnode.name = "effect_output.virtual-surround-kemar"\n' ;;
  "list short sinks") printf '34\teffect_input.virtual-surround-kemar\tPipeWire\n68\talsa_output.platform-hdmi1-sound.pro-output-0\tPipeWire\n' ;;
esac
PEOF
chmod +x "$B/pactl"
out="$(fgfs-mga --aeonwave -n 2>&1)"; has "$out" "PULSE_SINK=alsa_output.platform-hdmi1-sound.pro-output-0" "virtual surround skipped for its real output"
has "$out" "sound to alsa_output.platform-hdmi1" "sound output named in the summary"
out="$(FAKE_DEFAULT=alsa_output.usb-dac fgfs-mga -n 2>&1)"; hasnt "$out" "PULSE_SINK=" "plain default sink left alone"
rm -f "$B/pactl"
out="$(fgfs-mga -n 2>&1)"; has "$out" "--disable-developer" "developer alerts off by default"
out="$(fgfs-mga r44 --build system --telemetry --weather-in -n 2>&1)"
has "$out" "$T/sys/fgfs" "system build"; has "$out" "--aircraft=raven" "r44"
has "$out" "fg_telemetry_out" "telemetry socket"; has "$out" "fg_weather_in.xml isn't in" "missing protocol warned"
out="$(fgfs-mga-fleet c337 balanced -n 2>&1)"; has "$out" "--aircraft=Cessna337" "old fleet name"
out="$(fg-rock5b visual 2>&1)"; has "$out" "TOOL fg-rock5b visual" "fg-rock5b still runs original via gui"
out="$(fgfs-mga update build 2>&1)"; has "$out" "TOOL fgfs-mga-update build" "fgfs-mga update"
out="$(fgfs-mga-controller-setup 2>&1)"; has "$out" "TOOL fgfs-mga-controller-setup" "controller shim"
out="$(fgfs-mga warrior quality --no-addons 2>&1)"; has "$out" "ARG --aircraft=PA28-161-160" "real run execs fgfs"; hasnt "$out" "--addon=" "--no-addons"
out="$(fgfs-mga pa18 --no-addons 2>&1)"; has "$out" "ARG --aircraft-dir=$CAT/Aircraft/J3Cub" "pa18 found in the package catalog folder"
out="$(fgfs-mga list 2>&1)"; has "$out" "fgfs-mga update" "list shows tools"; has "$out" "fgfs-mga controls" "controls tool listed"
python3 -m py_compile "$HOME/.local/share/fgfs-mga/tools/fgfs-mga-controls" && ok "controls tool installed" || bad "controls tool"
grep -q 'Exec=.*fgfs-mga --launcher' "$AP/fgfs-mga.desktop" && ok "menu entry opens the launcher window" || bad "menu entry Exec";
grep -q '^Exec=.*fgfs-mga controls gui$' "$AP/fgfs-mga.desktop" && grep -q '^Actions=controls;' "$AP/fgfs-mga.desktop" && ok "menu entry has a Controls action" || bad "Controls action"
o2="$(env -u DISPLAY fgfs-mga warrior 2>&1)"; has "$o2" "Controls check:" "start warns when the sticks aren't set up"; has "$o2" "FGFS(" "and still starts FlightGear"
o2="$(fgfs-mga -n warrior 2>&1)"; [[ "$o2" != *"Controls check"* ]] && ok "dry run skips the controls check" || bad "dry run ran the check"
o3="$(fgfs-mga -n 2>&1)"; hasnt "$o3" "fgfs-mga-ffb" "no force feedback when the Evo has no FF driver (FFB=auto)"
o3="$(fgfs-mga --ffb -n 2>&1)"; has "$o3" "5630\,udp\,fgfs-mga-ffb" "--ffb sends FlightGear's data to the bridge"; has "$o3" "force feedback" "summary says force feedback is on"
[[ -x "$HOME/.local/share/fgfs-mga/tools/fgfs-mga-ffb" && -f "$HOME/.local/share/fgfs-mga/tools/fgfs-mga-ffb.xml" ]] && ok "force feedback bridge installed" || bad "ffb tool install"
o3="$(fgfs-mga ffb show 2>&1)"; has "$o3" "master" "fgfs-mga ffb show prints the settings"
python3 "$ROOT/tests/ffb_test.py" >/dev/null 2>&1 && ok "force feedback bridge (tests/ffb_test.py)" || bad "ffb bridge: run python3 tests/ffb_test.py"
 has "$out" "aeonwave  yes" "list shows builds"
out="$(fgfs-mga legacy aeonwave x 2>&1)"; has "$out" "ORIGINAL AEONWAVE x" "legacy aeonwave"
out="$(fgfs-mga legacy 2>&1)"; has "$out" "ORIGINAL TRAINING" "legacy training"

# ---- re-run, tidy, undo ----
sed -i '/^Actions=/d; /^\[Desktop Action controls\]/,$d' "$AP/fgfs-mga.desktop"   # an entry from before Controls existed
out="$(bash install-fgfs-mga.sh 2>&1)"; has "$out" "Already a shim: fgfs-mga-training" "re-run safe"; has "$out" "Kept your existing config" "config kept"
has "$out" "added a Controls action" "re-run adds Controls to an older menu entry"
grep -q '^Exec=.*fgfs-mga --launcher$' "$AP/fgfs-mga.desktop" && grep -q '^Actions=controls;' "$AP/fgfs-mga.desktop" && [[ $(grep -c 'Desktop Action controls' "$AP/fgfs-mga.desktop") == 1 ]] && ok "older entry keeps --launcher, gets one action" || bad "older entry upgrade"

out="$(bash install-fgfs-mga.sh --tidy 2>&1)"
has "$out" "now runs: fgfs-mga openal" "tidy points .desktop at fgfs-mga"
grep -q "^Exec=$B/fgfs-mga update build$" "$AP/flightgear-mga-source-updater.desktop" && ok "desktop Exec keeps its argument" || bad "desktop Exec"
has "$out" "kept fgfs-mga-training (still called by: fgfs-mga-joystick-test)" "tidy keeps names still in use"
has "$out" "removed old name fg-rock5b" "tidy removes unused names"
[[ ! -e "$B/fgfs-mga-training.bak" && -e "$B/fgfs-mga-training" ]] && ok "tidy moved .bak files" || bad "tidy bak"
out="$(fgfs-mga gui low 2>&1)"; has "$out" "TOOL fg-rock5b low" "gui works after tidy"
out="$(fgfs-mga-update 2>&1)"; has "$out" "not found" "old name gone after tidy"
out="$(bash install-fgfs-mga.sh --undo 2>&1)"
has "$out" "restored $B/fg-rock5b" "undo tidy restores shims"
[[ -e "$B/fgfs-mga-training.bak" ]] && grep -q "^Exec=$B/fgfs-mga-update build" "$AP/flightgear-mga-source-updater.desktop" && [[ -x "$B/fgfs-mga" ]] && ok "undo tidy: .bak + desktop back, fgfs-mga stays" || bad "undo tidy"
out="$(bash install-fgfs-mga.sh --undo 2>&1)"      # each run is one undo step: this one is the re-run
has "$out" "restored $AP/fgfs-mga.desktop" "undo the re-run puts the older menu entry back"
out="$(bash install-fgfs-mga.sh --undo 2>&1)"
grep -q 'ORIGINAL TRAINING' "$B/fgfs-mga-training" && grep -q 'TOOL fg-rock5b' "$B/fg-rock5b" && ok "second undo restores originals" || bad "second undo"
[[ ! -e "$B/fgfs-mga" ]] && ok "fgfs-mga removed by full undo" || bad "full undo removal"

# ---- Downloads archive ----
out="$(sed 's/^DRY=0 bash/DRY=1 bash/' archive-downloads.sh | bash 2>&1)"; has "$out" "would move: $DL/fg_aircraft_sweeper.py" "archive dry run"
out="$(bash archive-downloads.sh 2>&1)"
has "$out" "moved: fgfs-mga-training" "archive moves stale copy"
[[ -f "$DL/patch_launcher_live_weather.py" && -f "$DL/fg_weather_in.xml" && ! -e "$DL/fg_aircraft_sweeper.py" ]] && ok "archive keeps patches and protocol files" || bad "archive selection"

python3 "$ROOT/tests/controls_test.py" >/dev/null 2>&1 && ok "controls wizard walk-through (tests/controls_test.py)" || bad "controls wizard walk-through: run python3 tests/controls_test.py"
echo; echo "$N checks"; (( FAIL )) && { echo "SOME TESTS FAILED"; exit 1; } || echo "ALL TESTS PASSED"
