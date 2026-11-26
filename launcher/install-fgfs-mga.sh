# fgfs-mga installer: one FlightGear launcher for the MGA setup on the ROCK 5B+.
# Paste this whole block into a terminal on the board, or save it and run:
#   bash install-fgfs-mga.sh --dry-run     (look first)
#   bash install-fgfs-mga.sh               (install)
#   bash install-fgfs-mga.sh --undo        (put the old launchers back)
# To dry-run a paste, change the next line to:  bash -s -- --dry-run "$@" <<'__FGFS_MGA_INSTALL__'
bash -s -- "$@" <<'__FGFS_MGA_INSTALL__'
# Installs fgfs-mga and turns the old FlightGear launchers into small shims that call it.
# Old launchers are copied to ~/.local/share/fgfs-mga/backup-<time>/ first. Nothing is deleted.
#
#   --dry-run    show what would happen, change nothing
#   --keep-old   install fgfs-mga but leave the old launchers exactly as they are
#   --tidy       also: move the old-name shims and the *.bak launchers out of ~/.local/bin,
#                and point your menu/desktop shortcuts at fgfs-mga (all backed up first)
#   --undo       reverse the newest install or tidy (run again to go back one more)
set -u

DRY=0; KEEP_OLD=0; UNDO=0; TIDY=0
for a in "$@"; do
  case "$a" in
    --dry-run|-n) DRY=1 ;;
    --keep-old) KEEP_OLD=1 ;;
    --tidy) TIDY=1 ;;
    --undo) UNDO=1 ;;
    -h|--help) sed -n '2,10p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a (use --dry-run, --keep-old, --tidy or --undo)"; exit 2 ;;
  esac
done

BIN="$HOME/.local/bin"
SHARE="$HOME/.local/share/fgfs-mga"
TOOLS="$SHARE/tools"
CONF_DIR="$HOME/.config/fgfs-mga"
CONF="$CONF_DIR/config"
APPS="$HOME/.local/share/applications"
STAMP="$(date +%Y%m%d-%H%M%S)"
BK="$SHARE/backup-$STAMP"
# Two runs in the same second (an install, then a tidy) must not share a backup, or --undo mixes them.
n=2; while [[ -e "$BK" ]]; do BK="$SHARE/backup-$STAMP-$n"; n=$((n+1)); done
NEW="$BIN/fgfs-mga"

say() { printf '%s\n' "$*"; }
act() { if (( DRY )); then say "  [dry-run] $*"; else "$@"; fi; }
is_shim() { grep -q 'fgfs-mga shim' "$1" 2>/dev/null; }
mark() { (( DRY )) || { mkdir -p "$BK"; printf '%s\n' "$1" >> "$BK/.kind"; }; }

# Old launcher names -> what the shim runs instead.
LAUNCHERS="fgfs-mga-training fgfs-mga-training-aeonwave fgfs-mga-training-aeonwave3124 fgfs-mga-fleet fgfs-addons fgfs-addons-aeonwave"
# Your tools -> fgfs-mga subcommand. The tool itself is kept, unchanged, in ~/.local/share/fgfs-mga/tools/.
TOOL_FILES="fg-rock5b flightgear-edited-openal fgfs-mga-controller-setup fgfs-mga-joystick-test fgfs-mga-training-event-input fgfs-mga-update fgfs-mga-scenery-fleet-audit aeonwave-output-test"
shim_args() {
  case "$1" in
    fgfs-mga-training|fgfs-mga-fleet)                          echo '' ;;
    fgfs-mga-training-aeonwave|fgfs-mga-training-aeonwave3124) echo ' --build aeonwave' ;;
    fgfs-addons)                   echo ' raw --' ;;
    fgfs-addons-aeonwave)          echo ' raw --build aeonwave --' ;;
    fg-rock5b)                     echo ' gui' ;;
    flightgear-edited-openal)      echo ' openal' ;;
    fgfs-mga-controller-setup)     echo ' controller' ;;
    fgfs-mga-joystick-test)        echo ' joystick-test' ;;
    fgfs-mga-training-event-input) echo ' event-input' ;;
    fgfs-mga-update)               echo ' update' ;;
    fgfs-mga-scenery-fleet-audit)  echo ' scenery-audit' ;;
    aeonwave-output-test)          echo ' aeonwave-test' ;;
  esac
}
is_tool() { case " $TOOL_FILES " in *" $1 "*) return 0 ;; esac; return 1; }

(( DRY )) && say "DRY RUN: nothing will be changed."

# ---------------- undo ----------------
if (( UNDO )); then
  last="$(find "$SHARE" -maxdepth 1 -type d -name 'backup-*' 2>/dev/null | sort | tail -n 1)"
  [[ -n "$last" ]] || { say "Nothing to undo (no backups left in $SHARE)."; exit 1; }
  say "Undoing $last"
  for f in "$last"/* "$last"/shims/*; do
    [[ -f "$f" ]] || continue
    n="${f##*/}"
    if [[ -e "$BIN/$n" ]] && ! is_shim "$BIN/$n"; then say "  skip $n: $BIN/$n isn't a shim (you changed it), left alone"; continue; fi
    act cp -p -- "$f" "$BIN/$n"; say "  restored $BIN/$n"
  done
  for f in "$last"/old-bak/*; do
    [[ -f "$f" ]] || continue
    act mv -n -- "$f" "$BIN/"; say "  moved back $BIN/${f##*/}"
  done
  for f in "$last"/desktop/*.desktop; do
    [[ -f "$f" && -f "${f%.desktop}.path" ]] || continue
    dest="$(cat "${f%.desktop}.path")"
    act cp -p -- "$f" "$dest"; say "  restored $dest"
  done
  if grep -qx install "$last/.kind" 2>/dev/null; then
    [[ -f "$NEW" ]] && { act mv -- "$NEW" "$last/fgfs-mga.removed"; say "  removed fgfs-mga (kept as $last/fgfs-mga.removed)"; }
    [[ -f "$APPS/fgfs-mga.desktop" ]] && act mv -- "$APPS/fgfs-mga.desktop" "$last/fgfs-mga.desktop.removed"
  fi
  act mv -- "$last" "$SHARE/undone-${last##*/backup-}"
  say "Done. Config kept at $CONF. Your tools' copies stay in $TOOLS (harmless)."
  exit 0
fi

act mkdir -p "$BIN" "$SHARE" "$TOOLS" "$CONF_DIR" "$APPS"

# ---------------- read defaults from the old launcher ----------------
OLD="$BIN/fgfs-mga-training"
DEF_AIRCRAFT=""; DEF_AIRPORT=""
if [[ -f "$OLD" ]] && ! is_shim "$OLD"; then
  oid="$(grep -oE -- '--aircraft=[^ "'"'"'\\]+' "$OLD" | head -n 1 | cut -d= -f2)"
  oapt="$(grep -oE -- '--airport=[A-Za-z0-9]+' "$OLD" | head -n 1 | cut -d= -f2)"
  [[ -n "$oid" && "$oid" != *'$'* ]] && DEF_AIRCRAFT="$oid"
  [[ -n "$oapt" && "$oapt" != KCON ]] && DEF_AIRPORT="$oapt"
  say "Your current fgfs-mga-training: aircraft=${oid:-?} airport=${oapt:-?}"
  others="$(grep -oE -- '--[a-z][a-z0-9-]*(:[^ "'"'"'=]+)?(=[^ "'"'"'\\]*)?' "$OLD" \
    | grep -vE -- '^--(fg-root|fg-home|fg-scenery|fg-aircraft|aircraft|aircraft-dir|airport|addon|runway|help)(=|$)' \
    | sort -u | tr '\n' ' ')"
  if [[ -n "$others" ]]; then
    say "Other flags in it (fgfs-mga presets cover the usual ones; to keep any exactly, put"
    say "them in EXTRA_ARGS=( ... ) in $CONF, or run 'fgfs-mga legacy' for the original):"
    say "  $others"
  fi
fi

# ---------------- install the launcher ----------------
NEW_EXISTED=0; [[ -f "$NEW" ]] && NEW_EXISTED=1
if [[ -f "$NEW" ]] && ! grep -q '^# fgfs-mga: one launcher' "$NEW"; then
  act mkdir -p "$BK"; act cp -p -- "$NEW" "$BK/fgfs-mga.unrelated"; say "Backed up an unrelated $NEW to $BK/"
fi
if (( DRY )); then
  say "  [dry-run] would write $NEW"
else
  TMPN="$(mktemp "$BIN/.fgfs-mga.XXXXXX")"
  cat > "$TMPN" <<'__FGFS_MGA_LAUNCHER__'
#!/usr/bin/env bash
# fgfs-mga: one launcher for FlightGear MGA training on the ROCK 5B+.
# Old names (fgfs-mga-training, fgfs-mga-training-aeonwave, fgfs-mga-fleet, fg-rock5b,
# flightgear-edited-openal and the MGA tools) still work and call this.
#
# Usage:
#   fgfs-mga [AIRCRAFT] [PRESET] [options] [-- extra fgfs args]
#   fgfs-mga list                  aircraft, presets, builds and tools, and what's installed
#   fgfs-mga audit                 read-only scan for every FlightGear launcher on this machine
#   fgfs-mga raw [options] -- ARGS fgfs + add-ons + ARGS, nothing else
#   fgfs-mga legacy [aeonwave] ... run your original training launcher from the backup
# Tools (your own scripts, kept as they were):
#   fgfs-mga gui [low|balanced|visual]  FlightGear's own launcher window (was fg-rock5b)
#   fgfs-mga openal                 edited OpenAL build (was flightgear-edited-openal)
#   fgfs-mga controller             controller setup (was fgfs-mga-controller-setup)
#   fgfs-mga joystick-test          (was fgfs-mga-joystick-test)
#   fgfs-mga event-input            (was fgfs-mga-training-event-input)
#   fgfs-mga update [build]         rebuild FlightGear from source (was fgfs-mga-update)
#   fgfs-mga scenery-audit          (was fgfs-mga-scenery-fleet-audit)
#   fgfs-mga aeonwave-test          (was aeonwave-output-test)
#   fgfs-mga controls [gui|wizard|check|scan|test|show|defaults|bind JOB]  stick setup, sensitivity, curves
#   fgfs-mga ffb [test|show]        force feedback bridge for the Evo Force (strengths: controls gui)
#
# Words can come in any order:  fgfs-mga seminole fast   =   fgfs-mga fast seminole
#
# Aircraft: warrior archer arrow seminole cabri r22 r44 citabria decathlon zlin
#           c182 c182rg pa18 c337 dromader agcat an2   (or any aircraft id, e.g. c172p)
# Presets:  fast balanced training high   (default: balanced)
#           also accepted: low performance medium visual quality ultra lesson
#
# Options:
#   -a, --aircraft NAME     same as the AIRCRAFT word
#   -p, --preset NAME       same as the PRESET word
#       --airport ICAO      start airport (default KEZM, Heart of Georgia Regional, Eastman)
#       --runway RWY        start runway, e.g. 20
#       --build NAME        source (default) | aeonwave | system (/usr/local/bin/fgfs)
#       --aeonwave          same as --build aeonwave
#       --no-tune           leave the radios where the aircraft starts them (default: COM_TUNE setting)
#       --no-memprotect     don't ask the kernel to keep FlightGear's memory in RAM (default: MEM_PROTECT setting)
#       --new / --old       FlightGear 2024.1.7 build / the older 2024.1.1 build (default: NEW_BUILD setting)
#       --no-addons         don't load the add-ons
#       --addons "A B"      load only these add-ons (folder names or full paths)
#       --input MODE        event (default: Saitek sticks on this kernel) | joystick | both | off
#       --no-photoscenery   don't turn on the photoscenery overlay
#       --no-terrasync      don't download scenery
#       --telemetry         send telemetry out on UDP 5620 (fg_telemetry_out protocol)
#       --weather-in        take weather in on UDP 5610 (fg_weather_in protocol)
#       --fullscreen        start full screen
#       --window WxH        window size, e.g. 1920x1080
#       --fps               show the frame-rate counter
#       --ffb / --no-ffb    force feedback on the Evo Force on/off for this flight (default: FFB setting)
#   -n, --dry-run           print the command and stop
#   -h, --help              this help
# Any other --option is passed straight to fgfs.
#
# Settings live in ~/.config/fgfs-mga/config (paths, defaults, EXTRA_ARGS).

VERSION="1.2.0"
CONF="${FGFS_MGA_CONF:-$HOME/.config/fgfs-mga/config}"
SHARE="${FGFS_MGA_SHARE:-$HOME/.local/share/fgfs-mga}"

# ---------- defaults (override any of these in the config file) ----------
FG_HOME_DIR="$HOME/.fgfs"
FG_ROOT_DIR="$HOME/.fgfs/fgdata_2024_1"
FG_SCENERY_DIRS=""                  # empty = Scenery-Addons (photoscenery, if there):TerraSync:fgdata/Scenery
AIRCRAFT_DIRS="$HOME/.fgfs/Aircraft"
FGFS_BIN="$HOME/builds/flightgear/build/src/Main/fgfs"
FGFS_BIN_AEONWAVE=""                # empty = first that exists of the AeonWave builds below
FGFS_BIN_SYSTEM="/usr/local/bin/fgfs"
NEW_BUILD=1                         # 1 = FlightGear 2024.1.7 builds below, 0 = the older 2024.1.1 build (--new / --old per flight)
FGFS_BIN_NEW="$HOME/builds/flightgear-2024.1.7/build/src/Main/fgfs"
FGFS_BIN_AEONWAVE_NEW="$HOME/builds/flightgear-2024.1.7/build-aeonwave/src/Main/fgfs"
AEONWAVE_BINS="$HOME/builds/flightgear-aeonwave-prefix/bin/fgfs $HOME/builds/flightgear/build-aeonwave/src/Main/fgfs $HOME/builds/flightgear/build-aeonwave-3124/src/Main/fgfs"
AEONWAVE_LIBS="$HOME/builds/aeonwave-fixed-prefix/lib/aarch64-linux-gnu $HOME/builds/aeonwave-prefix/lib/aarch64-linux-gnu $HOME/builds/flightgear-aeonwave-prefix/lib $HOME/builds/aeonwave-prefix/lib $HOME/builds/aeonwave-3.12.4-prefix/lib"
AEONWAVE_DEVICE="PulseAudio on default"
AEONWAVE_LATENCY="1024/48000"      # PIPEWIRE_LATENCY for the AeonWave build
AEONWAVE_NO_SIMD=0                  # 1 = AAX_NO_SIMD_SUPPORT (AeonWave without NEON). Not needed with the fixed
                                    # library above (aeonwave-fixed-prefix: its NEON mixer muted 3D sounds and its
                                    # WAV reader crashed on tagged files; both fixed). 0 = NEON on
AUDIO_QUANTUM=1024                  # PipeWire buffer (frames at 48 kHz) while fgfs plays; the desktop's 256 gave
                                    # several underruns a second under FlightGear's load. 0 = leave it alone
AUDIO_SINK="auto"                   # auto = skip a virtual-surround effect sink and play straight to the output it
                                    # feeds; "" = system default; or a sink name from `pactl list short sinks`
OPENAL_DEVICE=""                    # source/system builds: sound device, empty = system default
ADDON_ROOT=""                       # old setting; if set, the only add-on folder searched
ADDON_DIRS=""                       # empty = $FG_HOME_DIR/Addons $FG_ROOT_DIR/Addons $FG_HOME_DIR/FlightGear-2024.1-Addons-MGA
# Searched in that order, so Logbook finds Logbook-v2.1.0 before the older 1.5.1 copy.
ADDONS="Logbook ATCChatter SpokenATC SpokenGCA PAR RedGriffinATC landing_rate which-runway mga-checklist"
INPUT_MODE="event"                  # event | joystick | both | off (this kernel has no joydev, so event)
AUDIO_FIX=1                         # unmute the board's ES8316 codec and the fgfs stream once sound starts
OUTPUT_WAKE=1                       # before each flight, reset any running sound output whose device has
                                    #   frozen (PipeWire says RUNNING, the card stopped; HDMI 1, Nov 2026). 0 = off
PHOTOSCENERY=1                      # turn on the photoscenery overlay when Scenery-Addons/Orthophotos exists
DEVELOPER=0                         # 1 = FlightGear developer mode (shows developer alerts, e.g. one
                                    #     "texture size not a power-of-two" line per GUI image)
FFB="auto"                          # force feedback bridge: auto = on when the Evo Force has its force-feedback
                                    #   driver loaded, 1 = always, 0 = never (strengths: fgfs-mga controls gui)
CONTROLS_CHECK=1                    # before each flight: warn if a stick is unplugged or a core control (roll,
                                    #   pitch, rudder, throttle, brakes) isn't bound; from the menu it's a window
COM_TUNE=1                          # tune COM1 to the start airport's tower (or CTAF/UNICOM) and COM2 to its
                                    #   approach (or departure, ATIS/AWOS), from apt.dat. Red Griffin ATC only
                                    #   finds a radio that is tuned to a station; the PA28 starts on 118.70/119.40
MEM_PROTECT="4G"                    # run fgfs in a user scope with MemoryLow= this much (0 = off), so the kernel
                                    #   swaps other programs first and FlightGear's sound keeps up. Only takes
                                    #   effect once user.slice has MemoryLow too (see README, needs root once)
DEFAULT_AIRCRAFT="warrior"
DEFAULT_PRESET="balanced"
DEFAULT_AIRPORT="KEZM"
DEFAULT_BUILD="source"
TERRASYNC=1
TRAINING_METAR="KEZM 011200Z 00000KT 10SM CLR 20/10 A3000"
EXTRA_ARGS=()

# shellcheck source=/dev/null
[[ -f "$CONF" ]] && . "$CONF"
[[ -n "${DEFAULT_AUDIO:-}" ]] && DEFAULT_BUILD="$DEFAULT_AUDIO"   # older config name
if [[ -n "$ADDON_ROOT" ]]; then ADDON_DIRS="$ADDON_ROOT"
elif [[ -z "$ADDON_DIRS" ]]; then ADDON_DIRS="$FG_HOME_DIR/Addons $FG_ROOT_DIR/Addons $FG_HOME_DIR/FlightGear-2024.1-Addons-MGA"; fi
if [[ -z "$FG_SCENERY_DIRS" ]]; then
  FG_SCENERY_DIRS="$FG_HOME_DIR/TerraSync:$FG_ROOT_DIR/Scenery"
  [[ -d "$FG_HOME_DIR/Scenery-Addons" ]] && FG_SCENERY_DIRS="$FG_HOME_DIR/Scenery-Addons:$FG_SCENERY_DIRS"
fi

PRESETS="fast balanced training high"
FLEET_NAMES="warrior archer arrow seminole cabri r22 r44 citabria decathlon zlin c182 c182rg pa18 c337 dromader agcat an2"

say()  { printf '%s\n' "$*"; }
warn() { printf 'fgfs-mga: %s\n' "$*" >&2; }
die()  { printf 'fgfs-mga: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,48p' "$0" | sed 's/^# \{0,1\}//'; }

# Short name -> "folder id". Same table the old fgfs-mga-fleet used.
fleet_map() {
  case "$1" in
    warrior)                 echo "PA28 PA28-161-160" ;;
    archer|arrow)            echo "PA28 PA28-161-180" ;;
    seminole|seneca)         echo "SenecaII SenecaII" ;;
    cabri|r22)               echo "R22 R22" ;;
    r44)                     echo "R44 raven" ;;
    citabria|decathlon|zlin) echo "Zlin-50lx z50lx" ;;
    c182)                    echo "c182s c182s" ;;
    c182rg)                  echo "c182rg c182rg" ;;
    pa18|supercub)           echo "J3Cub PA-18" ;;
    c337|skymaster)          echo "Cessna337 Cessna337" ;;
    dromader)                echo "Dromader Dromader" ;;
    agcat|g164)              echo "G-164 G-164" ;;
    an2)                     echo "an2 an2" ;;
    *) return 1 ;;
  esac
}

# Other names old launchers may have used for the same presets.
preset_alias() {
  case "$1" in
    low|perf|performance) echo fast ;;
    medium|normal|default) echo balanced ;;
    lesson|lessons) echo training ;;
    quality|ultra|max|visual) echo high ;;
    *) echo "$1" ;;
  esac
}
is_preset() { case " $PRESETS " in *" $(preset_alias "$1") "*) return 0 ;; esac; return 1; }

# Every folder that may hold aircraft, one per line.
aircraft_roots() {
  local IFS=:
  local d
  for d in $AIRCRAFT_DIRS; do [[ -d "$d" ]] && printf '%s\n' "$d"; done
  [[ -d "$FG_ROOT_DIR/Aircraft" ]] && printf '%s\n' "$FG_ROOT_DIR/Aircraft"
  # Planes installed from the launcher's Aircraft page (package catalogs), last so
  # a hand-installed copy wins. No link in ~/.fgfs/Aircraft is needed for these,
  # and such a link would list the plane twice in the launcher window.
  for d in $AIRCRAFT_DIRS; do
    for c in "$d"/*/Aircraft; do [[ -d "$c" && -f "${c%/Aircraft}/catalog.xml" ]] && printf '%s\n' "$c"; done
  done
}

# Sets AC_DIR and AC_ID for a short name or a raw aircraft id. Returns 1 if not found.
resolve_aircraft() {
  local want="$1" map folder id root f
  AC_DIR=""; AC_ID=""
  if map="$(fleet_map "$want")"; then
    folder="${map% *}"; id="${map#* }"
    while IFS= read -r root; do
      if [[ -d "$root/$folder" ]]; then
        AC_DIR="$root/$folder"
        if [[ -f "$AC_DIR/$id-set.xml" ]]; then
          AC_ID="$id"
        else
          f="$(find "$AC_DIR" -maxdepth 1 -name '*-set.xml' -print 2>/dev/null | sort | head -n 1)"
          [[ -n "$f" ]] || return 1
          f="${f##*/}"; AC_ID="${f%-set.xml}"
        fi
        return 0
      fi
    done < <(aircraft_roots)
    return 1
  fi
  # Not a short name: treat it as an aircraft id (the part before -set.xml).
  while IFS= read -r root; do
    f="$(find "$root" -maxdepth 2 -name "$want-set.xml" -print -quit 2>/dev/null)"
    if [[ -n "$f" ]]; then AC_DIR="$(dirname "$f")"; AC_ID="$want"; return 0; fi
  done < <(aircraft_roots)
  # Or a folder name (e.g. R44): use its first -set.xml.
  while IFS= read -r root; do
    if [[ -d "$root/$want" ]]; then
      f="$(find "$root/$want" -maxdepth 1 -name '*-set.xml' -print 2>/dev/null | sort | head -n 1)"
      [[ -n "$f" ]] || continue
      AC_DIR="$root/$want"; f="${f##*/}"; AC_ID="${f%-set.xml}"; return 0
    fi
  done < <(aircraft_roots)
  return 1
}

# ---------- add-ons ----------
# The add-on's id from addon-metadata.xml (two add-ons with one id crash FlightGear).
addon_id() {
  grep -m1 -o '<identifier[^>]*>[^<]*' "$1/addon-metadata.xml" 2>/dev/null | sed 's/.*>//; s/^ *//; s/ *$//'
}
# Name (or full path) -> add-on folder. Exact folder name first, then e.g. Logbook-v2.1.0.
find_addon() {
  local n="$1" d c m
  if [[ "$n" == /* ]]; then [[ -f "$n/addon-metadata.xml" ]] && { printf '%s' "$n"; return 0; }; return 1; fi
  for d in $ADDON_DIRS; do
    for c in "$d/$n" "$d/$n"-*; do
      [[ -d "$c" ]] || continue
      [[ -f "$c/addon-metadata.xml" ]] && { printf '%s' "$c"; return 0; }
      m="$(find "$c" -maxdepth 3 -name addon-metadata.xml -print -quit 2>/dev/null)"
      [[ -n "$m" ]] && { printf '%s' "${m%/*}"; return 0; }
    done
  done
  return 1
}
# Ids of the add-ons FlightGear's own launcher window already loads (its Add-ons page).
launcher_addon_ids() {
  local ini p
  ini="$(find "$FG_HOME_DIR/FlightGear" -maxdepth 1 -name 'FlightGear_*.ini' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n 1 | cut -d' ' -f2-)"
  [[ -f "$ini" ]] || return 0
  awk '/^\[/ { s = ($0 == "[addon-modules]") }
       s && /\\enable=/ { split($0, a, /[\\=]/); en[a[1]] = $0 ~ /=true$/ }
       s && /\\path=/   { split($0, a, /[\\=]/); p = $0; sub(/^[^=]*=/, "", p); path[a[1]] = p }
       END { for (k in path) if (!(k in en) || en[k]) print path[k] }' "$ini" |
    while IFS= read -r p; do addon_id "$p"; done
}
ADDON_ARGS=()
collect_addons() {   # list, 1 = FlightGear's launcher window is opening
  local list="$1" name dir id seen=" "
  ADDON_ARGS=()
  [[ "${2:-0}" == 1 ]] && seen=" $(launcher_addon_ids | tr '\n' ' ') "
  for name in $list; do
    if ! dir="$(find_addon "$name")"; then warn "skipping add-on $name (not found in: $ADDON_DIRS)"; continue; fi
    id="$(addon_id "$dir")"; [[ -n "$id" ]] || id="$dir"
    case "$seen" in *" $id "*) continue ;; esac      # already loaded once
    seen+="$id "
    ADDON_ARGS+=("--addon=$dir")
  done
}

pick_binary() {
  local b lib extra=""
  if [[ "$NEW_BUILD" == 1 ]]; then   # 2024.1.7; the older build stays the fallback while a new one is missing
    if [[ "$1" == aeonwave ]]; then
      if [[ -x "$FGFS_BIN_AEONWAVE_NEW" ]]; then FGFS_BIN_AEONWAVE="$FGFS_BIN_AEONWAVE_NEW"
      else warn "no 2024.1.7 AeonWave build at $FGFS_BIN_AEONWAVE_NEW; using the older one"; fi
    elif [[ "$1" == source || "$1" == default ]]; then
      if [[ -x "$FGFS_BIN_NEW" ]]; then FGFS_BIN="$FGFS_BIN_NEW"
      else warn "no 2024.1.7 build at $FGFS_BIN_NEW; using the older one"; fi
    fi
  fi
  case "$1" in
    source|default) BIN="$FGFS_BIN" ;;
    system) BIN="$FGFS_BIN_SYSTEM" ;;
    aeonwave)
      BIN="$FGFS_BIN_AEONWAVE"
      if [[ -z "$BIN" ]]; then
        for b in $AEONWAVE_BINS; do [[ -x "$b" ]] && { BIN="$b"; break; }; done
        [[ -n "$BIN" ]] || BIN="${AEONWAVE_BINS%% *}"
      fi
      for lib in $AEONWAVE_LIBS; do [[ -d "$lib" ]] && extra="${extra:+$extra:}$lib"; done
      [[ -n "$extra" ]] && export LD_LIBRARY_PATH="$extra${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      [[ -n "$AEONWAVE_LATENCY" ]] && export PIPEWIRE_LATENCY="$AEONWAVE_LATENCY"
      [[ "$AEONWAVE_NO_SIMD" == 1 ]] && export AAX_NO_SIMD_SUPPORT=1
      ;;
    *) die "unknown build '$1' (use source, aeonwave or system)" ;;
  esac
  if [[ ! -x "$BIN" ]]; then
    if (( DRY )); then warn "fgfs not found or not executable: $BIN"
    else die "fgfs not found or not executable: $BIN (fix the path in $CONF)"; fi
  fi
}

# Your own FlightGear tools: subcommand -> original file name.
TOOL_NAMES="gui openal controller controls ffb joystick-test event-input update scenery-audit aeonwave-test"
tool_file() {
  case "$1" in
    gui)           echo fg-rock5b ;;
    openal)        echo flightgear-edited-openal ;;
    controller)    echo fgfs-mga-controller-setup ;;
    controls)      echo fgfs-mga-controls ;;
    ffb)           echo fgfs-mga-ffb ;;
    joystick-test) echo fgfs-mga-joystick-test ;;
    event-input)   echo fgfs-mga-training-event-input ;;
    update)        echo fgfs-mga-update ;;
    scenery-audit) echo fgfs-mga-scenery-fleet-audit ;;
    aeonwave-test) echo aeonwave-output-test ;;
    *) return 1 ;;
  esac
}
# Where a tool lives: the copy the installer kept, or the original if not installed yet.
tool_path() {
  local n f
  n="$(tool_file "$1")" || return 1
  for f in "$SHARE/tools/$n" "$HOME/.local/bin/$n"; do
    [[ -f "$f" ]] && ! grep -q 'fgfs-mga shim' "$f" 2>/dev/null && { printf '%s' "$f"; return 0; }
  done
  return 1
}
run_tool() {
  local sub="$1" f; shift
  if f="$(tool_path "$sub")"; then
    (( DRY )) && { say "would run: $f $*"; exit 0; }
    # the tools read these; give them the same paths the sim uses
    export FG_HOME="$FG_HOME_DIR" FG_ROOT="$FG_ROOT_DIR" FG_SCENERY="$FG_SCENERY_DIRS"
    [[ -x "$f" ]] && exec "$f" "$@"
    exec bash "$f" "$@"
  fi
  if [[ "$sub" == gui ]]; then          # no fg-rock5b: open FlightGear's own launcher
    DRY=${DRY:-0}; pick_binary system; export FG_HOME="$FG_HOME_DIR"
    exec "$BIN" --launcher "$@"
  fi
  die "the $sub tool ($(tool_file "$sub")) isn't on this machine"
}

preset_args() {
  case "$(preset_alias "$1")" in
    fast)
      PRESET_ARGS=(--prop:/sim/rendering/shaders/quality-level=0
        --prop:/sim/rendering/shaders/custom-settings=false
        --prop:/sim/rendering/clouds3d-vis-range=10000 --prop:/sim/rendering/clouds3d-detail-range=10000
        --prop:/sim/rendering/clouds3d-density=0.25
        --prop:/environment/fog-structure=0 --prop:/environment/air-pollution-norm=0
        --prop:/sim/rendering/shadows/enabled=false
        --prop:/sim/rendering/multi-sample-buffers=false
        --disable-random-objects --disable-random-vegetation --disable-random-buildings
        --disable-ai-traffic --fog-fastest --visibility=10000) ;;
    balanced)
      PRESET_ARGS=(--prop:/sim/rendering/shaders/quality-level=2
        # realism round A (measured free on the board, Nov 2026): water detail, shinier aircraft finish,
        # clouds drawn to 20 km and thicker, patchy haze. custom-settings lets the two shader levels stick.
        --prop:/sim/rendering/shaders/custom-settings=true
        --prop:/sim/rendering/shaders/landmass=5 --prop:/sim/rendering/shaders/transition=5
        --prop:/sim/rendering/shaders/water=6 --prop:/sim/rendering/shaders/model=3
        --prop:/sim/rendering/clouds3d-vis-range=20000 --prop:/sim/rendering/clouds3d-detail-range=20000
        --prop:/sim/rendering/clouds3d-density=0.6
        --prop:/environment/fog-structure=3 --prop:/environment/air-pollution-norm=0.2
        --prop:/sim/rendering/shadows/enabled=false
        --enable-random-objects --disable-random-vegetation --disable-random-buildings
        --disable-ai-traffic --fog-fastest --visibility=20000) ;;
    training)
      # balanced, plus the same calm noon VFR weather every time so lessons repeat
      preset_args balanced
      PRESET_ARGS+=(--disable-real-weather-fetch --timeofday=noon "--metar=$TRAINING_METAR") ;;
    high)
      PRESET_ARGS=(--prop:/sim/rendering/shaders/quality-level=4
        --prop:/sim/rendering/shaders/custom-settings=false
        --prop:/sim/rendering/clouds3d-vis-range=20000 --prop:/sim/rendering/clouds3d-detail-range=20000
        --prop:/sim/rendering/clouds3d-density=0.6
        --prop:/environment/fog-structure=3 --prop:/environment/air-pollution-norm=0.2
        --enable-random-objects --enable-random-vegetation --enable-random-buildings
        --enable-ai-traffic --fog-nicest --visibility=40000) ;;
    *) die "unknown preset '$1' (use: $PRESETS)" ;;
  esac
}

print_cmd() {
  local a
  say "FG_HOME=$FG_HOME_DIR"
  [[ -n "${LD_LIBRARY_PATH:-}" ]] && say "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
  [[ -n "${PIPEWIRE_LATENCY:-}" ]] && say "PIPEWIRE_LATENCY=$PIPEWIRE_LATENCY"
  [[ -n "${AAX_NO_SIMD_SUPPORT:-}" ]] && say "AAX_NO_SIMD_SUPPORT=$AAX_NO_SIMD_SUPPORT"
  [[ -n "${PULSE_SINK:-}" ]] && say "PULSE_SINK=$PULSE_SINK"
  [[ -n "${PULSE_PROP:-}" ]] && say "PULSE_PROP=$PULSE_PROP"
  printf '%q' "$BIN"
  for a in "$@"; do printf ' \\\n  %q' "$a"; done
  printf '\n'
}

# Flight-control input. FlightGear reads Linux "event" devices with the configs in
# ~/.fgfs/Input/Event (fgfs-mga controls writes them). Plain joystick input needs joydev,
# which this kernel lacks; running both on one stick would double every input.
input_args() {
  case "$1" in
    event)    INPUT_ARGS=(--prop:bool:/sim/input/no-event-input=false --prop:bool:/sim/input/no-joystick-input=true --prop:bool:/sim/input/no-hid-input=true) ;;
    joystick) INPUT_ARGS=(--prop:bool:/sim/input/no-event-input=true --prop:bool:/sim/input/no-joystick-input=false) ;;
    both)     INPUT_ARGS=(--prop:bool:/sim/input/no-event-input=false --prop:bool:/sim/input/no-joystick-input=false) ;;
    off)      INPUT_ARGS=(--prop:bool:/sim/input/no-event-input=true --prop:bool:/sim/input/no-joystick-input=true --prop:bool:/sim/input/no-hid-input=true) ;;
    *) die "unknown input mode '$1' (use event, joystick, both or off)" ;;
  esac
}

# Before a flight: are the sticks there and the core controls bound? From a terminal it prints the
# warnings; from the menu (no terminal) it shows a window with "Open controls" and "Fly anyway".
controls_check() {
  (( CONTROLS_CHECK )) || return 0
  [[ "$INPUT" == event || "$INPUT" == both ]] || return 0
  local f; f="$(tool_path controls)" || return 0
  local gui=(); [[ -t 1 ]] || gui=(--gui)
  FG_HOME="$FG_HOME_DIR" python3 "$f" check "${gui[@]}" || true
}

# Force feedback: FlightGear sends a few properties over UDP (Protocol/fgfs-mga-ffb.xml) and the
# fgfs-mga-ffb bridge turns them into stick effects. It runs beside fgfs and stops when fgfs does.
FFB_NODE=/dev/input/by-id/usb-Saitek_Cyborg_Evo_Force-event-joystick
FFB_NOTE=""
ffb_wanted() {
  case "$FFB_RUN" in
    1|on|yes) return 0 ;;
    auto) [[ -e "$FFB_NODE" ]] && [[ "$(cat "/sys/class/input/$(basename "$(readlink -f "$FFB_NODE")")/device/capabilities/ff" 2>/dev/null)" =~ [1-9a-f] ]] ;;
    *) return 1 ;;
  esac
}
ffb_args() {
  ffb_wanted || return 0
  local tool proto; tool="$(tool_path ffb)" || { warn "force feedback is on but fgfs-mga-ffb isn't installed"; return 0; }
  proto="$FG_ROOT_DIR/Protocol/fgfs-mga-ffb.xml"
  if [[ -f "$(dirname "$tool")/fgfs-mga-ffb.xml" ]] && ! cmp -s "$(dirname "$tool")/fgfs-mga-ffb.xml" "$proto"; then
    (( DRY )) || cp "$(dirname "$tool")/fgfs-mga-ffb.xml" "$proto" 2>/dev/null || warn "couldn't copy fgfs-mga-ffb.xml to $FG_ROOT_DIR/Protocol"
  fi
  ARGS+=("--generic=socket,out,30,127.0.0.1,5630,udp,fgfs-mga-ffb")
  FFB_TOOL="$tool"; FFB_NOTE=", force feedback"
}
start_ffb() {   # $1 = the pid fgfs will have (exec keeps ours)
  [[ -n "${FFB_TOOL:-}" ]] || return 0
  mkdir -p "$SHARE"; nohup python3 "$FFB_TOOL" run --pid "$1" >"$SHARE/ffb.log" 2>&1 &
}

# Where the sound goes. A virtual-surround (effect_input.*) default sink turns FlightGear's output into
# 8 channels and runs it through a filter chain: heavy on this board and a source of underruns.
SINK_NOTE=""
resolve_sink() {
  local want="$AUDIO_SINK" def idx
  [[ -n "$want" ]] && command -v pactl >/dev/null 2>&1 || return 0
  if [[ "$want" == auto ]]; then
    want=""
    def="$(pactl get-default-sink 2>/dev/null)"
    [[ "$def" == effect_input.* ]] || return 0
    idx="$(pactl list sink-inputs 2>/dev/null | awk -v n="node.name = \"effect_output.${def#effect_input.}\"" \
      '/^Sink Input #/ { s = "" } /^[[:space:]]*Sink:/ { s = $2 } index($0, n) { print s; exit }')"
    [[ -n "$idx" ]] && want="$(pactl list short sinks 2>/dev/null | awk -v i="$idx" '$1 == i { print $2; exit }')"
    [[ -n "$want" ]] || return 0
  fi
  export PULSE_SINK="$want"; SINK_NOTE=", sound to $want"
}
# A per-stream property: the graph runs at this quantum only while fgfs's stream is open.
# (PIPEWIRE_LATENCY and PULSE_LATENCY_MSEC don't reach AeonWave's or OpenAL's PulseAudio stream.)
set_quantum() {
  (( AUDIO_QUANTUM > 0 )) || return 0
  export PULSE_PROP="${PULSE_PROP:+$PULSE_PROP }node.force-quantum=$AUDIO_QUANTUM"
}

# A sound output can freeze: PipeWire still shows the sink RUNNING, but its ALSA device sits stopped
# (state SETUP, hw_ptr not moving), so every program plays into nothing. HDMI 1 did this on 22 Nov 2026
# and stayed silent for a day and a half. Before each flight, check every running ALSA sink and, if its
# device is stuck, suspend and resume the sink so PipeWire reopens it. Takes about a second when all is well.
wake_output() {
  (( OUTPUT_WAKE )) || return 0
  command -v pactl >/dev/null 2>&1 || return 0
  local name card dev f st p1 p2
  while read -r name card dev; do
    f="/proc/asound/card$card/pcm${dev}p/sub0/status"
    [[ -r "$f" ]] || continue
    st="$(awk '/^state:/ { print $2; exit }' "$f")"
    p1="$(awk '/hw_ptr/ { print $3; exit }' "$f")"
    sleep 0.3
    p2="$(awk '/hw_ptr/ { print $3; exit }' "$f")"
    if [[ "$st" != RUNNING || "$p1" == "$p2" ]]; then
      warn "sound output $name was frozen (card $card: ${st:-closed}); resetting it"
      pactl suspend-sink "$name" 1 2>/dev/null; sleep 0.5; pactl suspend-sink "$name" 0 2>/dev/null
    fi
  done < <(pactl list sinks 2>/dev/null | awk '
    /^Sink #/ { n = ""; s = ""; c = ""; d = "" }
    /^[[:space:]]*State:/ { s = $2 }
    /^[[:space:]]*Name:/ { n = $2 }
    /alsa\.card = / { gsub(/"/, "", $3); c = $3 }
    /alsa\.device = / { gsub(/"/, "", $3); d = $3; if (s == "RUNNING" && n ~ /^alsa_output\./ && c != "") print n, c, d }')
}

# The ROCK 5B+ headphone codec (ES8316) can come up muted, and PipeWire can start the fgfs
# stream at 0 %. Once fgfs opens its stream, unmute both. Runs in the background, gives up
# after two minutes or when fgfs exits. (From the old aeonwave launcher, for every build now.)
start_audio_fix() {
  (( AUDIO_FIX )) || return 0
  command -v pactl >/dev/null 2>&1 || return 0
  local card
  card="$(awk '/es8316/ { print $1; exit }' /proc/asound/cards 2>/dev/null)"
  (
    trap '' HUP
    for _ in $(seq 1 120); do
      kill -0 "$1" 2>/dev/null || exit 0
      id="$(pactl list sink-inputs 2>/dev/null | awk '/^Sink Input #/ { i = substr($3, 2) } /application.name = "fgfs"/ { print i; exit }')"
      if [[ -n "$id" ]]; then
        if [[ -n "$card" ]] && command -v amixer >/dev/null 2>&1; then
          amixer -q -c "$card" sset 'Headphone Mixer' 100% 2>/dev/null
          amixer -q -c "$card" sset 'Left DAC' on 2>/dev/null; amixer -q -c "$card" sset 'Right DAC' on 2>/dev/null
          amixer -q -c "$card" cset "name='Headphone Switch'" on 2>/dev/null
          amixer -q -c "$card" sset 'Headphone' 100% unmute 2>/dev/null
          amixer -q -c "$card" sset 'Speaker' on 2>/dev/null; amixer -q -c "$card" cset "name='Speaker Switch'" on 2>/dev/null
          amixer -q -c "$card" sset 'DAC' 100% 2>/dev/null
        fi
        pactl set-sink-input-mute "$id" 0 2>/dev/null; pactl set-sink-input-volume "$id" 100% 2>/dev/null
        exit 0
      fi
      sleep 1
    done
  ) </dev/null >/dev/null 2>&1 &
}

# ---------- audit (read-only) ----------
# AUDIT-BEGIN
do_audit() {
  local d f hits line
  echo "== FlightGear launcher audit (read-only, changes nothing) =="
  echo
  echo "-- Launcher scripts that mention fgfs or FlightGear --"
  for d in "$HOME/.local/bin" "$HOME/bin" "$HOME/Desktop" "$HOME/Downloads" /usr/local/bin; do
    [[ -d "$d" ]] || continue
    while IFS= read -r f; do
      [[ -f "$f" ]] || continue
      case "$f" in *.bak*|*.orig|*.png|*.jpg|*.zip|*.gz|*.xz|*.tar) continue ;; esac
      case "${f##*/}" in
        *fgfs*|*flightgear*|*FlightGear*|fg[-_]*) ;;
        *) { grep -Iq . "$f" 2>/dev/null && grep -qiE 'fgfs|flightgear' "$f" 2>/dev/null; } || continue ;;
      esac
      {
        if grep -q 'fgfs-mga shim' "$f" 2>/dev/null; then
          echo "SHIM      $f  -> $(grep -m1 '^exec' "$f" | sed 's/^exec //')"
        elif grep -q '^# fgfs-mga: one launcher' "$f" 2>/dev/null; then
          echo "NEW       $f  (fgfs-mga $(grep -m1 '^VERSION=' "$f" | cut -d'"' -f2))"
        elif grep -Iq . "$f" 2>/dev/null; then
          echo "SCRIPT    $f"
          grep -nE '(^|[ /"=])fgfs([ "]|$)|/fgfs\b|--aircraft=|--airport=|--addon=|exec ' "$f" 2>/dev/null | head -n 6 | sed 's/^/            /'
        else
          echo "PROGRAM   $f"
        fi
      }
    done < <(find "$d" -maxdepth 1 \( -type f -o -type l \) 2>/dev/null | sort)
  done
  echo
  echo "-- Backups of old launchers --"
  find "$HOME/.local/bin" "$HOME/.local/share/fgfs-mga" -maxdepth 2 -type f \( -name '*fgfs*.bak*' -o -path '*fgfs-mga/backup-*' \) 2>/dev/null | sort | sed 's/^/  /'
  echo
  echo "-- Aliases and functions in shell startup files --"
  hits=0
  for f in "$HOME/.bashrc" "$HOME/.bash_aliases" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.zshrc" "$HOME/.config/fish/config.fish"; do
    [[ -f "$f" ]] || continue
    while IFS= read -r line; do echo "  $f:$line"; hits=1; done < <(grep -nE 'fgfs|flightgear|FG_HOME|FG_ROOT' "$f" 2>/dev/null)
  done
  (( hits )) || echo "  none"
  echo
  echo "-- Menu and desktop shortcuts (.desktop) --"
  hits=0
  for d in "$HOME/.local/share/applications" "$HOME/Desktop" /usr/share/applications /usr/local/share/applications "$HOME/.config/autostart"; do
    [[ -d "$d" ]] || continue
    while IFS= read -r f; do
      echo "  $f"; grep -m2 -E '^(Name|Exec)=' "$f" | sed 's/^/      /'; hits=1
    done < <(grep -lisE 'fgfs|flightgear' "$d"/*.desktop 2>/dev/null)
  done
  (( hits )) || echo "  none"
  echo
  echo "-- fgfs programs found --"
  command -v fgfs >/dev/null 2>&1 && echo "  on PATH: $(command -v fgfs)"
  find "$HOME/builds" -maxdepth 5 -type f -name fgfs -perm -u+x 2>/dev/null | sed 's/^/  /'
  echo
  echo "-- PATH --"
  case ":$PATH:" in *":$HOME/.local/bin:"*) echo "  ~/.local/bin is on PATH" ;; *) echo "  ~/.local/bin is NOT on PATH" ;; esac
  echo
  echo "Paste this whole output back so anything missing can be folded into fgfs-mga."
}
# AUDIT-END

do_list() {
  local n map
  say "Aircraft (short name -> FlightGear folder/id, installed?):"
  for n in $FLEET_NAMES; do
    map="$(fleet_map "$n")"
    if resolve_aircraft "$n"; then printf '  %-10s %-24s yes  %s\n' "$n" "${map/ //}" "$AC_DIR"
    else printf '  %-10s %-24s no\n' "$n" "${map/ //}"; fi
  done
  say "  (any other aircraft id also works, e.g. fgfs-mga c172p)"
  say ""
  say "Presets: $PRESETS   (default: $DEFAULT_PRESET)"
  say ""
  say "Builds (--build):"
  local b t f
  DRY=1
  for b in source aeonwave system; do
    pick_binary "$b" 2>/dev/null
    if [[ -x "$BIN" ]]; then printf '  %-9s yes  %s\n' "$b" "$BIN"; else printf '  %-9s no   %s\n' "$b" "$BIN"; fi
  done
  say ""
  say "Tools:"
  for t in $TOOL_NAMES; do
    if f="$(tool_path "$t")"; then printf '  fgfs-mga %-14s yes  %s\n' "$t" "$f"
    else printf '  fgfs-mga %-14s no   (%s not found)\n' "$t" "$(tool_file "$t")"; fi
  done
  say ""
  say "Add-ons (in load order; with --launcher, ones its window already loads are skipped):"
  collect_addons "$ADDONS" 0
  for t in "${ADDON_ARGS[@]}"; do t="${t#--addon=}"; printf '  %-16s %s\n' "$(addon_id "$t")" "$t"; done
  say ""
  say "Scenery: $FG_SCENERY_DIRS"
  say "Controls: input $INPUT_MODE; configs: $(find "$FG_HOME_DIR/Input/Event" -name 'fgfs-mga-*.xml' -printf '%f ' 2>/dev/null)"
  say ""
  say "Default aircraft: $DEFAULT_AIRCRAFT   airport: $DEFAULT_AIRPORT   build: $DEFAULT_BUILD"
  say "Config: $CONF"
}

do_legacy() {
  local which="training" f
  if [[ "${1:-}" == aeonwave || "${1:-}" == training ]]; then which="$1"; shift; fi
  local name="fgfs-mga-training"
  [[ "$which" == aeonwave ]] && name="fgfs-mga-training-aeonwave"
  f="$(find "$SHARE" -maxdepth 2 -type f \( -path "*/backup-*/$name" -o -path "*/backup-*/${name}3124" \) 2>/dev/null | sort | tail -n 1)"
  [[ -n "$f" ]] || die "no backup of $name found in $SHARE"
  say "Running your original launcher: $f"
  exec bash "$f" "$@"
}

# ---------- argument parsing ----------
DRY=0
MODE=run
case "${1:-}" in
  list)    shift; MODE=list ;;
  audit)   shift; do_audit; exit 0 ;;
  legacy)  shift; do_legacy "$@" ;;
  raw)     shift; MODE=raw ;;
  gui|openal|controller|controls|ffb|joystick-test|event-input|update|scenery-audit|aeonwave-test)
           DRY=0; t="$1"; shift
           [[ "${1:-}" == -n || "${1:-}" == --dry-run ]] && { DRY=1; shift; }
           run_tool "$t" "$@" ;;
  version|--version) say "fgfs-mga $VERSION"; exit 0 ;;
  help|-h|--help) usage; exit 0 ;;
esac
[[ "$MODE" == list ]] && { do_list; exit 0; }

AUDIO="$DEFAULT_BUILD"; USE_ADDONS=1; ADDON_LIST="$ADDONS"; PASS=()

if [[ "$MODE" == raw ]]; then
  # Only these options are read; everything else goes to fgfs untouched.
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --audio|--build) [[ -n "${2:-}" ]] || die "$1 needs a value"; AUDIO="$2"; shift ;;
      --aeonwave) AUDIO=aeonwave ;;
      --new|--fg2024) NEW_BUILD=1 ;;
      --old) NEW_BUILD=0 ;;
      --no-addons) USE_ADDONS=0 ;;
      --addons) [[ -n "${2:-}" ]] || die "--addons needs a value"; ADDON_LIST="$2"; shift ;;
      -n|--dry-run) DRY=1 ;;
      --) shift; PASS+=("$@"); break ;;
      *) PASS+=("$@"); break ;;
    esac
    shift
  done
fi

AIRCRAFT=""; PRESET=""; AIRPORT="$DEFAULT_AIRPORT"; RUNWAY=""; FULLSCREEN=0; WINDOW=""; FPS=0
INPUT="$INPUT_MODE"
TELEMETRY=0; WEATHER_IN=0; FFB_RUN="$FFB"

need() { [[ $# -ge 2 && -n "$2" ]] || die "$1 needs a value"; }
while [[ "$MODE" == run && $# -gt 0 ]]; do
  case "$1" in
    -a|--aircraft) need "$@"; AIRCRAFT="$2"; shift ;;
    --aircraft=*)  AIRCRAFT="${1#*=}" ;;
    -p|--preset)   need "$@"; PRESET="$2"; shift ;;
    --airport)     need "$@"; AIRPORT="$2"; shift ;;
    --airport=*)   AIRPORT="${1#*=}" ;;
    --runway)      need "$@"; RUNWAY="$2"; shift ;;
    --runway=*)    RUNWAY="${1#*=}" ;;
    --audio|--build) need "$@"; AUDIO="$2"; shift ;;
    --build=*)     AUDIO="${1#*=}" ;;
    --telemetry)   TELEMETRY=1 ;;
    --weather-in)  WEATHER_IN=1 ;;
    --aeonwave)    AUDIO=aeonwave ;;
    --new|--fg2024) NEW_BUILD=1 ;;
    --old)         NEW_BUILD=0 ;;
    --no-addons)   USE_ADDONS=0 ;;
    --addons)      need "$@"; ADDON_LIST="$2"; shift ;;
    --no-terrasync) TERRASYNC=0 ;;
    --no-tune)     COM_TUNE=0 ;;
    --no-memprotect) MEM_PROTECT=0 ;;
    --input)       need "$@"; INPUT="$2"; shift ;;
    --input=*)     INPUT="${1#*=}" ;;
    --no-photoscenery) PHOTOSCENERY=0 ;;
    --fullscreen)  FULLSCREEN=1 ;;
    --window)      need "$@"; WINDOW="$2"; shift ;;
    --fps)         FPS=1 ;;
    --ffb)         FFB_RUN=1 ;;
    --no-ffb)      FFB_RUN=0 ;;
    -n|--dry-run)  DRY=1 ;;
    -h|--help)     usage; exit 0 ;;
    --)            shift; PASS+=("$@"); break ;;
    --*)           PASS+=("$1") ;;       # anything else goes straight to fgfs
    aeonwave)      AUDIO=aeonwave ;;
    *)
      if is_preset "$1" && [[ -z "$PRESET" ]]; then PRESET="$1"
      elif [[ -z "$AIRCRAFT" ]]; then AIRCRAFT="$1"
      else die "don't know what '$1' is. Aircraft: $FLEET_NAMES. Presets: $PRESETS"
      fi ;;
  esac
  shift
done

pick_binary "$AUDIO"
export FG_HOME="$FG_HOME_DIR"     # fgfs reads FG_HOME only from the environment
run_fgfs() {   # exec fgfs, inside a memory-protected user scope when we can (same pid, so FFB/audio fix keep it)
  if [[ "$MEM_PROTECT" != 0 && -n "$MEM_PROTECT" ]] && command -v systemd-run >/dev/null 2>&1 \
     && [[ -n "${XDG_RUNTIME_DIR:-}" && -S "$XDG_RUNTIME_DIR/systemd/private" ]]; then
    exec systemd-run --user --scope --quiet --collect -p "MemoryLow=$MEM_PROTECT" \
      --unit="fgfs-mga-$$" -- "$BIN" "$@"
  fi
  exec "$BIN" "$@"
}
ARGS=()
in_pass() { local x; for x in "${PASS[@]}"; do [[ "$x" == "$1" ]] && return 0; done; return 1; }
LAUNCHER=0; in_pass --launcher && LAUNCHER=1
if (( USE_ADDONS )); then
  collect_addons "$ADDON_LIST" "$LAUNCHER"
  for a in "${ADDON_ARGS[@]}"; do in_pass "$a" || ARGS+=("$a"); done
fi

if [[ "$MODE" == raw ]]; then
  ARGS+=("${PASS[@]}")
  if (( DRY )); then print_cmd "${ARGS[@]}"; exit 0; fi
  controls_check
  run_fgfs "${ARGS[@]}"
fi

[[ -n "$AIRCRAFT" ]] || AIRCRAFT="$DEFAULT_AIRCRAFT"
[[ -n "$PRESET" ]] || PRESET="$DEFAULT_PRESET"
if ! resolve_aircraft "$AIRCRAFT"; then
  if (( LAUNCHER )); then   # a fresh install: open the launcher window anyway, its Aircraft page installs aircraft
    warn "$AIRCRAFT isn't installed yet, so the launcher opens without it (pick or install one on its Aircraft page)"
  elif fleet_map "$AIRCRAFT" >/dev/null; then
    die "$AIRCRAFT isn't installed (looked for folder $(fleet_map "$AIRCRAFT" | cut -d' ' -f1) in $AIRCRAFT_DIRS). Install it from the launcher's Aircraft page (fgfs-mga --launcher), or see: fgfs-mga list"
  else
    die "aircraft '$AIRCRAFT' not found. Try: fgfs-mga list"
  fi
fi
PRESET_ARGS=()
preset_args "$PRESET"

ARGS+=("--fg-root=$FG_ROOT_DIR" "--fg-scenery=$FG_SCENERY_DIRS" "--fg-aircraft=$AIRCRAFT_DIRS")
[[ -n "$AC_ID" ]] && ARGS+=("--aircraft-dir=$AC_DIR" "--aircraft=$AC_ID")
ARGS+=("--airport=$AIRPORT")
[[ -n "$RUNWAY" ]] && ARGS+=("--runway=$RUNWAY")
if (( TERRASYNC )); then ARGS+=(--enable-terrasync); else ARGS+=(--disable-terrasync); fi
ARGS+=("${PRESET_ARGS[@]}")
(( FULLSCREEN )) && ARGS+=(--enable-fullscreen)
[[ -n "$WINDOW" ]] && ARGS+=("--geometry=$WINDOW")
(( FPS )) && ARGS+=(--prop:/sim/rendering/fps-display=true)
radio_args() {   # RADIO_ARGS / RADIO_NOTE for the start airport, unless off or --com1/--com2 were given
  RADIO_ARGS=(); RADIO_NOTE=""
  [[ "$COM_TUNE" == 1 ]] && (( ! LAUNCHER )) || return 0   # the launcher window picks its own airport
  local p f key cache line f1="" f2=""
  for p in "${PASS[@]}"; do case "$p" in --com1=*|--com2=*) return 0 ;; esac; done
  f="$FG_ROOT_DIR/Airports/apt.dat.gz"; [[ -f "$f" ]] || return 0
  key="${1^^} $(stat -c %Y "$f" 2>/dev/null)"; cache="$SHARE/radio-cache"
  line=$(grep -m1 "^$key " "$cache" 2>/dev/null) && read -r _ _ f1 f2 <<<"$line"
  if [[ -z "$line" ]]; then
    read -r f1 f2 < <(zcat -f "$f" 2>/dev/null | awk -v icao="${1^^}" '
      ($1=="1" || $1=="16" || $1=="17") && NF >= 5 { if (p) exit; p = ($5 == icao); next }
      !p { next }
      { c = $1 + 0; m = 0
        if (c >= 50 && c <= 56)          { m = $2 / 100;  t = c - 50 }
        else if (c >= 1050 && c <= 1056) { m = $2 / 1000; t = c - 1050 }
        if (m > 0 && !(t in fr)) fr[t] = sprintf("%.3f", m) }
      END { a = (4 in fr) ? fr[4] : (1 in fr) ? fr[1] : (3 in fr) ? fr[3] : "-"
            b = (5 in fr) ? fr[5] : (6 in fr) ? fr[6] : (0 in fr) ? fr[0] : "-"
            print a, b }')
    [[ -n "$f1" ]] || return 0
    (( DRY )) || { mkdir -p "$SHARE" 2>/dev/null && printf '%s %s %s\n' "$key" "$f1" "$f2" >> "$cache" 2>/dev/null; }
  fi
  [[ "$f1" != "-" ]] && RADIO_ARGS+=("--com1=$f1")
  [[ -n "$f2" && "$f2" != "-" ]] && RADIO_ARGS+=("--com2=$f2")
  (( ${#RADIO_ARGS[@]} )) && RADIO_NOTE=", ${RADIO_ARGS[*]//--com/COM}"
  return 0
}
radio_args "$AIRPORT"; ARGS+=("${RADIO_ARGS[@]}")
proto_check() {
  [[ -f "$FG_ROOT_DIR/Protocol/$1.xml" || -f "$FG_HOME_DIR/Protocol/$1.xml" ]] \
    || warn "$1.xml isn't in $FG_ROOT_DIR/Protocol; copy it there from ~/Downloads or fgfs will refuse it"
}
(( TELEMETRY )) && { proto_check fg_telemetry_out; ARGS+=("--generic=socket,out,20,,5620,udp,fg_telemetry_out"); }
(( WEATHER_IN )) && { proto_check fg_weather_in; ARGS+=("--generic=socket,in,4,,5610,udp,fg_weather_in"); }
INPUT_ARGS=(); input_args "$INPUT"; ARGS+=("${INPUT_ARGS[@]}")
PHOTO=""
if (( PHOTOSCENERY )) && [[ ":$FG_SCENERY_DIRS:" == *":$FG_HOME_DIR/Scenery-Addons:"* && -d "$FG_HOME_DIR/Scenery-Addons/Orthophotos" ]]; then
  ARGS+=(--prop:bool:/sim/rendering/photoscenery/enabled=true); PHOTO=", photoscenery"
fi
# FlightGear saves the last sound device; an AeonWave-only name left there makes OpenAL fail over with errors,
# and the AeonWave "Audio Stream" device writes to a file instead of the speakers. Set it every start.
if [[ "$AUDIO" == aeonwave ]]; then
  [[ -n "$AEONWAVE_DEVICE" ]] && ARGS+=(--prop:/sim/sound/backend=aeonwave "--sound-device=$AEONWAVE_DEVICE")
elif [[ -n "$OPENAL_DEVICE" ]]; then
  ARGS+=("--prop:string:/sim/sound/device-name=$OPENAL_DEVICE")
fi   # empty: pass nothing. fgfs rejects "--prop:x=" with no value and only prints its usage text; an
     # AeonWave name left in the autosave just makes OpenAL say "trying default" and use the default.
(( DEVELOPER )) || ARGS+=(--disable-developer)
ffb_args
ARGS+=("${EXTRA_ARGS[@]}" "${PASS[@]}")
drop_empty_props() {   # fgfs stops at "--prop:name=" with nothing after "=", so never hand it one
  local a keep=()
  for a in "${ARGS[@]}"; do
    if [[ "$a" == --prop:*= ]]; then warn "left out ${a%=} (no value given)"; else keep+=("$a"); fi
  done
  ARGS=("${keep[@]}")
}
drop_empty_props

LW=""; (( LAUNCHER )) && LW=" (plus the ones the launcher window loads)"
resolve_sink; set_quantum
say "fgfs-mga: ${AC_ID:-no aircraft yet} at $AIRPORT, preset $PRESET, build $AUDIO, ${#ADDON_ARGS[@]} add-on(s)$LW, input $INPUT$PHOTO$RADIO_NOTE$SINK_NOTE$FFB_NOTE"
if (( DRY )); then print_cmd "${ARGS[@]}"; exit 0; fi
controls_check
wake_output
start_audio_fix "$$"
start_ffb "$$"
run_fgfs "${ARGS[@]}"
__FGFS_MGA_LAUNCHER__
  if bash -n "$TMPN"; then chmod 755 "$TMPN"; mv -f -- "$TMPN" "$NEW"; say "Installed $NEW"
  else rm -f -- "$TMPN"; say "ERROR: launcher failed a syntax check; nothing installed."; exit 1; fi
  (( NEW_EXISTED )) || mark install
fi

# ---------------- controller setup tool (Python, needs python3-evdev) ----------------
if (( DRY )); then
  say "  [dry-run] would write $TOOLS/fgfs-mga-controls"
else
  CT="$TOOLS/fgfs-mga-controls"
  [[ -f "$CT" ]] && { mkdir -p "$BK"; cp -p -- "$CT" "$BK/fgfs-mga-controls"; }
  TMPC="$(mktemp "$TOOLS/.fgfs-mga-controls.XXXXXX")"
  cat > "$TMPC" <<'__FGFS_MGA_CONTROLS__'
#!/usr/bin/env python3
"""fgfs-mga controls: set up Saitek (or any) joysticks for FlightGear's Linux event input.

  fgfs-mga controls scan       list the controllers and every axis/button FlightGear can see
  fgfs-mga controls gui        window: live sticks, Bind/Reverse/Clear for every FlightGear control (grouped),
                               and a Response tab: dead zone, sensitivity, curve, limit, trim offset,
                               smoothing and rudder brake split, for all aircraft or one, with a live curve
  fgfs-mga controls wizard     move each control when asked; writes the FlightGear config files
  fgfs-mga controls defaults   write configs from a standard layout without asking (best guess)
  fgfs-mga controls test       live view: what FlightGear will get from each control
  fgfs-mga controls show       print the current mapping, by group, with warnings
  fgfs-mga controls check      before a flight: warn if a stick is unplugged or a core control is free
                               (--gui: small window with Open controls / Fly anyway)
  fgfs-mga controls bind JOB   set one job again, keep the rest (e.g. bind brakes, bind brake_left_axis)
  fgfs-mga controls unbind JOB clear one job (e.g. unbind propeller)
  Run "fgfs-mga controls bind" with no job for the full list.

Options: --all (any joystick, not only Saitek), --dry-run (print the XML, write nothing),
         --restart (wizard: ignore saved progress and start over)

Why: FlightGear's event input names joystick buttons button-trigger, button-thumb ...
(button-0..9 are a different Linux key range that sticks never send) and axes
abs-x-translate, abs-z-rotate ... Values arrive as 0..1, so they must be re-centred.
This writes ~/.fgfs/Input/Event/Saitek/fgfs-mga-<device>.xml and moves any older
configs for the same device to a backup folder so FlightGear only sees one.
"""
import json
import os
import re
import select
import shutil
import sys
import time
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

HOME = os.path.expanduser("~")
FG_HOME = os.environ.get("FG_HOME", os.path.join(HOME, ".fgfs"))
EVENT_DIR = os.path.join(FG_HOME, "Input", "Event")
OUT_DIR = os.path.join(EVENT_DIR, "Saitek")
MAP_FILE = os.path.join(HOME, ".config", "fgfs-mga", "controls.json")
SHARE = os.path.join(HOME, ".local", "share", "fgfs-mga")
SAITEK_VENDOR = 0x06A3

# --- FlightGear 2024.1 FGLinuxEventInput.cxx names (copied from the source on this board) ---
EV_KEY, EV_ABS = 1, 3
KEY_NAMES = {}
for i in range(10):
    KEY_NAMES[0x100 + i] = "button-%d" % i
for code, n in zip(range(0x110, 0x118), "left right middle side extra forward back task".split()):
    KEY_NAMES[code] = "button-" + n
for code, n in zip(range(0x120, 0x130), ("trigger thumb thumb2 top top2 pinkie base base2 base3 "
                                         "base4 base5 base6").split() + [None, None, None, "dead"]):
    if n:
        KEY_NAMES[code] = "button-" + n
for code, n in zip(range(0x130, 0x13F), "a b c x y z tl tr tl2 tr2 select start mode thumbl thumbr".split()):
    KEY_NAMES[code] = "button-" + n
KEY_NAMES[0x150], KEY_NAMES[0x151] = "button-gear-down", "button-gear-up"
ABS_NAMES = {0x00: "abs-x-translate", 0x01: "abs-y-translate", 0x02: "abs-z-translate",
             0x03: "abs-x-rotate", 0x04: "abs-y-rotate", 0x05: "abs-z-rotate",
             0x06: "abs-throttle", 0x07: "abs-rudder", 0x08: "abs-wheel", 0x09: "abs-gas",
             0x0A: "abs-brake", 0x10: "abs-hat0-x", 0x11: "abs-hat0-y", 0x12: "abs-hat1-x",
             0x13: "abs-hat1-y", 0x14: "abs-hat2-x", 0x15: "abs-hat2-y", 0x16: "abs-hat3-x",
             0x17: "abs-hat3-y", 0x28: "abs-misc"}
HAT_CODES = set(range(0x10, 0x18))
PLAIN = {0x00: "X", 0x01: "Y", 0x02: "Z", 0x03: "RX", 0x04: "RY", 0x05: "RZ (twist)", 0x06: "throttle",
         0x07: "rudder", 0x10: "hat X", 0x11: "hat Y", 0x28: "misc"}

# --- what each function does in FlightGear (GA trainer) ---
AXES = [  # id, kind, prompt, required
    ("aileron", "bi", "ROLL (aileron): hold the stick fully RIGHT", True),
    ("elevator", "bi", "PITCH (elevator): hold the stick fully FORWARD (nose down)", True),
    ("rudder", "bi", "RUDDER: twist the stick (or press the pedal) fully RIGHT and hold", True),
    ("throttle", "uni", "THROTTLE", True),
    ("mixture", "uni", "MIXTURE (optional, e.g. the second stick's throttle)", False),
    ("propeller", "uni", "PROPELLER rpm (optional, only the Arrow/Seminole have one)", False),
]
# The wizard asks for these buttons, in this order. Every job (these and the rest) is in BUTTON_JOBS.
BUTTONS = ["brakes", "ptt", "flaps_down", "flaps_up", "trim_down", "trim_up", "parking_brake",
           "view_next", "view_reset", "center"]
GLANCE_DEG = (60, 30)  # hat: look left/right and up/down while held

# --- every job, for the GUI and `bind`. Groups show in this order.
GROUPS = ["Flight", "Engine", "Gear and flaps", "Trim", "Brakes", "Lights", "Radios", "Autopilot",
          "Views", "Sim", "Ag"]


def _axis(group, title, kind, props, hint, probe=None):
    return {"group": group, "title": title, "kind": kind, "props": props, "hint": hint, "probe": probe}


E0, E1 = "/controls/engines/engine[0]/", "/controls/engines/engine[1]/"
TWIN = ["engine[1]", 'engine n="1"']   # an aircraft file that mentions a second engine
AXIS_JOBS = {
    "aileron": _axis("Flight", "Roll (aileron)", "bi", ["/controls/flight/aileron"], "move the stick fully RIGHT"),
    "elevator": _axis("Flight", "Pitch (elevator)", "bi", ["/controls/flight/elevator"],
                      "push the stick fully FORWARD (nose down)"),
    "rudder": _axis("Flight", "Rudder", "bi", ["/controls/flight/rudder"], "twist (or press the pedal) fully RIGHT"),
    "throttle": _axis("Engine", "Throttle, all engines", "uni", [E0 + "throttle", E1 + "throttle"],
                      ("IDLE (closed)", "FULL power")),
    "mixture": _axis("Engine", "Mixture, all engines", "uni", [E0 + "mixture", E1 + "mixture"],
                     ("IDLE CUT-OFF (lean)", "FULL RICH"), ["mixture"]),
    "propeller": _axis("Engine", "Propeller rpm, all engines", "uni",
                       [E0 + "propeller-pitch", E1 + "propeller-pitch"], ("LOW rpm", "HIGH rpm"), ["propeller-pitch"]),
    "throttle_1": _axis("Engine", "Throttle, left engine", "uni", [E0 + "throttle"], ("IDLE", "FULL power"), TWIN),
    "throttle_2": _axis("Engine", "Throttle, right engine", "uni", [E1 + "throttle"], ("IDLE", "FULL power"), TWIN),
    "mixture_1": _axis("Engine", "Mixture, left engine", "uni", [E0 + "mixture"], ("CUT-OFF", "FULL RICH"), TWIN),
    "mixture_2": _axis("Engine", "Mixture, right engine", "uni", [E1 + "mixture"], ("CUT-OFF", "FULL RICH"), TWIN),
    "propeller_1": _axis("Engine", "Propeller, left engine", "uni", [E0 + "propeller-pitch"],
                         ("LOW rpm", "HIGH rpm"), TWIN),
    "propeller_2": _axis("Engine", "Propeller, right engine", "uni", [E1 + "propeller-pitch"],
                         ("LOW rpm", "HIGH rpm"), TWIN),
    "cowl_flaps_axis": _axis("Engine", "Cowl flaps lever", "uni", [E0 + "cowl-flaps-norm", E1 + "cowl-flaps-norm"],
                             ("CLOSED", "OPEN"), ["cowl-flaps"]),
    "flaps_axis": _axis("Gear and flaps", "Flaps lever", "uni", ["/controls/flight/flaps"], ("UP", "fully DOWN")),
    "elevator_trim_axis": _axis("Trim", "Elevator trim wheel", "bi", ["/controls/flight/elevator-trim"],
                                "move it fully toward nose DOWN"),
    "aileron_trim_axis": _axis("Trim", "Aileron trim knob", "bi", ["/controls/flight/aileron-trim"],
                               "move it fully RIGHT", ["aileron-trim"]),
    "rudder_trim_axis": _axis("Trim", "Rudder trim knob", "bi", ["/controls/flight/rudder-trim"],
                              "move it fully RIGHT", ["rudder-trim"]),
    "brake_left_axis": _axis("Brakes", "Left toe brake (pedal)", "uni", ["/controls/gear/brake-left"],
                             ("released", "fully pressed")),
    "brake_right_axis": _axis("Brakes", "Right toe brake (pedal)", "uni", ["/controls/gear/brake-right"],
                              ("released", "fully pressed")),
}
STICKS = {j for j, a in AXIS_JOBS.items() if a["kind"] == "bi"}   # centred on -1..1
AXIS_PROP = {j: a["props"][0] for j, a in AXIS_JOBS.items()}
UNI_ENDS = {j: a["hint"] for j, a in AXIS_JOBS.items() if a["kind"] == "uni"}


def _nas(s):
    return ("nasal", s)


def _btn(group, title, press, release=None, repeat=False, probe=None):
    return {"group": group, "title": title, "press": press, "release": release or [], "repeat": repeat,
            "probe": probe}


def _toggle(group, title, props, probe):
    return _btn(group, title, [("toggle", p) for p in props], probe=probe)


def _hold(group, title, prop, probe=None):
    return _btn(group, title, [("assign", prop, "true")], [("assign", prop, "false")], probe=probe)


def _kap(fn):  # only does something on aircraft that load the KAP 140 autopilot
    return [_nas('if (contains(globals, "kap140")) kap140.%s();' % fn)]


def _cowl(step):
    return [_nas('foreach (var e; [0, 1]) { var p = "/controls/engines/engine[" ~ e ~ "]/cowl-flaps-norm";'
                 ' setprop(p, math.min(1, math.max(0, (getprop(p) or 0) + %s))); }' % step)]


FUEL_CYCLE = ('var l = getprop("/controls/fuel/tank[0]/selected"); var r = getprop("/controls/fuel/tank[1]/selected");'
              ' if (l and r) { l = 1; r = 0; } elsif (l) { l = 0; r = 1; } else { l = 1; r = 1; }'
              ' setprop("/controls/fuel/tank[0]/selected", l); setprop("/controls/fuel/tank[1]/selected", r);'
              ' gui.popupTip("Fuel: " ~ (l and r ? "both" : (l ? "left" : "right")));')
HOLD_PROP = "/input/fgfs-mga/brake-hold"   # the brakes button also sets this, for the rudder/brake split
BUTTON_JOBS = {
    "brakes": _btn("Brakes", "Wheel brakes, both (hold)",
                   [_nas("controls.applyBrakes(1);"), ("assign", HOLD_PROP, "true")],
                   [_nas("controls.applyBrakes(0);"), ("assign", HOLD_PROP, "false")]),
    "brake_left": _btn("Brakes", "Left brake (hold)", [_nas("controls.applyBrakes(1, -1);")],
                       [_nas("controls.applyBrakes(0, -1);")]),
    "brake_right": _btn("Brakes", "Right brake (hold)", [_nas("controls.applyBrakes(1, 1);")],
                        [_nas("controls.applyBrakes(0, 1);")]),
    "parking_brake": _btn("Brakes", "Parking brake on/off", [_nas("controls.applyParkingBrake(1);")],
                          [_nas("controls.applyParkingBrake(0);")]),
    "starter": _btn("Engine", "Starter (hold)", [_nas("controls.startEngine(1);")], [_nas("controls.startEngine(0);")]),
    "mags_up": _btn("Engine", "Magnetos one step up (OFF, R, L, BOTH, START)", [_nas("controls.stepMagnetos(1);")],
                    [_nas("controls.stepMagnetos(0);")]),
    "mags_down": _btn("Engine", "Magnetos one step down", [_nas("controls.stepMagnetos(-1);")],
                      [_nas("controls.stepMagnetos(0);")]),
    "primer": _hold("Engine", "Primer (hold)", E0 + "primer", ["primer"]),
    "carb_heat": _toggle("Engine", "Carburettor heat on/off", ["/controls/anti-ice/engine[0]/carb-heat",
                                                               "/controls/anti-ice/engine[1]/carb-heat"], ["carb-heat"]),
    "fuel_pump": _toggle("Engine", "Electric fuel pump on/off", [E0 + "fuel-pump", E1 + "fuel-pump"], ["fuel-pump"]),
    "fuel_selector": _btn("Engine", "Fuel tank: both, left, right", [_nas(FUEL_CYCLE)], probe=["selected"]),
    "cowl_open": _btn("Engine", "Cowl flaps open a little (hold)", _cowl("0.05"), repeat=True, probe=["cowl-flaps"]),
    "cowl_close": _btn("Engine", "Cowl flaps close a little (hold)", _cowl("-0.05"), repeat=True, probe=["cowl-flaps"]),
    "flaps_down": _btn("Gear and flaps", "Flaps down one notch", [_nas("controls.flapsDown(1);")],
                       [_nas("controls.flapsDown(0);")]),
    "flaps_up": _btn("Gear and flaps", "Flaps up one notch", [_nas("controls.flapsDown(-1);")],
                     [_nas("controls.flapsDown(0);")]),
    "gear_down": _btn("Gear and flaps", "Gear down", [_nas("controls.gearDown(1);")], [_nas("controls.gearDown(0);")],
                      probe=["gear-down"]),
    "gear_up": _btn("Gear and flaps", "Gear up", [_nas("controls.gearDown(-1);")], [_nas("controls.gearDown(0);")],
                    probe=["gear-down"]),
    "gear_toggle": _btn("Gear and flaps", "Gear up/down", [_nas("controls.gearToggle();")], probe=["gear-down"]),
    "speedbrake": _toggle("Gear and flaps", "Speed brake in/out", ["/controls/flight/speedbrake"], ["speedbrake"]),
    "spoilers_more": _btn("Gear and flaps", "Spoilers one step out", [_nas("controls.stepSpoilers(1);")],
                          probe=["spoilers"]),
    "spoilers_less": _btn("Gear and flaps", "Spoilers one step in", [_nas("controls.stepSpoilers(-1);")],
                          probe=["spoilers"]),
    "trim_down": _btn("Trim", "Elevator trim nose DOWN (hold)", [_nas("controls.elevatorTrim(1);")], repeat=True),
    "trim_up": _btn("Trim", "Elevator trim nose UP (hold)", [_nas("controls.elevatorTrim(-1);")], repeat=True),
    "aileron_trim_left": _btn("Trim", "Aileron trim LEFT (hold)", [_nas("controls.aileronTrim(-1);")], repeat=True,
                              probe=["aileron-trim"]),
    "aileron_trim_right": _btn("Trim", "Aileron trim RIGHT (hold)", [_nas("controls.aileronTrim(1);")], repeat=True,
                               probe=["aileron-trim"]),
    "rudder_trim_left": _btn("Trim", "Rudder trim LEFT (hold)", [_nas("controls.rudderTrim(-1);")], repeat=True,
                             probe=["rudder-trim"]),
    "rudder_trim_right": _btn("Trim", "Rudder trim RIGHT (hold)", [_nas("controls.rudderTrim(1);")], repeat=True,
                              probe=["rudder-trim"]),
    "center": _btn("Trim", "Centre trims and controls", [_nas("controls.centerFlightControls();")]),
    "landing_light": _toggle("Lights", "Landing light on/off", ["/controls/lighting/landing-lights",
                                                                "/controls/lighting/landing-light"], ["landing-light"]),
    "taxi_light": _toggle("Lights", "Taxi light on/off", ["/controls/lighting/taxi-light"], ["taxi-light"]),
    "nav_lights": _toggle("Lights", "Nav lights on/off", ["/controls/lighting/nav-lights"], ["nav-lights"]),
    "strobe": _toggle("Lights", "Strobes on/off", ["/controls/lighting/strobe"], ["lighting/strobe"]),
    "beacon": _toggle("Lights", "Beacon on/off", ["/controls/lighting/beacon"], ["lighting/beacon"]),
    "ptt": _btn("Radios", "Push-to-talk COM1 for ATC (hold)", [_nas("controls.ptt(1);")], [_nas("controls.ptt(0);")]),
    "ptt2": _btn("Radios", "Push-to-talk COM2 (hold)", [_nas("controls.ptt(2);")], [_nas("controls.ptt(0);")]),
    "com1_swap": _btn("Radios", "COM1 swap active/standby", [("swap", "/instrumentation/comm[0]/frequencies/selected-mhz",
                                                               "/instrumentation/comm[0]/frequencies/standby-mhz")]),
    "com2_swap": _btn("Radios", "COM2 swap active/standby", [("swap", "/instrumentation/comm[1]/frequencies/selected-mhz",
                                                               "/instrumentation/comm[1]/frequencies/standby-mhz")],
                      probe=["comm[1]"]),
    "nav1_swap": _btn("Radios", "NAV1 swap active/standby", [("swap", "/instrumentation/nav[0]/frequencies/selected-mhz",
                                                               "/instrumentation/nav[0]/frequencies/standby-mhz")]),
    "ident": _hold("Radios", "Transponder IDENT", "/instrumentation/transponder/inputs/ident-btn"),
    "ap_disconnect": _btn("Autopilot", "Autopilot disconnect", [_nas("controls.autopilotDisconnect();")]),
    "kap_ap": _btn("Autopilot", "KAP 140: AP on/off", _kap("apButton"), probe=["kap140"]),
    "kap_hdg": _btn("Autopilot", "KAP 140: HDG", _kap("hdgButton"), probe=["kap140"]),
    "kap_nav": _btn("Autopilot", "KAP 140: NAV", _kap("navButton"), probe=["kap140"]),
    "kap_apr": _btn("Autopilot", "KAP 140: APR", _kap("aprButton"), probe=["kap140"]),
    "kap_alt": _btn("Autopilot", "KAP 140: ALT hold", _kap("altButton"), probe=["kap140"]),
    "kap_up": _btn("Autopilot", "KAP 140: UP", _kap("upButton"), probe=["kap140"]),
    "kap_down": _btn("Autopilot", "KAP 140: DN", _kap("downButton"), probe=["kap140"]),
    "view_next": _btn("Views", "Next view (cockpit, outside, tower...)", [_nas("view.stepView(1);")]),
    "view_prev": _btn("Views", "Previous view", [_nas("view.stepView(-1);")]),
    "view_reset": _btn("Views", "Back to the cockpit view, looking ahead", [_nas("view.resetView();")]),
    "zoom_in": _btn("Views", "Zoom in (hold)", [_nas("view.decrease();")], repeat=True),
    "zoom_out": _btn("Views", "Zoom out (hold)", [_nas("view.increase();")], repeat=True),
    "zoom_reset": _btn("Views", "Zoom back to normal", [_nas("view.resetFOV();")]),
    "look_left": _btn("Views", "Turn your head left (hold)", [_nas("view.panViewDir(1);")], repeat=True),
    "look_right": _btn("Views", "Turn your head right (hold)", [_nas("view.panViewDir(-1);")], repeat=True),
    "look_up": _btn("Views", "Look up (hold)", [_nas("view.panViewPitch(1);")], repeat=True),
    "look_down": _btn("Views", "Look down (hold)", [_nas("view.panViewPitch(-1);")], repeat=True),
    "pause": _btn("Sim", "Pause on/off", [("cmd", "pause")]),
    "replay": _btn("Sim", "Instant replay", [("cmd", "replay")]),
    "speed_up": _btn("Sim", "Sim speed up (time x2)", [_nas("controls.speedup(1);")]),
    "slow_down": _btn("Sim", "Sim speed down", [_nas("controls.speedup(-1);")]),
    "screenshot": _btn("Sim", "Screenshot", [("cmd", "screen-capture")]),
    "atc_menu": _btn("Sim", "ATC menu", [("cmd", "ATC-dialog")]),
    "spray": _toggle("Ag", "Spray on/off (for aircraft that read /controls/ag/spray)", ["/controls/ag/spray"],
                     ["controls/ag/spray"]),
}
HAT_JOB = {"group": "Views", "title": "Glance around (hat)", "hint": "push the hat in any direction", "probe": None}
JOBS = dict(AXIS_JOBS)
JOBS["hat"] = HAT_JOB
JOBS.update(BUTTON_JOBS)
CORE = ["aileron", "elevator", "rudder", "throttle", "brakes"]   # flying without these is hard work

# --- response shaping, per axis, per aircraft (or "default")
SHAPE_KEYS = ["deadzone", "sensitivity", "expo", "limit", "offset", "smooth", "split"]
SHAPE_RANGE = {"deadzone": (0.0, 0.3), "sensitivity": (0.3, 2.0), "expo": (0.0, 1.0), "limit": (0.2, 1.0),
               "offset": (-0.3, 0.3), "smooth": (0.0, 0.95)}
SHAPE_HELP = {"deadzone": "Dead zone: how far the stick moves before anything happens",
              "sensitivity": "Sensitivity: output per unit of stick (above 1 reaches full sooner)",
              "expo": "Curve: 0 straight, 1 soft in the middle and strong at the ends",
              "limit": "End limit: the most the control can reach",
              "offset": "Centre offset (trim): shifts the whole range",
              "smooth": "Smoothing: 0 instant, higher eases out jitter (adds lag)",
              "split": "Rudder steers the brakes while the brake button is held"}


def shape_default(job):
    return {"deadzone": 0.04 if job in STICKS else 0.0, "sensitivity": 1.0, "expo": 0.0, "limit": 1.0,
            "offset": 0.0, "smooth": 0.0, "split": False}


def get_shape(mapping, job, aircraft=None):
    shapes = (mapping or {}).get("shapes") or {}
    s = shape_default(job)
    s.update((shapes.get("default") or {}).get(job) or {})
    if aircraft:
        s.update((shapes.get(aircraft) or {}).get(job) or {})
    return s


def apply_shape(job, x, s):
    """Calibrated value (-1..1 for sticks, 0..1 for levers) -> what FlightGear gets. Mirrored in the Nasal."""
    stick = job in STICKS
    a = abs(x) if stick else max(0.0, min(1.0, x))
    dz = s["deadzone"]
    a = 0.0 if a <= dz else (a - dz) / (1.0 - dz)
    a = (1.0 - s["expo"]) * a + s["expo"] * a ** 3
    a = min(a * s["sensitivity"], s["limit"])
    y = (a if x >= 0 else -a) if stick else a
    y += s["offset"]
    return max(-1.0, min(1.0, y)) if stick else max(0.0, min(1.0, y))


def job_title(job):
    return JOBS[job]["title"]


def shape_handles(job, s):
    """Where the curve editor draws its three drag handles, in (input, output) units:
    dead zone on the rest line, the curve's midpoint (sets the curve), and the end limit."""
    dz = s["deadzone"]
    xm = dz + (1.0 - dz) * 0.5
    return {"deadzone": (dz, s["offset"] if job in STICKS else max(0.0, s["offset"])),
            "curve": (xm, apply_shape(job, xm, s)),
            "limit": (1.0, max(-1.0, min(1.0, s["limit"] + s["offset"])))}


def drag_shape(job, s, handle, x, y):
    """Turn a handle dragged to (input x, output y) into new settings {key: value}, clamped to SHAPE_RANGE.
    Only the positive half is edited; sticks are mirrored."""
    def clamp(key, v):
        lo, hi = SHAPE_RANGE[key]
        return round(max(lo, min(hi, v)), 3)
    if handle == "deadzone":
        return {"deadzone": clamp("deadzone", abs(x))}
    if handle == "limit":
        return {"limit": clamp("limit", abs(y) - s["offset"])}
    if handle == "curve":
        base = (abs(y) - s["offset"]) / max(s["sensitivity"], 1e-6)   # output at the midpoint before the limit
        return {"expo": round(max(0.0, min(1.0, (0.5 - base) / 0.375)), 3)}
    return {}


def find_aircraft(dirs=None):
    """{aircraft id: folder} for every *-set.xml under the aircraft folders (one level of catalog nesting)."""
    dirs = dirs or [os.path.join(FG_HOME, "Aircraft")]
    out = {}
    for base in dirs:
        for root, subdirs, files in os.walk(base):
            if root.count(os.sep) - base.count(os.sep) > 3:
                subdirs[:] = []
                continue
            subdirs[:] = [d for d in subdirs if d not in ("Models", "Sounds", "Nasal", "Systems", "Liveries")]
            for f in files:
                if f.endswith("-set.xml"):
                    out.setdefault(f[:-8], root)
    return dict(sorted(out.items()))


def aircraft_text(folder, limit=24 << 20):
    """All the XML and Nasal text in one aircraft folder, lower-cased, for the support marks."""
    parts, size = [], 0
    for root, _dirs, files in os.walk(folder):
        for f in files:
            if f.endswith((".xml", ".nas")):
                try:
                    with open(os.path.join(root, f), errors="replace") as fh:
                        t = fh.read()
                except OSError:
                    continue
                parts.append(t)
                size += len(t)
                if size > limit:
                    return "\n".join(parts).lower()
    return "\n".join(parts).lower()


def supported(job, text):
    """True if the aircraft's files mention what the job drives, False if not, None if no aircraft picked."""
    if text is None:
        return None
    probe = JOBS[job].get("probe")
    return True if not probe else any(p.lower() in text for p in probe)


def key_name(code):
    return KEY_NAMES.get(code, "button-%d" % code)


def abs_name(code):
    return ABS_NAMES.get(code, "abs-%d" % code)


def hat_codes(d):
    return [c for c in (0x10, 0x11) if c in [x[0] for x in describe(d)[0]]]


def slug(name):
    return re.sub(r"[^A-Za-z0-9]+", "-", name).strip("-") or "joystick"


# ------------------------------------------------------------------ devices
def evdev_mod():
    try:
        import evdev  # noqa: F401
        return evdev
    except ImportError:
        sys.exit("python3-evdev is missing: sudo apt install python3-evdev")


SYS_INPUT = os.environ.get("FGFS_MGA_SYS_INPUT", "/sys/class/input")


def is_dead_copy(path):
    """True for an input node whose USB device is gone: a copy a failed driver probe left behind. It opens
    fine but never sends anything, and only a restart clears it (replugging adds a fresh copy beside it)."""
    if not os.path.isdir(SYS_INPUT):
        return False
    return not os.path.exists(os.path.join(SYS_INPUT, os.path.basename(path), "device"))


def find_devices(all_sticks=False):
    evdev = evdev_mod()
    found, denied = [], []
    for path in sorted(evdev.list_devices(), key=lambda p: int(re.sub(r"\D", "", p) or 0)):
        if is_dead_copy(path):
            continue
        try:
            d = evdev.InputDevice(path)
        except PermissionError:
            denied.append(path)
            continue
        caps = d.capabilities()
        if EV_ABS not in caps:
            continue
        is_saitek = d.info.vendor == SAITEK_VENDOR or re.search(r"saitek|cyborg", d.name, re.I)
        keys = set(caps.get(EV_KEY, []))
        joyish = keys & set(range(0x120, 0x130)) or keys & set(range(0x130, 0x13F))
        if is_saitek or (all_sticks and joyish):
            found.append(d)
    if not found and denied:
        print("Can't read %s. Unplug and replug the controllers (the udev rule gives you access),"
              " or check /etc/udev/rules.d/70-flightgear-saitek-input.rules." % ", ".join(denied))
    return found


def dev_key(d):
    return "%04x:%04x %s" % (d.info.vendor, d.info.product, d.name)


def describe(d):
    caps = d.capabilities(absinfo=True)
    axes, buttons = [], []
    for code, ai in caps.get(EV_ABS, []):
        n = ABS_NAMES.get(code, "unknown-3-%d" % code)
        axes.append((code, n, ai.min, ai.max, ai.value))
    for code in caps.get(EV_KEY, []):
        buttons.append((code, key_name(code)))
    return axes, buttons


def cmd_scan(args):
    devs = find_devices("--all" in args)
    if not devs:
        print("No Saitek controller found. Plug both in (straight into the board, not a hub if you can) and run again.")
        return 1
    for d in devs:
        axes, buttons = describe(d)
        ff = " (force feedback capable)" if 0x15 in d.capabilities() else ""
        print("%s  %s  usb %04x:%04x%s" % (d.path, d.name, d.info.vendor, d.info.product, ff))
        for code, n, lo, hi, v in axes:
            print("   axis   %-17s %-12s range %d..%d, now %d" % (n, PLAIN.get(code, ""), lo, hi, v))
        print("   buttons (%d): %s" % (len(buttons), " ".join(b[1].replace("button-", "") for b in buttons)))
    return 0


# ------------------------------------------------------------------ mapping
def load_map():
    try:
        with open(MAP_FILE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def norm(d, code, value):
    ai = d.absinfo(code)
    return 0.0 if ai.max == ai.min else (value - ai.min) / float(ai.max - ai.min)


def snapshot(devs):
    snap = {}
    for d in devs:
        for code, _n, _lo, _hi, _v in describe(d)[0]:
            snap[(d.path, code)] = norm(d, code, d.absinfo(code).value)
    return snap


def ask(prompt):
    try:
        return input(prompt).strip().lower()
    except EOFError:
        return "q"


def pick_axis(devs, a, b, used, hats_ok=False, min_move=0.25):
    best, bd = None, 0.0
    for k in a:
        if k in used or (k[1] in HAT_CODES and not hats_ok):
            continue
        diff = b.get(k, a[k]) - a[k]
        if abs(diff) > abs(bd):
            best, bd = k, diff
    if best is None or abs(bd) < min_move:
        return None, 0
    return best, (1 if bd > 0 else -1)


def wait_button(devs, used, timeout=30):
    """First new key press on any device. Enter on the keyboard = skip."""
    for d in devs:
        while d.read_one() is not None:
            pass
    end = time.time() + timeout
    while time.time() < end:
        r, _w, _x = select.select([sys.stdin] + devs, [], [], 0.2)
        for src in r:
            if src is sys.stdin:
                sys.stdin.readline()
                return None
            for ev in src.read():
                if ev.type == EV_KEY and ev.value == 1 and (src.path, ev.code) not in used:
                    return (src.path, ev.code)
    return None


def calibrate(devs):
    """Track every axis's lowest and highest reading until Enter (normalised 0..1)."""
    lo, hi = {}, {}
    for d in devs:
        while d.read_one() is not None:
            pass
    while True:
        r, _w, _x = select.select([sys.stdin] + devs, [], [], 0.2)
        for src in r:
            if src is sys.stdin:
                sys.stdin.readline()
                return lo, hi
            for ev in src.read():
                if ev.type == EV_ABS and ev.code not in HAT_CODES:
                    k = (src.path, ev.code)
                    n = norm(src, ev.code, ev.value)
                    lo[k] = min(lo.get(k, n), n)
                    hi[k] = max(hi.get(k, n), n)


def cal_for(k, lo, hi, centre):
    if k in lo and hi[k] - lo[k] >= 0.3:
        return [round(lo[k], 4), round(centre.get(k, (lo[k] + hi[k]) / 2), 4), round(hi[k], 4)]
    return None


PARTIAL = os.path.join(HOME, ".config", "fgfs-mga", "controls-partial.json")


def save_partial(names, state):
    """Progress after every step, so a stop or a crash doesn't mean starting over."""
    def keyed(dct):
        return {"%s|%d" % (dev_key(names[p]), c): v for (p, c), v in dct.items()}
    out = {"lo": keyed(state["lo"]), "hi": keyed(state["hi"]), "centre": keyed(state["centre"]),
           "mapping": state["mapping"], "axes_done": state["axes_done"], "buttons_done": state["buttons_done"]}
    os.makedirs(os.path.dirname(PARTIAL), exist_ok=True)
    with open(PARTIAL + ".tmp", "w") as f:
        json.dump(out, f, indent=1)
    os.replace(PARTIAL + ".tmp", PARTIAL)


def load_partial(devs):
    """Saved progress for these same controllers, or None."""
    try:
        with open(PARTIAL) as f:
            raw = json.load(f)
    except (OSError, ValueError):
        return None
    path_of = {dev_key(d): d.path for d in devs}

    def unkeyed(dct):
        out = {}
        for k, v in dct.items():
            dk, _, code = k.rpartition("|")
            if dk not in path_of:
                raise KeyError(dk)
            out[(path_of[dk], int(code))] = v
        return out
    try:
        state = {"lo": unkeyed(raw["lo"]), "hi": unkeyed(raw["hi"]), "centre": unkeyed(raw["centre"]),
                 "mapping": raw["mapping"], "axes_done": raw["axes_done"], "buttons_done": raw["buttons_done"]}
        for part in ("axes", "buttons"):
            for v in state["mapping"][part].values():
                if v["dev"] not in path_of:
                    raise KeyError(v["dev"])
    except (KeyError, ValueError, TypeError):
        return None
    return state


def cmd_wizard(args):
    devs = find_devices("--all" in args)
    if not devs:
        print("No Saitek controller found. Plug them in and run: fgfs-mga controls wizard")
        return 1
    names = {d.path: d for d in devs}
    path_of = {dev_key(d): d.path for d in devs}
    print("Found: " + "; ".join("%s (%s)" % (d.name, d.path) for d in devs))
    print("For each step, do what it says, keep holding, and press Enter with your other hand.")
    print("Type s then Enter to skip a step, q then Enter to stop (progress is kept).\n")
    state = None if "--restart" in args else load_partial(devs)
    if state and (state["axes_done"] or state["buttons_done"]):
        done = ", ".join(state["axes_done"] + state["buttons_done"])
        if ask("Picking up where you stopped (done: %s). Press Enter, or type r to start over " % done) == "r":
            state = None
    if not state:
        print("1) Calibrate: move BOTH sticks in full circles, twist each fully left and right,")
        print("   and run each throttle lever end to end, two or three times. Then press Enter.")
        cal_lo, cal_hi = calibrate(devs)
        if ask("2) Now let go of everything (sticks centred) and press Enter ") == "q":
            return 1
        state = {"lo": cal_lo, "hi": cal_hi, "centre": snapshot(devs),
                 "mapping": {"axes": {}, "buttons": {}, "hat": {}}, "axes_done": [], "buttons_done": []}
        save_partial(names, state)
    mapping, centre = state["mapping"], state["centre"]
    used = {(path_of[a["dev"]], a["code"]) for a in mapping["axes"].values()}
    r = ""
    for fid, kind, prompt, required in AXES:
        if fid in state["axes_done"]:
            continue
        while True:
            if kind == "bi":
                r = ask("%s, press Enter %s" % (prompt, "" if required else "(s = skip) "))
                if r in ("s", "q"):
                    break
                # twists travel less than the stick, so a smaller move counts there
                k, direction = pick_axis(devs, centre, snapshot(devs), used, min_move=0.12 if fid == "rudder" else 0.2)
            else:
                end_lo, end_hi = UNI_ENDS[fid]
                r = ask("%s: set it to %s, press Enter %s" % (prompt, end_lo, "" if required else "(s = skip) "))
                if r in ("s", "q"):
                    break
                before = snapshot(devs)
                r = ask("  now move it to %s, press Enter " % end_hi)
                if r in ("s", "q"):
                    break
                k, direction = pick_axis(devs, before, snapshot(devs), used)
            if k is None:
                print("  didn't see anything move far enough; try again (s to skip)")
                continue
            used.add(k)
            mapping["axes"][fid] = {"dev": dev_key(names[k[0]]), "code": k[1], "dir": direction,
                                    "cal": cal_for(k, state["lo"], state["hi"], centre)}
            print("  -> %s on %s" % (PLAIN.get(k[1], abs_name(k[1])), names[k[0]].name))
            break
        if r == "q":
            print("Stopped. Run 'fgfs-mga controls wizard' again to carry on from here.")
            return 1
        state["axes_done"].append(fid)
        save_partial(names, state)
    # hat: glance view on the stick that does roll, if it has one
    roll = mapping["axes"].get("aileron")
    if "hat" not in state["buttons_done"]:
        for d in devs:
            if roll and dev_key(d) == roll["dev"]:
                codes = [c for c in (0x10, 0x11) if c in dict((x[0], 1) for x in describe(d)[0])]
                if codes and ask("Use the hat on %s to glance around while held? [Y/n] " % d.name) != "n":
                    mapping["hat"] = {"dev": dev_key(d), "codes": codes}
        state["buttons_done"].append("hat")
        save_partial(names, state)
    print("\nButtons: press the button you want for each job, or press Enter to leave it free.")
    btn_used = {(path_of[b["dev"]], b["code"]) for b in mapping["buttons"].values()}
    for fid in BUTTONS:
        what = BUTTON_JOBS[fid]["title"]
        if fid in state["buttons_done"]:
            continue
        print("  %-42s ... " % what, end="", flush=True)
        k = wait_button(devs, btn_used)
        if k is None:
            print("free")
        else:
            btn_used.add(k)
            mapping["buttons"][fid] = {"dev": dev_key(names[k[0]]), "code": k[1]}
            print("%s on %s" % (key_name(k[1]).replace("button-", ""), names[k[0]].name))
        state["buttons_done"].append(fid)
        save_partial(names, state)
    rc = write_all(devs, mapping, "--dry-run" in args)
    if rc == 0 and "--dry-run" not in args:
        os.remove(PARTIAL)
    return rc


def cmd_defaults(args):
    devs = find_devices("--all" in args)
    if not devs:
        print("No Saitek controller found.")
        return 1
    # primary = the stick with X/Y that has the most axes; Evo Force wins ties
    devs.sort(key=lambda d: (-len(describe(d)[0]), "evo" not in d.name.lower()))
    p = devs[0]
    acodes = [a[0] for a in describe(p)[0]]
    bcodes = [b[0] for b in describe(p)[1]]
    k = dev_key(p)
    m = {"axes": {}, "buttons": {}, "hat": {}}
    m["axes"]["aileron"] = {"dev": k, "code": 0x00, "dir": 1}
    m["axes"]["elevator"] = {"dev": k, "code": 0x01, "dir": -1}   # stick forward = low raw value
    for c in (0x05, 0x07):
        if c in acodes:
            m["axes"]["rudder"] = {"dev": k, "code": c, "dir": 1}
            break
    for c in (0x06, 0x02):
        if c in acodes:
            m["axes"]["throttle"] = {"dev": k, "code": c, "dir": -1}  # Saitek: lever forward = low raw value
            break
    if len(devs) > 1:
        sk = dev_key(devs[1])
        sc = [a[0] for a in describe(devs[1])[0]]
        for c in (0x06, 0x02):
            if c in sc:
                m["axes"]["mixture"] = {"dev": sk, "code": c, "dir": -1}
                break
    if 0x10 in acodes:
        m["hat"] = {"dev": k, "codes": [c for c in (0x10, 0x11) if c in acodes]}
    order = ["brakes", "ptt", "view_next", "view_reset", "flaps_up", "flaps_down",
             "trim_down", "trim_up", "parking_brake", "center"]
    for fid, code in zip(order, [c for c in bcodes if 0x120 <= c < 0x140]):
        m["buttons"][fid] = {"dev": k, "code": code}
    print("Wrote a best-guess layout. Run 'fgfs-mga controls test' to check it, or the wizard to set it by hand.")
    return write_all(devs, m, "--dry-run" in args)


# ------------------------------------------------------------------ XML
def interp_points(fid, a):
    """Calibrated axis -> list of (input, output) points FlightGear's interpolater uses, or None.
    Sticks work on the -1..1 value (after min-range/max-range) and come out -1..1 centred on the
    measured centre; levers work on the raw 0..1 value and come out 0..1, reversed if need be."""
    cal = a.get("cal")
    if not cal:
        return None
    lo, c, hi = cal
    if fid in STICKS:
        lo, c, hi = 2 * lo - 1, 2 * c - 1, 2 * hi - 1
        if not lo < c < hi:
            return None
        return [(lo, -1.0), (c, 0.0), (hi, 1.0)]
    return [(lo, 0.0), (hi, 1.0)] if a["dir"] > 0 else [(lo, 1.0), (hi, 0.0)]


def cal_value(fid, a, n):
    """Normalised device value n (0..1) -> the calibrated value the XML writes to the raw property."""
    pts = interp_points(fid, a)
    stick = fid in STICKS
    v = 2 * n - 1 if stick else n
    if pts:
        if v <= pts[0][0]:
            v = pts[0][1]
        elif v >= pts[-1][0]:
            v = pts[-1][1]
        else:
            for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
                if x0 <= v <= x1:
                    v = y0 + (y1 - y0) * (v - x0) / (x1 - x0)
                    break
        return v * a["dir"] if stick else v
    if stick:
        return v * a["dir"]
    return n if a["dir"] > 0 else 1 - n


def fg_value(fid, a, n, shape=None):
    """What FlightGear will put in the control for normalised input n (mirrors the XML and its Nasal)."""
    return apply_shape(fid, cal_value(fid, a, n), shape or shape_default(fid))


RAW = "/input/fgfs-mga/raw/"


def axis_xml(fid, a):
    """The event writes the calibrated value to /input/fgfs-mga/raw/<job>; the device's Nasal shapes it."""
    code, direction = a["code"], a["dir"]
    pts = interp_points(fid, a)
    stick = fid in STICKS
    lines = ["  <event>", "    <desc>%s</desc>" % escape(job_title(fid)), "    <name>%s</name>" % abs_name(code)]
    if stick:   # 0..1 from the device -> -1..1
        lines += ["    <min-range>0</min-range>", "    <max-range>1</max-range>"]
    if pts:     # measured ends and centre of this control, so its travel maps to the full range
        lines.append("    <interpolater>")
        for x, y in pts:
            lines.append("      <entry><ind>%.4f</ind><dep>%g</dep></entry>" % (x, y))
        lines.append("    </interpolater>")
        offset, factor = 0.0, (float(direction) if stick else 1.0)
    elif stick:
        offset, factor = 0.0, float(direction)
    else:
        offset, factor = (0.0, 1.0) if direction > 0 else (-1.0, -1.0)
    lines += ["    <binding>", "      <command>property-scale</command>",
              "      <property>%s%s</property>" % (RAW, fid),
              "      <offset>%g</offset>" % offset, "      <factor>%g</factor>" % factor, "    </binding>",
              "  </event>"]
    return lines


def hat_xml(code):
    deg = GLANCE_DEG[0] if code in (0x10, 0x12) else GLANCE_DEG[1]
    prop = "/sim/current-view/goal-heading-offset-deg" if code in (0x10, 0x12) else "/sim/current-view/goal-pitch-offset-deg"
    # hat right / hat up -> look right / look up (FlightGear heading offset is positive to the left)
    return ["  <event>", "    <desc>Glance %s while the hat is held</desc>" % ("left/right" if deg == 60 else "up/down"),
            "    <name>%s</name>" % abs_name(code), "    <min-range>0</min-range>", "    <max-range>1</max-range>",
            "    <binding>", "      <command>property-scale</command>", "      <property>%s</property>" % prop,
            "      <factor>%d</factor>" % -deg, "    </binding>", "  </event>"]


def binding_xml(b, indent):
    sp = " " * indent
    kind = b[0]
    if kind == "nasal":
        body = ["<command>nasal</command>", "<script>%s</script>" % escape(b[1])]
    elif kind == "toggle":
        body = ["<command>property-toggle</command>", "<property>%s</property>" % b[1]]
    elif kind == "assign":
        body = ["<command>property-assign</command>", "<property>%s</property>" % b[1],
                "<value type=\"bool\">%s</value>" % b[2]]
    elif kind == "swap":
        body = ["<command>property-swap</command>", "<property>%s</property>" % b[1], "<property>%s</property>" % b[2]]
    elif kind == "cmd":
        body = ["<command>%s</command>" % b[1]]
    else:
        raise ValueError(b)
    return [sp + "<binding>"] + [sp + "  " + x for x in body] + [sp + "</binding>"]


def button_xml(fid, code):
    j = BUTTON_JOBS[fid]
    lines = ["  <event>", "    <desc>%s</desc>" % escape(j["title"]), "    <name>%s</name>" % key_name(code),
             "    <repeatable type=\"bool\">%s</repeatable>" % ("true" if j["repeat"] else "false")]
    for b in j["press"]:
        lines += binding_xml(b, 4)
    if j["release"]:
        lines.append("    <mod-up>")
        for b in j["release"]:
            lines += binding_xml(b, 6)
        lines.append("    </mod-up>")
    lines.append("  </event>")
    return lines


def _nas_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def shaping_nasal(jobs, mapping, slug_name):
    """Nasal that runs every frame: raw value -> dead zone, curve, sensitivity, limit, offset, smoothing ->
    the control properties, using the aircraft's own settings when there are some. Writes only on change,
    so the keyboard and autopilot can still move the controls."""
    shapes = (mapping.get("shapes") or {})
    tables = {}
    for ac in ["default"] + sorted(k for k in shapes if k != "default"):
        tables[ac] = {j: get_shape(mapping, j, None if ac == "default" else ac) for j in jobs}
    def row(s, j):
        return "[%g, %g, %g, %g, %g, %g, %d, %d]" % (s["deadzone"], s["sensitivity"], s["expo"], s["limit"],
                                                    s["offset"], s["smooth"], 1 if j in STICKS else 0,
                                                    1 if (s.get("split") and j == "rudder") else 0)
    tab = ",\n".join("  %s: {%s}" % (_nas_str(ac), ", ".join("%s: %s" % (_nas_str(j), row(s, j)) for j, s in t.items()))
                     for ac, t in tables.items())
    outs = ", ".join("%s: [%s]" % (_nas_str(j), ", ".join(_nas_str(p) for p in AXIS_JOBS[j]["props"])) for j in jobs)
    g = "fgfs_mga_loop_" + re.sub(r"[^A-Za-z0-9]", "_", slug_name)
    return """
var shapes = {
%s
};
var outs = {%s};
var last = {};
var smooth = {};
var clamp = func(v, a, b) { return v < a ? a : (v > b ? b : v); };
var shape = func(x, p) {
  var a = p[6] ? math.abs(x) : clamp(x, 0, 1);
  a = a <= p[0] ? 0 : (a - p[0]) / (1 - p[0]);
  a = (1 - p[2]) * a + p[2] * a * a * a;
  a = math.min(a * p[1], p[3]);
  var y = p[6] ? (x < 0 ? -a : a) : a;
  y = y + p[4];
  return p[6] ? clamp(y, -1, 1) : clamp(y, 0, 1);
};
var loop = func {
  var ac = getprop("/sim/aircraft") or "";
  var tab = contains(shapes, ac) ? shapes[ac] : shapes["default"];
  foreach (var j; keys(outs)) {
    var raw = getprop("%s" ~ j);
    if (raw == nil) continue;
    var p = contains(tab, j) ? tab[j] : shapes["default"][j];
    var y = shape(raw, p);
    if (p[5] > 0 and contains(smooth, j)) y = smooth[j] + (1 - p[5]) * (y - smooth[j]);
    smooth[j] = y;
    if (!contains(last, j) or math.abs(y - last[j]) > 0.0002) {
      last[j] = y;
      foreach (var prop; outs[j]) setprop(prop, y);
    }
    if (p[7] and getprop("%s")) {
      setprop("/controls/gear/brake-left", clamp(1 - y, 0, 1));
      setprop("/controls/gear/brake-right", clamp(1 + y, 0, 1));
    }
  }
};
if (contains(globals, "%s")) globals["%s"].stop();
globals["%s"] = maketimer(0, loop);
globals["%s"].start();
""" % (tab, outs, RAW, HOLD_PROP, g, g, g, g)


def device_xml(d, mapping):
    k = dev_key(d)
    head = ["<?xml version=\"1.0\"?>", "<!--", "  Written by fgfs-mga controls on %s." % time.strftime("%Y-%m-%d %H:%M"),
            "  %s (usb %04x:%04x). Change it with 'fgfs-mga controls gui'." % (escape(d.name), d.info.vendor, d.info.product)]
    body, axis_jobs = [], []
    for fid in AXIS_JOBS:
        a = mapping["axes"].get(fid)
        if a and a["dev"] == k:
            head.append("  %-18s %s%s%s" % (fid, PLAIN.get(a["code"], abs_name(a["code"])), " (reversed)" if a["dir"] < 0 else "",
                                            ", calibrated" if a.get("cal") else ""))
            body += axis_xml(fid, a)
            axis_jobs.append(fid)
    h = mapping.get("hat") or {}
    if h.get("dev") == k:
        head.append("  hat                glance around while held")
        for c in h["codes"]:
            body += hat_xml(c)
    for fid in BUTTON_JOBS:
        b = mapping["buttons"].get(fid)
        if b and b["dev"] == k:
            head.append("  %-24s %s" % (key_name(b["code"]).replace("button-", "button "), escape(BUTTON_JOBS[fid]["title"])))
            body += button_xml(fid, b["code"])
    if not body:
        return None
    head += ["-->", "<PropertyList>", "  <name>%s</name>" % escape(d.name),
             "  <debug-events type=\"bool\">false</debug-events>", "  <grab type=\"bool\">false</grab>"]
    if axis_jobs:
        head += ["  <nasal>", "    <open><![CDATA[" + shaping_nasal(axis_jobs, mapping, slug(d.name)) + "]]></open>",
                 "  </nasal>"]
    xml = "\n".join(head + body + ["</PropertyList>", ""])
    ET.fromstring(xml.split("?>", 1)[1])   # refuse to write broken XML
    return xml


def old_configs_for(name):
    hits = []
    for root, _dirs, files in os.walk(EVENT_DIR):
        for f in files:
            p = os.path.join(root, f)
            try:
                txt = open(p, errors="replace").read()
            except OSError:
                continue
            names = re.findall(r"<name>([^<]*)</name>", txt.split("<event>", 1)[0])
            if any(n.strip().lower() == name.lower() for n in names):
                hits.append(p)
    return hits


def write_all(devs, mapping, dry):
    outs, empty = [], []
    for d in devs:
        xml = device_xml(d, mapping)
        if xml:
            outs.append((d, os.path.join(OUT_DIR, "fgfs-mga-%s.xml" % slug(d.name)), xml))
        else:
            empty.append(d)
    if not outs and not empty:
        print("Nothing mapped, nothing written.")
        return 1
    if dry:
        for _d, p, x in outs:
            print("==== would write %s\n%s" % (p, x))
        return 0
    bk = os.path.join(SHARE, "backup-%s" % time.strftime("%Y%m%d-%H%M%S"), "input-event")
    moved = 0
    for d in [o[0] for o in outs] + empty:
        for old in old_configs_for(d.name):
            rel = os.path.relpath(old, EVENT_DIR)
            dst = os.path.join(bk, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.move(old, dst)
            moved += 1
    os.makedirs(OUT_DIR, exist_ok=True)
    for d, p, x in outs:
        tmp = p + ".tmp"
        with open(tmp, "w") as f:
            f.write(x)
        os.replace(tmp, p)
        print("Wrote %s" % p)
    os.makedirs(os.path.dirname(MAP_FILE), exist_ok=True)
    with open(MAP_FILE, "w") as f:
        json.dump(mapping, f, indent=1)
    if moved:
        print("Moved %d older config file(s) for these controllers to %s" % (moved, bk))
    print("\nFlightGear reads these at start. fgfs-mga turns on event input for you.")
    return cmd_show([])


def duplicates(mapping):
    """[(device, code, [jobs])] for any button or axis that more than one job uses on the same device."""
    seen = {}
    for part in ("axes", "buttons"):
        for job, v in (mapping.get(part) or {}).items():
            seen.setdefault((v["dev"], part, v["code"]), []).append(job)
    return [(k[0], k[2], jobs) for k, jobs in seen.items() if len(jobs) > 1]


def cmd_show(_args):
    m = load_map()
    if not m:
        print("No mapping yet. Run: fgfs-mga controls gui  (or: fgfs-mga controls wizard)")
        return 1
    print("Current controls (%s):" % MAP_FILE)
    for group in GROUPS:
        rows = []
        for fid in [j for j, v in JOBS.items() if v["group"] == group]:
            if fid in AXIS_JOBS and fid in m["axes"]:
                a = m["axes"][fid]
                rows.append("  %-36s %s on %s%s" % (job_title(fid), PLAIN.get(a["code"], abs_name(a["code"])),
                                                    a["dev"][10:], "  (reversed)" if a["dir"] < 0 else ""))
            elif fid == "hat" and (m.get("hat") or {}).get("dev"):
                rows.append("  %-36s hat on %s" % (job_title(fid), m["hat"]["dev"][10:]))
            elif fid in BUTTON_JOBS and fid in m["buttons"]:
                b = m["buttons"][fid]
                rows.append("  %-36s %s on %s" % (job_title(fid), key_name(b["code"]).replace("button-", "button "),
                                                  b["dev"][10:]))
        if rows:
            print(group + ":")
            print("\n".join(rows))
    free = [j for j in CORE if j not in m["axes"] and j not in m["buttons"]]
    if free:
        print("Not bound yet: " + ", ".join(job_title(j) for j in free))
    for dev, code, jobs in duplicates(m):
        print("Warning: %s on %s does several jobs: %s" % (key_name(code), dev[10:], ", ".join(jobs)))
    return 0


def cmd_test(args):
    m = load_map()
    devs = find_devices("--all" in args)
    if not m or not devs:
        print("Need a mapping and the controllers plugged in.")
        return 1
    bykey = {dev_key(d): d for d in devs}
    rev = {}
    for fid, a in m["axes"].items():
        if a["dev"] in bykey:
            rev[(bykey[a["dev"]].path, a["code"])] = fid
    btn = {(bykey[b["dev"]].path, b["code"]): fid for fid, b in m["buttons"].items() if b["dev"] in bykey}
    print("Move the controls; this shows what FlightGear will get. Ctrl+C to stop.")
    vals = {}
    try:
        while True:
            r, _w, _x = select.select(devs, [], [], 0.5)
            for d in r:
                for ev in d.read():
                    if ev.type == EV_ABS and (d.path, ev.code) in rev:
                        fid = rev[(d.path, ev.code)]
                        vals[fid] = fg_value(fid, m["axes"][fid], norm(d, ev.code, ev.value), get_shape(m, fid))
                    elif ev.type == EV_KEY and ev.value == 1:
                        print("\n  pressed %s -> %s" % (KEY_NAMES.get(ev.code, ev.code),
                                                       btn.get((d.path, ev.code), "not mapped")))
            line = "  ".join("%s %+.2f" % (k, vals[k]) for k in sorted(vals))
            print("\r" + line + " " * 8, end="", flush=True)
    except KeyboardInterrupt:
        print()
    return 0


def ffb_module():
    """The fgfs-mga-ffb tool next to this one (installed side by side), or None."""
    here = os.path.dirname(os.path.realpath(__file__))
    for path in (os.path.join(here, "fgfs-mga-ffb"), os.path.join(SHARE, "tools", "fgfs-mga-ffb")):
        if os.path.exists(path):
            try:
                from importlib.machinery import SourceFileLoader
                return SourceFileLoader("fgfs_mga_ffb", path).load_module(), path
            except Exception:  # a broken copy shouldn't take the controls window down
                return None, path
    return None, None


# ------------------------------------------------------------------ GUI
class Session:
    """Everything the GUI does, without the widgets, so it can be tested with fake sticks.

    Axis values are kept normalised 0..1. Every axis's lowest and highest reading since the
    window opened is tracked, so moving each control end to end once calibrates it.
    `aircraft` is the aircraft the response settings are edited for (None = all aircraft)."""

    def __init__(self, devs, mapping, aircraft_dirs=None):
        self.devs = devs
        self.names = {d.path: d for d in devs}
        self.path_of = {dev_key(d): d.path for d in devs}
        self.mapping = mapping if mapping else {"axes": {}, "buttons": {}, "hat": {}}
        self.mapping.setdefault("hat", {})
        self.mapping.setdefault("shapes", {})
        self.values, self.lo, self.hi, self.pressed = {}, {}, {}, set()
        for d in devs:
            for code, _n, _a, _b, v in describe(d)[0]:
                self.values[(d.path, code)] = norm(d, code, v)
        self.capture = None          # (job, starting values)
        self.dirty = False
        self.aircraft = None         # response settings target; None = all aircraft
        self.aircraft_dirs = aircraft_dirs
        self._ac_text = None
        self.message = "Move every stick, twist and lever end to end once (that calibrates them), then Bind any job."

    # --- aircraft and support marks
    def set_aircraft(self, aircraft, folder=None):
        self.aircraft = aircraft or None
        self._ac_text = aircraft_text(folder) if (aircraft and folder) else None

    def support(self, job):
        return supported(job, self._ac_text)

    # --- reading the sticks
    def poll(self):
        try:
            ready, _w, _x = select.select(self.devs, [], [], 0)
        except (OSError, ValueError):
            return
        for d in ready:
            try:
                for ev in d.read():
                    self.handle(d, ev)
            except (BlockingIOError, OSError):
                pass

    def handle(self, d, ev):
        k = (d.path, ev.code)
        if ev.type == EV_ABS:
            n = norm(d, ev.code, ev.value)
            self.values[k] = n
            if ev.code not in HAT_CODES:
                self.lo[k] = min(self.lo.get(k, n), n)
                self.hi[k] = max(self.hi.get(k, n), n)
            self._check_axis(d, k, n, ev)
        elif ev.type == EV_KEY:
            if ev.value:
                self.pressed.add(k)
                self._check_button(d, k)
            else:
                self.pressed.discard(k)

    # --- binding
    def start_capture(self, job):
        self.capture = (job, dict(self.values))
        if job in BUTTON_JOBS:
            hint = "press the button you want"
        elif job == "hat":
            hint = HAT_JOB["hint"]
        elif AXIS_JOBS[job]["kind"] == "bi":
            hint = AXIS_JOBS[job]["hint"]
        else:
            hint = "move it from %s to %s" % AXIS_JOBS[job]["hint"]
        self.message = "%s: %s (Cancel bind to stop)." % (job_title(job), hint)

    def cancel_capture(self):
        self.capture = None
        self.message = "Cancelled."

    def _part(self, job):
        return "hat" if job == "hat" else ("axes" if job in AXIS_JOBS else "buttons")

    def _users(self, part, k, job):
        return [j for j, v in self.mapping[part].items()
                if j != job and v.get("dev") in self.path_of and (self.path_of[v["dev"]], v["code"]) == k]

    def _check_axis(self, d, k, n, ev):
        if not self.capture:
            return
        job, base = self.capture
        if job == "hat":
            if ev.code in HAT_CODES and ev.value != 0:
                self.mapping["hat"] = {"dev": dev_key(d), "codes": hat_codes(d)}
                self._bound("Glance: hat on %s" % d.name)
            return
        if job not in AXIS_JOBS or ev.code in HAT_CODES or self._users("axes", k, job):
            return     # an axis another job uses is ignored, so a stick nudged while binding isn't stolen
        move = n - base.get(k, n)
        if abs(move) < (0.12 if job == "rudder" else 0.3):
            return
        stick = job in STICKS
        centre = {k: base[k]} if stick and k in base else {}
        self.mapping["axes"][job] = {"dev": dev_key(d), "code": ev.code, "dir": 1 if move > 0 else -1,
                                     "cal": cal_for(k, self.lo, self.hi, centre), "centre": base.get(k)}
        self._bound("%s: %s on %s" % (job_title(job), PLAIN.get(ev.code, abs_name(ev.code)), d.name))

    def _check_button(self, d, k):
        if not self.capture or self.capture[0] not in BUTTON_JOBS:
            return
        job = self.capture[0]
        was = self._users("buttons", k, job)
        for j in was:      # one button, one job on this stick: the old job lets go of it
            self.mapping["buttons"].pop(j, None)
        self.mapping["buttons"][job] = {"dev": dev_key(d), "code": k[1]}
        text = "%s: %s on %s" % (job_title(job), key_name(k[1]).replace("button-", "button "), d.name)
        if was:
            text += ". That button was %s, which is free now" % " and ".join(job_title(j) for j in was)
        self._bound(text)

    def _bound(self, text):
        self.capture = None
        self.dirty = True
        self.message = text + ". Save when you're done."

    def reverse(self, job):
        a = self.mapping["axes"].get(job)
        if a:
            a["dir"] = -a["dir"]
            self.dirty = True

    def clear(self, job):
        if job == "hat":
            self.mapping["hat"] = {}
        else:
            self.mapping[self._part(job)].pop(job, None)
        self.dirty = True

    # --- response settings
    def shape(self, job):
        return get_shape(self.mapping, job, self.aircraft)

    def set_shape(self, job, key, value):
        scope = self.aircraft or "default"
        tab = self.mapping["shapes"].setdefault(scope, {}).setdefault(job, {})
        if key in SHAPE_RANGE:
            lo, hi = SHAPE_RANGE[key]
            value = round(max(lo, min(hi, float(value))), 3)
        else:
            value = bool(value)
        tab[key] = value
        self.dirty = True

    def reset_shape(self, job):
        scope = self.aircraft or "default"
        (self.mapping["shapes"].get(scope) or {}).pop(job, None)
        self.dirty = True

    def has_own_shape(self, job):
        return bool(self.aircraft and job in (self.mapping["shapes"].get(self.aircraft) or {}))

    def curve(self, job, n=41):
        """[(input, output)] across the axis's whole range, for drawing."""
        s = self.shape(job)
        xs = [-1 + 2 * i / (n - 1) for i in range(n)] if job in STICKS else [i / (n - 1) for i in range(n)]
        return [(x, apply_shape(job, x, s)) for x in xs]

    # --- showing
    def binding_text(self, job):
        if job == "hat":
            h = self.mapping.get("hat") or {}
            return "hat on %s" % h["dev"][10:] if h.get("dev") else "-"
        v = self.mapping[self._part(job)].get(job)
        if not v:
            return "-"
        dev = v["dev"][10:]
        if job in AXIS_JOBS:
            return "%s on %s%s" % (PLAIN.get(v["code"], abs_name(v["code"])), dev, " (rev)" if v["dir"] < 0 else "")
        return "%s on %s" % (key_name(v["code"]).replace("button-", "button "), dev)

    def raw(self, job):
        """The calibrated value the XML hands to the shaping (before dead zone, curve...), or None."""
        a = self.mapping["axes"].get(job)
        if not a or a["dev"] not in self.path_of:
            return None
        k = (self.path_of[a["dev"]], a["code"])
        return cal_value(job, self._with_cal(job, a), self.values.get(k, 0.5))

    def live(self, job):
        """What FlightGear would get right now: a number for axes, True/False for buttons."""
        if job in BUTTON_JOBS:
            b = self.mapping["buttons"].get(job)
            return bool(b and b["dev"] in self.path_of and (self.path_of[b["dev"]], b["code"]) in self.pressed)
        r = self.raw(job)
        return None if r is None else apply_shape(job, r, self.shape(job))

    def _with_cal(self, job, a):
        k = (self.path_of[a["dev"]], a["code"])
        if k in self.lo and self.hi[k] - self.lo[k] >= 0.3:
            old = a.get("cal")
            centre = a.get("centre")
            if centre is None:
                centre = old[1] if old else (self.lo[k] + self.hi[k]) / 2
            lo, hi = self.lo[k], self.hi[k]
            if old:   # a wider range seen before still counts
                lo, hi = min(lo, old[0]), max(hi, old[2])
            return dict(a, cal=[round(lo, 4), round(centre, 4), round(hi, 4)])
        return a

    def problems(self):
        out = ["%s isn't bound" % job_title(j) for j in CORE if j not in self.mapping["axes"] and j not in self.mapping["buttons"]]
        out += ["%s on %s does several jobs: %s" % (key_name(c), dev[10:], ", ".join(job_title(j) for j in jobs))
                for dev, c, jobs in duplicates(self.mapping)]
        return out

    def save(self, dry=False):
        for job, a in list(self.mapping["axes"].items()):
            if a.get("dev") in self.path_of:
                self.mapping["axes"][job] = self._with_cal(job, a)
        rc = write_all(self.devs, self.mapping, dry)
        if rc == 0:
            self.dirty = False
            self.message = "Saved. Start FlightGear with fgfs-mga as usual."
        else:
            self.message = "Nothing to save yet."
        return rc


def qt_module():
    """The Qt window (fgfs-mga-controls-qt next to this tool), or (None, reason)."""
    here = os.path.dirname(os.path.realpath(__file__))
    for path in (os.path.join(here, "fgfs-mga-controls-qt"), os.path.join(SHARE, "tools", "fgfs-mga-controls-qt")):
        if os.path.exists(path):
            try:
                from importlib.machinery import SourceFileLoader
                return SourceFileLoader("fgfs_mga_controls_qt", path).load_module(), None
            except ImportError as e:
                return None, "Qt for Python isn't installed (%s): sudo apt install python3-pyqt5" % e
            except Exception as e:  # a broken copy shouldn't stop the controls window opening
                return None, "the Qt window failed to load (%s)" % e
    return None, "the Qt window (fgfs-mga-controls-qt) isn't installed"


def cmd_gui(args):
    """The controls window: the Qt one, or the older Tk one with --tk (or when Qt can't load)."""
    if "--tk" not in args:
        qt, why = qt_module()
        if qt is not None:
            try:
                return qt.run(sys.modules[__name__], args)
            except Exception as e:  # noqa: BLE001 - fall back rather than leave the user with nothing
                why = "the Qt window stopped: %s" % e
        print("Using the older window: %s." % why)
    return cmd_gui_tk([a for a in args if a != "--tk"])


def cmd_gui_tk(args):
    try:
        import tkinter as tk
        from tkinter import messagebox, ttk
    except ImportError:
        print("Tkinter is missing: sudo apt install python3-tk  (or use: fgfs-mga controls wizard)")
        return 1
    devs = find_devices("--all" in args)
    if not devs:
        print("No Saitek controller found. Plug them in and try again.")
    try:
        root = tk.Tk()
    except tk.TclError as e:
        print("Can't open a window (%s). Run it from the desktop, or use: fgfs-mga controls wizard" % e)
        return 1
    root.title("FlightGear controls - fgfs-mga")
    root.geometry("1180x760")
    ses = Session(devs, load_map())
    planes = find_aircraft()
    style = ttk.Style(root)
    style.configure("On.TLabel", background="#2e7d32", foreground="white")
    style.configure("Off.TLabel", background="#dddddd", foreground="#444444")
    style.configure("No.TLabel", foreground="#9e9e9e")
    style.configure("Group.TButton", anchor="w", font=("TkDefaultFont", 10, "bold"))

    top = ttk.Frame(root, padding=(8, 6))
    top.pack(fill="x")
    ttk.Label(top, text="Aircraft:").pack(side="left")
    ac_var = tk.StringVar(value="(all aircraft)")
    ac_box = ttk.Combobox(top, textvariable=ac_var, width=36, state="readonly",
                          values=["(all aircraft)"] + list(planes))
    ac_box.pack(side="left", padx=6)
    ac_note = ttk.Label(top, text="Pick one to mark the jobs it doesn't have and to give it its own response settings.")
    ac_note.pack(side="left", padx=6)

    def pick_aircraft(_e=None):
        a = ac_var.get()
        if a.startswith("("):
            ses.set_aircraft(None)
            ac_note.configure(text="Response settings apply to every aircraft (unless one has its own).")
        else:
            ses.set_aircraft(a, planes.get(a))
            ac_note.configure(text="Jobs %s doesn't use are greyed. Response settings changed now apply to it only." % a)
        refresh_response()
    ac_box.bind("<<ComboboxSelected>>", pick_aircraft)

    nb = ttk.Notebook(root)
    nb.pack(fill="both", expand=True, padx=8)
    tab_bind = ttk.Frame(nb, padding=6)
    tab_resp = ttk.Frame(nb, padding=6)
    nb.add(tab_bind, text="Buttons and axes")
    nb.add(tab_resp, text="Response (sensitivity, curves)")
    tab_ffb = ttk.Frame(nb, padding=10)
    nb.add(tab_ffb, text="Force feedback")

    # ---- left: live view of each stick
    left = ttk.Frame(tab_bind)
    left.pack(side="left", fill="y")
    bars, lamps = [], []
    for d in devs:
        box = ttk.LabelFrame(left, text=d.name, padding=6)
        box.pack(fill="x", pady=4)
        for code, name, _a, _b, _v in describe(d)[0]:
            row = ttk.Frame(box)
            row.pack(fill="x")
            ttk.Label(row, text="%-12s" % PLAIN.get(code, name), width=12).pack(side="left")
            c = tk.Canvas(row, width=180, height=12, bg="#eeeeee", highlightthickness=0)
            c.pack(side="left", padx=4, pady=1)
            bars.append((c, (d.path, code), code in HAT_CODES))
        grid = ttk.Frame(box)
        grid.pack(fill="x", pady=(4, 0))
        for i, (code, name) in enumerate(describe(d)[1]):
            lab = ttk.Label(grid, text=name.replace("button-", ""), style="Off.TLabel", padding=(3, 1))
            lab.grid(row=i // 4, column=i % 4, padx=1, pady=1, sticky="ew")
            lamps.append((lab, (d.path, code)))

    # ---- right: every job, grouped, collapsible, scrollable
    outer = ttk.Frame(tab_bind)
    outer.pack(side="left", fill="both", expand=True, padx=(8, 0))
    canvas = tk.Canvas(outer, highlightthickness=0)
    sb = ttk.Scrollbar(outer, orient="vertical", command=canvas.yview)
    inner = ttk.Frame(canvas)
    inner.bind("<Configure>", lambda _e: canvas.configure(scrollregion=canvas.bbox("all")))
    canvas.create_window((0, 0), window=inner, anchor="nw")
    canvas.configure(yscrollcommand=sb.set)
    canvas.pack(side="left", fill="both", expand=True)
    sb.pack(side="right", fill="y")
    for w in (canvas, inner):
        w.bind_all("<Button-4>", lambda _e: canvas.yview_scroll(-3, "units"))
        w.bind_all("<Button-5>", lambda _e: canvas.yview_scroll(3, "units"))

    rows, heads, bodies, opened = {}, {}, {}, {}
    for group in GROUPS:
        jobs = [j for j, v in JOBS.items() if v["group"] == group]
        head = ttk.Button(inner, style="Group.TButton", width=60)
        head.pack(fill="x", pady=(6, 0))
        body = ttk.Frame(inner)
        heads[group], bodies[group] = head, body
        opened[group] = group in ("Flight", "Engine", "Brakes")
        for r, job in enumerate(jobs):
            t = ttk.Label(body, text=job_title(job), width=40)
            t.grid(row=r, column=0, sticky="w", padx=(12, 6))
            mark = ttk.Label(body, width=14)
            mark.grid(row=r, column=1, sticky="w")
            bound = ttk.Label(body, width=30)
            bound.grid(row=r, column=2, sticky="w")
            now = ttk.Label(body, width=6)
            now.grid(row=r, column=3, sticky="w")
            ttk.Button(body, text="Bind", width=5, command=lambda j=job: ses.start_capture(j)).grid(row=r, column=4)
            if job in AXIS_JOBS:
                ttk.Button(body, text="Reverse", width=7, command=lambda j=job: ses.reverse(j)).grid(row=r, column=5)
            ttk.Button(body, text="Clear", width=5, command=lambda j=job: ses.clear(j)).grid(row=r, column=6)
            rows[job] = (t, mark, bound, now)

        def toggle(g=group):
            opened[g] = not opened[g]
            relayout()
        head.configure(command=toggle)

    def relayout():
        for g in GROUPS:
            bodies[g].pack_forget()
        for g in GROUPS:
            heads[g].pack_forget()
            heads[g].pack(fill="x", pady=(6, 0))
            if opened[g]:
                bodies[g].pack(fill="x")
    relayout()

    # ---- response tab: pick an axis, sliders, live curve
    rl = ttk.Frame(tab_resp)
    rl.pack(side="left", fill="y")
    ttk.Label(rl, text="Axis").pack(anchor="w")
    axis_list = tk.Listbox(rl, height=20, exportselection=False, width=30)
    axis_list.pack(fill="y", expand=True)
    rr = ttk.Frame(tab_resp, padding=(12, 0))
    rr.pack(side="left", fill="both", expand=True)
    scope_lab = ttk.Label(rr, font=("TkDefaultFont", 10, "bold"))
    scope_lab.grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 6))
    sliders, slabels = {}, {}
    cur = {"job": None, "busy": False}

    def on_slide(key, val):
        if cur["job"] and not cur["busy"]:
            ses.set_shape(cur["job"], key, float(val))
            slabels[key].configure(text="%.2f" % float(val))
    for i, key in enumerate(["deadzone", "sensitivity", "expo", "limit", "offset", "smooth"], start=1):
        lo, hi = SHAPE_RANGE[key]
        ttk.Label(rr, text=SHAPE_HELP[key], wraplength=330).grid(row=i, column=0, sticky="w", pady=3)
        sc = ttk.Scale(rr, from_=lo, to=hi, length=260, command=lambda v, k=key: on_slide(k, v))
        sc.grid(row=i, column=1, padx=6)
        lab = ttk.Label(rr, width=6)
        lab.grid(row=i, column=2, sticky="w")
        sliders[key], slabels[key] = sc, lab
    split_var = tk.BooleanVar()

    def on_split():
        if cur["job"]:
            ses.set_shape(cur["job"], "split", split_var.get())
    split_chk = ttk.Checkbutton(rr, text=SHAPE_HELP["split"], variable=split_var, command=on_split)
    split_chk.grid(row=7, column=0, columnspan=3, sticky="w", pady=4)
    btns = ttk.Frame(rr)
    btns.grid(row=8, column=0, columnspan=3, sticky="w", pady=4)

    def reset():
        if cur["job"]:
            ses.reset_shape(cur["job"])
            refresh_response()
    ttk.Button(btns, text="Reset these settings", command=reset).pack(side="left")
    ttk.Button(btns, text="Reverse this axis", command=lambda: cur["job"] and ses.reverse(cur["job"])).pack(side="left", padx=6)
    graph = tk.Canvas(rr, width=300, height=300, bg="#fafafa", highlightthickness=1, highlightbackground="#cccccc")
    graph.grid(row=1, column=3, rowspan=8, padx=16, sticky="n")
    ttk.Label(rr, text="Across: stick position.  Up: what FlightGear gets.  Red dot: your stick now.").grid(
        row=9, column=3, padx=16, sticky="w")

    def axis_jobs():
        return [j for j in AXIS_JOBS if j in ses.mapping["axes"]]

    def refresh_axis_list():
        sel = cur["job"]
        axis_list.delete(0, "end")
        for j in axis_jobs():
            axis_list.insert("end", job_title(j))
        if sel in axis_jobs():
            axis_list.selection_set(axis_jobs().index(sel))

    def refresh_response():
        job = cur["job"]
        scope_lab.configure(text=("Settings for %s%s" % (ses.aircraft, "" if (not job or ses.has_own_shape(job)) else
                                                          " (now the same as all aircraft; changes make its own copy)"))
                            if ses.aircraft else "Settings for all aircraft")
        if not job:
            return
        s = ses.shape(job)
        cur["busy"] = True
        for key, sc in sliders.items():
            sc.set(s[key])
            slabels[key].configure(text="%.2f" % s[key])
        split_var.set(bool(s.get("split")))
        split_chk.state(["!disabled"] if job == "rudder" else ["disabled"])
        cur["busy"] = False

    def on_pick(_e=None):
        sel = axis_list.curselection()
        if sel:
            cur["job"] = axis_jobs()[sel[0]]
            refresh_response()
    axis_list.bind("<<ListboxSelect>>", on_pick)
    refresh_axis_list()

    def draw_graph():
        graph.delete("all")
        job = cur["job"]
        W = 300
        graph.create_line(0, W / 2, W, W / 2, fill="#dddddd")
        graph.create_line(W / 2, 0, W / 2, W, fill="#dddddd")
        if not job:
            graph.create_text(W / 2, W / 2, text="Pick an axis", fill="#777777")
            return
        stick = job in STICKS
        sx = (lambda x: (x + 1) / 2 * W) if stick else (lambda x: x * W)
        sy = (lambda y: W - (y + 1) / 2 * W) if stick else (lambda y: W - y * W)
        graph.create_line(sx(-1 if stick else 0), sy(-1 if stick else 0), sx(1), sy(1), fill="#cfd8dc", dash=(3, 3))
        pts = ses.curve(job)
        graph.create_line(*[c for x, y in pts for c in (sx(x), sy(y))], fill="#1565c0", width=2)
        r = ses.raw(job)
        if r is not None:
            y = ses.live(job)
            graph.create_oval(sx(r) - 5, sy(y) - 5, sx(r) + 5, sy(y) + 5, fill="#d32f2f", outline="")
            graph.create_text(8, 10, anchor="w", text="in %+.2f  out %+.2f" % (r, y), fill="#333333")

    # ---- force feedback tab: strengths for fgfs-mga-ffb (applies in flight within a second of Save)
    ffbm, ffb_path = ffb_module()
    ffb_state = {"dirty": False}
    if ffbm is None:
        ttk.Label(tab_ffb, text="The force feedback bridge (fgfs-mga-ffb) isn't installed next to this tool.").pack(anchor="w")
    else:
        fconf = ffbm.load_conf()
        en_var = tk.BooleanVar(value=fconf["enabled"])

        def fmark(*_a):
            ffb_state["dirty"] = True
            ffb_note.configure(text="* not saved yet")
        ttk.Checkbutton(tab_ffb, text="Force feedback on (Saitek Cyborg Evo Force)", variable=en_var,
                        command=fmark).grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 8))
        fvars = {}
        for i, key in enumerate(["master", "spring", "buffet", "rumble", "vref_kt", "buffet_alpha", "trim_follow"], start=1):
            lo, hi = ffbm.RANGE[key]
            ttk.Label(tab_ffb, text=ffbm.HELP[key], width=52).grid(row=i, column=0, sticky="w", pady=3)
            v = tk.DoubleVar(value=fconf[key])
            lab = ttk.Label(tab_ffb, width=6, text="%g" % round(fconf[key], 1))

            def moved(val, k=key, lab=lab):
                lab.configure(text="%g" % round(float(val), 1))
                fmark()
            ttk.Scale(tab_ffb, from_=lo, to=hi, length=300, variable=v, command=moved).grid(row=i, column=1, padx=6)
            lab.grid(row=i, column=2, sticky="w")
            fvars[key] = v

        def fcollect():
            c = {k: round(v.get(), 1) for k, v in fvars.items()}
            c["enabled"] = en_var.get()
            return c

        def fsave():
            ffbm.save_conf(dict(ffbm.load_conf(), **fcollect()))
            ffb_state["dirty"] = False
            ffb_note.configure(text="Saved. A running flight picks it up within a second.")

        def fdefaults():
            for k, v in fvars.items():
                v.set(ffbm.DEFAULTS[k])
            en_var.set(True)
            fmark()

        def ftest():
            fsave()
            import subprocess
            try:
                subprocess.Popen([sys.executable, ffb_path, "test"])
                ffb_note.configure(text="Playing spring, buffet and rumble for 2 s each. Hold the stick loosely.")
            except OSError as e:
                ffb_note.configure(text="Couldn't start the test: %s" % e)
        row = ttk.Frame(tab_ffb)
        row.grid(row=9, column=0, columnspan=3, sticky="w", pady=(10, 4))
        ttk.Button(row, text="Save", command=fsave).pack(side="left")
        ttk.Button(row, text="Test on the stick", command=ftest).pack(side="left", padx=6)
        ttk.Button(row, text="Moderate defaults", command=fdefaults).pack(side="left")
        ffb_note = ttk.Label(tab_ffb, text="fgfs-mga turns it on by itself when the Evo's force feedback driver is loaded. "
                             "For one flight: fgfs-mga --ffb or --no-ffb.",
                             wraplength=640)
        ffb_note.grid(row=10, column=0, columnspan=3, sticky="w")

    # ---- bottom
    bottom = ttk.Frame(root, padding=8)
    bottom.pack(fill="x")
    status = ttk.Label(bottom, wraplength=900)
    status.pack(side="left", fill="x", expand=True)

    def close():
        if (ses.dirty or ffb_state["dirty"]) and not messagebox.askyesno("Unsaved changes", "Close without saving?"):
            return
        root.destroy()

    def save():
        ses.save("--dry-run" in args)
        warn = ses.problems()
        if warn:
            ses.message += "  Check: " + "; ".join(warn) + "."
    ttk.Button(bottom, text="Cancel bind", command=ses.cancel_capture).pack(side="right", padx=2)
    ttk.Button(bottom, text="Close", command=close).pack(side="right", padx=2)
    ttk.Button(bottom, text="Save", command=save).pack(side="right", padx=2)
    root.protocol("WM_DELETE_WINDOW", close)

    seen_axes = {"n": -1}

    def tick():
        ses.poll()
        for c, k, hat in bars:
            v = ses.values.get(k, 0.5)
            c.delete("all")
            if k in ses.lo and not hat:
                c.create_rectangle(ses.lo[k] * 180, 0, ses.hi[k] * 180, 12, fill="#c8e6c9", width=0)
            c.create_rectangle(v * 180 - 3, 0, v * 180 + 3, 12, fill="#1565c0", width=0)
            c.create_line(90, 0, 90, 12, fill="#999999")
        for lab, k in lamps:
            lab.configure(style="On.TLabel" if k in ses.pressed else "Off.TLabel")
        counts = {}
        for job, (t, mark, bound, now) in rows.items():
            sup = ses.support(job)
            mark.configure(text="" if sup is None else ("" if sup else "not on this aircraft"), style="No.TLabel")
            t.configure(style="No.TLabel" if sup is False else "TLabel")
            b = ses.binding_text(job)
            bound.configure(text=b)
            if b != "-":
                counts[JOBS[job]["group"]] = counts.get(JOBS[job]["group"], 0) + 1
            v = None if job == "hat" else ses.live(job)
            now.configure(text=("ON" if v else "") if isinstance(v, bool) else ("%+.2f" % v if v is not None else ""))
        for g in GROUPS:
            heads[g].configure(text="%s %s   (%d bound)" % ("▾" if opened[g] else "▸", g, counts.get(g, 0)))
        if len(axis_jobs()) != seen_axes["n"]:
            seen_axes["n"] = len(axis_jobs())
            refresh_axis_list()
        draw_graph()
        status.configure(text=("* " if ses.dirty else "") + ses.message)
        root.after(40, tick)
    tick()
    close_after = os.environ.get("FGFS_MGA_GUI_AUTOCLOSE")
    if close_after:   # smoke test: open, run, close
        root.after(int(float(close_after) * 1000), root.destroy)
    root.mainloop()
    return 0


def cmd_bind(args, unbind=False):
    jobs = [a for a in args if not a.startswith("-")]
    bad = [j for j in jobs if j not in JOBS]
    if not jobs or bad:
        print("Which job? One or more of:")
        for g in GROUPS:
            print("  %-15s %s" % (g + ":", " ".join(j for j, v in JOBS.items() if v["group"] == g)))
        return 2
    m = load_map()
    devs = find_devices("--all" in args)
    if not m:
        print("No mapping yet. Run: fgfs-mga controls gui  (or: fgfs-mga controls wizard)")
        return 1
    if not devs:
        print("No Saitek controller found. Plug them in and try again.")
        return 1
    m.setdefault("hat", {})
    names = {d.path: d for d in devs}
    path_of = {dev_key(d): d.path for d in devs}
    prompts = {a[0]: a[2] for a in AXES}
    for fid in jobs:
        if unbind:
            if fid == "hat":
                m["hat"] = {}
            else:
                m["axes" if fid in AXIS_JOBS else "buttons"].pop(fid, None)
            print("  %s cleared" % job_title(fid))
            continue
        if fid in BUTTON_JOBS:
            print("Press the button for %s (Enter = leave it free) ... " % job_title(fid), end="", flush=True)
            k = wait_button(devs, set(), timeout=60)
            if k is None:
                m["buttons"].pop(fid, None)
                print("free")
                continue
            for j, b in list(m["buttons"].items()):   # one button, one job on a stick
                if j != fid and b["dev"] in path_of and (path_of[b["dev"]], b["code"]) == k:
                    m["buttons"].pop(j)
                    print("  (that button was %s; that job is free now)" % job_title(j))
            m["buttons"][fid] = {"dev": dev_key(names[k[0]]), "code": k[1]}
            print("%s on %s" % (key_name(k[1]).replace("button-", ""), names[k[0]].name))
        elif fid == "hat":
            d = next((x for x in devs if ask("Use the hat on %s to glance around? [y/N] " % x.name) == "y"), None)
            m["hat"] = {"dev": dev_key(d), "codes": hat_codes(d)} if d else {}
        else:
            stick = fid in STICKS
            used = {(path_of[a["dev"]], a["code"]) for j, a in m["axes"].items() if j != fid and a["dev"] in path_of}
            print("Move that control end to end two or three times, then press Enter.")
            cal_lo, cal_hi = calibrate(devs)
            if stick:
                if ask("Let go of it (centred) and press Enter ") == "q":
                    return 1
                centre = snapshot(devs)
                prompt = prompts.get(fid) or "%s: %s" % (job_title(fid), AXIS_JOBS[fid]["hint"])
                if ask("%s, press Enter " % prompt) == "q":
                    return 1
                k, direction = pick_axis(devs, centre, snapshot(devs), used, min_move=0.12 if fid == "rudder" else 0.2)
            else:
                end_lo, end_hi = UNI_ENDS[fid]
                if ask("%s: set it to %s, press Enter " % (job_title(fid), end_lo)) == "q":
                    return 1
                centre = snapshot(devs)
                if ask("  now move it to %s, press Enter " % end_hi) == "q":
                    return 1
                k, direction = pick_axis(devs, centre, snapshot(devs), used)
                centre = {}
            if k is None:
                print("  didn't see anything move far enough; %s left as it was" % fid)
                continue
            m["axes"][fid] = {"dev": dev_key(names[k[0]]), "code": k[1], "dir": direction,
                              "cal": cal_for(k, cal_lo, cal_hi, centre)}
            print("  -> %s on %s" % (PLAIN.get(k[1], abs_name(k[1])), names[k[0]].name))
    return write_all(devs, m, "--dry-run" in args)


def stick_health(devs):
    """Warnings for sticks that are plugged in but can't work: X and Y both parked at their minimum, which a
    centred stick never reports (the stick isn't sending movement). Dead copies left by a driver reload are
    skipped by find_devices: FlightGear gives every copy the same bindings, so they don't affect flying."""
    out, seen = [], {}
    for d in devs:
        if not is_dead_copy(getattr(d, "path", "")):
            seen.setdefault(dev_key(d), []).append(d)
    for key, ds in sorted(seen.items()):
        name = key[10:]
        for d in ds:
            try:
                ai = dict(d.capabilities(absinfo=True).get(EV_ABS, []))
            except OSError:
                continue
            x, y = ai.get(0), ai.get(1)                      # ABS_X, ABS_Y
            if x and y and x.max > x.min and y.max > y.min and x.value == x.min and y.value == y.min:
                out.append("%s isn't sending any movement (X and Y read their minimum). Unplug it and plug it"
                           " back in; if that doesn't help, its force feedback driver is blocking input." % name)
    return out


def cmd_check(args):
    """Before a flight: are the mapped sticks plugged in, and are the core jobs bound? Exit 0 = fine, 3 = warnings.
    --gui shows a small window with 'Open controls' and 'Fly anyway' (goes on by itself after 20 s)."""
    m = load_map()
    warn = []
    if not m:
        warn.append("The joysticks aren't set up for FlightGear yet.")
    else:
        devs = find_devices(True)
        present = {dev_key(d) for d in devs}
        warn += stick_health(devs)
        want = {v["dev"] for part in ("axes", "buttons") for v in m.get(part, {}).values()}
        if (m.get("hat") or {}).get("dev"):
            want.add(m["hat"]["dev"])
        for dev in sorted(want - present):
            warn.append("%s isn't plugged in." % dev[10:])
        free = [job_title(j) for j in CORE if j not in m.get("axes", {}) and j not in m.get("buttons", {})]
        if free:
            warn.append("Not bound: %s." % ", ".join(free))
        for dev, code, jobs in duplicates(m):
            warn.append("%s on %s does several jobs (%s)." % (key_name(code), dev[10:], ", ".join(job_title(j) for j in jobs)))
    if not warn:
        return 0
    if "--quiet" not in args or "--gui" not in args:
        print("Controls check:\n  " + "\n  ".join(warn))
    if "--gui" not in args or not os.environ.get("DISPLAY"):
        return 3
    try:
        import tkinter as tk
        from tkinter import ttk
        root = tk.Tk()
    except Exception:
        return 3
    root.title("Before you fly")
    choice = {"v": "fly"}
    ttk.Label(root, text="Controls check", font=("TkDefaultFont", 12, "bold"), padding=(12, 10, 12, 2)).pack(anchor="w")
    ttk.Label(root, text="\n".join(warn), padding=(12, 4), wraplength=460, justify="left").pack(anchor="w")
    left = {"n": 20}
    note = ttk.Label(root, padding=(12, 2))
    note.pack(anchor="w")
    row = ttk.Frame(root, padding=10)
    row.pack(anchor="e")

    def go(v):
        choice["v"] = v
        root.destroy()
    ttk.Button(row, text="Open controls", command=lambda: go("gui")).pack(side="left", padx=4)
    ttk.Button(row, text="Fly anyway", command=lambda: go("fly")).pack(side="left", padx=4)

    def count():
        note.configure(text="FlightGear starts by itself in %d s." % left["n"])
        left["n"] -= 1
        if left["n"] < 0:
            go("fly")
        else:
            root.after(1000, count)
    count()
    root.mainloop()
    if choice["v"] == "gui":
        cmd_gui([a for a in args if a == "--all"])
    return 3


def main(argv):
    cmd = argv[0] if argv and not argv[0].startswith("-") else "wizard"
    rest = argv[1:] if argv and not argv[0].startswith("-") else argv
    fn = {"scan": cmd_scan, "wizard": cmd_wizard, "defaults": cmd_defaults, "test": cmd_test,
          "show": cmd_show, "gui": cmd_gui, "gui-tk": cmd_gui_tk, "bind": cmd_bind, "unbind": lambda a: cmd_bind(a, unbind=True),
          "check": cmd_check}.get(cmd)
    if fn is None or "-h" in rest or "--help" in rest:
        print(__doc__)
        return 0 if fn else 2
    return fn(rest)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
__FGFS_MGA_CONTROLS__
  if python3 -m py_compile "$TMPC" 2>/dev/null; then chmod 755 "$TMPC"; mv -f -- "$TMPC" "$CT"; say "Installed $CT (run: fgfs-mga controls)"
  else rm -f -- "$TMPC"; say "WARNING: controller tool failed a Python check; not installed."; fi
  rm -rf -- "$TOOLS/__pycache__"
fi

# ---------------- controls window in Qt (needs python3-pyqt5; the Tk window stays as `controls gui-tk`) ----------------
if (( DRY )); then
  say "  [dry-run] would write $TOOLS/fgfs-mga-controls-qt"
else
  CQ="$TOOLS/fgfs-mga-controls-qt"
  [[ -f "$CQ" ]] && { mkdir -p "$BK/tools"; cp -p -- "$CQ" "$BK/tools/fgfs-mga-controls-qt"; }
  TMPQ="$(mktemp "$TOOLS/.fgfs-mga-controls-qt.XXXXXX")"
  cat > "$TMPQ" <<'__FGFS_MGA_CONTROLS_QT__'
#!/usr/bin/env python3
"""fgfs-mga controls window (Qt). Opened by `fgfs-mga controls gui`; the older Tk window is `gui-tk`.

All the binding, calibration and response logic lives in fgfs-mga-controls (class Session); this file is
only the window. Works with PySide6, PyQt5 or PySide2, whichever is installed (Debian: python3-pyqt5).
"""
import os
import sys

QT = None
for _name in ("PySide6", "PyQt5", "PySide2"):
    try:
        if _name == "PySide6":
            from PySide6 import QtCore, QtGui, QtWidgets
        elif _name == "PyQt5":
            from PyQt5 import QtCore, QtGui, QtWidgets
        else:
            from PySide2 import QtCore, QtGui, QtWidgets
        QT = _name
        break
    except ImportError:
        continue
if QT is None:
    raise ImportError("no Qt for Python (install python3-pyqt5)")

Qt = QtCore.Qt
Signal = getattr(QtCore, "pyqtSignal", None) or QtCore.Signal

# ---------------------------------------------------------------- look
C = {"bg": "#12151a", "panel": "#1b2027", "card": "#222831", "card2": "#2a313c", "line": "#343c48",
     "text": "#e6e9ee", "dim": "#8b95a5", "faint": "#5b6574", "accent": "#4c9bff", "accent2": "#2f6fd1",
     "ok": "#3ccf7a", "warn": "#f5b340", "bad": "#ef5b5b", "curve": "#4c9bff", "dot": "#ff6b6b"}

QSS = """
* { color: %(text)s; font-size: 11pt; }
QMainWindow, QWidget#root { background: %(bg)s; }
QFrame#topbar { background: %(panel)s; border-bottom: 1px solid %(line)s; }
QLabel#title { font-size: 15pt; font-weight: 600; }
QLabel#dim, QLabel.dim { color: %(dim)s; }
QLabel#scope { color: %(dim)s; }
QLabel#h2 { font-size: 13pt; font-weight: 600; }
QFrame#card, QFrame#axiscard { background: %(card)s; border: 1px solid %(line)s; border-radius: 10px; }
QFrame#axiscard:hover { border-color: %(faint)s; }
QFrame#axiscard[selected="true"] { border: 2px solid %(accent)s; background: %(card2)s; }
QTabWidget::pane { border: none; }
QTabBar::tab { background: transparent; color: %(dim)s; padding: 10px 22px; margin-right: 4px;
               border-bottom: 3px solid transparent; }
QTabBar::tab:selected { color: %(text)s; border-bottom: 3px solid %(accent)s; }
QTabBar::tab:hover { color: %(text)s; }
QPushButton { background: %(card2)s; border: 1px solid %(line)s; border-radius: 8px; padding: 7px 14px; }
QPushButton:hover { border-color: %(faint)s; background: #313948; }
QPushButton:pressed { background: #252b34; }
QPushButton:disabled { color: %(faint)s; }
QPushButton#primary { background: %(accent2)s; border-color: %(accent)s; font-weight: 600; }
QPushButton#primary:hover { background: %(accent)s; }
QPushButton#assign { border-color: %(accent)s; }
QPushButton#danger:hover { border-color: %(bad)s; }
QComboBox, QLineEdit, QDoubleSpinBox { background: %(card)s; border: 1px solid %(line)s; border-radius: 7px;
               padding: 5px 9px; min-height: 22px; }
QComboBox:hover, QLineEdit:focus, QDoubleSpinBox:focus { border-color: %(accent)s; }
QComboBox QAbstractItemView { background: %(card)s; selection-background-color: %(accent2)s; border: 1px solid %(line)s; }
QSlider::groove:horizontal { height: 6px; background: %(line)s; border-radius: 3px; }
QSlider::sub-page:horizontal { background: %(accent)s; border-radius: 3px; }
QSlider::handle:horizontal { background: %(text)s; width: 16px; height: 16px; margin: -6px 0; border-radius: 8px; }
QCheckBox::indicator { width: 18px; height: 18px; border-radius: 4px; border: 1px solid %(faint)s; background: %(card)s; }
QCheckBox::indicator:checked { background: %(accent)s; border-color: %(accent)s; }
QTreeWidget { background: %(card)s; border: 1px solid %(line)s; border-radius: 10px; alternate-background-color: #252c36; }
QTreeWidget::item { padding: 5px 4px; }
QTreeWidget::item:selected { background: %(accent2)s; }
QHeaderView::section { background: %(panel)s; color: %(dim)s; border: none; padding: 7px; font-weight: 600; }
QScrollArea { border: none; background: transparent; }
QScrollBar:vertical { background: transparent; width: 10px; }
QScrollBar::handle:vertical { background: %(line)s; border-radius: 5px; min-height: 30px; }
QScrollBar::add-line, QScrollBar::sub-line { height: 0; }
QFrame#status { background: %(panel)s; border-top: 1px solid %(line)s; }
QFrame#status[capture="true"] { background: #3a2e12; border-top: 2px solid %(warn)s; }
QLabel#statustext { font-size: 12pt; }
QToolTip { background: %(card2)s; color: %(text)s; border: 1px solid %(line)s; padding: 6px; }
""" % C


def qcolor(name):
    return QtGui.QColor(C.get(name, name))


def label(text="", obj=None, wrap=False):
    w = QtWidgets.QLabel(text)
    if obj:
        w.setObjectName(obj)
    w.setWordWrap(wrap)
    return w


def button(text, slot=None, obj=None, tip=None):
    b = QtWidgets.QPushButton(text)
    if obj:
        b.setObjectName(obj)
    if slot:
        b.clicked.connect(slot)
    if tip:
        b.setToolTip(tip)
    b.setCursor(Qt.PointingHandCursor)
    return b


def card():
    f = QtWidgets.QFrame()
    f.setObjectName("card")
    return f


# ---------------------------------------------------------------- widgets
class Meter(QtWidgets.QWidget):
    """A bar for one value. bi=True: -1..1 filled from the centre; else 0..1 from the left.
    lo/hi (0..1, raw) draw the range seen so far, for calibration."""

    def __init__(self, bi=False, height=16, parent=None):
        super().__init__(parent)
        self.bi, self.value, self.lo, self.hi, self.marker = bi, None, None, None, None
        self.setMinimumHeight(height)
        self.setMinimumWidth(80)

    def set(self, value, lo=None, hi=None, marker=None):
        if (value, lo, hi, marker) != (self.value, self.lo, self.hi, self.marker):
            self.value, self.lo, self.hi, self.marker = value, lo, hi, marker
            self.update()

    def paintEvent(self, _e):
        p = QtGui.QPainter(self)
        p.setRenderHint(QtGui.QPainter.Antialiasing)
        r = QtCore.QRectF(self.rect()).adjusted(0.5, 0.5, -0.5, -0.5)
        rad = r.height() / 2
        p.setPen(Qt.NoPen)
        p.setBrush(qcolor("line"))
        p.drawRoundedRect(r, rad, rad)
        w = r.width()
        if self.lo is not None and self.hi is not None and self.hi > self.lo:
            p.setBrush(QtGui.QColor(60, 207, 122, 55))
            p.drawRoundedRect(QtCore.QRectF(r.x() + self.lo * w, r.y(), (self.hi - self.lo) * w, r.height()), rad, rad)
        if self.value is not None:
            v = max(-1.0, min(1.0, self.value)) if self.bi else max(0.0, min(1.0, self.value))
            p.setBrush(qcolor("accent"))
            if self.bi:
                c = r.x() + w / 2
                x0, x1 = sorted((c, c + v * w / 2))
                p.drawRoundedRect(QtCore.QRectF(x0, r.y() + 2, max(x1 - x0, 3), r.height() - 4), rad - 2, rad - 2)
            else:
                p.drawRoundedRect(QtCore.QRectF(r.x(), r.y() + 2, max(v * w, 3), r.height() - 4), rad - 2, rad - 2)
        if self.marker is not None:
            x = r.x() + max(0.0, min(1.0, self.marker)) * w
            p.setBrush(qcolor("text"))
            p.drawRoundedRect(QtCore.QRectF(x - 2, r.y(), 4, r.height()), 2, 2)
        if self.bi:
            p.setPen(QtGui.QPen(qcolor("faint"), 1))
            p.drawLine(QtCore.QPointF(r.center().x(), r.y()), QtCore.QPointF(r.center().x(), r.bottom()))
        p.end()


class Lamp(QtWidgets.QLabel):
    def __init__(self, text):
        super().__init__(text)
        self.setAlignment(Qt.AlignCenter)
        self.setMinimumSize(54, 28)
        self.on = None
        self.set(False)

    def set(self, on):
        if on == self.on:
            return
        self.on = on
        self.setStyleSheet("border-radius: 7px; padding: 2px 6px; font-size: 10pt; %s" % (
            "background: %s; color: #0b1a10; font-weight: 600;" % C["ok"] if on else
            "background: %s; color: %s;" % (C["card2"], C["dim"])))


class HatView(QtWidgets.QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.x = self.y = 0
        self.setFixedSize(64, 64)

    def set(self, x, y):
        if (x, y) != (self.x, self.y):
            self.x, self.y = x, y
            self.update()

    def paintEvent(self, _e):
        p = QtGui.QPainter(self)
        p.setRenderHint(QtGui.QPainter.Antialiasing)
        p.setPen(QtGui.QPen(qcolor("line"), 2))
        p.setBrush(qcolor("card2"))
        p.drawEllipse(QtCore.QRectF(4, 4, 56, 56))
        p.setPen(Qt.NoPen)
        p.setBrush(qcolor("ok") if (self.x or self.y) else qcolor("faint"))
        p.drawEllipse(QtCore.QPointF(32 + 18 * self.x, 32 + 18 * self.y), 7, 7)
        p.end()


class CurveEditor(QtWidgets.QWidget):
    """The response curve, with three handles to drag: dead zone, curve (midpoint) and end limit."""
    changed = Signal()

    def __init__(self, ctl, ses, parent=None):
        super().__init__(parent)
        self.ctl, self.ses, self.job = ctl, ses, None
        self.drag = None
        self.hover = None
        self.setMinimumSize(380, 380)
        self.setMouseTracking(True)
        self.setSizePolicy(QtWidgets.QSizePolicy.Expanding, QtWidgets.QSizePolicy.Expanding)

    def sizeHint(self):
        return QtCore.QSize(460, 460)

    def set_job(self, job):
        self.job = job
        self.update()

    # geometry: a square plot inside a margin
    def _box(self):
        m = 34
        side = min(self.width(), self.height()) - 2 * m
        return QtCore.QRectF((self.width() - side) / 2, m * 0.6, side, side)

    def _stick(self):
        return self.job in self.ctl.STICKS

    def _to_px(self, x, y):
        b = self._box()
        if self._stick():
            return QtCore.QPointF(b.x() + (x + 1) / 2 * b.width(), b.bottom() - (y + 1) / 2 * b.height())
        return QtCore.QPointF(b.x() + x * b.width(), b.bottom() - y * b.height())

    def _from_px(self, pt):
        b = self._box()
        fx = (pt.x() - b.x()) / b.width()
        fy = (b.bottom() - pt.y()) / b.height()
        if self._stick():
            return fx * 2 - 1, fy * 2 - 1
        return fx, fy

    def _handles(self):
        if not self.job:
            return {}
        return self.ctl.shape_handles(self.job, self.ses.shape(self.job))

    def _hit(self, pos):
        best, bd = None, 18.0
        for name, (x, y) in self._handles().items():
            q = self._to_px(x, y)
            d = ((q.x() - pos.x()) ** 2 + (q.y() - pos.y()) ** 2) ** 0.5
            if d < bd:
                best, bd = name, d
        return best

    def mousePressEvent(self, e):
        self.drag = self._hit(e.pos())
        if self.drag:
            self.setCursor(Qt.ClosedHandCursor)

    def mouseMoveEvent(self, e):
        if self.drag and self.job:
            x, y = self._from_px(QtCore.QPointF(e.pos()))
            upd = self.ctl.drag_shape(self.job, self.ses.shape(self.job), self.drag, x, y)
            for k, v in upd.items():
                self.ses.set_shape(self.job, k, v)
            self.changed.emit()
            self.update()
            return
        h = self._hit(e.pos())
        if h != self.hover:
            self.hover = h
            self.setCursor(Qt.OpenHandCursor if h else Qt.ArrowCursor)
            self.setToolTip({"deadzone": "Drag sideways: dead zone", "curve": "Drag up or down: curve",
                             "limit": "Drag up or down: end limit"}.get(h, ""))
            self.update()

    def mouseReleaseEvent(self, _e):
        self.drag = None
        self.setCursor(Qt.OpenHandCursor if self.hover else Qt.ArrowCursor)

    def paintEvent(self, _e):
        p = QtGui.QPainter(self)
        p.setRenderHint(QtGui.QPainter.Antialiasing)
        b = self._box()
        p.setPen(Qt.NoPen)
        p.setBrush(qcolor("card"))
        p.drawRoundedRect(b.adjusted(-6, -6, 6, 6), 10, 10)
        grid = QtGui.QPen(qcolor("line"), 1)
        p.setPen(grid)
        for i in range(1, 8):
            x = b.x() + b.width() * i / 8
            y = b.y() + b.height() * i / 8
            p.drawLine(QtCore.QPointF(x, b.y()), QtCore.QPointF(x, b.bottom()))
            p.drawLine(QtCore.QPointF(b.x(), y), QtCore.QPointF(b.right(), y))
        if not self.job:
            p.setPen(qcolor("dim"))
            p.drawText(b, Qt.AlignCenter, "Pick an axis on the left")
            p.end()
            return
        stick = self._stick()
        s = self.ses.shape(self.job)
        lo = -1 if stick else 0
        # dead zone band
        dz = s["deadzone"]
        if dz > 0:
            p.setPen(Qt.NoPen)
            p.setBrush(QtGui.QColor(245, 179, 64, 40))
            a, c = self._to_px(-dz if stick else 0, 1), self._to_px(dz, lo)
            p.drawRect(QtCore.QRectF(a, c))
        # straight line for reference
        p.setPen(QtGui.QPen(qcolor("faint"), 1, Qt.DashLine))
        p.drawLine(self._to_px(lo, lo), self._to_px(1, 1))
        # axes through the centre
        if stick:
            p.setPen(QtGui.QPen(qcolor("faint"), 1))
            p.drawLine(self._to_px(-1, 0), self._to_px(1, 0))
            p.drawLine(self._to_px(0, -1), self._to_px(0, 1))
        # the curve
        path = QtGui.QPainterPath()
        pts = self.ses.curve(self.job, n=121)
        path.moveTo(self._to_px(*pts[0]))
        for x, y in pts[1:]:
            path.lineTo(self._to_px(x, y))
        glow = QtGui.QPen(QtGui.QColor(76, 155, 255, 60), 9)
        glow.setCapStyle(Qt.RoundCap)
        p.setPen(glow)
        p.setBrush(Qt.NoBrush)
        p.drawPath(path)
        p.setPen(QtGui.QPen(qcolor("curve"), 3))
        p.drawPath(path)
        # limit line
        lim = max(-1.0, min(1.0, s["limit"] + s["offset"]))
        p.setPen(QtGui.QPen(QtGui.QColor(239, 91, 91, 120), 1, Qt.DashLine))
        p.drawLine(self._to_px(lo, lim), self._to_px(1, lim))
        # handles
        for name, (x, y) in self._handles().items():
            q = self._to_px(x, y)
            active = name in (self.drag, self.hover)
            col = {"deadzone": "warn", "curve": "accent", "limit": "bad"}[name]
            p.setPen(QtGui.QPen(qcolor("bg"), 2))
            p.setBrush(qcolor(col))
            p.drawEllipse(q, 9 if active else 7, 9 if active else 7)
        # live dot
        r = self.ses.raw(self.job)
        if r is not None:
            y = self.ses.live(self.job)
            q = self._to_px(r, y)
            p.setPen(QtGui.QPen(QtGui.QColor(255, 107, 107, 90), 1))
            p.drawLine(QtCore.QPointF(q.x(), b.bottom()), q)
            p.setPen(QtGui.QPen(qcolor("bg"), 2))
            p.setBrush(qcolor("dot"))
            p.drawEllipse(q, 6, 6)
        # labels
        p.setPen(qcolor("dim"))
        f = p.font()
        f.setPointSizeF(9.5)
        p.setFont(f)
        p.drawText(QtCore.QRectF(b.x(), b.bottom() + 6, b.width(), 18), Qt.AlignCenter, "stick position")
        p.save()
        p.translate(b.x() - 10, b.center().y())
        p.rotate(-90)
        p.drawText(QtCore.QRectF(-b.height() / 2, -16, b.height(), 16), Qt.AlignCenter, "to FlightGear")
        p.restore()
        p.end()


class AxisCard(QtWidgets.QFrame):
    clicked = Signal(str)

    def __init__(self, ctl, job, parent=None):
        super().__init__(parent)
        self.job = job
        self.sup = None
        self.setObjectName("axiscard")
        self.setProperty("selected", False)
        self.setCursor(Qt.PointingHandCursor)
        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(12, 8, 12, 10)
        lay.setSpacing(4)
        row = QtWidgets.QHBoxLayout()
        self.title = label(ctl.AXIS_JOBS[job]["title"].split(" (")[0])
        self.title.setStyleSheet("font-weight: 600;")
        self.value = label("", "dim")
        row.addWidget(self.title)
        row.addStretch(1)
        row.addWidget(self.value)
        lay.addLayout(row)
        self.bound = label("", "dim")
        self.bound.setStyleSheet("font-size: 9.5pt; color: %s;" % C["dim"])
        lay.addWidget(self.bound)
        self.meter = Meter(bi=job in ctl.STICKS, height=8)
        lay.addWidget(self.meter)

    def mousePressEvent(self, _e):
        self.clicked.emit(self.job)

    def select(self, on):
        self.setProperty("selected", bool(on))
        self.style().unpolish(self)
        self.style().polish(self)


# ---------------------------------------------------------------- pages
class AxesPage(QtWidgets.QWidget):
    def __init__(self, win):
        super().__init__()
        self.win, self.ctl, self.ses = win, win.ctl, win.ses
        ctl = self.ctl
        lay = QtWidgets.QHBoxLayout(self)
        lay.setContentsMargins(16, 14, 16, 10)
        lay.setSpacing(16)

        # left: one card per axis job
        col = QtWidgets.QVBoxLayout()
        col.setSpacing(8)
        col.addWidget(label("Axes", "h2"))
        area = QtWidgets.QScrollArea()
        area.setWidgetResizable(True)
        area.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        host = QtWidgets.QWidget()
        host.setObjectName("root")
        left = QtWidgets.QVBoxLayout(host)
        left.setContentsMargins(0, 0, 8, 0)
        left.setSpacing(8)
        self.cards = {}
        main = [j for j in ("aileron", "elevator", "rudder", "throttle", "mixture", "propeller") if j in ctl.AXIS_JOBS]
        rest = [j for j in ctl.AXIS_JOBS if j not in main]
        for job in main:
            self._add_card(left, job)
        if rest:
            more = label("More axes", "dim")
            more.setStyleSheet("color: %s; font-weight: 600; padding-top: 8px;" % C["dim"])
            left.addWidget(more)
            for job in rest:
                self._add_card(left, job)
        left.addStretch(1)
        area.setWidget(host)
        col.addWidget(area, 1)
        lw = QtWidgets.QWidget()
        lw.setLayout(col)
        lw.setFixedWidth(340)
        lay.addWidget(lw)

        # right: editor
        ed = card()
        el = QtWidgets.QVBoxLayout(ed)
        el.setContentsMargins(18, 14, 18, 14)
        head = QtWidgets.QHBoxLayout()
        tl = QtWidgets.QVBoxLayout()
        self.h_title = label("", "h2")
        self.h_bound = label("", "dim")
        tl.addWidget(self.h_title)
        tl.addWidget(self.h_bound)
        head.addLayout(tl)
        head.addStretch(1)
        self.b_assign = button("Assign: move the axis", self.assign, "assign",
                               "Then move the stick, twist or lever you want for this job")
        self.b_rev = button("Reverse", self.reverse, tip="Flip the direction")
        self.b_clear = button("Clear", self.clear, "danger", tip="Unbind this job")
        self.b_reset = button("Reset curve", self.reset, tip="Back to the default response for this scope")
        for b in (self.b_assign, self.b_rev, self.b_clear, self.b_reset):
            head.addWidget(b)
        el.addLayout(head)

        body = QtWidgets.QHBoxLayout()
        body.setSpacing(18)
        self.curve = CurveEditor(ctl, self.ses)
        self.curve.changed.connect(self.sync_controls)
        body.addWidget(self.curve, 3)

        side = QtWidgets.QVBoxLayout()
        side.setSpacing(8)
        self.rows = {}
        names = {"deadzone": "Dead zone", "sensitivity": "Sensitivity", "expo": "Curve", "limit": "End limit",
                 "offset": "Centre offset", "smooth": "Smoothing"}
        for key in ["deadzone", "sensitivity", "expo", "limit", "offset", "smooth"]:
            lo, hi = ctl.SHAPE_RANGE[key]
            top = QtWidgets.QHBoxLayout()
            name = label(names[key])
            name.setStyleSheet("font-weight: 600;")
            name.setToolTip(ctl.SHAPE_HELP[key])
            spin = QtWidgets.QDoubleSpinBox()
            spin.setRange(lo, hi)
            spin.setDecimals(2)
            spin.setSingleStep(0.01)
            spin.setFixedWidth(90)
            spin.setButtonSymbols(QtWidgets.QAbstractSpinBox.NoButtons)
            spin.setAlignment(Qt.AlignRight)
            top.addWidget(name)
            top.addStretch(1)
            top.addWidget(spin)
            sl = QtWidgets.QSlider(Qt.Horizontal)
            sl.setRange(0, 1000)
            hint = label(ctl.SHAPE_HELP[key].split(": ", 1)[-1], "dim", wrap=True)
            hint.setStyleSheet("font-size: 9.5pt; color: %s;" % C["dim"])
            side.addLayout(top)
            side.addWidget(sl)
            side.addWidget(hint)
            side.addSpacing(4)
            sl.valueChanged.connect(lambda v, k=key: self.from_slider(k, v))
            spin.valueChanged.connect(lambda v, k=key: self.from_spin(k, v))
            self.rows[key] = (sl, spin)
        self.split = QtWidgets.QCheckBox(ctl.SHAPE_HELP["split"])
        self.split.toggled.connect(self.on_split)
        side.addWidget(self.split)
        side.addStretch(1)
        sw = QtWidgets.QWidget()
        sw.setLayout(side)
        sw.setFixedWidth(330)
        body.addWidget(sw)
        el.addLayout(body, 1)

        live = QtWidgets.QGridLayout()
        live.setHorizontalSpacing(12)
        live.addWidget(label("Stick", "dim"), 0, 0)
        self.m_in = Meter(bi=True, height=14)
        live.addWidget(self.m_in, 0, 1)
        self.t_in = label("", "dim")
        self.t_in.setFixedWidth(70)
        live.addWidget(self.t_in, 0, 2)
        live.addWidget(label("FlightGear", "dim"), 1, 0)
        self.m_out = Meter(bi=True, height=14)
        live.addWidget(self.m_out, 1, 1)
        self.t_out = label("", "dim")
        self.t_out.setFixedWidth(70)
        live.addWidget(self.t_out, 1, 2)
        live.setColumnStretch(1, 1)
        el.addLayout(live)
        lay.addWidget(ed, 1)

        self.job = None
        self.busy = False
        first = next((j for j in ctl.AXIS_JOBS if j in self.ses.mapping["axes"]), next(iter(ctl.AXIS_JOBS)))
        self.pick(first)

    def _add_card(self, lay, job):
        c = AxisCard(self.ctl, job)
        c.clicked.connect(self.pick)
        lay.addWidget(c)
        self.cards[job] = c

    # -- picking and editing
    def pick(self, job):
        self.job = job
        for j, c in self.cards.items():
            c.select(j == job)
        self.curve.set_job(job)
        stick = job in self.ctl.STICKS
        self.m_in.bi = self.m_out.bi = stick
        self.split.setVisible(job == "rudder")
        self.h_title.setText(self.ctl.AXIS_JOBS[job]["title"])
        self.sync_controls()

    def _to_slider(self, key, v):
        lo, hi = self.ctl.SHAPE_RANGE[key]
        return int(round((v - lo) / (hi - lo) * 1000))

    def from_slider(self, key, v):
        if self.busy or not self.job:
            return
        lo, hi = self.ctl.SHAPE_RANGE[key]
        self.ses.set_shape(self.job, key, lo + (hi - lo) * v / 1000.0)
        self.sync_controls(skip=key)

    def from_spin(self, key, v):
        if self.busy or not self.job:
            return
        self.ses.set_shape(self.job, key, v)
        self.sync_controls()

    def on_split(self, on):
        if not self.busy and self.job:
            self.ses.set_shape(self.job, "split", on)

    def sync_controls(self, skip=None):
        if not self.job:
            return
        s = self.ses.shape(self.job)
        self.busy = True
        for key, (sl, spin) in self.rows.items():
            if key != skip:
                sl.setValue(self._to_slider(key, s[key]))
            spin.setValue(s[key])
        self.split.setChecked(bool(s.get("split")))
        self.busy = False
        self.curve.update()
        self.win.mark()

    def assign(self):
        self.ses.start_capture(self.job)
        self.win.mark()

    def reverse(self):
        self.ses.reverse(self.job)
        self.win.mark()

    def clear(self):
        self.ses.clear(self.job)
        self.win.mark()

    def reset(self):
        self.ses.reset_shape(self.job)
        self.sync_controls()

    def scope_changed(self):
        self.sync_controls()

    # -- live
    def tick(self):
        ses = self.ses
        for job, c in self.cards.items():
            b = ses.binding_text(job)
            c.bound.setText("Not bound" if b == "-" else b)
            v = ses.live(job)
            c.meter.set(v)
            c.value.setText("" if v is None else ("%+.2f" % v if job in self.ctl.STICKS else "%.2f" % v))
            sup = (ses.support(job), ses.aircraft)
            if c.sup != sup:   # style sheets are slow to apply, so only on a change
                c.sup = sup
                c.title.setStyleSheet("font-weight: 600; color: %s;" % (C["faint"] if sup[0] is False else C["text"]))
                c.setToolTip("%s doesn't use this" % ses.aircraft if sup[0] is False else "")
        job = self.job
        b = ses.binding_text(job)
        self.h_bound.setText("Not bound yet: press Assign, then move the axis" if b == "-" else "Bound to " + b)
        self.b_rev.setEnabled(b != "-")
        self.b_clear.setEnabled(b != "-")
        r, v = ses.raw(job), ses.live(job)
        self.m_in.set(r)
        self.m_out.set(v)
        self.t_in.setText("" if r is None else "%+.2f" % r)
        self.t_out.setText("" if v is None else "%+.2f" % v)
        self.curve.update()


class ButtonsPage(QtWidgets.QWidget):
    def __init__(self, win):
        super().__init__()
        self.win, self.ctl, self.ses = win, win.ctl, win.ses
        ctl = self.ctl
        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(16, 14, 16, 10)
        lay.setSpacing(10)
        bar = QtWidgets.QHBoxLayout()
        bar.addWidget(label("Buttons and switches", "h2"))
        bar.addSpacing(16)
        self.search = QtWidgets.QLineEdit()
        self.search.setPlaceholderText("Search jobs, e.g. flaps, brake, view")
        self.search.setClearButtonEnabled(True)
        self.search.textChanged.connect(self.filter)
        self.search.setMinimumWidth(320)
        bar.addWidget(self.search)
        self.show_box = QtWidgets.QComboBox()
        self.show_box.addItems(["All jobs", "Bound", "Not bound", "This aircraft only"])
        self.show_box.currentIndexChanged.connect(self.filter)
        bar.addWidget(self.show_box)
        bar.addStretch(1)
        self.b_assign = button("Assign: press a button", self.assign, "assign",
                               "Then press the stick button (or push the hat) you want for the selected job")
        self.b_clear = button("Clear", self.clear, "danger")
        bar.addWidget(self.b_assign)
        bar.addWidget(self.b_clear)
        lay.addLayout(bar)
        tip = label("Press any button on a stick to jump to the job it does. Double-click a job to assign it.", "dim")
        lay.addWidget(tip)

        self.tree = QtWidgets.QTreeWidget()
        self.tree.setColumnCount(3)
        self.tree.setHeaderLabels(["Job", "Bound to", ""])
        self.tree.setAlternatingRowColors(True)
        self.tree.setRootIsDecorated(True)
        self.tree.setUniformRowHeights(True)
        self.tree.setIndentation(18)
        hdr = self.tree.header()
        hdr.setStretchLastSection(False)
        mode = QtWidgets.QHeaderView.Stretch
        hdr.setSectionResizeMode(0, mode)
        hdr.setSectionResizeMode(1, mode)
        hdr.setSectionResizeMode(2, QtWidgets.QHeaderView.Fixed)
        self.tree.setColumnWidth(2, 70)
        self.tree.itemDoubleClicked.connect(lambda *_a: self.assign())
        self.items, self.groups = {}, {}
        jobs = ["hat"] + list(ctl.BUTTON_JOBS)
        for g in ctl.GROUPS:
            mine = [j for j in jobs if ctl.JOBS[j]["group"] == g]
            if not mine:
                continue
            gi = QtWidgets.QTreeWidgetItem([g, "", ""])
            f = gi.font(0)
            f.setBold(True)
            gi.setFont(0, f)
            gi.setFlags(Qt.ItemIsEnabled)
            self.tree.addTopLevelItem(gi)
            self.groups[g] = gi
            for j in mine:
                it = QtWidgets.QTreeWidgetItem([ctl.job_title(j), "", ""])
                it.setData(0, Qt.UserRole, j)
                it.setTextAlignment(2, Qt.AlignCenter)
                gi.addChild(it)
                self.items[j] = it
            gi.setExpanded(True)
        lay.addWidget(self.tree, 1)
        self.last_pressed = set()
        self.cache = {}

    def selected_job(self):
        it = self.tree.currentItem()
        return it.data(0, Qt.UserRole) if it is not None else None

    def assign(self):
        j = self.selected_job()
        if j:
            self.ses.start_capture(j)
        else:
            self.ses.message = "Pick a job in the list first."
        self.win.mark()

    def clear(self):
        j = self.selected_job()
        if j:
            self.ses.clear(j)
            self.win.mark()

    def filter(self, *_a):
        q = self.search.text().strip().lower()
        mode = self.show_box.currentIndex()
        for g, gi in self.groups.items():
            shown = 0
            for i in range(gi.childCount()):
                it = gi.child(i)
                j = it.data(0, Qt.UserRole)
                bound = self.ses.binding_text(j) != "-"
                ok = (not q or q in it.text(0).lower() or q in it.text(1).lower())
                ok = ok and (mode != 1 or bound) and (mode != 2 or not bound) and (mode != 3 or self.ses.support(j) is not False)
                it.setHidden(not ok)
                shown += ok
            gi.setHidden(shown == 0)

    def tick(self):
        ses = self.ses
        dim, txt, ok = qcolor("faint"), qcolor("text"), qcolor("ok")
        for j, it in self.items.items():
            b = ses.binding_text(j)
            sup = ses.support(j)
            live = ses.live(j) if j != "hat" else None
            state = (b, sup, bool(live))
            if self.cache.get(j) == state:
                continue
            self.cache[j] = state
            it.setText(1, "" if b == "-" else b)
            col = dim if sup is False else txt
            it.setForeground(0, QtGui.QBrush(col))
            it.setForeground(1, QtGui.QBrush(qcolor("dim")))
            it.setToolTip(0, ("%s doesn't use this" % ses.aircraft) if sup is False else "")
            it.setText(2, "●" if live else "")
            it.setForeground(2, QtGui.QBrush(ok))
        for g, gi in self.groups.items():
            n = sum(1 for i in range(gi.childCount()) if gi.child(i).text(1))
            gi.setText(1, "%d bound" % n if n else "")
            gi.setForeground(1, QtGui.QBrush(qcolor("dim")))
        # press-to-find: a fresh press (not while assigning) selects the job it does
        new = ses.pressed - self.last_pressed
        self.last_pressed = set(ses.pressed)
        if new and not ses.capture:
            path, code = sorted(new)[0]
            d = ses.names.get(path)
            dev = self.ctl.dev_key(d) if d else None
            hit = [j for j, v in ses.mapping["buttons"].items() if v.get("dev") == dev and v.get("code") == code]
            bname = self.ctl.key_name(code).replace("button-", "button ")
            if hit:
                it = self.items.get(hit[0])
                if it is not None:
                    it.setHidden(False)
                    it.parent().setHidden(False)
                    self.tree.setCurrentItem(it)
                    self.tree.scrollToItem(it)
                ses.message = "%s on %s does: %s." % (bname, d.name if d else "?", ", ".join(self.ctl.job_title(h) for h in hit))
            else:
                ses.message = "%s on %s isn't bound. Pick a job and press Assign." % (bname, d.name if d else "?")


class SticksPage(QtWidgets.QWidget):
    def __init__(self, win):
        super().__init__()
        self.win, self.ctl, self.ses = win, win.ctl, win.ses
        outer = QtWidgets.QVBoxLayout(self)
        outer.setContentsMargins(16, 14, 16, 10)
        outer.addWidget(label("Your sticks", "h2"))
        outer.addWidget(label("Move every stick, twist and lever end to end once: the green band is the range "
                              "seen, and that calibrates the axis when you save.", "dim", wrap=True))
        area = QtWidgets.QScrollArea()
        area.setWidgetResizable(True)
        host = QtWidgets.QWidget()
        host.setObjectName("root")
        hv = QtWidgets.QVBoxLayout(host)
        hv.setContentsMargins(0, 8, 0, 0)
        grid = QtWidgets.QHBoxLayout()
        grid.setSpacing(16)
        hv.addLayout(grid)
        hv.addStretch(1)
        self.bars, self.lamps, self.hats = [], [], []
        ctl = self.ctl
        if not self.ses.devs:
            grid.addWidget(label("No Saitek controller found. Plug them in and reopen this window.", "dim"))
        for d in self.ses.devs:
            c = card()
            cl = QtWidgets.QVBoxLayout(c)
            cl.setContentsMargins(16, 12, 16, 14)
            t = label(d.name)
            t.setStyleSheet("font-weight: 600; font-size: 12pt;")
            cl.addWidget(t)
            axes, keys = ctl.describe(d)
            g = QtWidgets.QGridLayout()
            g.setHorizontalSpacing(10)
            row = 0
            hat = [code for code, *_r in axes if code in ctl.HAT_CODES]
            for code, name, _a, _b, _v in axes:
                if code in ctl.HAT_CODES:
                    continue
                g.addWidget(label(ctl.PLAIN.get(code, name), "dim"), row, 0)
                m = Meter(height=14)
                g.addWidget(m, row, 1)
                self.bars.append((m, (d.path, code)))
                row += 1
            g.setColumnStretch(1, 1)
            cl.addLayout(g)
            if hat:
                hr = QtWidgets.QHBoxLayout()
                hr.addWidget(label("Hat", "dim"))
                hv = HatView()
                hr.addWidget(hv)
                hr.addStretch(1)
                cl.addLayout(hr)
                self.hats.append((hv, d.path, hat))
            lg = QtWidgets.QGridLayout()
            lg.setSpacing(5)
            for i, (code, name) in enumerate(keys):
                lamp = Lamp(name.replace("button-", ""))
                lg.addWidget(lamp, i // 6, i % 6)
                self.lamps.append((lamp, (d.path, code)))
            cl.addLayout(lg)
            grid.addWidget(c, 1, Qt.AlignTop)
        area.setWidget(host)
        outer.addWidget(area, 1)

    def tick(self):
        ses = self.ses
        for m, k in self.bars:
            m.set(None, ses.lo.get(k), ses.hi.get(k), marker=ses.values.get(k, 0.5))
        for lamp, k in self.lamps:
            lamp.set(k in ses.pressed)
        for hv, path, codes in self.hats:
            xs = [ses.values.get((path, c), 0.5) for c in codes[:2]]
            hv.set(*[(-1 if v < 0.25 else (1 if v > 0.75 else 0)) for v in xs + [0.5] * (2 - len(xs))])


class FFBPage(QtWidgets.QWidget):
    def __init__(self, win):
        super().__init__()
        self.win = win
        self.dirty = False
        self.ffbm, self.ffb_path = win.ctl.ffb_module()
        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(16, 14, 16, 10)
        lay.addWidget(label("Force feedback", "h2"))
        if self.ffbm is None:
            lay.addWidget(label("The force feedback bridge (fgfs-mga-ffb) isn't installed next to this tool.", "dim"))
            lay.addStretch(1)
            return
        m = self.ffbm
        conf = m.load_conf()
        c = card()
        c.setMaximumWidth(900)
        cl = QtWidgets.QVBoxLayout(c)
        cl.setContentsMargins(20, 16, 20, 16)
        cl.setSpacing(10)
        self.en = QtWidgets.QCheckBox("Force feedback on (Saitek Cyborg Evo Force)")
        self.en.setChecked(bool(conf["enabled"]))
        self.en.toggled.connect(self.touch)
        self.en.setStyleSheet("font-weight: 600; font-size: 12pt;")
        cl.addWidget(self.en)
        self.vals = {}
        g = QtWidgets.QGridLayout()
        g.setHorizontalSpacing(14)
        g.setVerticalSpacing(10)
        for i, key in enumerate(["master", "spring", "buffet", "rumble", "vref_kt", "buffet_alpha", "trim_follow"]):
            lo, hi = m.RANGE[key]
            text = m.HELP[key]
            name, _sep, rest = text.partition(": ")
            nl = label(name)
            nl.setStyleSheet("font-weight: 600;%s" % (" font-size: 12pt;" if key == "master" else ""))
            hl = label(rest, "dim", wrap=True)
            hl.setStyleSheet("font-size: 9.5pt; color: %s;" % C["dim"])
            box = QtWidgets.QVBoxLayout()
            box.setSpacing(0)
            box.addWidget(nl)
            box.addWidget(hl)
            sl = QtWidgets.QSlider(Qt.Horizontal)
            step = 10 if hi - lo <= 30 else 1
            sl.setRange(int(lo * step), int(hi * step))
            sl.setValue(int(round(conf[key] * step)))
            val = label("", "dim")
            val.setFixedWidth(60)
            val.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
            unit = "%" if hi == 100 else (" kt" if key == "vref_kt" else "°")

            def moved(v, val=val, step=step, unit=unit):
                val.setText(("%g" % round(v / step, 1)) + unit)
                self.touch()
            sl.valueChanged.connect(moved)
            val.setText(("%g" % round(conf[key], 1)) + unit)
            g.addLayout(box, i, 0)
            g.addWidget(sl, i, 1)
            g.addWidget(val, i, 2)
            self.vals[key] = (sl, step)
        g.setColumnStretch(1, 1)
        g.setColumnMinimumWidth(0, 330)
        cl.addLayout(g)
        row = QtWidgets.QHBoxLayout()
        row.addWidget(button("Test on the stick", self.test, tip="Saves, then plays spring, buffet and rumble for 2 s each"))
        row.addWidget(button("Moderate defaults", self.defaults))
        row.addStretch(1)
        cl.addLayout(row)
        self.note = label("fgfs-mga turns force feedback on by itself when the Evo's driver is loaded. "
                          "For one flight: fgfs-mga --ffb or --no-ffb. A running flight picks up a save within a second.",
                          "dim", wrap=True)
        cl.addWidget(self.note)
        lay.addWidget(c)
        lay.addStretch(1)
        self.dirty = False

    def touch(self, *_a):
        self.dirty = True
        self.win.mark()

    def collect(self):
        c = {k: round(sl.value() / step, 1) for k, (sl, step) in self.vals.items()}
        c["enabled"] = self.en.isChecked()
        return c

    def save(self):
        if self.ffbm is None or not self.dirty:
            return False
        self.ffbm.save_conf(dict(self.ffbm.load_conf(), **self.collect()))
        self.dirty = False
        return True

    def defaults(self):
        for k, (sl, step) in self.vals.items():
            sl.setValue(int(round(self.ffbm.DEFAULTS[k] * step)))
        self.en.setChecked(True)

    def test(self):
        self.dirty = True
        self.save()
        try:
            QtCore.QProcess.startDetached(sys.executable, [self.ffb_path, "test"])
            self.win.ses.message = "Playing spring, buffet and rumble for 2 s each. Hold the stick loosely."
        except Exception as e:  # noqa: BLE001 - shown to the user
            self.win.ses.message = "Couldn't start the test: %s" % e
        self.win.mark()


# ---------------------------------------------------------------- window
class Window(QtWidgets.QMainWindow):
    def __init__(self, ctl, ses, planes, dry=False):
        super().__init__()
        self.ctl, self.ses, self.planes, self.dry = ctl, ses, planes, dry
        self.ready = False
        ses.message = ("Move every stick, twist and lever end to end once (that calibrates them), "
                       "then pick a job and press Assign.")
        self.setWindowTitle("FlightGear controls")
        root = QtWidgets.QWidget()
        root.setObjectName("root")
        self.setCentralWidget(root)
        v = QtWidgets.QVBoxLayout(root)
        v.setContentsMargins(0, 0, 0, 0)
        v.setSpacing(0)

        top = QtWidgets.QFrame()
        top.setObjectName("topbar")
        tl = QtWidgets.QHBoxLayout(top)
        tl.setContentsMargins(18, 10, 18, 10)
        tl.setSpacing(12)
        tl.addWidget(label("Controls", "title"))
        tl.addSpacing(18)
        tl.addWidget(label("Aircraft", "dim"))
        self.ac = QtWidgets.QComboBox()
        self.ac.addItem("All aircraft")
        for a in planes:
            self.ac.addItem(a)
        self.ac.setMinimumWidth(260)
        self.ac.currentIndexChanged.connect(self.pick_aircraft)
        tl.addWidget(self.ac)
        self.scope = label("", "scope")
        tl.addWidget(self.scope, 1)
        self.b_save = button("Save", self.save, "primary", "Ctrl+S")
        self.b_close = button("Close", self.close)
        tl.addWidget(self.b_save)
        tl.addWidget(self.b_close)
        v.addWidget(top)

        self.tabs = QtWidgets.QTabWidget()
        self.tabs.setDocumentMode(True)
        tf = self.tabs.tabBar().font()
        tf.setPointSizeF(12)
        self.tabs.tabBar().setFont(tf)
        self.axes = AxesPage(self)
        self.buttons = ButtonsPage(self)
        self.sticks = SticksPage(self)
        self.ffb = FFBPage(self)
        self.tabs.addTab(self.axes, "Axes and response")
        self.tabs.addTab(self.buttons, "Buttons")
        self.tabs.addTab(self.sticks, "Sticks")
        self.tabs.addTab(self.ffb, "Force feedback")
        v.addWidget(self.tabs, 1)

        self.status = QtWidgets.QFrame()
        self.status.setObjectName("status")
        sl = QtWidgets.QHBoxLayout(self.status)
        sl.setContentsMargins(18, 10, 18, 10)
        self.msg = label("", "statustext", wrap=True)
        sl.addWidget(self.msg, 1)
        self.b_cancel = button("Cancel assign", self.cancel)
        sl.addWidget(self.b_cancel)
        v.addWidget(self.status)

        sc = getattr(QtWidgets, "QShortcut", None) or QtGui.QShortcut
        for keys, slot in (("Ctrl+S", self.save), ("Escape", self.cancel)):
            s = sc(QtGui.QKeySequence(keys), self)
            s.activated.connect(slot)

        self.ready = True
        self.pick_aircraft(0)
        self.timer = QtCore.QTimer(self)
        self.timer.timeout.connect(self.tick)
        self.timer.start(33)
        self.tick()

    def mark(self):
        if self.ready:
            self.tick(poll=False)

    def pick_aircraft(self, i):
        if i <= 0:
            self.ses.set_aircraft(None)
        else:
            a = self.ac.itemText(i)
            self.ses.set_aircraft(a, self.planes.get(a))
        self.axes.scope_changed()
        self.buttons.cache.clear()
        self.buttons.filter()

    def cancel(self):
        if self.ses.capture:
            self.ses.cancel_capture()
            self.mark()

    def save(self):
        rc = self.ses.save(self.dry)
        saved_ffb = self.ffb.save()
        if rc != 0 and saved_ffb:
            self.ses.message = "Force feedback saved. A running flight picks it up within a second."
        warn = self.ses.problems()
        if rc == 0 and warn:
            self.ses.message += "  Check: " + "; ".join(warn) + "."
        self.mark()

    def closeEvent(self, e):
        if self.ses.dirty or self.ffb.dirty:
            box = QtWidgets.QMessageBox(self)
            box.setWindowTitle("Unsaved changes")
            box.setText("Save your changes before closing?")
            box.setStandardButtons(QtWidgets.QMessageBox.Save | QtWidgets.QMessageBox.Discard |
                                   QtWidgets.QMessageBox.Cancel)
            r = box.exec() if hasattr(box, "exec") else box.exec_()
            if r == QtWidgets.QMessageBox.Cancel:
                e.ignore()
                return
            if r == QtWidgets.QMessageBox.Save:
                self.save()
        e.accept()

    def tick(self, poll=True):
        if poll:
            try:
                self.ses.poll()
            except Exception:  # noqa: BLE001 - a stick unplugged mid-read shouldn't close the window
                pass
        ses = self.ses
        if ses.aircraft:
            own = self.axes.job and ses.has_own_shape(self.axes.job)
            self.scope.setText("Response changes apply to %s only%s" % (
                ses.aircraft, "" if own else " (it uses the all-aircraft settings until you change one)"))
        else:
            self.scope.setText("Response changes apply to every aircraft (unless one has its own)")
        cap = bool(ses.capture)
        if self.status.property("capture") != cap:
            self.status.setProperty("capture", cap)
            self.status.style().unpolish(self.status)
            self.status.style().polish(self.status)
        self.b_cancel.setVisible(cap)
        dirty = ses.dirty or self.ffb.dirty
        self.msg.setText(("Unsaved changes.  " if dirty and not cap else "") + ses.message)
        self.b_save.setText("Save *" if dirty else "Save")
        page = self.tabs.currentWidget()
        if hasattr(page, "tick"):
            page.tick()
        if page is not self.buttons:
            self.buttons.last_pressed = set(ses.pressed)


def apply_theme(app):
    """Dark Fusion look with the palette and style sheet above."""
    app.setStyle("Fusion")
    pal = QtGui.QPalette()
    for role, col in (("Window", "bg"), ("WindowText", "text"), ("Base", "card"), ("AlternateBase", "card2"),
                      ("Text", "text"), ("Button", "card2"), ("ButtonText", "text"), ("Highlight", "accent2"),
                      ("HighlightedText", "text"), ("ToolTipBase", "card2"), ("ToolTipText", "text")):
        r = getattr(QtGui.QPalette, role, None)
        if r is None:
            r = getattr(QtGui.QPalette.ColorRole, role)
        pal.setColor(r, qcolor(col))
    app.setPalette(pal)
    f = app.font()
    try:
        fams = set(QtGui.QFontDatabase.families() if QT == "PySide6" else QtGui.QFontDatabase().families())
    except Exception:  # noqa: BLE001
        fams = set()
    for fam in ("Inter", "Noto Sans", "Cantarell", "DejaVu Sans"):
        if fam in fams:
            f.setFamily(fam)
            break
    f.setPointSizeF(11)
    app.setFont(f)
    app.setStyleSheet(QSS)


def arg_value(args, name):
    """The value after `name` (or in `name=value`) in args, else None."""
    for i, a in enumerate(args):
        if a == name and i + 1 < len(args):
            return args[i + 1]
        if a.startswith(name + "="):
            return a.split("=", 1)[1]
    return None


def run(ctl, args):
    """Open the window. ctl is the fgfs-mga-controls module. Returns an exit code.
    --aircraft ID opens on that aircraft's settings (the FlightGear launcher passes the one it has picked).
    Only one window at a time: a second start just says so and exits."""
    lock = None
    if not os.environ.get("FGFS_MGA_GUI_SHOT"):
        run_dir = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
        lock = QtCore.QLockFile(os.path.join(run_dir, "fgfs-mga-controls-gui.lock"))
        lock.setStaleLockTime(0)
        if not lock.tryLock(200):
            print("The controls window is already open.")
            return 0
    devs = ctl.find_devices("--all" in args)
    if not devs:
        print("No Saitek controller found. Plug them in and try again.")
    ses = ctl.Session(devs, ctl.load_map())
    if hasattr(Qt, "AA_EnableHighDpiScaling"):
        QtWidgets.QApplication.setAttribute(Qt.AA_EnableHighDpiScaling, True)
    app = QtWidgets.QApplication.instance() or QtWidgets.QApplication([sys.argv[0]])
    app.setApplicationName("fgfs-mga controls")
    apply_theme(app)
    win = Window(ctl, ses, ctl.find_aircraft(), dry="--dry-run" in args)
    want = arg_value(args, "--aircraft")
    if want:
        i = win.ac.findText(want)
        if i > 0:
            win.ac.setCurrentIndex(i)   # pick_aircraft runs through the signal
    win.resize(1440, 900)
    win.setMinimumSize(1100, 700)
    shot = os.environ.get("FGFS_MGA_GUI_SHOT")   # test hook: save pictures of each tab, then close
    close_after = os.environ.get("FGFS_MGA_GUI_AUTOCLOSE")
    win.show()
    if shot:
        def snap():
            for i in range(win.tabs.count()):
                win.tabs.setCurrentIndex(i)
                win.tick()
                app.processEvents()
                win.grab().save("%s-%d.png" % (shot, i))
            win.ses.dirty = win.ffb.dirty = False
            win.close()
        QtCore.QTimer.singleShot(400, snap)
    elif close_after:
        def done():
            win.ses.dirty = win.ffb.dirty = False
            win.close()
        QtCore.QTimer.singleShot(int(float(close_after) * 1000), done)
    return app.exec() if hasattr(app, "exec") else app.exec_()


if __name__ == "__main__":
    from importlib.machinery import SourceFileLoader
    here = os.path.dirname(os.path.realpath(__file__))
    sys.exit(run(SourceFileLoader("fgfs_mga_controls", os.path.join(here, "fgfs-mga-controls")).load_module(),
                 sys.argv[1:]))
__FGFS_MGA_CONTROLS_QT__
  if python3 -m py_compile "$TMPQ" 2>/dev/null; then chmod 755 "$TMPQ"; mv -f -- "$TMPQ" "$CQ"; say "Installed $CQ (run: fgfs-mga controls gui)"
  else rm -f -- "$TMPQ"; say "WARNING: Qt controls window failed a Python check; not installed (the Tk window still works)."; fi
  rm -rf -- "$TOOLS/__pycache__"
fi

# ---------------- force feedback bridge for the Evo Force (Python, python3-evdev) ----------------
if (( DRY )); then
  say "  [dry-run] would write $TOOLS/fgfs-mga-ffb and $TOOLS/fgfs-mga-ffb.xml"
else
  for f in fgfs-mga-ffb fgfs-mga-ffb.xml; do [[ -f "$TOOLS/$f" ]] && { mkdir -p "$BK/tools"; cp -p -- "$TOOLS/$f" "$BK/tools/$f"; }; done   # not in $BK itself: --undo copies those into ~/.local/bin
  TMPF="$(mktemp "$TOOLS/.fgfs-mga-ffb.XXXXXX")"
  cat > "$TMPF" <<'__FGFS_MGA_FFB__'
#!/usr/bin/env python3
"""fgfs-mga ffb: force feedback for the Saitek Cyborg Evo Force while FlightGear flies.

FlightGear sends a few properties over UDP (Protocol/fgfs-mga-ffb.xml, started by fgfs-mga with
FFB=1 or --ffb); this turns them into stick effects:
  control loading  a centring spring that stiffens with airspeed, centred on the elevator trim
  stall buffet     a shake that grows past the stall warning / high angle of attack
  ground rumble    a rumble on the ground that grows with ground speed
Strengths come from ~/.config/fgfs-mga/ffb.json (the Force feedback tab in `fgfs-mga controls gui`),
re-read once a second, so changes apply in flight.

  fgfs-mga-ffb run [--port 5630] [--pid PID]   run the bridge (fgfs-mga starts it for you)
  fgfs-mga-ffb test [effect]                   play each effect for 2 s at the saved strengths
  fgfs-mga-ffb show                            print the settings and the stick found
"""
import json
import os
import select
import socket
import sys
import time

HOME = os.path.expanduser("~")
CONF = os.path.join(HOME, ".config", "fgfs-mga", "ffb.json")
NODE = "/dev/input/by-id/usb-Saitek_Cyborg_Evo_Force-event-joystick"
PORT = 5630
FIELDS = ["ias", "gs", "alpha", "stall", "wow0", "wow1", "wow2", "trim", "frozen"]

DEFAULTS = {          # percent, moderate on purpose
    "enabled": True,
    "master": 70,
    "spring": 45,      # control loading
    "buffet": 50,
    "rumble": 35,
    "vref_kt": 110,    # airspeed where the controls reach full stiffness
    "buffet_alpha": 14.0,   # angle of attack (deg) where the buffet starts without a stall warning
    "trim_follow": 50,      # how far the spring centre follows the elevator trim
}
RANGE = {"master": (0, 100), "spring": (0, 100), "buffet": (0, 100), "rumble": (0, 100),
         "vref_kt": (40, 250), "buffet_alpha": (5.0, 25.0), "trim_follow": (0, 100)}
HELP = {
    "master": "Master strength: scales every effect",
    "spring": "Control loading: centring spring, stiffer as you speed up",
    "buffet": "Stall buffet: shake near the stall",
    "rumble": "Ground rumble: on the runway and taxiways",
    "vref_kt": "Airspeed (kt) where the controls are fully stiff",
    "buffet_alpha": "Angle of attack (deg) where the buffet starts",
    "trim_follow": "How far the spring centre follows elevator trim (%)",
}


def load_conf():
    c = dict(DEFAULTS)
    try:
        with open(CONF) as f:
            c.update({k: v for k, v in json.load(f).items() if k in DEFAULTS})
    except (OSError, ValueError):
        pass
    for k, (lo, hi) in RANGE.items():
        try:
            c[k] = max(lo, min(hi, float(c[k])))
        except (TypeError, ValueError):
            c[k] = DEFAULTS[k]
    c["enabled"] = bool(c["enabled"])
    return c


def save_conf(c):
    os.makedirs(os.path.dirname(CONF), exist_ok=True)
    tmp = CONF + ".tmp"
    with open(tmp, "w") as f:
        json.dump({k: c[k] for k in DEFAULTS}, f, indent=1)
    os.replace(tmp, CONF)


def clamp(x, lo=0.0, hi=1.0):
    return lo if x < lo else hi if x > hi else x


def parse(line):
    """One line from FlightGear -> dict of floats, or None if it doesn't look right."""
    parts = line.strip().split(",")
    if len(parts) != len(FIELDS):
        return None
    try:
        return dict(zip(FIELDS, (float(p) for p in parts)))
    except ValueError:
        return None


def targets(s, c):
    """What each effect should do now: spring (coef 0..1, centre -1..1), buffet and rumble
    (amplitude 0..1, period ms). Strength sliders are applied here; master is the device gain."""
    on_ground = s["wow0"] > 0.5 or s["wow1"] > 0.5 or s["wow2"] > 0.5
    q = clamp((max(s["ias"], 0.0) / c["vref_kt"]) ** 2)
    spring = (c["spring"] / 100.0) * (0.15 + 0.85 * q)
    centre = clamp(-s["trim"] * c["trim_follow"] / 100.0, -1.0, 1.0)
    start = c["buffet_alpha"]
    shake = clamp((s["alpha"] - start) / 6.0)
    if s["stall"] > 0.5:
        shake = max(shake, 0.5)
    if on_ground:
        shake = 0.0
    buffet = (c["buffet"] / 100.0) * shake
    gs = max(s["gs"], 0.0)
    rumble = (c["rumble"] / 100.0) * clamp(gs / 40.0) if on_ground and gs > 2.0 else 0.0
    rumble_ms = int(max(25, min(70, 70 - gs)))
    if s["frozen"] > 0.5:
        buffet = rumble = 0.0
    return {"spring": (round(spring, 3), round(centre, 3)), "buffet": (round(buffet, 3), 70),
            "rumble": (round(rumble, 3), rumble_ms)}


class Stick:
    """The Evo Force through evdev. Each effect is uploaded once and then updated in place."""

    def __init__(self, path=NODE):
        import evdev
        from evdev import ecodes, ff
        self.E, self.ff = ecodes, ff
        self.dev = evdev.InputDevice(path)
        self.ids, self.playing, self.last = {}, set(), {}

    def gain(self, pct):
        self.dev.write(self.E.EV_FF, self.E.FF_GAIN, int(0xFFFF * clamp(pct / 100.0)))

    def _effect(self, kind, value):
        E, ff = self.E, self.ff
        env = ff.Envelope(0, 0, 0, 0)
        eid = self.ids.get(kind, -1)
        if kind == "spring":
            coef, centre = value
            k = int(0x7FFF * coef)
            cy = int(0x7FFF * centre)
            x = ff.Condition(0xFFFF, 0xFFFF, k, k, 0, 0)
            y = ff.Condition(0xFFFF, 0xFFFF, k, k, 0, cy)
            return ff.Effect(E.FF_SPRING, eid, 0, ff.Trigger(0, 0), ff.Replay(0, 0),
                             ff.EffectType(ff_condition_effect=(x, y)))
        amp, period = value
        return ff.Effect(E.FF_PERIODIC, eid, 0x4000 if kind == "buffet" else 0, ff.Trigger(0, 0), ff.Replay(0, 0),
                         ff.EffectType(ff_periodic_effect=ff.Periodic(E.FF_SINE, period, int(0x7FFF * amp), 0, 0, env)))

    def set(self, kind, value):
        """Upload/update one effect; play it when it's non-zero, stop it when it's zero."""
        active = (value[0] > 0.005)
        if self.last.get(kind) != value:
            if active or kind in self.ids:
                self.ids[kind] = self.dev.upload_effect(self._effect(kind, value))
            self.last[kind] = value
        if active and kind not in self.playing:
            self.dev.write(self.E.EV_FF, self.ids[kind], 1)
            self.playing.add(kind)
        elif not active and kind in self.playing:
            self.dev.write(self.E.EV_FF, self.ids[kind], 0)
            self.playing.discard(kind)

    def stop(self):
        for kind in list(self.playing):
            try:
                self.dev.write(self.E.EV_FF, self.ids[kind], 0)
            except OSError:
                pass
        self.playing.clear()

    def close(self):
        self.stop()
        for eid in self.ids.values():
            try:
                self.dev.erase_effect(eid)
            except OSError:
                pass
        self.ids.clear()
        self.last.clear()


def changed(a, b, tol=0.02):
    """True when targets moved enough to be worth a USB update (keeps the stick's link quiet)."""
    if a is None:
        return True
    for k in b:
        for x, y in zip(a[k], b[k]):
            if abs(x - y) > (tol if isinstance(x, float) else 2):
                return True
    return False


def run(args, stick_factory=Stick, sock=None, clock=time.monotonic, max_loops=None):
    port = int(args[args.index("--port") + 1]) if "--port" in args else PORT
    pid = int(args[args.index("--pid") + 1]) if "--pid" in args else None
    if sock is None:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind(("127.0.0.1", port))
    stick = None
    conf, conf_mtime, next_conf = load_conf(), None, 0.0
    sent, last_rx, loops, gain_set = None, None, 0, None
    log = lambda m: print("fgfs-mga-ffb: " + m, flush=True)
    log("listening on udp %d%s" % (port, " for fgfs pid %d" % pid if pid else ""))
    try:
        while max_loops is None or loops < max_loops:
            loops += 1
            now = clock()
            if now >= next_conf:                       # settings changed in the GUI?
                next_conf = now + 1.0
                try:
                    m = os.path.getmtime(CONF)
                except OSError:
                    m = None
                if m != conf_mtime:
                    conf_mtime, conf, sent = m, load_conf(), None
                if pid and not os.path.exists("/proc/%d" % pid):
                    log("FlightGear closed; stopping")
                    break
            if stick is None:
                try:
                    stick, gain_set = stick_factory(), None
                    log("stick ready")
                except OSError:
                    stick = None
            r, _w, _x = select.select([sock], [], [], 0.1)
            s = None
            while r:                                    # keep only the newest good packet
                data = sock.recv(512)
                for ln in data.decode("ascii", "replace").splitlines():
                    s = parse(ln) or s
                r, _w, _x = select.select([sock], [], [], 0)
            if stick is None:
                continue
            try:
                if s is not None:
                    last_rx = now
                    if not conf["enabled"]:
                        stick.stop()
                        continue
                    if gain_set != conf["master"]:
                        stick.gain(conf["master"])
                        gain_set = conf["master"]
                    t = targets(s, conf)
                    if changed(sent, t):
                        for kind in ("spring", "buffet", "rumble"):
                            stick.set(kind, t[kind])
                        sent = t
                elif last_rx is not None and now - last_rx > 2.0:   # sim paused, reset or gone
                    stick.stop()
                    sent, last_rx = None, None
            except OSError as e:                        # unplugged mid-flight
                log("lost the stick (%s); waiting for it" % e)
                stick, sent = None, None
    except KeyboardInterrupt:
        pass
    finally:
        if stick:
            stick.close()
    return 0


def cmd_test(args):
    c = load_conf()
    which = [a for a in args if a in ("spring", "buffet", "rumble")] or ["spring", "buffet", "rumble"]
    try:
        st = Stick()
    except OSError as e:
        print("Can't open the Evo Force (%s). Is it plugged in, with its force feedback driver loaded?" % e)
        return 1
    demo = {"spring": {"ias": c["vref_kt"], "gs": c["vref_kt"], "alpha": 3, "stall": 0, "wow0": 0, "wow1": 0, "wow2": 0, "trim": 0, "frozen": 0},
            "buffet": {"ias": 50, "gs": 50, "alpha": c["buffet_alpha"] + 4, "stall": 1, "wow0": 0, "wow1": 0, "wow2": 0, "trim": 0, "frozen": 0},
            "rumble": {"ias": 30, "gs": 30, "alpha": 0, "stall": 0, "wow0": 1, "wow1": 1, "wow2": 1, "trim": 0, "frozen": 0}}
    try:
        st.gain(c["master"])
        for kind in which:
            t = targets(demo[kind], c)
            print("  %-7s %s ... " % (kind, t[kind]), end="", flush=True)
            st.set(kind, t[kind])
            time.sleep(2.0)
            st.set(kind, (0.0,) + tuple(t[kind][1:]))
            time.sleep(0.4)
            print("done")
    except KeyboardInterrupt:
        pass
    finally:
        st.close()
    return 0


def cmd_show(_args):
    c = load_conf()
    for k in DEFAULTS:
        print("  %-13s %s" % (k, c[k]))
    print("  stick: %s" % (os.path.realpath(NODE) if os.path.exists(NODE) else "not found (" + NODE + ")"))
    return 0


def main(argv):
    cmd = argv[0] if argv else "show"
    fn = {"run": run, "test": cmd_test, "show": cmd_show}.get(cmd)
    if fn is None or "-h" in argv or "--help" in argv:
        print(__doc__)
        return 0 if fn else 2
    return fn(argv[1:])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
__FGFS_MGA_FFB__
  cat > "$TOOLS/fgfs-mga-ffb.xml" <<'__FGFS_MGA_FFB_XML__'
<?xml version="1.0"?>
<!-- fgfs-mga force feedback: what FlightGear sends to fgfs-mga-ffb (fgfs-mga adds
     generic=socket,out,30,127.0.0.1,5630,udp,fgfs-mga-ffb when FFB=1 or with ffb on the command line).
     The field order must match FIELDS in fgfs-mga-ffb. -->
<PropertyList>
 <generic>
  <output>
   <line_separator>newline</line_separator>
   <var_separator>,</var_separator>
   <chunk><name>ias</name><type>float</type><format>%.1f</format><node>/velocities/airspeed-kt</node></chunk>
   <chunk><name>gs</name><type>float</type><format>%.1f</format><node>/velocities/groundspeed-kt</node></chunk>
   <chunk><name>alpha</name><type>float</type><format>%.2f</format><node>/orientation/alpha-deg</node></chunk>
   <chunk><name>stall</name><type>bool</type><format>%d</format><node>/sim/alarms/stall-warning</node></chunk>
   <chunk><name>wow0</name><type>bool</type><format>%d</format><node>/gear/gear[0]/wow</node></chunk>
   <chunk><name>wow1</name><type>bool</type><format>%d</format><node>/gear/gear[1]/wow</node></chunk>
   <chunk><name>wow2</name><type>bool</type><format>%d</format><node>/gear/gear[2]/wow</node></chunk>
   <chunk><name>trim</name><type>float</type><format>%.3f</format><node>/controls/flight/elevator-trim</node></chunk>
   <chunk><name>frozen</name><type>bool</type><format>%d</format><node>/sim/freeze/master</node></chunk>
  </output>
 </generic>
</PropertyList>
__FGFS_MGA_FFB_XML__
  if python3 -m py_compile "$TMPF" 2>/dev/null; then chmod 755 "$TMPF"; mv -f -- "$TMPF" "$TOOLS/fgfs-mga-ffb"; say "Installed $TOOLS/fgfs-mga-ffb (run: fgfs-mga ffb test)"
  else rm -f -- "$TMPF"; say "WARNING: force feedback bridge failed a Python check; not installed."; fi
  rm -rf -- "$TOOLS/__pycache__"
fi

# ---------------- config (never overwritten) ----------------
if [[ -f "$CONF" ]]; then
  say "Kept your existing config: $CONF"
  # 1.1.x workaround: ADDONS="" stopped double add-ons with --launcher but also turned every
  # add-on off for normal starts. 1.2 skips the launcher window's own add-ons instead.
  if grep -qx 'ADDONS=""' "$CONF" && (( ! DRY )); then
    mkdir -p "$BK"; cp -p -- "$CONF" "$BK/config"
    sed -i 's/^ADDONS=""$/#ADDONS=""   # not needed since fgfs-mga 1.2 (it skips add-ons the launcher window already loads)/' "$CONF"
    say "  turned off the old ADDONS=\"\" line in $CONF (backup in $BK/config)"
  fi
elif (( DRY )); then
  say "  [dry-run] would write $CONF (aircraft=${DEF_AIRCRAFT:-warrior}, airport=${DEF_AIRPORT:-KEZM})"
else
  cat > "$CONF" <<EOF
# fgfs-mga settings. Lines here override the launcher's defaults. Plain bash.
DEFAULT_AIRCRAFT="${DEF_AIRCRAFT:-warrior}"   # short name (warrior, r44, seminole...) or an aircraft id
DEFAULT_PRESET="balanced"                    # fast | balanced | training | high
DEFAULT_AIRPORT="${DEF_AIRPORT:-KEZM}"                       # KEZM = Heart of Georgia Regional, Eastman (MGA)
DEFAULT_BUILD="source"                       # source | aeonwave | system
#FGFS_BIN="\$HOME/builds/flightgear/build/src/Main/fgfs"
#FGFS_BIN_AEONWAVE="\$HOME/builds/flightgear-aeonwave-prefix/bin/fgfs"
#FGFS_BIN_SYSTEM="/usr/local/bin/fgfs"
#FG_ROOT_DIR="\$HOME/.fgfs/fgdata_2024_1"
#AIRCRAFT_DIRS="\$HOME/.fgfs/Aircraft"
#ADDONS="Logbook ATCChatter SpokenATC SpokenGCA PAR RedGriffinATC landing_rate which-runway mga-checklist"
#TERRASYNC=1
#INPUT_MODE="event"                         # event | joystick | both | off
#AUDIO_FIX=1                                # unmute the ES8316 codec and fgfs stream at start
#AUDIO_SINK="auto"                         # auto = skip a virtual-surround sink; "" = default; or a sink name
#AUDIO_QUANTUM=1024                         # PipeWire buffer while fgfs plays (0 = leave it)
#DEVELOPER=0                                # 1 = FlightGear developer mode (noisy log)
#FFB="auto"                                 # force feedback bridge: auto, 1 or 0
#CONTROLS_CHECK=1                           # warn before a flight if a stick is unplugged or roll/pitch/rudder/throttle/brakes is free
#PHOTOSCENERY=1                             # photoscenery overlay on when Orthophotos exist
# Extra fgfs flags added to every start, e.g. EXTRA_ARGS=(--prop:/sim/rendering/fps-display=true)
EXTRA_ARGS=()
EOF
  say "Wrote $CONF"
fi

# ---------------- old launchers and tools -> shims ----------------
write_shim() {  # name target-args
  local n="$1" t="$2" tmp
  tmp="$(mktemp "$BIN/.$n.XXXXXX")"
  # shellcheck disable=SC2016  # $HOME and $@ are meant literally in the shim
  printf '#!/usr/bin/env bash\n# fgfs-mga shim: the old name "%s" now calls fgfs-mga.\n# Original saved in %s\nexec "$HOME/.local/bin/fgfs-mga"%s "$@"\n' \
    "$n" "$BK/$n" "$t" > "$tmp"
  chmod 755 "$tmp"; mv -f -- "$tmp" "$BIN/$n"
}
for n in $LAUNCHERS $TOOL_FILES; do
  f="$BIN/$n"
  [[ -e "$f" ]] || continue
  if is_shim "$f"; then say "Already a shim: $n"; continue; fi
  if (( KEEP_OLD )); then say "Left as is (--keep-old): $n"; continue; fi
  t="$(shim_args "$n")"
  act mkdir -p "$BK"; act cp -p -- "$f" "$BK/$n"
  if is_tool "$n"; then act cp -p -- "$f" "$TOOLS/$n"; act chmod u+x "$TOOLS/$n"; fi
  if (( DRY )); then say "  [dry-run] would back up $n and make it run: fgfs-mga$t"
  else write_shim "$n" "$t"; say "Backed up $n ; it now runs: fgfs-mga$t"; fi
done

# ---------------- anything else that looks like a FlightGear launcher ----------------
while IFS= read -r f; do
  n="${f##*/}"
  case " $LAUNCHERS $TOOL_FILES fgfs-mga " in *" $n "*) continue ;; esac
  case "$n" in *.bak*) continue ;; esac
  say "Not touched (unknown): $f   -> send me 'fgfs-mga audit' if it should be folded in"
done < <(find "$BIN" -maxdepth 1 -type f \( -name '*fgfs*' -o -name '*flightgear*' -o -name 'fg-*' \) 2>/dev/null | sort)

# ---------------- menu entry ----------------
if [[ -f "$APPS/fgfs-mga.desktop" ]]; then
  say "Kept your menu entry: $APPS/fgfs-mga.desktop ($(grep -m1 '^Exec=' "$APPS/fgfs-mga.desktop"))"
  if ! grep -q '^\[Desktop Action controls\]' "$APPS/fgfs-mga.desktop"; then
    if (( DRY )); then say "  [dry-run] would add a Controls action to it"
    else
      mkdir -p "$BK/desktop"; cp -p -- "$APPS/fgfs-mga.desktop" "$BK/desktop/menu.desktop"
      printf '%s\n' "$APPS/fgfs-mga.desktop" > "$BK/desktop/menu.path"   # so --undo puts it back
      if grep -q '^Actions=' "$APPS/fgfs-mga.desktop"; then
        sed -i -E 's/^Actions=(.*)$/Actions=\1;controls;/; s/;;+/;/g' "$APPS/fgfs-mga.desktop"
      else
        sed -i '0,/^\[Desktop Entry\]/{/^\[Desktop Entry\]/a Actions=controls;
}' "$APPS/fgfs-mga.desktop"
      fi
      printf '\n[Desktop Action controls]\nName=Controls (sticks, sensitivity, curves)\nExec=%s controls gui\n' "$NEW" >> "$APPS/fgfs-mga.desktop"
      say "  added a Controls action (right-click the menu entry); backup in $BK/desktop"
    fi
  fi
elif (( DRY )); then
  say "  [dry-run] would write $APPS/fgfs-mga.desktop"
else
  cat > "$APPS/fgfs-mga.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=FlightGear MGA
Comment=FlightGear at KEZM with the MGA fleet (fgfs-mga)
Exec=$NEW --launcher
Terminal=false
Categories=Game;Simulation;
Actions=controls;

[Desktop Action controls]
Name=Controls (sticks, sensitivity, curves)
Exec=$NEW controls gui
EOF
  say "Menu entry: $APPS/fgfs-mga.desktop"
fi

# ---------------- tidy (optional) ----------------
if (( TIDY )); then
  say ""
  say "Tidy:"
  mark tidy
  # 1. point .desktop shortcuts at fgfs-mga
  i=0
  for f in "$APPS"/*.desktop "$HOME/Desktop"/*.desktop; do
    [[ -f "$f" ]] || continue
    for n in $LAUNCHERS $TOOL_FILES; do
      grep -qE "^Exec=(\"?$BIN/)?$n( |\"|$)" "$f" || continue
      t="$(shim_args "$n")"; i=$((i + 1))
      act mkdir -p "$BK/desktop"
      act cp -p -- "$f" "$BK/desktop/$i.desktop"
      if (( DRY )); then say "  [dry-run] would point $f at fgfs-mga$t"
      else
        printf '%s\n' "$f" > "$BK/desktop/$i.path"
        sed -i -E "s#^Exec=(\"?$BIN/)?$n(\"?)( |$)#Exec=$NEW$t\3#" "$f"
        say "  $f now runs: fgfs-mga$t"
      fi
      break
    done
  done
  # 2. move the old-name shims out of ~/.local/bin, unless something still calls the old name
  for n in $LAUNCHERS $TOOL_FILES; do
    f="$BIN/$n"; is_shim "$f" || continue
    users=""
    for u in "$TOOLS"/* "$BIN"/* "$APPS"/*.desktop "$HOME/Desktop"/*.desktop; do
      [[ -f "$u" && "${u##*/}" != "$n" && "$u" != "$NEW" && "$u" != *.bak* ]] || continue
      is_shim "$u" && continue
      grep -qE -- "(^|[^-A-Za-z0-9_.])$n([^-A-Za-z0-9_.]|\$)" "$u" 2>/dev/null && users="$users ${u##*/}"
    done
    if [[ -n "$users" ]]; then say "  kept $n (still called by:$users)"; continue; fi
    act mkdir -p "$BK/shims"; act mv -- "$f" "$BK/shims/$n"; say "  removed old name $n (shim moved to $BK/shims/)"
  done
  # 3. move *.bak launchers out of ~/.local/bin
  for f in "$BIN"/*fgfs*.bak* "$BIN"/*flightgear*.bak*; do
    [[ -f "$f" ]] || continue
    act mkdir -p "$BK/old-bak"; act mv -- "$f" "$BK/old-bak/"; say "  moved $f to $BK/old-bak/"
  done
fi

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) say "NOTE: $BIN is not on your PATH. Add this to ~/.bashrc:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

say ""
if (( DRY )); then
  say "Dry run done. Run again without --dry-run to apply."
else
  say "Done. Check it with:  fgfs-mga list   and   fgfs-mga --dry-run"
  say "Start the sim with:   fgfs-mga            (or e.g. fgfs-mga seminole fast)"
  [[ -d "$BK" ]] && say "Backups: $BK   (reverse with this installer's --undo)"
fi
__FGFS_MGA_INSTALL__
