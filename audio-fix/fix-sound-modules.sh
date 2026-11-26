#!/usr/bin/env bash
# Run once with sudo:  sudo bash ~/.local/share/audio-fix/fix-sound-modules.sh
# Why: the board now boots kernel 6.1.84-9-rk2410 from the SD card's boot files, but the root system
# is the NVMe, which has no modules for that kernel. The sound card drivers are modules, so no sound
# card appears and nothing can play. This copies that kernel's modules from the SD card's system
# (same kernel, installed there on 25 Nov 2026) onto the NVMe and loads the sound drivers.
# Undo: sudo rm -rf /lib/modules/6.1.84-9-rk2410   (then reboot)
set -euo pipefail
K=6.1.84-9-rk2410
SRC=/media/radxa/rootfs/lib/modules/$K
[[ $EUID -eq 0 ]] || { echo "Run it with sudo."; exit 1; }
[[ "$(uname -r)" == "$K" ]] || { echo "Running kernel is $(uname -r), not $K. Nothing changed."; exit 1; }
[[ -d "$SRC/kernel/sound" ]] || { echo "SD card modules not found at $SRC (is the SD card mounted?). Nothing changed."; exit 1; }
if [[ -e /lib/modules/$K ]]; then
  echo "/lib/modules/$K already exists, leaving it as it is."
else
  cp -a "$SRC" /lib/modules/
  echo "Copied $SRC to /lib/modules/$K"
fi
depmod -a "$K"
# The board's sound nodes use Rockchip's own card drivers (device tree: "rockchip,hdmi" for HDMI 0/1,
# DP and HDMI-in, "rockchip,multicodecs-card" for the ES8316 headphone jack), not simple-card.
modprobe -a snd-soc-rockchip-hdmi snd-soc-rockchip-multicodecs snd-soc-es8316 || echo "warning: a sound driver did not load"
sleep 3
echo "Sound cards now:"
cat /proc/asound/cards
