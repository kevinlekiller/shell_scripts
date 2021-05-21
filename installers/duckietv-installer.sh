#!/bin/bash

# Install or update DuckieTV nightly on Linux. https://github.com/DuckieTV/Nightlies

<<LICENSE
    Copyright (C) 2020  kevinlekiller
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

DVERS=$(curl -s https://github.com/DuckieTV/Nightlies/commits//master.atom | grep -m1 -Po "nightly-20\d{10}" | grep -o "[0-9]*")
if [[ $DVERS == "" ]]; then
        echo "Error finding new DuckieTV version."
        exit
fi

if [[ -f /opt/DuckieTV/VERSION ]] && [[ $DVERS -le $(cat /opt/DuckieTV/VERSION) ]]; then
        echo "DuckieTV is up to date."
        exit
fi

mkdir -p /tmp/duckietv
cd /tmp/duckietv
wget -q -O duckietv.tar.gz https://github.com/DuckieTV/Nightlies/releases/download/nightly-$DVERS/DuckieTV-$DVERS-linux-x64.tar.gz

if ! [[ -f duckietv.tar.gz ]]; then
        echo "Error downloading DuckieTV."
        exit
fi

tar -xf duckietv.tar.gz
sudo chmod +x setup
sudo ./setup
cd /tmp
rm -rf duckietv
