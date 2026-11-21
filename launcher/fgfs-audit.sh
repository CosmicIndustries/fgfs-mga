# Read-only FlightGear launcher audit. Paste this whole block into a terminal on the board.
bash <<'__FGFS_AUDIT__'
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
do_audit
__FGFS_AUDIT__
