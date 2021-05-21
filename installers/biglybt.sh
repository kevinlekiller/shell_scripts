#!/bin/bash

# Download biglybt and store it in ~/.biglybt/biglybt

cd /tmp
rm -rf biglybt
mkdir biglybt
cd biglybt
wget https://files.biglybt.com/installer/BiglyBT_unix.tar.gz
if [[ ! -f BiglyBT_unix.tar.gz ]]; then
        exit
fi
tar xf BiglyBT_unix.tar.gz
mkdir -p ~/.biglybt
rm -rf ~/.biglybt/biglybt
mv biglybt ~/.biglybt/
rm BiglyBT_unix.tar.gz
