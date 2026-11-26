#!/usr/bin/env bash
# Tests audio-watchdog with a fake sound card and a fake pactl. Touches no real sound output.
T=$(mktemp -d); W=$HOME/.local/bin/audio-watchdog
mkdir -p $T/asound/card9/pcm0p/sub0 $T/bin; S=$T/asound/card9/pcm0p/sub0/status
cat > $T/bin/pactl <<EOF
#!/usr/bin/env bash
if [[ "\$1" == list ]]; then printf 'Sink #5\n\tState: RUNNING\n\tName: alsa_output.fake-hdmi.pro-output-0\n\t\talsa.card = "9"\n\t\talsa.device = "0"\nSink #6\n\tState: SUSPENDED\n\tName: alsa_output.other\n\t\talsa.card = "8"\n\t\talsa.device = "0"\n'
else echo "\$*" >> $T/calls; fi
EOF
cat > $T/bin/fsleep <<EOF
#!/usr/bin/env bash
if [[ -f $T/flowing ]]; then p=\$(awk '/hw_ptr/{print \$3}' $S); printf 'state: RUNNING\nhw_ptr      : %d\n' \$((p+4800)) > $S; fi
EOF
chmod +x $T/bin/*
run() { : > $T/calls; AW_ASOUND=$T/asound AW_PACTL=$T/bin/pactl AW_SLEEP=$T/bin/fsleep AW_INTERVAL=0 AW_ITER=$1 bash $W >/dev/null; wc -l < $T/calls; }
touch $T/flowing; printf 'state: RUNNING\nhw_ptr      : 1000\n' > $S; echo "healthy playback, 6 checks: resets=$(( $(run 6) / 2 )) (want 0)"
rm -f $T/flowing; printf 'state: SETUP\nhw_ptr      : 9484792\n' > $S; echo "Nov 22 frozen state, 6 checks: resets=$(( $(run 6) / 2 )) (want 1, then cooldown)"
printf 'state: RUNNING\nhw_ptr      : 5000\n' > $S; echo "running but pointer stuck, 3 checks: resets=$(( $(run 3) / 2 )) (want 1)"
printf 'state: RUNNING\nhw_ptr      : 5000\n' > $S; echo "pointer stuck, only 2 checks: resets=$(( $(run 2) / 2 )) (want 0, needs 2 strikes)"
rm -rf $T
