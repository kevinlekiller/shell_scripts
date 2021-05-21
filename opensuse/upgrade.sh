#!/bin/bash
echo "Upgrading pip packages"
pipx upgrade-all
echo "Done upgrading pip packages"
#echo "Upgrading nixpkgs"
#nix-env -u || exit $?
#echo "Done upgrading nixpkgs"
echo "Upgrading Flatpak packages."
sudo flatpak upgrade || exit $?
sudo flatpak uninstall --unused || exit $?
echo "Done upgrading Flatpak packages."
echo "Upgrading zypper packages."
sudo zypper dup || exit $?
echo "Done upgrading zypper packages."
echo "Cleaning temp files"
sudo journalctl --rotate --vacuum-size=500M || exit $?
rm -rf ~/.cache/*
rm -rf ~/.thumbnails/
rm -rf ~/.wget-hsts
rm -rf ~/.xsession-errors*
rm -rf ~/.lesshs*
