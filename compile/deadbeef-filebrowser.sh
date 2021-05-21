#!/bin/bash
# Compiles / installs the deadbeef-fb addon for deadbeef.
# Install deadbeef / deadbeef-devel first.

cd /tmp
rm -rf deadbeef-fb
git clone https://gitlab.com/zykure/deadbeef-fb
cd deadbeef-fb
sed -i "s/errno/errorNum/g" utils.c
./autogen.sh
./configure --prefix=/usr --disable-gtk2
make -j7
sudo make install
