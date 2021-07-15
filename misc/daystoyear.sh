#!/bin/bash

# Shows the year of x days ago

daysago="$1"
if ! [[ $daysago =~ ^[0-9]*$ ]]; then
    echo "Enter number of days as first argument."
    exit 1
fi

date --date="$daysago days ago" +%Y
