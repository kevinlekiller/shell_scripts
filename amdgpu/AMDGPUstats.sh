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

# This file has info on the GPU voltage (VDDGFX) ; Alternatively, without root
# access you can get the voltage from /sys/class/drm/card0/device/hwmon/hwmon2/in0_input
DBGFILE=/sys/kernel/debug/dri/0/amdgpu_pm_info
CARDWD="/sys/class/drm/card0/device"
HWMON="$(find $CARDWD/hwmon/ -name hwmon[0-9] -type d | head -n 1)"
while [[ true ]]; do
        echo "Fan Speed: $(cat $HWMON/fan1_input) RPM"
        sudo pcregrep -M "GFX Clocks.*(\n.*)*GPU Load.*" "$DBGFILE"
        cat $CARDWD/pp_power_profile_mode
        cat $CARDWD/pp_od_clk_voltage
        echo "GPU CLK:"
        grep "*" $CARDWD/pp_dpm_sclk
        echo "HBM CLK:"
        grep "*" $CARDWD/pp_dpm_mclk
        echo "SOC CLK:"
        cat $CARDWD/pp_dpm_socclk
        sleep 2
        clear
done

<<EXAMPLE
$ ./AMDGPUStats.sh

Fan Speed: 391 RPM
GFX Clocks and Power:
        167 MHz (MCLK)
        27 MHz (SCLK)
        1138 MHz (PSTATE_SCLK)
        800 MHz (PSTATE_MCLK)
        856 mV (VDDGFX)
        6.0 W (average GPU)

GPU Temperature: 32 C
GPU Load: 0 %
NUM        MODE_NAME BUSY_SET_POINT FPS USE_RLC_BUSY MIN_ACTIVE_LEVEL
  0 BOOTUP_DEFAULT*:             70  60          0              0
  1 3D_FULL_SCREEN :             70  60          1              3
  2   POWER_SAVING :             90  60          0              0
  3          VIDEO :             70  60          0              0
  4             VR :             70  90          0              0
  5        COMPUTE :             30  60          0              6
  6         CUSTOM :              0   0          0              0
OD_SCLK:
0:        852Mhz        800mV
1:        991Mhz        900mV
2:       1084Mhz        950mV
3:       1138Mhz       1000mV
4:       1200Mhz       1050mV
5:       1401Mhz       1100mV
6:       1536Mhz       1150mV
7:       1630Mhz       1200mV
OD_MCLK:
0:        167Mhz        800mV
1:        500Mhz        800mV
2:        800Mhz        950mV
3:        945Mhz       1100mV
OD_RANGE:
SCLK:     852MHz       2400MHz
MCLK:     167MHz       1500MHz
VDDC:     800mV        1200mV
GPU CLK:
0: 852Mhz *
HBM CLK:
0: 167Mhz *
SOC CLK:
0: 600Mhz *
1: 720Mhz 
2: 800Mhz 
3: 847Mhz 
4: 900Mhz 
5: 960Mhz 
6: 1028Mhz
EXAMPLE
