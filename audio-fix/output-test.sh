#!/usr/bin/env bash
# Plays a beep pattern straight to each sound output in turn, 3 rounds:
# 1 beep = HDMI 0, 2 beeps = HDMI 1, 3 beeps = board headphone jack (ES8316).
export XDG_RUNTIME_DIR=/run/user/$(id -u)
beeps() { python3 -I -c "
import struct,math,sys
r=48000; n=int(sys.argv[1]); out=bytearray()
for b in range(n):
  for i in range(int(r*0.35)):
    e=min(1,i/480,(r*0.35-i)/480); v=int(16000*e*math.sin(2*math.pi*660*i/r)); out+=struct.pack('<hh',v,v)
  out+=bytes(4*int(r*0.25))
out+=bytes(4*int(r*0.5))
sys.stdout.buffer.write(out)" "$1"; }
for round in 1 2 3; do
  beeps 1 | pacat -d alsa_output.platform-hdmi0-sound.pro-output-0 --format=s16le --channels=2 --rate=48000 --client-name=claude-output-test
  sleep 2
  beeps 2 | pacat -d alsa_output.platform-hdmi1-sound.pro-output-0 --format=s16le --channels=2 --rate=48000 --client-name=claude-output-test
  sleep 2
  beeps 3 | pacat -d alsa_output.platform-es8316-sound.stereo-fallback --format=s16le --channels=2 --rate=48000 --client-name=claude-output-test
  sleep 4
done
echo done
