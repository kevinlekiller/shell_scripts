#!/bin/bash
VERSION=21.0

cd /tmp
rm -rf nzbget
mkdir nzbget
cd nzbget
wget https://github.com/nzbget/nzbget/releases/download/v$VERSION/nzbget-$VERSION-src.tar.gz
if [[ ! -f nzbget-$VERSION-src.tar.gz ]]; then
    exit
fi
tar -xf nzbget-$VERSION-src.tar.gz
cd nzbget-$VERSION
./configure --with-tlslib=OpenSSL
make -j14
if [[ ! -f ~/.config/nzbget.conf ]]; then
    cp nzbget.conf ~/.config/
fi
mkdir -p ~/Transfers
mkdir -p ~/Transfers/.nzbget
rm ~/Transfers/.nzbget/nzbget.template.conf
cp nzbget.conf ~/Transfers/.nzbget/nzbget.template.conf
rm -rf ~/Transfers/.nzbget/webui
cp -r webui ~/Transfers/.nzbget/
rm -f ~/bin/nzbget
cp nzbget ~/bin/
cd ~/
rm -rf /tmp/nzbget
