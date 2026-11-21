#!/usr/bin/env bash
# Builds the two paste-able files from src/:
#   install-fgfs-mga.sh  installer with the launcher embedded
#   fgfs-audit.sh        read-only audit block (the same code as `fgfs-mga audit`)
set -euo pipefail
cd "$(dirname "$0")"

python3 - <<'PY'
src = open('src/fgfs-mga').read()
body = open('src/install-body.sh').read()
ctl = open('src/fgfs-mga-controls').read()
ffb = open('src/fgfs-mga-ffb').read()
ctlqt = open('src/fgfs-mga-controls-qt').read()
assert '__FGFS_MGA_CONTROLS_QT__' not in ctlqt and '@@' not in ctlqt
ffbxml = open('src/fgfs-mga-ffb.xml').read()
assert '__FGFS_MGA_FFB__' not in ffb and '__FGFS_MGA_FFB_XML__' not in ffbxml and '@@' not in ffb + ffbxml
assert '__FGFS_MGA_LAUNCHER__' not in src and '__FGFS_MGA_INSTALL__' not in src + body + ctl
assert '__FGFS_MGA_CONTROLS__' not in ctl and '@@' not in src + ctl
body = body.replace('#!/usr/bin/env bash\n', '', 1).replace('@@LAUNCHER@@', src.rstrip('\n')).replace('@@CONTROLS@@', ctl.rstrip('\n')).replace('@@CONTROLSQT@@', ctlqt.rstrip('\n')).replace('@@FFB@@', ffb.rstrip('\n')).replace('@@FFBXML@@', ffbxml.rstrip('\n'))
head = ('# fgfs-mga installer: one FlightGear launcher for the MGA setup on the ROCK 5B+.\n'
        '# Paste this whole block into a terminal on the board, or save it and run:\n'
        '#   bash install-fgfs-mga.sh --dry-run     (look first)\n'
        '#   bash install-fgfs-mga.sh               (install)\n'
        '#   bash install-fgfs-mga.sh --undo        (put the old launchers back)\n'
        '# To dry-run a paste, change the next line to:  bash -s -- --dry-run "$@" <<\'__FGFS_MGA_INSTALL__\'\n')
out = head + 'bash -s -- "$@" <<\'__FGFS_MGA_INSTALL__\'\n' + body.rstrip('\n') + '\n__FGFS_MGA_INSTALL__\n'
assert '\t' not in out, 'tabs break pasting'
open('install-fgfs-mga.sh', 'w').write(out)

a = src.index('# AUDIT-BEGIN\n'); b = src.index('# AUDIT-END\n')
fn = src[a + len('# AUDIT-BEGIN\n'):b]
audit = ('# Read-only FlightGear launcher audit. Paste this whole block into a terminal on the board.\n'
         "bash <<'__FGFS_AUDIT__'\n" + fn + 'do_audit\n__FGFS_AUDIT__\n')
assert '\t' not in audit
open('fgfs-audit.sh', 'w').write(audit)
PY
chmod 755 install-fgfs-mga.sh fgfs-audit.sh src/fgfs-mga src/fgfs-mga-controls src/fgfs-mga-controls-qt
bash -n install-fgfs-mga.sh && bash -n fgfs-audit.sh
echo "built install-fgfs-mga.sh ($(wc -l < install-fgfs-mga.sh) lines) and fgfs-audit.sh ($(wc -l < fgfs-audit.sh) lines)"
