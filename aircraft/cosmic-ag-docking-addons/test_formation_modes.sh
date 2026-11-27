#!/usr/bin/env bash
# Offline test of Nasal/cosmic_modes.nas (formation modes) flying with the real
# Nasal/cosmic_formation.nas, in the standalone `nasal` interpreter, using the
# stubs from Scripts/test_drone_physics.sh.
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
R="$HOME/.fgfs/fgdata_2024_1"
T=$(mktemp /tmp/cosmic-modes-test.XXXX.nas)
# the stub preamble: the heredoc in test_drone_physics.sh
sed -n '/^cat > "\$T" <<.EOF.$/,/^EOF$/p' "$D/test_drone_physics.sh" | sed '1d;$d' > "$T"
cat >> "$T" <<'EOF2'
var settimer = func(f, t) {};
var maketimer = func(t, f) { return { start: func {}, stop: func {} }; };
if (!contains(math, "mod")) math.mod = func(a, b) { return a - b * math.floor(a / b); };
EOF2
cat "$R/Nasal/cosmic_formation.nas" >> "$T"
{ echo "var cosmic_modes = (func {"; cat "${MODES:-$R/Nasal/cosmic_modes.nas}"; echo "return caller(0)[0]; })();"; } >> "$T"
cat "$D/test_modes_run.nas" >> "$T"
nasal "$T"
rm -f "$T"
