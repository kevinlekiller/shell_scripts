#!/bin/bash

# Disable LED's on Intel i218-V network adapter. Requires recent e1000e 
# driver (works on 3.4, not 3.2 - `modinfo e1000e | grep ^version` to see 
# your version).
  

<<LICENSE
	Copyright (C) 2018  kevinlekiller

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

<<INFO
	Read this page for more info: https://pwmon.org/p/1900/quest-disable-lan-leds-intel-nuc/

	Requires ethtool, python (2 or 3), Intel e1000e driver probably 3.4 or higher (not tested on 3.3,
	3.2 not working), 3.4 does not compile against kernel 4.17, 4.14 was working.
	
	You can supply the interface device name as an argument (eth0 / eno1 for example, get by running ip link).

	Maybe other devices can be adapted to this script? ; I looked at the i211 datasheet, it has 3 bytes instead
	of 2 for the LEDs, might try testing and update this script in the future to support i211.
INFO

IDEVICE="I218-V"
OFFSET1="30"
OFFSET2="31"
VALUE1="a5"
VALUE2="14"

which ethtool > /dev/null 2>&1

if [[ $? != 0 ]]; then
	echo "Failed to find ethtool executable."
	exit 1
fi

which python > /dev/null 2>&1

if [[ $? != 0 ]]; then
	echo "Failed to find python executable."
	exit 1
fi

lspciOutput=$(lspci -nnq | grep -i "$IDEVICE")

if [[ -z $lspciOutput ]]; then
	echo "Failed to find $IDEVICE network device."
	exit 1
fi

if [[ -z $1 ]]; then
	adapter=$(ip link | grep -Po "^\d: e[^:]+" | grep -o "e.*")
else
	if [[ $(ip link | grep "$1") == "" ]]; then
		echo "Supplied interface device name ($1) not found."
		exit 1
	fi
	adapter="$1"
fi

if [[ ! $adapter ]]; then
	echo "Could not find network interface device name."
	exit 1
fi

echo "$IDEVICE interface device name: $adapter"

hex1=$(echo "$lspciOutput" | grep -Po "[a-f0-9]{4}:[a-f0-9]{4}")
hex2=$(echo "$hex1" | cut -d : -f 2)
hex1=$(echo "$hex1" | cut -d : -f 1)

magic=$(python -c "print(hex(0x"$hex1"  | (0x"$hex2" << 16)))")

echo "Magic string for ethtool: $magic"

echo "Running ethtool:"

echo sudo ethtool -E "$adapter" magic "$magic" offset "0x$OFFSET1" value "0x$VALUE1"
sudo ethtool -E "$adapter" magic "$magic" offset "0x$OFFSET1" value "0x$VALUE1"
echo sudo ethtool -E "$adapter" magic "$magic" offset "0x$OFFSET2" value "0x$VALUE2"
sudo ethtool -E "$adapter" magic "$magic" offset "0x$OFFSET2" value "0x$VALUE2"

if [[ $(sudo ethtool -e "$adapter" offset "0x$OFFSET1" length 2 | grep -Po "0x00$OFFSET1:\s*$VALUE1 $VALUE2") == "" ]]; then
	echo $(sudo ethtool -e "$adapter" offset "0x$OFFSET1" length 2)
	echo "Failed to change the LED config of network device $IDEVICE."
	exit 1
fi

echo "LED configuration of $IDEVICE changed, restart the kernel module or computer to see the change."
