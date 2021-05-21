#!/bin/bash

cat > /dev/null <<LICENSE
    Copyright (C) 2021  kevinlekiller
    
    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation; either version 2
    of the License, or (at your option) any later version.
    
    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
    
    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
    https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html
LICENSE

# Simple script to downscale all videos in specified directory to be re-encoded to HEVC using ffmpeg.

# Delete input file after conversion is done. Set to 1 to enable.
DELINFIL=${DELINFIL:-1}
# Skip files / folders which contain this word in the name.
SKIPFILEMATCH=${SKIPFILEMATCH:-SKIPIT}
# Minimun video height to convert video.
MININHEIGHT=${MININHEIGHT:-900}
# Desired height of the output video in pixels.
OUTHEIGHT=${OUTHEIGHT:-720}
# File to store paths to files that have been already converted to
# speed up conversion if script has already been run.
SKIPFILELOG=${SKIPFILELOG:-~/.config/ffmpeg_downscale.done}
# Niceness to set ffmpeg to, 20 is lowest priority.
FFMPEGNICE=${FFMPEGNICE:-20}
# lixb265 CRF value ; ffmpeg default is 28, lower number results in higher image quality
FFMPEGCRF=${FFMPEGCRF:-20}
# libx265 preset value ; ffmpeg default is medium ; see x265 manual for valid values
FFMPEGPRESET=${FFMPEGPRESET:-medium}
# Extra options to send to ffmpeg. ; aq-mode=3 is better for 8 bit content
FFMPEGEXTRA=${FFMPEGEXTRA:--x265-params log-level=error:aq-mode=3}
# vf options to set to ffmpeg. ; lanczos results in a bit sharper downscaling
FFMPEGVF=${FFMPEGVF:-scale=-2:$OUTHEIGHT:flags=lanczos}
# Log file to put files that are too low res, on future runs on the script they are skipped.
LOWLOG=${LOWLOG:-~/.config/ffmpeg_downscale.low}
# Succesfully completed files are logged here.
CONVERSIONLOG=${CONVERSIONLOG:-~/.config/ffmpeg_downscale.tsv}

if [[ ! -d $1 ]]; then
    echo "Supply folder as first argument."
    exit 1
fi

trap catchExit SIGHUP SIGINT SIGQUIT SIGFPE SIGTERM
function catchExit() {
    exit 0
}

if [[ ! $FFMPEGNICE =~ ^[0-9]*$ ]] || [[ $FFMPEGNICE -gt 20 ]] || [[ $FFMPEGNICE -lt 0 ]]; then
    FFMPEGNICE=20
fi

if [[ ! $MININHEIGHT =~ ^[0-9]*$ ]] || [[ $MININHEIGHT -lt 1 ]]; then
    MININHEIGHT=900
fi
if [[ ! $OUTHEIGHT =~ ^[0-9]*$ ]] || [[ $OUTHEIGHT -lt 1 ]]; then
    OUTHEIGHT=720
fi
if [[ -n $CONVERSIONLOG ]] && [[ ! -f $CONVERSIONLOG ]]; then
    echo -e "Time\tInput File\tInput File Size\tOutput File\tOutput File Size\tConversion time" > "$CONVERSIONLOG"
fi

cd "$1" || exit
shopt -s globstar
for inFile in **; do
    if [[ ! -f $inFile ]]; then
        continue
    fi
    if [[ $inFile =~ $SKIPFILEMATCH ]]; then
        echo "Skipping file \"$inFile\". Matched on \"$SKIPFILEMATCH\"."
        continue
    fi
    ouFile=$(echo "$inFile" | sed -E "s/ (360|480|540|720|1080|2160)[pр]//" | sed -E "s/\.[^\.]+$/ ${OUTHEIGHT}p HEVC.mkv/")
    if [[ -f $SKIPFILELOG ]]; then
        if grep -Fxq  "$ouFile" "$SKIPFILELOG" || grep -Fxq "$inFile" "$SKIPFILELOG"; then
            echo "Already converted \"$inFile\". Skipping."
            continue
        fi
    fi
    if [[ -f $LOWLOG ]] && grep -Fxq  "$inFile" "$LOWLOG"; then
        echo "Resolution too low: \"$inFile\". Skipping."
        continue
    fi
    details=$(ffprobe -hide_banner -show_entries stream=height,codec_name "$inFile" 2>&1)
    if [[ $details =~ codec_name=([xh]265|hevc) ]]; then
        echo "Codec is $(echo "$details" | grep -Po "codec_name=([xh]265|hevc)" | cut -d= -f2) for file \"$inFile\". Skipping."
        if [[ -n $SKIPFILELOG ]]; then
            if [[ ! $ouFile =~ "HEVC 720p HEVC" ]]; then
                echo "$ouFile" >> "$SKIPFILELOG"
            fi
            echo "$inFile" >> "$SKIPFILELOG"
        fi
        continue
    fi
    height=$(echo "$details" | grep -Po "height=\d+" | cut -d= -f2)
    if [[ $height == "" ]] || [[ $height -le $MININHEIGHT ]]; then
        echo "Resolution of video is too low: height is $height, minimum is $MININHEIGHT. Skipping. \"$inFile\""
        if [[ -n $LOWLOG ]]; then
            echo "$inFile" >> "$LOWLOG"
        fi
        continue
    fi
    START=$(date +%s)
    echo "Converting \"$inFile\" to \"$ouFile\". File $(echo "$details" | grep -Po "Duration: [\d:.]+")"
    nice -n $FFMPEGNICE ffmpeg \
        -loglevel error \
        -stats -hide_banner -y \
        -i "$inFile" \
        -vf "$FFMPEGVF" \
        -c:v libx265 \
        $FFMPEGEXTRA \
        -preset "$FFMPEGPRESET" \
        -crf "$FFMPEGCRF" \
        -c:a copy \
        -c:s copy \
        "$ouFile"
    if [[ $? == 0 ]]; then
        ENDT=$(date -d@$(($(date +%s) - START)) -u +%Hh:%Mm:%Ss)
        origSize=$(du -h "$inFile" | grep -Po "^\S+")
        endSize=$(du -h "$ouFile" | grep -Po "^\S+")
        echo "Finished converting in $ENDT. Orignal size: $origSize, new size: $endSize."
        if [[ -n $CONVERSIONLOG ]]; then
            echo -e "[$(date)]\t$inFile\t$origSize\t$ouFile\t$endSize\t$ENDT" >> "$CONVERSIONLOG"
        fi
        if [[ $DELINFIL -eq 1 ]]; then
            echo "Deleting input file \"$inFile\"."
            rm "$inFile"
        elif [[ -n $SKIPFILELOG ]]; then
            echo "$inFile" >> "$SKIPFILELOG"
        fi
        if [[ -n $SKIPFILELOG ]]; then
            echo "$ouFile" >> "$SKIPFILELOG"
        fi
    else
        rm -f "$ouFile"
        echo "Failed to convert video \"$inFile\"."
    fi
done
