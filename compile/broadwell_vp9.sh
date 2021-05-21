#!/bin/bash

# Enable VP9 hybrid decode on Broadwell, (Arch) Linux. Read the script to understand what it's doing.

sudo pacman --needed -Syu libva git meson libdrm

cd ~/

mkdir -p broadwell_vp9

cd broadwell_vp9

if [[ -d intel-hybrid-driver ]]; then
  cd intel-hybrid-driver
  git pull
else
  git clone -b mark_global_var_as_extern https://github.com/eclipseo/intel-hybrid-driver
  cd intel-hybrid-driver
fi
make clean
autoreconf -v --install
./configure --prefix=/usr
make
sudo make install
cd ..

if [[ -d intel-vaapi-driver ]]; then
  cd intel-vaapi-driver
  rm -rf build
  git checkout meson.build
  git pull
else
  git clone https://github.com/intel/intel-vaapi-driver
  cd intel-vaapi-driver
fi
sed -i "s#'warning_level=1',#'warning_level=1','enable_hybrid_codec=true',#" meson.build
arch-meson . build
ninja -C build
sudo ninja -C build install
