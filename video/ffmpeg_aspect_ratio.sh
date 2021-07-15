#!/bin/bash

# Change aspect ratio of video

AR="$1"
if [[ ! $AR =~ ^[0-9]*:[0-9]*$ ]]; then
    echo "First argument must be aspect ratio in this format: 16:9"
    exit 1
fi
AR=$(echo "$AR" | sed "s#:#/#")

if [[ ! -f "$2" ]]; then
    echo "Supply video file as second argument."
    exit 1
fi

inFile=$(realpath "$2")
ouFile=$(echo "$inFile" | sed "s/\.[a-zA-Z]*$/_\0/")

if [[ -f "$ouFile" ]]; then
    echo "Output file already exists: $ouFile"
    exit 1
fi

ffmpeg -nostdin -i "$inFile" -aspect $(bc -l <<< "$AR") -c copy "$ouFile"
