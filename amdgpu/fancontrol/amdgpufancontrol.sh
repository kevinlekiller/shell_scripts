# cat /usr/local/sbin/amdgpufancontrol.sh
#!/bin/bash

<<LICENSE
	Copyright (C) 2018-2019  kevinlekiller

	This program is free software; you can redistribute it and/or
	modify it under the terms of the GNU General Public License
	as published by the Free Software Foundation; either version 2
	of the License, or (at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program; if not, write to the Free Software
	Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
	https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html
LICENSE

if [[ ! $(lspci | grep VGA.*AMD) ]]; then
    while [[ 1 ]]; do
        sleep 99999
    done
fi

# Which GPU to use.
GPUID=${GPUID:-0}

# How many seconds to wait before checking temps / setting fan speeds. Lower values mean higher CPU usage. Leave empty to disable fan control.
INTERVAL=4

# Show the temp to speed map then exit. Leave empty to disable.
SHOWMAP=${SHOWMAP:-}

# Set fan speed to this speed if GPU temperature under TEMP[0]
MINSPEED=400

# What fan speed to set at what temperature, for example set the fan speed at 25% when GPU temp is 50 degrees.
# All other values are calculated on the fly, pass the SHOWMAP=true environment variable to show the calculated values.
# These values work for a reference Vega 64 with a Morpheus 2 cooler and Noctua NF-F12 PWM fans.
TEMP[0]=40
SPEED[0]=500

TEMP[1]=47
SPEED[1]=1700

TEMP[2]=53
SPEED[2]=2900

TEMP[3]=60
SPEED[3]=4100

# This is in case there's some kind of logic flaw in the while loop. Can be left as is.
SAFESPEED=${SPEED[1]}

CARDWD="/sys/class/drm/card$GPUID/device"
if [[ $(grep 0x1002 $CARDWD/vendor 2> /dev/null) == "" ]]; then
    echo "AMD GPU not found, exiting."
    exit 1
fi

HWMON="$(find $CARDWD/hwmon/ -name hwmon[0-9] -type d | head -n 1)"
if [[ ! -d $HWMON ]]; then
    echo "Unable to find hwmon directory for the GPU, fan control and power control requires it, exiting."
    exit 1
fi

declare -A PAIRS
for PAIR in 0:1 1:2 2:3; do
    LOW=$(echo "$PAIR" | cut -d: -f1)
    HIGH=$(echo "$PAIR" | cut -d: -f2)
    TDIFF0=$(bc -l <<< "$((${SPEED[$HIGH]} - ${SPEED[$LOW]})) / $((${TEMP[$HIGH]} - ${TEMP[$LOW]}))")
    CURSPEED=${SPEED[$LOW]}
    for i in $(seq ${TEMP[$LOW]} ${TEMP[$HIGH]}); do
        RNDSPEED=$(echo $CURSPEED | awk '{print int($1+0.5)}')
        if [[ $RNDSPEED -le ${SPEED[$LOW]} ]]; then
            PAIRS[$i]=${SPEED[$LOW]}
        elif [[ $RNDSPEED -ge ${SPEED[$HIGH]} ]]; then
            PAIRS[$i]=${SPEED[$HIGH]}
        else
            PAIRS[$i]=$RNDSPEED
        fi
        CURSPEED=$(bc -l <<< "$TDIFF0 + $CURSPEED")
    done
done

if [[ $SHOWMAP ]]; then
    echo "TEMP SPEED"
    for i in "${!PAIRS[@]}"; do
        echo "$i   ${PAIRS[$i]}"
    done | sort -n
    exit
fi

if [[ ! $INTERVAL ]]; then
    exit
fi

trap cleanup SIGHUP SIGINT SIGQUIT SIGFPE SIGKILL SIGTERM
function cleanup() {
    echo "0" > "$HWMON/fan1_enable"
    exit
}

cp /etc/default/pp_table "$CARDWD/pp_table"

while [[ true ]]; do
    gpuTemp=$(($(cat $HWMON/temp1_input)/1000))
    if [[ $gpuTemp -lt ${TEMP[0]} ]]; then
        SPEED=$MINSPEED
    elif [[ $gpuTemp -ge ${TEMP[3]} ]]; then
        SPEED=${SPEED[3]}
    elif [[ ! -z ${PAIRS[$gpuTemp]} ]]; then
        SPEED=${PAIRS[$gpuTemp]}
    else
        SPEED=$SAFESPEED
    fi
    if [[ $(cat $HWMON/in0_input) -ge 1000 ]] || [[ $(cat $HWMON/freq2_input) == 800000000 ]]; then
        cp /etc/default/pp_table "$CARDWD/pp_table"
    fi
    echo "1" > "$HWMON/fan1_enable"
    echo "$SPEED" > "$HWMON/fan1_target"
    sleep $INTERVAL
done
