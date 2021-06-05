#!/bin/bash

cat > /dev/null <<LICENSE
    Copyright (C) 2018-2021  kevinlekiller

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

if ! lspci | grep -q "VGA.*AMD"; then
    while true; do
        sleep 99999
    done
fi

# Set to 1 to apply custom overclock settings.
# Change overclock settings below.
OVERCLOCK=${OVERCLOCK:-1}

# Set to 1 to set GPU power limit to max.
POWERLIMIT=${POWERLIMIT:-1}

# Which GPU to use.
GPUID=${GPUID:-0}

# How many seconds to wait before checking temps / setting fan speeds. Lower values mean higher CPU usage. Leave empty to disable fan control.
INTERVAL=${INTERVAL:-2.5}

# Show the temp to speed map then exit. Leave empty to disable.
SHOWMAP=${SHOWMAP:-}

# Set fan speed to this speed if GPU temperature under TEMP[0]
MINSPEED=400

# What fan speed to set at what temperature, for example set the fan speed at 25% when GPU temp is 50 degrees.
# All other values are calculated on the fly, pass the SHOWMAP=true environment variable to show the calculated values.
# These values work for a reference Vega 64 with a Morpheus 2 cooler and Noctua NF-F12 PWM fans.
TEMP[0]=40
SPEED[0]=500

TEMP[1]=45
SPEED[1]=857

TEMP[2]=50
SPEED[2]=1234

TEMP[3]=55
SPEED[3]=1600

# This is in case there's some kind of logic flaw in the while loop. Can be left as is.
SAFESPEED=${SPEED[1]}

CARDWD="/sys/class/drm/card$GPUID/device"
if [[ $(grep 0x1002 "$CARDWD/vendor" 2> /dev/null) == "" ]]; then
    echo "AMD GPU not found, exiting."
    exit 1
fi

HWMON="$(find "$CARDWD/hwmon/" -name "hwmon[0-9]" -type d | head -n 1)"
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

trap cleanup SIGHUP SIGINT SIGQUIT SIGTERM
function cleanup() {
    if [[ $INTERVAL ]]; then
        echo "0" > "$HWMON/fan1_enable"
    fi
    if [[ $OVERCLOCK ]]; then
        echo "r" > "$CARDWD/pp_od_clk_voltage"
    fi
    if [[ $POWERLIMIT && $POWERLIMIT -gt 1 ]]; then
        echo "$POWERLIMIT"  > "$HWMON/power1_cap"
    fi
    exit 0
}

if [[ $OVERCLOCK ]]; then
    # s is for the GPU clock speed
    # m is the memory clock speed
    # The first number the P-State
    # The second number is the clock speed
    # The third number is the voltage in mV
    # The memory p-states 0 and 1 must have the same voltage as the GPU p-state 0
    # The memory p-state 2 must have the same voltage as the GPU p-state 2
    # The memory p-state 3 must have the same voltage as the GPU p-state 5
    # Get default values with : cat /sys/class/drm/card0/device/pp_od_clk_voltage

    for string in\
        "s 0 852 800"\
        "s 1 991 850"\
        "s 2 1084 900"\
        "s 3 1138 925"\
        "s 4 1200 950"\
        "s 5 1431 975"\
        "s 6 1630 1000"\
        "s 7 1722 1025"\
        "m 0 167 800"\
        "m 1 500 800"\
        "m 2 800 900"\
        "m 3 1085 975";
    do
        echo "$string" > "$CARDWD/pp_od_clk_voltage"
    done
    echo "c" > "$CARDWD/pp_od_clk_voltage"
fi

if [[ $POWERLIMIT ]]; then
    POWERLIMIT=$(cat "$HWMON/power1_cap")
    echo "$(cat "$HWMON/power1_cap_max")" > "$HWMON/power1_cap"
fi

if [[ ! $INTERVAL ]]; then
    exit
fi

echo "1" > "$HWMON/fan1_enable"
while true; do
    gpuTemp=$(($(cat "$HWMON/temp1_input")/1000))
    if [[ $gpuTemp -lt ${TEMP[0]} ]]; then
        CSPEED=$MINSPEED
    elif [[ $gpuTemp -ge ${TEMP[3]} ]]; then
        CSPEED=${SPEED[3]}
    elif [[ -n ${PAIRS[$gpuTemp]} ]]; then
        CSPEED=${PAIRS[$gpuTemp]}
    else
        CSPEED=$SAFESPEED
    fi
    echo "$CSPEED" > "$HWMON/fan1_target"
    sleep "$INTERVAL"
done
