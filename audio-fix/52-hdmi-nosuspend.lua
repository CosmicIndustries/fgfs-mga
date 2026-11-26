-- Keep the board's HDMI and DP sound outputs open instead of closing them after 5 s of silence.
-- The ROCK 5B+ HDMI audio (RK3588 i2s + hdmi codec, vendor kernel 6.1.84) froze on 22 Nov 2026;
-- fewer close/reopen cycles means fewer chances for that. audio-watchdog resets one if it still does.
-- Added 26 Nov 2026 by Claude. Undo: ~/.local/bin/audio-fix-undo (or delete this file and
-- run: systemctl --user restart wireplumber).
table.insert(alsa_monitor.rules, {
  matches = {
    { { "node.name", "matches", "alsa_output.platform-hdmi*" } },
    { { "node.name", "matches", "alsa_output.platform-dp*" } },
  },
  apply_properties = {
    ["session.suspend-timeout-seconds"] = 0,
  },
})
