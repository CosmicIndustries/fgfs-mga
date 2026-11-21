# Moves stale one-off FlightGear files out of ~/Downloads into ~/Downloads/fg-archive-<date>/.
# Nothing is deleted. Paste the whole block into a terminal on the board.
# To only look, change DRY=0 to DRY=1 on the next line.
DRY=0 bash <<'__FG_ARCHIVE__'
D="$HOME/Downloads"; A="$D/fg-archive-$(date +%Y%m%d)"
# Stale: old launcher copy (KCON + R44), AeonWave 3.12.4 build/triage scripts for a
# build-aeonwave-3124 folder that isn't on the board any more, one-off aircraft cleanups, a site log.
STALE="fgfs-mga-training fg_aeonwave_3124_compat_build.sh fg_aeonwave_3124_zeroxml_fix.sh fg_aeonwave_audio_triage.sh fg_aircraft_launcher_cleanup.py fg_aircraft_search_path_dedup.py fg_aircraft_sweeper.py"
moved=0
for n in $STALE cosmicindustries.github.io-*.log; do
  for f in "$D"/$n; do
    [[ -f "$f" ]] || continue
    if [[ "$DRY" == 1 ]]; then echo "would move: $f"; else mkdir -p "$A"; mv -n -- "$f" "$A/" && echo "moved: ${f##*/}"; fi
    moved=1
  done
done
(( moved )) || echo "Nothing to move."
echo
echo "Kept in ~/Downloads (still useful):"
echo "  patch_launcher_*.py   source patches; needed again if the FlightGear source is reset and rebuilt"
echo "  FG_INTEGRATION_README.md fg_telemetry_out.xml fg_weather_in.xml   weather/telemetry setup (fgfs-mga --telemetry / --weather-in)"
[[ "$DRY" == 1 || ! -d "$A" ]] || echo "To put them back:  mv -n \"$A\"/* \"$D\"/"
__FG_ARCHIVE__
