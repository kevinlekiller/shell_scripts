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

# Example image of script running: https://raw.githubusercontent.com/kevinlekiller/shell_scripts/main/misc/osd_stats.png

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
valType[0]=MHz
valLoc_[0]="/proc/cpuinfo"

valName[1]=CPU
valType[1]=C
valLoc_[1]="$it8665_dir/temp1_input"

valName[2]=CPU
valType[2]=RPM
valLoc_[2]="$it8665_dir/fan1_input"

valName[3]=Chassis
valType[3]=RPM
valLoc_[3]="$it8665_dir/fan5_input"

valName[4]=GPU
valType[4]=RPM
valLoc_[4]="$amdgpu_dir/fan1_input"

valName[5]=GPU
valType[5]=mV
valLoc_[5]="$amdgpu_dir/in0_input"

valName[6]="GPU Load"
valType[6]=%
valLoc_[6]="$amdgpu_dir/device/gpu_busy_percent"

valName[7]=GPU
valType[7]=W
valLoc_[7]="$amdgpu_dir/power1_average"

valName[8]=GPU
valType[8]=MHz
valLoc_[8]="$amdgpu_dir/device/pp_dpm_sclk"

valName[9]="GPU HBM"
valType[9]=MHz
valLoc_[9]="$amdgpu_dir/device/pp_dpm_mclk"

valName[10]=GPU
valType[10]=C
valLoc_[10]="$amdgpu_dir/temp1_input"

valName[11]="GPU HBM"
valType[11]=C
valLoc_[11]="$amdgpu_dir/temp3_input"

valName[12]="GPU jnc"
valType[12]=C
valLoc_[12]="$amdgpu_dir/temp2_input"

valName[13]=VRAM
valType[13]=MB
valLoc_[13]="$amdgpu_dir/device/mem_info_vram_used"

vals=14

###########################################################
###########################################################
unset "$tmpPath" "$device"
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
    if [[ ! -f ${valLoc_[$i]} ]]; then
        echo "Error: Sensor path not found: '${valLoc_[$i]}'"
        exit 1
    fi
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
        elif [[ ${valType[$i]} == MB ]]; then
            string="$string$(($(cat "${valLoc_[$i]}")/1048576))\n"
        elif [[ ${valName[$i]} == CPU && ${valType[$i]} == MHz ]]; then
            string="$string$(grep MHz "${valLoc_[$i]}"  | cut -d: -f2 | cut -d. -f1 | sort -nr | head -n1 | sed "s/ *//g")\n"
        elif [[ ${valType[$i]} == MHz ]]; then
            string="$string$(grep "\*" "${valLoc_[$i]}" | grep -Po "[0-9]{3,4}")\n"
        else
            string="$string$(cat "${valLoc_[$i]}")\n"
        fi
    done
    printOSD "$osd_delay"
    sleep "$sleep_delay"
done
