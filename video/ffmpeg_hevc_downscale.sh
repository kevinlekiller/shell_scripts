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
# If a file is too low res, log it here, it will be skipped on the next run.
LOWLOG=${LOWLOG:-~/.config/ffmpeg_downscale.low}
# Log converted files to this file:
CONVERSIONLOG=${CONVERSIONLOG:-~/.config/ffmpeg_downscale.tsv}
# Checks if video is interlaced and deinterlaces it.
# Set the vf filter to pass to ffmpeg to enable. Set empty to disable.
DEINTERLACE=${DEINTERLACE:-yadif=1}
# Log of files that have been deinterlaced.
DEINTERLACELOG=${DEINTERLACELOG:-~/.config/ffmpeg_downscale.deint}
# (If DELINFIL is enabled) Delete input files after deinterlacing. Set to 1 to enable.
DEINTERLACEDELETE=${DEINTERLACEDELETE:-0}
# If the new file is bigger than the original file, delete the new file and add the original file to SKIPFILELOG
SIZECHECK=${SIZECHECK:-1}

if [[ ! -d $1 ]]; then
    echo "Supply folder as first argument."
    exit 1
fi

trap catchExit SIGHUP SIGINT SIGQUIT SIGFPE SIGTERM
function catchExit() {
    exit 0
}

function checkDeinterlace {
    if [[ -z $DEINTERLACE ]]; then
        return
    fi
    idetData="$(ffmpeg -hide_banner -vf select="between(n\,100\,300),setpts=PTS-STARTPTS",idet -frames:v 200 -an -f rawvideo -y /dev/null -i "$inFile" 2>&1)"
    for fieldType in "Single" "Multi"; do
        for fieldOrder in "TFF" "BFF"; do
            if [[ $(echo "$idetData" | grep -Po "$fieldType frame detection:.*" | grep -Po "$fieldOrder:\s*\d+" | grep -o "[0-9]*") -gt 0 ]]; then
                if [[ -n $VFTEMP ]]; then
                    VFTEMP="$VFTEMP,$DEINTERLACE"
                else
                    VFTEMP="$DEINTERLACE"
                fi
                return
            fi
        done
    done
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
    VFTEMP="$FFMPEGVF"
    DETECTEDINTERLACE=0
    checkDeinterlace
    START=$(date +%s)
    echo "Converting \"$inFile\" to \"$ouFile\". File $(echo "$details" | grep -Po "Duration: [\d:.]+")"
    if [[ $DETECTEDINTERLACE == 1 ]]; then
        echo "Video has been detected to be interlaced."
    fi
    nice -n $FFMPEGNICE ffmpeg \
        -loglevel error \
        -stats -hide_banner -y \
        -i "$inFile" \
        -vf "$VFTEMP" \
        -c:v libx265 \
        $FFMPEGEXTRA \
        -preset "$FFMPEGPRESET" \
        -crf "$FFMPEGCRF" \
        -c:a copy \
        -c:s copy \
        "$ouFile"
    if [[ $? == 0 ]]; then
        ENDT=$(date -d@$(($(date +%s) - START)) -u +%Hh:%Mm:%Ss)
        origSize=$(stat --format=%s "$inFile")
        endSize=$(stat --format=%s "$ouFile")
        echo "Finished converting in $ENDT. Orignal size: $((origSize/1024/1024))MiB, new size: $((endSize/1024/1024))MiB."
        if [[ $SIZECHECK == 1 ]] && [[ $endSize -ge $origSize ]]; then
            echo "New file is larger than original file. Deleting new file."
            rm "$ouFile"
            echo "$inFile" >> "$SKIPFILELOG"
            continue
        fi
        if [[ -n $CONVERSIONLOG ]]; then
            echo -e "[$(date)]\t$inFile\t$origSize\t$ouFile\t$endSize\t$ENDT" >> "$CONVERSIONLOG"
        fi
        if [[ $DELINFIL -eq 1 ]]; then
            if [[ $DETECTEDINTERLACE == 0 ]] || [[ $DETECTEDINTERLACE == 1 && $DEINTERLACEDELETE == 1 ]]; then
                echo "Deleting input file \"$inFile\"."
                rm "$inFile"
            fi
        elif [[ -n $SKIPFILELOG ]]; then
            echo "$inFile" >> "$SKIPFILELOG"
        fi
        if [[ -n $SKIPFILELOG ]]; then
            echo "$ouFile" >> "$SKIPFILELOG"
        fi
        if [[ $DETECTEDINTERLACE == 1 && -n $DEINTERLACELOG ]]; then
            if [[ $DEINTERLACEDELETE == 1 ]]; then
                echo "$ouFile" >> "$DEINTERLACELOG"
            else
                echo -e "$inFile  ->  $ouFile" >> "$DEINTERLACELOG"
            fi
        fi
    else
        rm -f "$ouFile"
        echo "Failed to convert video \"$inFile\"."
    fi
done
