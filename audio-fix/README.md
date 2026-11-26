# Board audio fix (26 Nov 2026)

What was wrong
1. Since 25 Nov the board boots kernel 6.1.84-9-rk2410 from the SD card's boot files, with the NVMe as the
   root system. The NVMe had no modules for that kernel, so the sound card drivers never loaded and no sound
   card existed. fix-sound-modules.sh (run once with sudo) copied them from the SD card and loaded the
   Rockchip card drivers (snd-soc-rockchip-hdmi, snd-soc-rockchip-multicodecs, snd-soc-es8316).
2. The default output was the virtual surround (KEMAR HRTF) filter, which stopped passing sound out after the
   cards came back. The default output is now HDMI 1 directly (WirePlumber saves it, so it survives reboots).
3. On 22 Nov HDMI 1's ALSA device froze while PipeWire still showed it RUNNING. audio-watchdog
   (systemd --user service) resets any running output whose device stops for two 5 s checks.
   52-hdmi-nosuspend.lua keeps HDMI/DP outputs open when idle (applies after a reboot or wireplumber restart).

Files on the board
- ~/.local/bin/audio-watchdog, ~/.config/systemd/user/audio-watchdog.service (journalctl --user -u audio-watchdog)
- ~/.config/wireplumber/main.lua.d/52-hdmi-nosuspend.lua
- ~/.local/share/audio-fix/: fix-sound-modules.sh, test-watchdog.sh, output-test.sh (1/2/3 beeps = HDMI 0/HDMI 1/jack)
- ~/.local/bin/fgfs-mga: OUTPUT_WAKE pre-flight check (23 Nov)

Undo
- ~/.local/bin/audio-fix-undo   (watchdog + HDMI rule)
- pactl set-default-sink effect_input.virtual-surround-kemar   (surround back as default)
- sudo rm -rf /lib/modules/6.1.84-9-rk2410   (driver copy; only if you stop booting that kernel)

Not tested / open
- Watchdog tested only on a fake card, not on a real freeze. Cause of the 22 Nov freeze unknown (no kernel log access).
- Surround filter output stalled; a PipeWire restart may fix it if headphones are used again (untested).
- Booting from the SD card is still how the board starts.
