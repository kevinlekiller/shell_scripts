#!/bin/bash

while [[ $(pgrep yakuake) == "" ]]; do
    sleep 10
done

if [[ $XDG_SESSION_TYPE == x11 ]]; then
    while true; do
        DISPLAY=$(ls -U /tmp/.X11-unix | head -n1 | tr 'X' ':') dispwin ~/.local/share/icc/#1\ 2021-04-06\ 16-32\ D6500\ Rec.\ 1886\ S\ XYZLUT+MTX.icc
        sleep 60
    done
else 
    ICC_ID="icc-e6986a5adb77e2ef3bcd551da1130454"
    DISP_ID="HDMI-A-1"
    while true; do
        if ! [[ $(colormgr device-get-default-profile $DISP_ID) =~ "$ICC_ID" ]]; then
            colormgr device-set-enabled "$DISP_ID" True
            colormgr device-make-profile-default "$DISP_ID" "$ICC_ID"
        fi
        sleep 60
    done
fi
