#!/bin/bash

cat > /dev/null <<LICENSE
    Copyright (C) 2022  kevinlekiller

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

# Control 3 pin fans using Corsair Commander Pro.

# Temperature sensor to monitor.
# Find sensors with : for file in $(find /sys/devices -name temp[[0-9]*_input); do echo "$(cat "$(dirname "$file")/name") -> $file"; done
# The hwmon[NUMBER] folder changes on reboot, so set it to hwmon[0-9]*
TEMPSENSOR=${TEMPSENSOR:-/sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon[0-9]*/temp1_input}

# Which fans to control.
# To control fans 1,4 and 6, set to [146] for example.
FANS=${FANS:-[123456]}

# Show the temp to speed lookup table then exit. Leave empty to disable. eg.: SHOWLUT=1 ./fanspeed.sh
SHOWLUT=${SHOWLUT:-}

# Delay between checking temps / setting fan speed.
INTERVAL=${INTERVAL:-2.0}

# If this is enabled, lower RPM by at most this much each $INTERVAL, to smooth out the fan speed.
# Can be disabled with 0, max value is 500.
SMOOTHDESCENT=${SMOOTHDESCENT:-50}

# Similar to SMOOTHDESCENT, but for when the fan PWM goes up.
SMOOTHASCENT=${SMOOTHASCENT:-50}

# Set to this fan PWM when temperature is lower than TEMP[0].
MINSPEED=0

# What fan speed to set at what temperature, for example set the fans to 400 RPM when the temp is 50c, shut off the fans when the temp is 35c or less.
# All other values are calculated on the fly, pass the SHOWMAP=true environment variable to show the calculated values.
TEMP[0]=35
SPEED[0]=0

TEMP[1]=50
SPEED[1]=400

TEMP[2]=65
SPEED[2]=800

TEMP[3]=80
SPEED[3]=1200

###############################################################################
###############################################################################

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

if [[ $SHOWLUT ]]; then
    echo "TEMP SPEED"
    for i in "${!PAIRS[@]}"; do
        echo "$i   ${PAIRS[$i]}"
    done | sort -n
    exit
fi

if [[ $EUID != 0 ]]; then
    echo "Error: Must run as root."
    exit 1
fi


TEMPSENSOR=$(realpath $TEMPSENSOR)
if [[ ! -f $TEMPSENSOR ]] || [[ ! $(cat $TEMPSENSOR) =~ ^[0-9]+$ ]]; then
    echo "ERROR: Unable to find temperature sensor '$TEMPSENSOR'."
    exit 1
fi

if ! ls /sys/bus/hid/drivers/corsair-cpro/[0-9A-Z:]*/hwmon/hwmon*/fan${FANS}_target &> /dev/null; then
    echo "Unable to find fan target files."
    exit 1
fi

if [[ ! $SMOOTHDESCENT =~ ^[0-9]*$ ]] || [[ $SMOOTHDESCENT -gt 500 ]] || [[ $SMOOTHDESCENT -lt 1 ]]; then
    SMOOTHDESCENT=0
fi
if [[ ! $SMOOTHASCENT =~ ^[0-9]*$ ]] || [[ $SMOOTHASCENT -gt 500 ]] || [[ $SMOOTHASCENT -lt 1 ]]; then
    SMOOTHASCENT=0
fi

trap catchExit SIGHUP SIGINT SIGQUIT SIGTERM
function catchExit() {
    exit 0
}

LSPEED=127
while true; do
    CTEMP=$(($(cat "$TEMPSENSOR")/1000))
    if [[ $CTEMP -le ${TEMP[0]} ]]; then
        CSPEED=$MINSPEED
    elif [[ $CTEMP -ge ${TEMP[3]} ]]; then
        CSPEED=${SPEED[3]}
    elif [[ -n ${PAIRS[$CTEMP]} ]]; then
        CSPEED=${PAIRS[$CTEMP]}
    else
        CSPEED=${SPEED[1]}
    fi
    if [[ $CSPEED -lt $LSPEED ]]; then
        CSPEED=$((LSPEED-SMOOTHDESCENT))
        if [[ $CSPEED -lt $MINSPEED ]]; then
            CSPEED=$MINSPEED
        fi
    elif [[ $CSPEED -gt $LSPEED ]]; then
        CSPEED=$((LSPEED+SMOOTHASCENT))
        if [[ $CSPEED -gt ${SPEED[3]} ]]; then
            CSPEED=${SPEED[3]}
        fi
    fi
    LSPEED=$CSPEED
    echo $CSPEED > /sys/bus/hid/drivers/corsair-cpro/[0-9A-Z:]*/hwmon/hwmon*/fan${FANS}_target

    sleep "$INTERVAL"
done
