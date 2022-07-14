#!/bin/bash

trap catchExit SIGHUP SIGINT SIGQUIT SIGTERM
function catchExit() {
    [[ -z $1 ]] && exit 0 || exit "$1"
}

if [[ ! -t 0 ]]; then
    for term in konsole gnome-terminal xfce4-terminal lxterminal xterm; do
        wTerm=$(which $term 2> /dev/null)
        if [[ -n $wTerm ]]; then
            eval "$wTerm" -e "$0"
            exit $?
        fi
    done
fi

cd ~ || exit

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
    flatpak --user upgrade && flatpak --user uninstall --unused
    echo "Done upgrading Flatpak packages."
fi
if which snap &> /dev/null; then
    echo "Upgrading Snap packages."
    sudo snap refresh
    echo "Done upgrading Snap packages."
fi
echo "Upgrading distro packages."
if which pmm &> /dev/null; then
    sudo pmm -Syu # Bedrock linux's package manager manager
elif [[ -f /usr/lib/os-release ]] && which zypper &> /dev/null; then
    sudo zypper refresh
    if grep -qi "openSUSE Leap" /usr/lib/os-release; then
        sudo zypper up --no-recommends
    elif grep -qi "openSUSE Tumbleweed" /usr/lib/os-release; then
        sudo zypper dup --no-recommends
    fi
elif which yay &> /dev/null; then
    yay -Syu
elif which pacman &> /dev/null; then
    sudo pacman -Syu
elif which apt &> /dev/null; then
    sudo apt update && sudo apt upgrade
elif which dnf &> /dev/null; then
    sudo dnf upgrade && sudo dnf autoremove
elif which yum &> /dev/null; then
    sudo yum check-update && sudo yum update
elif which emerge &> /dev/null; then
    sudo emerge --sync && sudo emerge --verbose --update --deep --changed-use @world
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
rm -f ~/.y2log

read -rp 'Done. Press any key to exit... '
