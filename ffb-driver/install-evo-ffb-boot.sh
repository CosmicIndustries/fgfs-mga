#!/usr/bin/env bash
# Install the built Cyborg v2 module for the running kernel and load it at boot.
#   sudo bash install-evo-ffb-boot.sh          install
#   sudo bash install-evo-ffb-boot.sh off      restore previous module/config or remove this install
#
# The first install preserves any existing module and modules-load config under
# /var/lib/fgfs-mga-ffb/<kernel-release>. The off mode only acts on files that
# still match this install's recorded copies; modified files are left untouched.
set -Eeuo pipefail
umask 077

[[ "$(id -u)" == 0 ]] || { echo "run it with sudo" >&2; exit 1; }

MODE="${1:-install}"
case "$MODE" in
  install|off) ;;
  *)
    echo "Usage: sudo bash $0 [install|off]" >&2
    exit 2
    ;;
esac

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_RELEASE="${FFB_KERNEL_RELEASE:-$(uname -r)}"
MODULE_ROOT="${FFB_MODULE_ROOT:-/lib/modules}"
CONFIG_ROOT="${FFB_CONFIG_ROOT:-/etc/modules-load.d}"
STATE_ROOT="${FFB_STATE_ROOT:-/var/lib/fgfs-mga-ffb}"
KO="${FFB_KO:-$SCRIPT_DIR/evo-cyborg-v2/hid_universal_pidff.ko}"
DEST="$MODULE_ROOT/$KERNEL_RELEASE/extra/hid_universal_pidff.ko"
CONF="$CONFIG_ROOT/evo-ffb.conf"
STATE_DIR="$STATE_ROOT/$KERNEL_RELEASE"

restore_prior() {
  local path=$1 backup=$2 marker=$3 tmp
  if [[ -f "$marker" ]]; then
    if [[ -e "$backup" || -L "$backup" ]]; then
      tmp="$(mktemp "$(dirname "$path")/.ffb-restore.XXXXXXXX")"
      rm -f -- "$tmp"
      cp -a -- "$backup" "$tmp"
      mv -fT -- "$tmp" "$path"
    else
      echo "ERROR: recorded backup is missing: $backup" >&2
      return 1
    fi
  else
    rm -f -- "$path"
  fi
}

if [[ "$MODE" == off ]]; then
  [[ -d "$STATE_DIR" && ! -L "$STATE_DIR" ]] || {
    echo "ERROR: no install-state record for kernel $KERNEL_RELEASE; refusing to delete module/config files that may belong to another package." >&2
    exit 1
  }
  [[ -f "$STATE_DIR/installed-module.ko" && -f "$STATE_DIR/installed-conf" ]] || {
    echo "ERROR: install-state record is incomplete: $STATE_DIR" >&2
    exit 1
  }

  if [[ -f "$DEST" && ! -L "$DEST" ]] && cmp -s -- "$DEST" "$STATE_DIR/installed-module.ko"; then
    :
  else
    echo "ERROR: installed module has changed since this script installed it; leaving module, config and backups untouched." >&2
    exit 1
  fi
  if [[ -f "$CONF" && ! -L "$CONF" ]] && cmp -s -- "$CONF" "$STATE_DIR/installed-conf"; then
    :
  else
    echo "ERROR: boot config has changed since this script installed it; leaving module, config and backups untouched." >&2
    exit 1
  fi

  if grep -q '^hid_universal_pidff ' /proc/modules 2>/dev/null; then
    command -v rmmod >/dev/null 2>&1 || { echo "ERROR: rmmod is required to unload the module" >&2; exit 1; }
    rmmod hid_universal_pidff || { echo "ERROR: module is in use; close its users and retry off" >&2; exit 1; }
  fi

  mkdir -p -- "$(dirname "$DEST")" "$CONFIG_ROOT"
  restore_prior "$DEST" "$STATE_DIR/prior-module" "$STATE_DIR/module-was-present"
  restore_prior "$CONF" "$STATE_DIR/prior-conf" "$STATE_DIR/conf-was-present"
  depmod -a
  restored="$STATE_ROOT/restored-$KERNEL_RELEASE-$(date +%Y%m%d-%H%M%S)"
  mv -- "$STATE_DIR" "$restored"
  echo "Restored the pre-install module/config state. Backup retained at: $restored"
  exit 0
fi

[[ -s "$KO" && ! -L "$KO" ]] || { echo "missing regular module $KO; run build-evo-cyborg-v2.sh first" >&2; exit 1; }
command -v modinfo >/dev/null 2>&1 || { echo "modinfo is required (install kmod)" >&2; exit 1; }
command -v depmod >/dev/null 2>&1 || { echo "depmod is required" >&2; exit 1; }
command -v install >/dev/null 2>&1 || { echo "install is required" >&2; exit 1; }

vermagic="$(modinfo -F vermagic "$KO")"
[[ "${vermagic%% *}" == "$KERNEL_RELEASE" ]] || {
  echo "module is for $vermagic, kernel is $KERNEL_RELEASE: rebuild first" >&2
  exit 1
}

if [[ -d "$STATE_DIR" && ! -L "$STATE_DIR" ]]; then
  if [[ -f "$DEST" && ! -L "$DEST" && -f "$CONF" && ! -L "$CONF" ]] &&
     cmp -s -- "$DEST" "$STATE_DIR/installed-module.ko" &&
     cmp -s -- "$CONF" "$STATE_DIR/installed-conf"; then
    echo "Already installed for $KERNEL_RELEASE; prior files are backed up at $STATE_DIR"
    exit 0
  fi
  echo "ERROR: an install-state directory already exists but does not match the installed files: $STATE_DIR" >&2
  echo "Run 'sudo bash $0 off' after reviewing the paths, or inspect the backup manually." >&2
  exit 1
fi
[[ ! -e "$STATE_DIR" && ! -L "$STATE_DIR" ]] || {
  echo "ERROR: install-state path exists and is not a real directory: $STATE_DIR" >&2
  exit 1
}

mkdir -p -- "$MODULE_ROOT/$KERNEL_RELEASE/extra" "$CONFIG_ROOT" "$STATE_ROOT"
mkdir -- "$STATE_DIR"

# Record the previous state before touching either destination.
for pair in "module|$DEST" "conf|$CONF"; do
  name=${pair%%|*}
  path=${pair#*|}
  if [[ -d "$path" && ! -L "$path" ]]; then
    echo "ERROR: destination is a directory; refusing to replace it: $path" >&2
    rm -rf -- "$STATE_DIR"
    exit 1
  fi
  if [[ -e "$path" || -L "$path" ]]; then
    cp -a -- "$path" "$STATE_DIR/prior-$name"
    : > "$STATE_DIR/${name}-was-present"
  fi
done

cp -- "$KO" "$STATE_DIR/installed-module.ko"
chmod 600 "$STATE_DIR/installed-module.ko"
printf '%s\n' hid_universal_pidff > "$STATE_DIR/installed-conf"
chmod 600 "$STATE_DIR/installed-conf"

module_tmp="$(mktemp "$MODULE_ROOT/$KERNEL_RELEASE/extra/.hid_universal_pidff.XXXXXXXX")"
conf_tmp="$(mktemp "$CONFIG_ROOT/.evo-ffb.conf.XXXXXXXX")"
cleanup_temps() {
  rm -f -- "${module_tmp:-}" "${conf_tmp:-}"
}
trap cleanup_temps EXIT

install -m 644 -- "$KO" "$module_tmp"
mv -fT -- "$module_tmp" "$DEST"
module_tmp=''
printf '%s\n' hid_universal_pidff > "$conf_tmp"
chmod 644 "$conf_tmp"
mv -fT -- "$conf_tmp" "$CONF"
conf_tmp=''

if ! depmod -a; then
  echo "ERROR: depmod failed; restoring the previous module/config state." >&2
  restore_prior "$DEST" "$STATE_DIR/prior-module" "$STATE_DIR/module-was-present" || true
  restore_prior "$CONF" "$STATE_DIR/prior-conf" "$STATE_DIR/conf-was-present" || true
  depmod -a || true
  rm -rf -- "$STATE_DIR"
  exit 1
fi

echo "Installed: $DEST and $CONF"
echo "Previous files, if any, are backed up at: $STATE_DIR"
echo "Undo: sudo bash $0 off"
