#!/bin/bash

# How many days of backups to keep before deleting
MAXBACKUPDAYS=10
# How many backups to keep.
MAXBACKUPS=10
# Minimum time between making a backup.
MINBACKUPDAYS=0

mkdir -p ~/.firefox_backups
cd ~/.firefox_backups

utime=$(date +%s)
bdirs=$(find . -type d -regex '.*/[0-9]+$' | cut -d/ -f 2 | sort -n)
bcount=$(echo "$bdirs" | wc -l)
if [[ $bcount -ge $MAXBACKUPS ]]; then
    maxbackuptime=$((utime-$((MAXBACKUPDAYS*24*60*60))))
    todelete=$((bcount-MAXBACKUPS))
    deleted=0
    for bdir in $bdirs; do
        if [[ $bdir -lt $maxbackuptime ]]; then
            echo "Removing backup dir $bdir which is older than max threshold ($maxbackuptime)."
            ((++deleted))
            rm -rf "$bdir"
        fi
        if [[ $deleted -ge $todelete ]]; then
            break
        fi
    done
fi

if [[ $(ls) == "" ]] || [[ $(ls | sort -n -r | head -n1) -lt $((utime-$((MINBACKUPDAYS*24*60*60)))) ]]; then
    if [[ -d $utime ]]; then
        rm -rf $utime
    fi

    mkdir $utime
    cd $utime
    7z a -y backup.7z ~/.mozilla
fi
