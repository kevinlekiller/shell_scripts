#!/bin/bash

cat > /dev/null <<LICENSE
    Copyright (C) 2021  kevinlekiller
    
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

if [[ $EUID != 0 ]]; then
    echo "Error: Must run as root."
    exit 1
fi

it87BaseDir=$(realpath /sys/devices/platform/it87.656/hwmon/hwmon* | head -n1)
if [[ ! -d $it87BaseDir ]]; then
    echo "Error: Could not find it87 hwmon directory."
fi
gpuBaseDir=$(realpath "$(dirname "$(find /sys/devices/ -name pp_power_profile_mode)")"/hwmon/hwmon* | head -n1)
if [[ ! -d $gpuBaseDir ]]; then
    echo "Error: Could not find GPU hwmon directory."
    exit 1
fi
k10BaseDir=$(realpath "/sys/devices/pci0000:00/0000:00:18.3"/hwmon/hwmon* | head -n1)
if [[ ! -d $k10BaseDir ]]; then
    echo "Error: Could not find GPU hwmon directory."
    exit 1
fi

#fanCpuEnable="$it87BaseDir/pwm1_enable"
#fanCpuControl="$it87BaseDir/pwm1"

# File used to enable manual control of fan PWM.
fanChassisEnable="$it87BaseDir/pwm5_enable"
# File used to control fan PWM.
fanChassisControl="$it87BaseDir/pwm5"

# How many sensors are we monitoring.
tempSensors=3
# CPU TDie
tempSensor[0]="$k10BaseDir/temp2_input"
# GPU Edge
tempSensor[1]="$gpuBaseDir/temp1_input"
# GPU HBM
tempSensor[2]="$gpuBaseDir/temp3_input"

# Show the temp to speed map then exit. Leave empty to disable.
SHOWMAP=${SHOWMAP:-}

# Delay between checking temps / setting fan speed.
INTERVAL=${INTERVAL:-2.0}

# If this is enabled, lower PWM by this much each $INTERVAL, to smooth out the fan speed.
# Can be disabled with 0, max value is 50.
SMOOTHDESCENT=${SMOOTHDESCENT:-5}

# Set to this fan PWM when temperature is lower than TEMP[0].
MINSPEED=0

# What fan PWM to set at what temperature, for example set the fan to 45 PWM when the temp is 45 degrees.
# All other values are calculated on the fly, pass the SHOWMAP=true environment variable to show the calculated values.
TEMP[0]=45
SPEED[0]=45

TEMP[1]=55
SPEED[1]=115

TEMP[2]=65
SPEED[2]=185

TEMP[3]=75
SPEED[3]=255

###############################################################################
###############################################################################

((--tempSensors))

if [[ ! $SMOOTHDESCENT =~ ^[0-9]*$ ]] || [[ $SMOOTHDESCENT -gt 50 ]] || [[ $SMOOTHDESCENT -lt 1 ]]; then
    SMOOTHDESCENT=0
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

trap catchExit SIGHUP SIGINT SIGQUIT SIGTERM
function catchExit() {
    exit 0
}

echo 1 > "$fanChassisEnable"

LSPEED=0
while true; do
    CTEMP=0
    for i in $(seq 0 $tempSensors); do
        TTEMP=$(($(cat "${tempSensor[$i]}")/1000))
        if [[ $TTEMP -gt $CTEMP ]]; then
            CTEMP=$TTEMP
        fi
    done
    if [[ $CTEMP -lt ${TEMP[0]} ]]; then
        CSPEED=$MINSPEED
    elif [[ $CTEMP -ge ${TEMP[3]} ]]; then
        CSPEED=${SPEED[3]}
    elif [[ -n ${PAIRS[$CTEMP]} ]]; then
        CSPEED=${PAIRS[$CTEMP]}
    else
        CSPEED=${SPEED[1]}
    fi
    if [[ $SMOOTHDESCENT -gt 0 ]]; then
        if [[ $CSPEED -lt $LSPEED ]]; then
            CSPEED=$(($LSPEED-$SMOOTHDESCENT))
            if [[ $CSPEED -lt $MINSPEED ]]; then
                CSPEED=$MINSPEED
            fi
        fi
        LSPEED=$CSPEED
    fi
    echo $CSPEED > "$fanChassisControl"
    sleep "$INTERVAL"
done
