#!/usr/bin/env bash
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
@@LAUNCHER@@
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
@@CONTROLS@@
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
@@CONTROLSQT@@
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
@@FFB@@
__FGFS_MGA_FFB__
  cat > "$TOOLS/fgfs-mga-ffb.xml" <<'__FGFS_MGA_FFB_XML__'
@@FFBXML@@
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
