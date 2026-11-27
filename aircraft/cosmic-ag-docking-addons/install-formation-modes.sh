#!/usr/bin/env bash
# Installs the formation modes (Nasal/cosmic_modes.nas), the Remora spray /
# scout add-on and the retardant bag into the project and into fgdata, with
# one-line hooks in files owned by the docking work:
#   remora-drone-v2-{port,starboard}.xml  <model> remora-modes.xml
#   mothership.xml                         <model> retardant-bag.xml
#   Cosmic-AgMothership-set.xml            Ctrl-F (key 6) -> cosmic_modes.key_formation()
# Idempotent: hooks are only added once (marker "cosmic-modes").
# Backups of every hooked file: ~/backups/cosmic-modes-<time>/
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
P="$(cd "$HERE/../.." && pwd)"
R="${FG_ROOT:-$HOME/.fgfs/fgdata_2024_1}"
SRC="${SRC:-$HERE}"
B="$HOME/backups/cosmic-modes-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$B"
HOOKED=(
  "$R/Aircraft/Cosmic-AgParasite/Models/remora-drone-v2-port.xml"
  "$R/Aircraft/Cosmic-AgParasite/Models/remora-drone-v2-starboard.xml"
  "$R/Aircraft/Cosmic-AgMothership/Models/mothership.xml"
  "$R/Aircraft/Cosmic-AgMothership/Cosmic-AgMothership-set.xml"
  "$P/Models/v2/remora-drone-v2-port.xml"
  "$P/Models/v2/remora-drone-v2-starboard.xml"
  "$P/Aircraft/Cosmic-AgMothership/Models/mothership.xml"
  "$P/Aircraft/Cosmic-AgMothership/Cosmic-AgMothership-set.xml"
)
for f in "${HOOKED[@]}"; do
  d="$B/$(echo "${f#$HOME/}" | tr / _)"; cp -p "$f" "$d"
done
echo "backups: $B"

# new files
TEX="$R/Aircraft/c172p/Models/Effects/pontoon/spray.png"
for M in "$R/Aircraft/Cosmic-AgParasite/Models" "$P/Models/v2"; do
  install -m 644 "$SRC/remora-modes.ac" "$SRC/remora-modes.xml" "$M/"
  install -d "$M/Effects"; install -m 644 "$TEX" "$M/Effects/spray.png"
done
for M in "$R/Aircraft/Cosmic-AgMothership/Models" "$P/Aircraft/Cosmic-AgMothership/Models"; do
  install -m 644 "$SRC/retardant-bag.ac" "$SRC/retardant-bag.xml" "$M/"
done
install -m 644 "$SRC/cosmic_modes.nas" "$R/Nasal/"
install -m 644 "$SRC/cosmic_modes.nas" "$P/Nasal/"

# hooks
python3 - "${HOOKED[@]}" <<'PY'
import sys
MODEL = """  <!-- cosmic-modes: {what} (Scripts/formation-addons) -->
  <model>
    <name>{name}</name>
    <path>{path}</path>
  </model>
</PropertyList>"""
KEY = """      <!-- cosmic-modes: formation modes (Nasal/cosmic_modes.nas) -->
      <key n="6">
        <name>Ctrl-F</name>
        <desc>Drone formation: escort / scout ahead / spray behind</desc>
        <binding>
          <command>nasal</command>
          <script>cosmic_modes.key_formation();</script>
        </binding>
      </key>
    </keyboard>"""
for f in sys.argv[1:]:
    s = open(f).read()
    if "cosmic-modes" in s:
        print("already hooked:", f); continue
    if f.endswith("-set.xml"):
        assert s.count("</keyboard>") == 1 and 'key n="6"' not in s, f
        s = s.replace("    </keyboard>", KEY, 1) if "    </keyboard>" in s else s.replace("</keyboard>", KEY.strip(), 1)
    elif "remora-drone-v2" in f:
        assert s.count("</PropertyList>") == 1, f
        s = s.replace("</PropertyList>", MODEL.format(what="spray bar, spray mist and scout gimbal",
                                                     name="remora-modes", path="remora-modes.xml"))
    else:
        assert s.count("</PropertyList>") == 1, f
        s = s.replace("</PropertyList>", MODEL.format(what="fire retardant bag in the belly ring",
                                                     name="retardant-bag", path="retardant-bag.xml"))
    open(f, "w").write(s)
    print("hooked:", f)
PY
for f in "${HOOKED[@]}"; do xmllint --noout "$f" 2>/dev/null || python3 -c "import sys,xml.dom.minidom as m; m.parse(sys.argv[1])" "$f"; done
echo "installed; xml ok"
