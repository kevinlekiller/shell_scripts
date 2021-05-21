#!/bin/bash

if which pipx &> /dev/null; then
    echo "Upgrading pip packages"
    pipx upgrade-all
    echo "Done upgrading pip packages"
fi
if which nix-env &> /dev/null; then
    echo "Upgrading nixpkgs"
    nix-env -u
    echo "Done upgrading nixpkgs"
fi
if which flatpak &> /dev/null; then
    echo "Upgrading Flatpak packages."
    sudo flatpak upgrade && sudo flatpak uninstall --unused
    echo "Done upgrading Flatpak packages."
fi
echo "Upgrading distro packages."
if which pmm &> /dev/null; then
    sudo pmm -Syu # Bedrock linux's package manager manager
elif [[ -f /usr/lib/os-release ]] && which zypper &> /dev/null; then
    if grep -qi "openSUSE Leap" /usr/lib/os-release; then
        sudo zypper up
    elif grep -qi "openSUSE Tumbleweed" /usr/lib/os-release; then
        sudo zypper dup
    fi
elif which yay &> /dev/null; then
    yay -Syu
elif which pacman &> /dev/null; then
    sudo pacman -Syu
elif which apt &> /dev/nulll; then
    sudo apt update
    sudo apt upgrade
elif which dnf &> /dev/null; then
    sudo dnf upgrade
    sudo dns autoremove
elif which yum &> /dev/null; then
    sudo yum check-update
    sudo yum update
elif which emerge &> /dev/null; then
    sudo emerge --sync
    sudo emerge --update --deep --with-bdeps=y @world
fi
echo "Done upgrading distro packages."
if which journalctl &> /dev/null; then
    echo "Vacuuming systemd journal."
    sudo journalctl --rotate --vacuum-size=500M
fi
echo "Cleaning ~/.cache"
rm -rf ~/.cache/*
echo "Cleaning ~/.thumbnails"
rm -rf ~/.thumbnails/
echo "Cleaning ~/.wget-hsts"
rm -rf ~/.wget-hsts
echo "Cleaning ~/.xession-errors"
rm -rf ~/.xsession-errors*
echo "Cleaning ~/.lesshs"
rm -rf ~/.lesshs*
