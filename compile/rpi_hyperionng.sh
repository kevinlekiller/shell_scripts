#!/bin/bash

# Build hyperion-ng on raspberry pi for ws2812b

cd ~
rm -rf hyperion.ng
git clone --recursive https://github.com/hyperion-project/hyperion.ng
cd hyperion.ng/dependencies/external
rm -rf rpi_ws281x
git clone https://github.com/jgarff/rpi_ws281x
cd ~/hyperion.ng

mkdir -p build
cd build
cmake -DMAKE_BUILD_TYPE=Release -DPLATFORM="rpi" \
 -DENABLE_DISPMANX=OFF -DENABLE_AMLOGIC=OFF -DENABLE_FB=OFF -DENABLE_OSX=OFF -DENABLE_PROFILER=OFF \
 -DENABLE_QT5=ON -DENABLE_SPIDEV=OFF -DENABLE_TESTS=OFF -DENABLE_TINKERFORGE=OFF -DENABLE=V4L2=ON \
 -DENABLE_WS2812BPWM=OFF -DENABLE_WS281XPWM=ON -DENABLE_X11=OFF -DENABLE_ZEROCONF=OFF \
 -DENABLE_OPENCV=OFF -DENABLE_CEC=OFF -Wno-dev ..

if [[ $? != 0 ]]; then
        exit
fi

make -j 2
if [[ $? != 0 ]]; then
        exit
fi

strip bin/*
sudo rm -f /usr/local/bin/hyperiond
sudo cp bin/hyperiond /usr/local/bin
