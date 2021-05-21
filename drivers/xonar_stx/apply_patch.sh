#!/bin/bash

# Reduces the POP noise when switching outputs on the Asus Xonar Essence STX (ST also probably). Linux Kernel Patch.

MAKE_FLAGS="-j8"

<<About
    This script compiles the snd_oxygen_lib/snd_oxygen/snd_virtuoso modules with the patch in this gist and installs them.
    You will need to rerun this every time you use a new kernel.
    Tested on Arch Linux (Kernel 4.4).

    Copyright (C) 2016  kevinlekiller
    
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
About

kernel_version=$(uname -r | grep -Po "^[\d.]+")

if [[ -z $kernel_version ]]; then
    echo "Error: Problem detecting current kernel version."
    exit 1
fi

modules_path="/lib/modules/$(uname -r)"

if [[ ! -f "$modules_path/build/Module.symvers" ]]; then
    echo "Error: Can not find the Modules.symvers file for the current kernel."
    exit 1
fi

if [[ ! -f "xonar_pcm179x.c.patch" ]]; then
    wget "https://gist.githubusercontent.com/kevinlekiller/f533f4d1f7318a7cf81a/raw/xonar_pcm179x.c.patch"
    if [[ $? != 0 ]] || [[ ! -f "xonar_pcm179x.c.patch" ]]; then
        echo "Error: Problem downloading kernel patch."
        exit 1
    fi
fi

if [[ ! -f "linux-$kernel_version.tar.xz" ]]; then

    wget "https://cdn.kernel.org/pub/linux/kernel/v$(echo $kernel_version | head -c 1).x/linux-$kernel_version.tar.xz"

    if [[ $? != 0 ]]; then
        echo "Error: Problem downloading kernel source."
        exit 1
    fi

    tar -xf "linux-$kernel_version.tar.xz"

    if [[ $? != 0 ]]; then
        echo "Error: Could not extract kernel."
        exit 1
    fi
else
    tar -xf "linux-$kernel_version.tar.xz"

    if [[ $? != 0 ]]; then
        echo "Error: Could not extract kernel."
        exit 1
    fi
fi

if [[ ! -d "linux-$kernel_version" ]]; then
    echo "Error: Kernel directory not found."
    exit 1
fi

cd "linux-$kernel_version"

make clean

cp "$modules_path/build/Module.symvers" .

zcat /proc/config.gz > .config

sed -i "s/CONFIG_LOCALVERSION=\".*\"/CONFIG_LOCALVERSION=\"$(uname -r | grep -Po "\-.*$")\"/" .config

patch sound/pci/oxygen/xonar_pcm179x.c ../xonar_pcm179x.c.patch

if [[ $? != 0 ]]; then
    echo "Error: Problem patching xonar_pcm179x.c"
    exit 1
fi

make prepare

make "$MAKE_FLAGS" sound/pci/oxygen

make modules_prepare

make "$MAKE_FLAGS" modules SUBDIRS=sound/pci/oxygen

sudo make modules_install SUBDIRS=sound/pci/oxygen

sudo mv "$modules_path"/extra/snd-*.ko.* "$modules_path"/extramodules/

sudo depmod -a

cd ..

sudo rm -rf linux-$kernel_version*
sudo rm -rf linux-$kernel-version
rm -f xonar_pcm179x.c.patch
rm -f "linux-$kernel_version.tar.xz"

echo "Done, reboot to safely reload the compiled modules."
