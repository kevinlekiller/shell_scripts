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

# Example image of script running: https://raw.githubusercontent.com/kevinlekiller/shell_scripts/main/misc/osd_stats.jpg

# To pause / resume the OSD, add a custom shortcut.
# Add this as the action : bash -c "if pgrep osd_stats.sh$; then pkill osd_stats.sh$; else osd_stats.sh; fi"
# For example, in KDE Plasma, go in system settings, click Shortcuts -> Custom Shortcuts.
# Right click ; New -> Global Shortcut -> Command/URL
# In the Trigger, add the keyboard shortcut.
# In the Action, paste the command above.

i=0
for device in amdgpu it8665 zenpower; do
    tmpPath=$(grep "$device" /sys/class/hwmon/hwmon*/name | grep -Po "^/sys/class/hwmon/hwmon\d+")
    if [[ -z $tmpPath ]]; then
        echo "Could not find hwmon path for device '$device'."
        exit 1
    fi
    eval "${device}_dir"="$tmpPath"
done

osd_delay=3
osd_position=top
osd_align=right
osd_top_offset=5
osd_side_offset=5
osd_outline=2
osd_color=green
osd_font="-*-*-*-*-*-*-20-*-*-*-*-*-*-*"

valName[$i]=CPU
valType[$i]=MHz
valLoc_[$i]="/proc/cpuinfo"
((++i))

valName[$i]=CPU
valType[$i]=W
valLoc_[$i]="$zenpower_dir/power1_input"
((++i))

valName[$i]=CPU
valType[$i]=mV
valLoc_[$i]="$it8665_dir/in0_input"
((++i))

valName[$i]=DRAM
valType[$i]=mV
valLoc_[$i]="$it8665_dir/in1_input"
((++i))

valName[$i]="CPU SOC"
valType[$i]=W
valLoc_[$i]="$zenpower_dir/power2_input"
((++i))

valName[$i]=CPU
valType[$i]=C
valLoc_[$i]="$it8665_dir/temp1_input"
((++i))

valName[$i]=CPU
valType[$i]=RPM
valLoc_[$i]="$it8665_dir/fan1_input"
((++i))

valName[$i]=Chassis
valType[$i]=RPM
valLoc_[$i]="$it8665_dir/fan5_input"
((++i))

valName[$i]=GPU
valType[$i]=RPM
valLoc_[$i]="$amdgpu_dir/fan1_input"
((++i))

valName[$i]=GPU
valType[$i]=mV
valLoc_[$i]="$amdgpu_dir/in0_input"
((++i))

valName[$i]="GPU Load"
valType[$i]=%
valLoc_[$i]="$amdgpu_dir/device/gpu_busy_percent"
((++i))

valName[$i]=GPU
valType[$i]=W
valLoc_[$i]="$amdgpu_dir/power1_average"
((++i))

valName[$i]=GPU
valType[$i]=MHz
valLoc_[$i]="$amdgpu_dir/freq1_input"
((++i))

valName[$i]="GPU HBM"
valType[$i]=MHz
valLoc_[$i]="$amdgpu_dir/freq2_input"
((++i))

valName[$i]=GPU
valType[$i]=C
valLoc_[$i]="$amdgpu_dir/temp1_input"
((++i))

valName[$i]="GPU HBM"
valType[$i]=C
valLoc_[$i]="$amdgpu_dir/temp3_input"
((++i))

valName[$i]="GPU jnc"
valType[$i]=C
valLoc_[$i]="$amdgpu_dir/temp2_input"
((++i))

valName[$i]=VRAM
valType[$i]=MB
valLoc_[$i]="$amdgpu_dir/device/mem_info_vram_used"
((++i))

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
((--i))
osd_lines="$((i+2))"
sleep_delay=$(bc -l <<< "$osd_delay-0.1")
for j in $(seq 0 "$i"); do
    string="$string$(printf "%-8s%6s%-3s" "${valName[$j]}" "" "${valType[$j]}")\n"
    if [[ ! -f ${valLoc_[$i]} ]]; then
        echo "Error: Sensor path not found: '${valLoc_[$j]}'"
        exit 1
    fi
done
printOSD "-1"
osd_side_offset="$((osd_side_offset+40))"
while true; do
    string=""
    for j in $(seq 0 "$i"); do
        if [[ ${valType[$j]} == C ]]; then
            string="$string$(($(cat "${valLoc_[$j]}")/1000))\n"
        elif [[ ${valName[$j]} == CPU && ${valType[$j]} == MHz ]]; then
            string="$string$(grep MHz "${valLoc_[$j]}"  | cut -d: -f2 | cut -d. -f1 | sort -nr | head -n1 | sed "s/ *//g")\n"
        elif [[ ${valType[$j]} == W || ${valType[$j]} == MHz ]]; then
            string="$string$(($(cat "${valLoc_[$j]}")/1000000))\n"
        elif [[ ${valType[$j]} == MB ]]; then
            string="$string$(($(cat "${valLoc_[$j]}")/1048576))\n"
        else
            string="$string$(cat "${valLoc_[$j]}")\n"
        fi
    done
    printOSD "$osd_delay"
    sleep "$sleep_delay"
done
