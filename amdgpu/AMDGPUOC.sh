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

# This script uses https://github.com/Eliovp/amdmemorytweak and https://github.com/Lucie2A/amdtweak/tree/contribution

# Enables GPU scaling so the monitor doesn't go out of range when using non supported modes.
for output in $(xrandr --prop | grep -E -o -i "^[A-Z\-]+-[0-9]+"); do xrandr --output "$output" --set "scaling mode" "Full aspect"; done

# These modes allow for 75% of 4K if a game is too demanding, a 60 and 30hz mode are added.
if ! [[ $(xrandr) =~ 3200x1800.*60 ]]; then
    xrandr --newmode "3200x1800" 364.47  3200 3208 3240 3280  1800 1838 1846 1852 +hsync -vsync
    xrandr --addmode HDMI-A-0 "3200x1800"
fi

if ! [[ $(xrandr) =~ 3200x1800.*30 ]]; then
    xrandr --newmode "3200x1800_30" 179.68  3200 3208 3240 3280  1800 1812 1820 1826 +hsync -vsync
    xrandr --addmode HDMI-A-0 "3200x1800_30"
fi

# Which GPU to use.
GPUID=${GPUID:-0}

############################################################################################
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

DBGFILE=/sys/kernel/debug/dri/0/amdgpu_pm_info
function stats() {
    echo "Fan Speed: $(cat $HWMON/fan1_input) RPM"
    sudo pcregrep -M "GFX Clocks.*(\n.*)*GPU Load.*" /sys/kernel/debug/dri/0/amdgpu_pm_info
    cat $CARDWD/pp_power_profile_mode
    cat $CARDWD/pp_od_clk_voltage
    cat $CARDWD/pp_dpm_sclk
    cat $CARDWD/pp_dpm_mclk
    echo "Limit (currently)       : $(($(cat $HWMON/power1_cap)/1000000)) watts"
}

trap cleanup SIGHUP SIGINT SIGQUIT SIGFPE SIGKILL SIGTERM
function cleanup() {
    echo "Reverting overclock settings."
    sudo amdtweak.sh r
    sudo amdmemtweak --ref 3900
    sudo bash -c "echo $(($DEFAULTPOWERCAP*1000000)) > $HWMON/power1_cap"
    stats
    exit
}

# Changes the powerplay table, see the included script. 
sudo amdtweak.sh
# Raises the power limit from 220 watts to 330 (50%)
sudo bash -c "echo 330000000 > $HWMON/power1_cap"
# Changes the tref, seems to be the only timing that makes any significant difference on my card.
sudo amdmemtweak --ref 25000

while [[ true ]]; do
    clear
    stats
    sleep  1
done
