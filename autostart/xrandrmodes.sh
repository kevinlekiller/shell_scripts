#!/bin/bash

# Adds resolutions between 2688x1512 and 3712x2088 using xrandr

while [[ $(pgrep yakuake) == "" ]]; do
    sleep 10
done

DISPLAY=$(ls -U /tmp/.X11-unix | head -n1 | tr 'X' ':')
OUTPUT="HDMI-A-0"
xrandr --output "$OUTPUT" --set "scaling mode" "Full"

for i in $(seq 21 29 | sort -r); do
    MODELINE=$(cvt12 $(bc -l <<< 16*8*$i) $(bc -l <<< 9*8*$i) 60 -b | grep -Po \".* | sed 's/"//g' | sed "s/_60.00_rb2//")
    MODE=$(echo "$MODELINE" | cut -d\  -f1)
    #xrandr --delmode "$OUTPUT" "$MODE"
    #xrandr --rmmode "$MODE"
    #continue
    if [[ $(xrandr | grep "$MODE") != "" ]]; then
        continue
    fi
    xrandr --newmode $MODELINE
    xrandr --addmode "$OUTPUT" "$MODE"
done
