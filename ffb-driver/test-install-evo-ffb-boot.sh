#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
INSTALLER="$SCRIPT_DIR/install-evo-ffb-boot.sh"
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

mkdir -p "$ROOT/bin"
cat > "$ROOT/bin/modinfo" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == -F && "$2" == vermagic ]] || exit 2
printf '%s SMP mod_unload\n' "${TEST_VERMAGIC:-$FFB_KERNEL_RELEASE}"
EOF
cat > "$ROOT/bin/depmod" <<'EOF'
#!/usr/bin/env bash
printf 'depmod %s\n' "$*" >> "$FFB_TEST_LOG"
[[ "${FAIL_DEPMOD:-0}" != 1 ]]
EOF
chmod +x "$ROOT/bin/"*

export PATH="$ROOT/bin:$PATH"
export FFB_MODULE_ROOT="$ROOT/modules"
export FFB_CONFIG_ROOT="$ROOT/modules-load.d"
export FFB_STATE_ROOT="$ROOT/state"
export FFB_KO="$ROOT/test-module.ko"
export FFB_TEST_LOG="$ROOT/depmod.log"
printf 'new module image\n' > "$FFB_KO"
chmod 644 "$FFB_KO"

run_installer() {
  local kernel=$1 mode=${2:-install}
  FFB_KERNEL_RELEASE="$kernel" bash "$INSTALLER" "$mode"
}
expect_failure() {
  if "$@"; then fail 'command unexpectedly succeeded'; fi
}

# Existing regular module and symlink config must be backed up and restored.
mkdir -p "$FFB_MODULE_ROOT/kernel-a/extra" "$FFB_CONFIG_ROOT" "$ROOT/original"
printf 'old module image\n' > "$FFB_MODULE_ROOT/kernel-a/extra/hid_universal_pidff.ko"
printf 'old config target\n' > "$ROOT/original/old.conf"
ln -s "$ROOT/original/old.conf" "$FFB_CONFIG_ROOT/evo-ffb.conf"

run_installer kernel-a
cmp -s "$FFB_KO" "$FFB_MODULE_ROOT/kernel-a/extra/hid_universal_pidff.ko" || fail 'new module not installed'
[[ -f "$FFB_CONFIG_ROOT/evo-ffb.conf" && ! -L "$FFB_CONFIG_ROOT/evo-ffb.conf" ]] || fail 'config symlink was not replaced with a regular managed file'
grep -qx 'hid_universal_pidff' "$FFB_CONFIG_ROOT/evo-ffb.conf" || fail 'boot config contents are incorrect'

run_installer kernel-a
[[ "$(find "$FFB_STATE_ROOT" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ]] || fail 'idempotent install created another backup state'

run_installer kernel-a off
[[ "$(cat "$FFB_MODULE_ROOT/kernel-a/extra/hid_universal_pidff.ko")" == 'old module image' ]] || fail 'previous module was not restored'
[[ -L "$FFB_CONFIG_ROOT/evo-ffb.conf" ]] || fail 'previous config symlink was not restored'
[[ "$(readlink "$FFB_CONFIG_ROOT/evo-ffb.conf")" == "$ROOT/original/old.conf" ]] || fail 'previous config symlink target changed'
[[ "$(cat "$FFB_CONFIG_ROOT/evo-ffb.conf")" == 'old config target' ]] || fail 'previous config target content changed'
pass 'previous module and symlink config are restored; repeated install is idempotent'

# Reset the shared test config path so this next case truly starts with no config.
rm -f -- "$FFB_CONFIG_ROOT/evo-ffb.conf"

# When no prior paths existed, off removes only the paths this installer created.
run_installer kernel-b
[[ -f "$FFB_MODULE_ROOT/kernel-b/extra/hid_universal_pidff.ko" ]] || fail 'kernel-b module missing after install'
[[ -f "$FFB_CONFIG_ROOT/evo-ffb.conf" ]] || fail 'kernel-b boot config missing after install'
run_installer kernel-b off
[[ ! -e "$FFB_MODULE_ROOT/kernel-b/extra/hid_universal_pidff.ko" && ! -L "$FFB_MODULE_ROOT/kernel-b/extra/hid_universal_pidff.ko" ]] || fail 'new module was not removed on off'
[[ ! -e "$FFB_CONFIG_ROOT/evo-ffb.conf" && ! -L "$FFB_CONFIG_ROOT/evo-ffb.conf" ]] || fail 'new config was not removed on off'
pass 'off removes module/config only when they were absent before installation'

# Post-install modifications are never overwritten by off.
run_installer kernel-c
printf 'user changed this module\n' > "$FFB_MODULE_ROOT/kernel-c/extra/hid_universal_pidff.ko"
expect_failure run_installer kernel-c off
[[ "$(cat "$FFB_MODULE_ROOT/kernel-c/extra/hid_universal_pidff.ko")" == 'user changed this module' ]] || fail 'modified module was overwritten'
[[ "$(cat "$FFB_CONFIG_ROOT/evo-ffb.conf")" == 'hid_universal_pidff' ]] || fail 'boot config was unexpectedly changed'
pass 'off refuses to overwrite files modified after installation'

# With no state record, off must leave unrelated files alone.
mkdir -p "$FFB_MODULE_ROOT/kernel-d/extra"
printf 'unmanaged module\n' > "$FFB_MODULE_ROOT/kernel-d/extra/hid_universal_pidff.ko"
printf 'unmanaged config\n' > "$FFB_CONFIG_ROOT/evo-ffb.conf"
expect_failure run_installer kernel-d off
[[ "$(cat "$FFB_MODULE_ROOT/kernel-d/extra/hid_universal_pidff.ko")" == 'unmanaged module' ]] || fail 'unmanaged module was removed'
[[ "$(cat "$FFB_CONFIG_ROOT/evo-ffb.conf")" == 'unmanaged config' ]] || fail 'unmanaged config was removed'
pass 'off refuses to remove files without an install-state record'

# A vermagic mismatch is rejected before creating install state.
expect_failure env FFB_KERNEL_RELEASE=kernel-e TEST_VERMAGIC=wrong \
  bash "$INSTALLER" install
[[ ! -e "$FFB_STATE_ROOT/kernel-e" ]] || fail 'vermagic mismatch left install state'
pass 'vermagic mismatch is rejected before any installation'

# depmod failure rolls back the module and config replacements.
mkdir -p "$FFB_MODULE_ROOT/kernel-f/extra"
printf 'old ffb module\n' > "$FFB_MODULE_ROOT/kernel-f/extra/hid_universal_pidff.ko"
printf 'old ffb config\n' > "$FFB_CONFIG_ROOT/evo-ffb.conf"
expect_failure env FFB_KERNEL_RELEASE=kernel-f FAIL_DEPMOD=1 \
  bash "$INSTALLER" install
[[ "$(cat "$FFB_MODULE_ROOT/kernel-f/extra/hid_universal_pidff.ko")" == 'old ffb module' ]] || fail 'failed install did not restore module'
[[ "$(cat "$FFB_CONFIG_ROOT/evo-ffb.conf")" == 'old ffb config' ]] || fail 'failed install did not restore config'
[[ ! -e "$FFB_STATE_ROOT/kernel-f" ]] || fail 'failed install left unusable state'
pass 'depmod failure rolls back both replacements and clears partial state'

printf 'All FFB boot installer rollback tests passed.\n'
