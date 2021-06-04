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

# To pause / resume the OSD, add a custom shortcut.
# Add this as the action : bash -c "if pgrep osd_stats.sh$; then pkill osd_stats.sh$; else osd_stats.sh; fi"
# For example, in KDE Plasma, go in system settings, click Shortcuts -> Custom Shortcuts.
# Right click ; New -> Global Shortcut -> Command/URL
# In the Trigger, add the keyboard shortcut.
# In the Action, paste the command above.

for device in amdgpu it8665; do
    tmpPath=$(grep "$device" /sys/class/hwmon/hwmon*/name | grep -Po "^/sys/class/hwmon/hwmon\d+")
    if [[ -z $tmpPath ]]; then
        echo "Could not find hwmon path for device '$device'."
        exit 1
    fi
    eval "${device}_dir"="$tmpPath"
done

osd_delay=2
osd_position=top
osd_align=right
osd_top_offset=5
osd_side_offset=5
osd_outline=2
osd_color=green
osd_font="-*-*-*-*-*-*-20-*-*-*-*-*-*-*"

valName[0]=CPU
valType[0]=C
valLoc_[0]="$it8665_dir/temp1_input"

valName[1]=CPU
valType[1]=RPM
valLoc_[1]="$it8665_dir/fan1_input"

valName[2]=Chassis
valType[2]=RPM
valLoc_[2]="$it8665_dir/fan5_input"

valName[3]=GPU
valType[3]=RPM
valLoc_[3]="$amdgpu_dir/fan1_input"

valName[4]=GPU
valType[4]=mV
valLoc_[4]="$amdgpu_dir/in0_input"

valName[5]=GPU
valType[5]=W
valLoc_[5]="$amdgpu_dir/power1_average"

valName[6]=GPU
valType[6]=C
valLoc_[6]="$amdgpu_dir/temp1_input"

valName[7]="GPU HBM"
valType[7]=C
valLoc_[7]="$amdgpu_dir/temp3_input"

valName[8]="GPU jnc"
valType[8]=C
valLoc_[8]="$amdgpu_dir/temp2_input"

vals=9

###########################################################
###########################################################
function printOSD() {
    echo -e "$string" | osd_cat \
    --pos="$osd_position" \
    --offset="$osd_top_offset" \
    --align="$osd_align" \
    --indent="$osd_side_offset" \
    --color="$osd_color" \
    --lines="$osd_lines" \
    --font="$osd_font" \
    --outline="$osd_outline" \
    --delay="$1" &
}
trap catchExit SIGHUP SIGINT SIGQUIT SIGTERM
function catchExit() {
    pkill osd_cat
    exit 0
}
((--vals))
osd_lines="$((vals+2))"
sleep_delay=$(bc -l <<< "$osd_delay-0.1")
for i in $(seq 0 $vals); do
    string="$string$(printf "%-8s%6s%-3s" "${valName[$i]}" "" "${valType[$i]}")\n"
done
printOSD "-1"
osd_side_offset="$((osd_side_offset+40))"
while true; do
    string=""
    for i in $(seq 0 $vals); do
        if [[ ${valType[$i]} == C ]]; then
            string="$string$(($(cat "${valLoc_[$i]}")/1000))\n"
        elif [[ ${valType[$i]} == W ]]; then
            string="$string$(($(cat "${valLoc_[$i]}")/1000000))\n"
        else
            string="$string$(cat "${valLoc_[$i]}")\n"
        fi
    done
    printOSD "$osd_delay"
    sleep "$sleep_delay"
done
