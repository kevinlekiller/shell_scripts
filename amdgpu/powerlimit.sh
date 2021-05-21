#!/bin/bash

if [[ ! $1 =~ ^[0-9]*$ ]] || [[ $1 -lt 100 ]] || [[ $1 -gt 330 ]]; then
        echo "Wrong power limit: $1 ; min 100, max 330"
        exit 1
fi
POWERLIMIT=$1
POWERLIMIT=$((POWERLIMIT * 1000000))
GPUID=0
CARDWD="/sys/class/drm/card$GPUID/device"
HWMON="$(find $CARDWD/hwmon/ -name hwmon[0-9] -type d | head -n 1)"
echo "Limit (currently)       : $(($(cat $HWMON/power1_cap)/1000000)) watts"
sudo bash -c "echo $POWERLIMIT > $HWMON/power1_cap"
echo "Limit (new)             : $(($(cat $HWMON/power1_cap)/1000000)) watts"
