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

srcdir=/usr/src

updit87=1

cd "$srcdir" || exit
if [[ ! -d $srcdir/it87 ]]; then
    sudo git clone https://github.com/frankcrawford/it87
    cd it87 || exit
else
    cd it87 || exit
    if [[ $(sudo git pull) =~ ^Already ]]; then
        updit87=0
    fi
fi

if [[ ! -f uname ]]; then
    updit87=1
elif [[ $(cat uname) != $(uname -r) ]]; then
    updit87=1
fi

if [[ $updit87 == 0 ]]; then
    echo "it87 already up to date"
    exit 0
fi

it87str=$(sudo dkms status | grep -m1 it87)

sudo modprobe -r it87 &> /dev/null

if [[ $it87str != "" ]]; then
    sudo dkms remove "it87/$(echo "$it87str" | cut -d, -f2 | xargs)" -k "$(echo "$it87str" | cut -d, -f3 | xargs)"
fi

sudo ./dkms-install.sh

sudo bash -c "uname -r > $srcdir/it87/uname"

if [[ ! -f /etc/modules-load.d/99-it87.conf ]]; then
    sudo bash -c "echo it87 > /etc/modules-load.d/99-it87.conf"
fi

if [[ ! -f /etc/modprobe.d/99-it87.conf ]]; then
    sudo bash -c "echo 'options it87 ignore_resource_conflict=1' > /etc/modprobe.d/99-it87.conf"
fi

sudo modprobe it87 ignore_resource_conflict=1
sudo systemctl restart cfancontrol
