#!/bin/bash
# Aquila walker: FlightGear's walker in the Aquila Flight Program flight suit, on every fleet plane.
#
#   bash install.sh             install (or re-run after an aircraft update; it changes nothing twice)
#   bash install.sh --dry-run   show what each plane would get
#   bash install.sh --undo      put every changed file back and remove the Aquila files
#
# Changes, each original copied first to $AQUILA_BACKUP (default ~/.local/share/fgfs-mga/backups/aquila-walker):
#   fgdata Aircraft/Generic/Human/Models: adds outfit 5 (the Aquila flight suit) to walker-inc.xml and
#     walker.xml, the suit files, and two themes for Walker > Select Theme.
#   each fleet plane: writes aquila-walker.xml beside the bottom file of its include chain and points
#     that file's <PropertyList include=...> at it (see src/gen_walker.py for what it holds).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export FGROOT="${FG_ROOT:-$HOME/.fgfs/fgdata_2024_1}"
BK="${AQUILA_BACKUP:-$HOME/.local/share/fgfs-mga/backups/aquila-walker}"
mode="${1:-}"

[[ -f "$FGROOT/Aircraft/Generic/Human/Include/walker-include.xml" ]] || { echo "no FlightGear data at $FGROOT (set FG_ROOT)"; exit 1; }
if pgrep -x fgfs >/dev/null; then echo "FlightGear is running; close it first so it doesn't hold the old files."; exit 1; fi

case "$mode" in
  --dry-run)
    python3 "$HERE/src/gen_walker.py" "$HERE/exits.txt" "$BK" --dry-run ;;
  --undo)
    python3 "$HERE/src/gen_walker.py" "$HERE/exits.txt" "$BK" --undo
    python3 "$HERE/src/patch_fgdata.py" "$HERE/fgdata" "$FGROOT" "$BK" --undo ;;
  "")
    python3 "$HERE/src/patch_fgdata.py" "$HERE/fgdata" "$FGROOT" "$BK"
    python3 "$HERE/src/gen_walker.py" "$HERE/exits.txt" "$BK"
    echo "Done. In the sim: Walker > Toggle Walker out/in, then View > Walker Orbit View or Walk View." ;;
  *) sed -n '2,8p' "$0"; exit 1 ;;
esac
