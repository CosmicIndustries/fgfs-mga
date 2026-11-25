#!/usr/bin/env bash
# fgfs-mga: one-step install from a fresh clone. Run it from anywhere:  bash install.sh
#   bash install.sh                 the launcher (fgfs-mga), its tools, the launcher add-on, the ROCK 5B
#                                   profiles and a menu entry. Anything it replaces is backed up first.
#   bash install.sh --with-fgfs     also download the FlightGear 2024.1.7 MGA builds from this repo's
#                                   latest release (about 60 MB, checked against SHA256SUMS)
#   bash install.sh --with-fgdata   also download the FlightGear 2024.1.7 data (1.9 GB, official mirror),
#                                   if ~/.fgfs/fgdata_2024_1 isn't there yet
#   bash install.sh --all           both of the above
#   bash install.sh --dry-run       show what would happen, change nothing
#   bash install.sh --undo          put back the files the last run of this script replaced
# Needs no sudo. If system packages are missing, it prints the one apt line to install them.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="https://github.com/CosmicIndustries/fgfs-mga"
FGDATA_URL="https://sourceforge.net/projects/flightgear/files/release-2024.1/FlightGear-2024.1.7-data.txz/download"
FGDATA_SHA256="46e831109911a067f34b7b14d01f8a2fce8a783c84738e8e203760ceb3406ac4"

DRY=0; UNDO=0; WITH_FGFS=0; WITH_FGDATA=0; PASS=()
for a in "$@"; do
  case "$a" in
    --dry-run|-n) DRY=1; PASS+=(--dry-run) ;;
    --with-fgfs) WITH_FGFS=1 ;;
    --with-fgdata) WITH_FGDATA=1 ;;
    --all) WITH_FGFS=1; WITH_FGDATA=1 ;;
    --undo) UNDO=1 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a (try --help)"; exit 2 ;;
  esac
done

SHARE="$HOME/.local/share/fgfs-mga"
TOOLS="$SHARE/tools"
CONF="$HOME/.config/fgfs-mga/config"
BK="$SHARE/setup-backup-$(date +%Y%m%d-%H%M%S)"
say() { printf '%s\n' "$*"; }
warn() { printf 'NOTE: %s\n' "$*"; }

# ---------------- undo ----------------
if (( UNDO )); then
  last="$(find "$SHARE" -maxdepth 2 -path '*/setup-backup-*/manifest' 2>/dev/null | sort | tail -n 1)"; last="${last%/manifest}"
  [[ -n "$last" && -f "$last/manifest" ]] || { say "Nothing to undo (no setup-backup-* in $SHARE)."; exit 1; }
  say "Undoing $last"
  while IFS=$'\t' read -r kind dest saved; do
    case "$kind" in
      replaced) (( DRY )) || cp -p -- "$saved" "$dest"; say "  restored $dest" ;;
      created)  (( DRY )) || { mkdir -p "$last/created"; mv -f -- "$dest" "$last/created/" 2>/dev/null; }; say "  removed $dest (kept in $last/created/)" ;;
    esac
  done < <(tac "$last/manifest")
  (( DRY )) || mv -- "$last" "${last/setup-backup-/setup-undone-}"
  say "Done. The launcher itself has its own undo:  bash $HERE/launcher/install-fgfs-mga.sh --undo"
  exit 0
fi

(( DRY )) && say "DRY RUN: nothing will be changed."
[[ "$(uname -m)" == aarch64 ]] || warn "this is $(uname -m); the FlightGear builds here are for aarch64 (ROCK 5B / RK3588). The scripts still install."

# place SRC DEST [MODE]: copy if different, back up what it replaces, note it for --undo
place() {
  local src="$1" dest="$2" mode="${3:-644}"
  if [[ -f "$dest" ]] && cmp -s -- "$src" "$dest"; then return 0; fi
  if (( DRY )); then say "  [dry-run] would write $dest"; return 0; fi
  mkdir -p "$(dirname "$dest")" "$BK" || {
    say "ERROR: could not create the destination or backup directory for $dest" >&2
    return 1
  }
  if [[ -f "$dest" ]]; then
    local saved="$BK/files/${dest#"$HOME"/}"
    mkdir -p "$(dirname "$saved")" || {
      say "ERROR: could not create backup directory for $dest" >&2
      return 1
    }
    cp -p -- "$dest" "$saved" || {
      say "ERROR: could not back up existing file $dest" >&2
      return 1
    }
    printf 'replaced\t%s\t%s\n' "$dest" "$saved" >> "$BK/manifest" || {
      say "ERROR: could not record backup for $dest" >&2
      return 1
    }
    say "  updated $dest (old copy in $BK)"
  else
    printf 'created\t%s\t-\n' "$dest" >> "$BK/manifest" || {
      say "ERROR: could not record new file $dest" >&2
      return 1
    }
    say "  added $dest"
  fi
  install -m "$mode" -- "$src" "$dest" || {
    say "ERROR: could not install $src to $dest" >&2
    return 1
  }
}

place_or_die() {
  place "$@" || exit 1
}

# ---------------- 1. the launcher (its own installer: backups, shims, menu entry) ----------------
say "== fgfs-mga launcher"
if ( set -o pipefail; bash "$HERE/launcher/install-fgfs-mga.sh" "${PASS[@]}" | sed 's/^/  /' ); then
  :
else
  launcher_status=$?
  say "ERROR: launcher installation failed (exit $launcher_status); remaining files were not installed." >&2
  exit "$launcher_status"
fi

# ---------------- 2. tools, launcher add-on, profiles ----------------
say "== tools (in $TOOLS)"
for f in "$HERE"/launcher/tools/*; do
  case "$f" in *.c) continue ;; esac
  place_or_die "$f" "$TOOLS/${f##*/}" 755
done
for f in fgfs-mga-arcgis fgfs-mga-terrasync; do place_or_die "$HERE/launcher/src/$f" "$TOOLS/$f" 755; done
place_or_die "$HERE/launcher/tools/aeonwave-output-test.c" "$HOME/.local/share/aeonwave/aeonwave-output-test.c"

say "== launcher add-on (start state, crash reset, auto mixture)"
for f in "$HERE"/launcher/addons/mga-launcher-extras/*; do
  place_or_die "$f" "$HOME/.fgfs/fgfs-mga-addons/mga-launcher-extras/${f##*/}"
done

say "== in-flight checklist add-on (Ctrl-K in flight)"
while IFS= read -r f; do
  sub="${f#"$HERE"/launcher/addons/mga-checklist/}"
  place_or_die "$f" "$HOME/.fgfs/FlightGear-2024.1-Addons-MGA/mga-checklist/$sub"
done < <(find "$HERE/launcher/addons/mga-checklist" -type f ! -path '*/tools/*' ! -name '*.pyc' | sort)

say "== ROCK 5B performance profiles (yours are kept if you have them)"
for f in "$HERE"/launcher/config/flightgear-rock5b/*; do
  d="$HOME/.config/flightgear-rock5b/${f##*/}"
  [[ -f "$d" ]] && continue
  place_or_die "$f" "$d"
done

# ---------------- 3. FlightGear builds from the release (optional) ----------------
own_new="$HOME/builds/flightgear-2024.1.7/build/src/Main/fgfs"
rel="$SHARE/release"
if (( WITH_FGFS )); then
  say "== FlightGear 2024.1.7 MGA builds (release)"
  if (( DRY )); then say "  [dry-run] would download fgfs-2024.1.7-openal-aarch64, fgfs-2024.1.7-aeonwave-aarch64 and libaax.so.4.0.0 to $rel"
  else
    tmp="$(mktemp -d)"; ok=1
    for a in SHA256SUMS fgfs-2024.1.7-openal-aarch64 fgfs-2024.1.7-aeonwave-aarch64 libaax.so.4.0.0; do
      curl -fL --retry 5 --retry-all-errors --progress-bar -o "$tmp/$a" "$REPO_URL/releases/latest/download/$a" || { say "  download failed: $a"; ok=0; break; }
    done
    if (( ok )) && ( cd "$tmp" && sha256sum -c --quiet SHA256SUMS ); then
      mkdir -p "$rel/bin" "$rel/lib" "$BK"
      for a in fgfs-2024.1.7-openal-aarch64 fgfs-2024.1.7-aeonwave-aarch64; do
        [[ -f "$rel/bin/$a" ]] || printf 'created\t%s\t-\n' "$rel/bin/$a" >> "$BK/manifest"
        install -m 755 "$tmp/$a" "$rel/bin/$a"
      done
      [[ -f "$rel/lib/libaax.so.4.0.0" ]] || printf 'created\t%s\t-\n' "$rel/lib/libaax.so.4.0.0" >> "$BK/manifest"
      install -m 644 "$tmp/libaax.so.4.0.0" "$rel/lib/libaax.so.4.0.0"
      ln -sf libaax.so.4.0.0 "$rel/lib/libaax.so.4"
      say "  checked and installed in $rel"
      if [[ -x "$own_new" ]]; then
        say "  you have your own 2024.1.7 build ($own_new); fgfs-mga keeps using it"
      elif ! grep -q 'install.sh --with-fgfs' "$CONF" 2>/dev/null; then
        if [[ -f "$CONF" ]]; then
          saved="$BK/files/.config/fgfs-mga/config"; mkdir -p "$(dirname "$saved")"; cp -p -- "$CONF" "$saved"
          printf 'replaced\t%s\t%s\n' "$CONF" "$saved" >> "$BK/manifest"
        else mkdir -p "$(dirname "$CONF")"; printf 'created\t%s\t-\n' "$CONF" >> "$BK/manifest"
        fi
        cat >> "$CONF" <<'EOF'

# added by install.sh --with-fgfs: the release builds (delete these lines to use your own builds)
FGFS_BIN_NEW="$HOME/.local/share/fgfs-mga/release/bin/fgfs-2024.1.7-openal-aarch64"
FGFS_BIN_AEONWAVE_NEW="$HOME/.local/share/fgfs-mga/release/bin/fgfs-2024.1.7-aeonwave-aarch64"
AEONWAVE_LIBS="$HOME/.local/share/fgfs-mga/release/lib $AEONWAVE_LIBS"
EOF
        say "  pointed fgfs-mga at them in $CONF (old copy in $BK)"
      fi
    else
      say "  not installed: a download failed or a checksum didn't match"
    fi
    rm -rf -- "$tmp"
  fi
fi

# ---------------- 4. FlightGear data (optional) ----------------
fgdata="$HOME/.fgfs/fgdata_2024_1"
if (( WITH_FGDATA )); then
  say "== FlightGear 2024.1.7 data"
  if [[ -f "$fgdata/version" && ! -L "$fgdata/version" ]]; then
    say "  already there: $fgdata ($(cat "$fgdata/version"))"
  elif [[ -e "$fgdata" || -L "$fgdata" ]]; then
    say "  not installed: $fgdata already exists but is not a recognized versioned FGData tree; it was left untouched."
  elif (( DRY )); then
    say "  [dry-run] would download 1.9 GB, verify SHA-256, and safely unpack it to $fgdata (about 3.5 GB)"
  else
    free_kb="$(df -Pk "$HOME" | awk 'NR==2{print $4}')"
    if (( free_kb < 6000000 )); then say "  not enough space: needs about 6 GB free in $HOME"
    else
      mkdir -p "$HOME/.cache/fgfs-mga" "$HOME/.fgfs"
      arc="$HOME/.cache/fgfs-mga/FlightGear-2024.1.7-data.txz"
      say "  downloading (resumes if stopped): $arc"
      if curl -fL --retry 8 --retry-all-errors --progress-bar -C - -o "$arc" "$FGDATA_URL"; then
        if bash "$HERE/flightgear-2024.1.7/install-fgdata-safe.sh" "$arc" "$fgdata" "$FGDATA_SHA256"; then
          rm -f -- "$arc"
          if mkdir -p "$BK" && printf 'created\t%s\t-\n' "$fgdata" >> "$BK/manifest"; then
            say "  unpacked: $fgdata ($(cat "$fgdata/version"))"
          else
            say "  ERROR: FGData was installed at $fgdata but the undo manifest could not be recorded; do not remove it until it is backed up." >&2
          fi
        else
          fgdata_status=$?
          if (( fgdata_status == 65 )); then
            rm -f -- "$arc"
            say "  rejected and removed the downloaded archive because its SHA-256 did not match; run again to download a fresh copy"
          else
            say "  FGData install failed (exit $fgdata_status); archive retained at $arc and existing data was left untouched"
          fi
        fi
      else say "  download stopped; run this again to resume it"
      fi
    fi
  fi
fi

# ---------------- 5. what's still missing ----------------
say "== check"
missing_pk=""
pick=""; for b in "$own_new" "$rel/bin/fgfs-2024.1.7-openal-aarch64"; do [[ -x "$b" ]] && { pick="$b"; break; }; done
if [[ -n "$pick" ]]; then
  miss="$(ldd "$pick" 2>/dev/null | awk '/not found/{print $1}' | tr '\n' ' ')"
  if [[ -n "$miss" ]]; then say "  FlightGear needs these libraries: $miss"; missing_pk="libs"
  else say "  FlightGear build: $pick (all libraries found)"; fi
else
  say "  no FlightGear 2024.1.7 build yet: run  bash $HERE/install.sh --with-fgfs"
fi
[[ -f "$fgdata/version" ]] && say "  FlightGear data: $fgdata" || say "  no FlightGear data yet: run  bash $HERE/install.sh --with-fgdata"
python3 -c 'import evdev' 2>/dev/null || { say "  python3-evdev is missing (sticks, controls window, force feedback)"; missing_pk="py"; }
python3 -c 'import PyQt5' 2>/dev/null || { say "  python3-pyqt5 is missing (the Qt controls window)"; missing_pk="py"; }
if [[ -n "$missing_pk" ]]; then
  say ""
  say "  Install the system packages once (Debian 12 / Armbian bookworm):"
  say "  sudo apt install libopenscenegraph161 libplib1 libopenal1 libqt6core6 libqt6gui6 libqt6widgets6 libqt6network6 libqt6opengl6 libqt6qml6 libqt6quick6 libqt6dbus6 libqt6svg6 qt6-qpa-plugins qml6-module-qtqml qml6-module-qtqml-models qml6-module-qtqml-workerscript qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-templates qml6-module-qtquick-window libavcodec59 libavformat59 libswscale6 libcurl4 libzmq5 python3-evdev python3-pyqt5 xz-utils curl"
fi

rmdir "$BK" 2>/dev/null || true   # nothing was replaced or added this time
say ""
if (( DRY )); then say "Dry run done. Run again without --dry-run to apply."
else
  say "Done. Start FlightGear from the menu (FlightGear MGA), or run:  fgfs-mga --launcher"
  [[ -f "$BK/manifest" ]] && say "To take this back out:  bash $HERE/install.sh --undo   (anything it replaced is saved in $BK)"
fi
exit 0
