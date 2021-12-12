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
# Minimun allowed bitrate of input video @30fps
# If the video is 60fps for example, then this value is doubled.
# Set to 1 to disable.
MINBITRATE=${MINBITRATE:-3000}
# If a file is too low res, log it here, it will be skipped on the next run.
BITRATELOG=${BITRATELOG:-~/.config/ffmpeg_downscale.bitrate}
# Minimun input video height in pixels to convert video.
MININHEIGHT=${MININHEIGHT:-800}
# If a file is too low res, log it here, it will be skipped on the next run.
LOWLOG=${LOWLOG:-~/.config/ffmpeg_downscale.low}
# Desired height of the output video in pixels.
OUTHEIGHT=${OUTHEIGHT:-720}
# File to store paths to files that have been already converted to
# speed up conversion if script has already been run.
SKIPFILELOG=${SKIPFILELOG:-~/.config/ffmpeg_downscale.done}
# Niceness to set ffmpeg to, 19 is lowest priority.
FFMPEGNICE=${FFMPEGNICE:-19}
# Set the amount of threads used by ffmpeg. Setting to 0, ffmpeg will automatically use the optimal amount of threads.
FFMPEGTHREADS=${FFMPEGTHREADS:-0}
# lixb265 CRF value ; ffmpeg default is 28, lower number results in higher image quality
FFMPEGCRF=${FFMPEGCRF:-19}
# libx265 preset value ; ffmpeg default is medium ; see x265 manual for valid values
FFMPEGPRESET=${FFMPEGPRESET:-medium}
# Extra options to send to ffmpeg. ; aq-mode=3 is better for 8 bit content
# You can limit the amount of threads x265 uses with the pools parameter
# For example -x265-params log-level=error:aq-mode=3:pools=2
FFMPEGEXTRA=${FFMPEGEXTRA:--x265-params log-level=error:aq-mode=3}
# vf options to set to ffmpeg. ; lanczos results in a bit sharper downscaling
FFMPEGVF=${FFMPEGVF:-scale=-2:$OUTHEIGHT:flags=lanczos}
# Log converted files to this file:
CONVERSIONLOG=${CONVERSIONLOG:-~/.config/ffmpeg_downscale.tsv}
# Checks if video is interlaced and deinterlaces it.
# Set the vf filter to pass to ffmpeg to enable. Set empty to disable.
DEINTERLACE=${DEINTERLACE:-yadif=1}
# Log of files that have been deinterlaced.
DEINTERLACELOG=${DEINTERLACELOG:-~/.config/ffmpeg_downscale.deint}
# (If DELINFIL is enabled) Delete input files after deinterlacing. Set to 1 to enable.
DEINTERLACEDELETE=${DEINTERLACEDELETE:-0}
# The new file must be at least this percentage smaller than the original file.
# Deletes the new file and add the original file to SKIPFILELOG
# For example if this is set to 5, the original file is 1000MiB, the new file will be deleted if it's 950MiB or bigger.
# Set to 0 to disable
SIZECHECK=${SIZECHECK:-5}

if [[ ! -d $1 ]]; then
    echo "Supply folder as first argument."
    exit 1
fi

trap catchExit SIGHUP SIGINT SIGQUIT SIGFPE SIGTERM
function catchExit() {
    exit 0
}

if [[ ! $FFMPEGTHREADS =~ ^[0-9]*$ ]] || [[ $FFMPEGTHREADS -lt 0 ]]; then
    FFMPEGTHREADS=0
fi
if [[ ! $FFMPEGNICE =~ ^[0-9]*$ ]] || [[ $FFMPEGNICE -gt 19 ]] || [[ $FFMPEGNICE -lt 0 ]]; then
    FFMPEGNICE=19
fi
if [[ ! $MINBITRATE =~ ^[0-9]*$ ]] || [[ $MINBITRATE -lt 1 ]]; then
    MINBITRATE=3000
fi
if [[ ! $MININHEIGHT =~ ^[0-9]*$ ]] || [[ $MININHEIGHT -lt 1 ]]; then
    MININHEIGHT=800
fi
if [[ ! $OUTHEIGHT =~ ^[0-9]*$ ]] || [[ $OUTHEIGHT -lt 1 ]]; then
    OUTHEIGHT=720
fi
if [[ -n $CONVERSIONLOG ]] && [[ ! -f $CONVERSIONLOG ]]; then
    echo -e "Time\tInput File\tInput File Size\tOutput File\tOutput File Size\tConversion time" > "$CONVERSIONLOG"
fi
if [[ ! $SIZECHECK =~ ^[0-9]*$ ]] || [[ $SIZECHECK -lt 1 ]]; then
    SIZECHECK=0
fi
if [[ $SIZECHECK -gt 100 ]]; then
    SIZECHECK=100
fi

cd "$1" || exit

function checkDeinterlace {
    if [[ -z $DEINTERLACE ]]; then
        return
    fi
    idetData="$(ffmpeg -nostdin -y -hide_banner -vf select="between(n\,900\,1100),setpts=PTS-STARTPTS",idet -frames:v 200 -an -f null - -i "$inFile" 2>&1)"
    for frameType in "Single" "Multi"; do
        for frameOrder in "TFF" "BFF"; do
            if [[ $(echo "$idetData" | grep -Po "$frameType frame detection:.*" | grep -Po "$frameOrder:\s*\d+" | grep -o "[0-9]*") -gt 0 ]]; then
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

echoColors=$(tput colors 2> /dev/null)
[[ -n $echoColors && $echoColors -ge 8 ]] && echoColors=1 || echoColors=0
function echoCol {
    if [[ $echoColors != 1 ]]; then
        echo "$1"
        return
    fi
    case $2 in
        red) echo -ne "\e[31m";;
        green) echo -ne "\e[32m";;
        brown) echo -ne "\e[33m";;
        blue) echo -ne "\e[34m";;
    esac
    echo -e "$1\e[0m"
}

shopt -s globstar
for inFile in **; do
    if [[ ! -f $inFile ]]; then
        continue
    fi
    if [[ $inFile =~ $SKIPFILEMATCH ]]; then
        echoCol "Skipping file \"$inFile\". Matched on \"$SKIPFILEMATCH\"." "blue"
        continue
    fi
    # Remove resolution from filename, add new resolution / codec name.
    ouFile=$(echo "$inFile" | sed -E "s/[^A-Za-z0-9](360|480|540|720|1080|2160)[pр]//g" | sed -E "s/\.[^\.]+$/ ${OUTHEIGHT}p HEVC.mkv/")
    # If both the input and output files are still the same name, append _.
    if [[ "$inFile" == "$ouFile" ]]; then
        ouFile="${ouFile}_"
    fi
    if [[ -f $SKIPFILELOG ]]; then
        if grep -Fxq  "$ouFile" "$SKIPFILELOG" || grep -Fxq "$inFile" "$SKIPFILELOG"; then
            echoCol "Already converted \"$inFile\". Skipping." "blue"
            continue
        fi
    fi
    if [[ -f $LOWLOG ]] && grep -Fxq  "$inFile" "$LOWLOG"; then
        echoCol "Resolution too low: \"$inFile\". Skipping." "blue"
        continue
    fi
    if [[ -f $BITRATELOG ]] && grep -Fxq "$inFile" "$BITRATELOG"; then
        echoCol "Bitrate too low: \"$inFile\". Skipping." "blue"
        continue
    fi
    # Create output and parent directoties if they don't exist.
    if [[ ! -f $ouFile ]]; then
        mkdir -p "$ouFile"
        if [[ -d $ouFile ]]; then
            rmdir "$ouFile"
        fi
    fi
    details=$(ffprobe -hide_banner -select_streams v:0  -show_entries stream=height,codec_name,r_frame_rate "$inFile" 2>&1)
    if [[ $details =~ codec_name=([xh]265|hevc) ]]; then
        echoCol "Codec is $(echo "$details" | grep -Po "codec_name=([xh]265|hevc)" | cut -d= -f2) for file \"$inFile\". Skipping." "blue"
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
        echoCol "Resolution of input video is too low: height is $height, minimum is $MININHEIGHT. Skipping. \"$inFile\"" "blue"
        if [[ -n $LOWLOG ]]; then
            echo "$inFile" >> "$LOWLOG"
        fi
        continue
    fi
    if [[ $MINBITRATE -gt 1 ]]; then
        bitRate=$(echo "$details" | grep -Po "Duration: .*? bitrate: \d+" | grep -o "bitrate: [0-9]*" | cut -d\  -f2)
        frameRate=$(echo "$details" | grep -Po "r_frame_rate=[\d/]+" | cut -d= -f2)
        minBitRate=$(bc -l <<< \(\("$frameRate"\)/30\)*"$MINBITRATE")
        minBitRate=${minBitRate%.*}
        if [[ $bitRate =~ ^[0-9]*$ ]] && [[ $frameRate =~ ^[0-9]*\/[0-9]*$ ]] && [[ $bitRate -lt $minBitRate ]]; then
            echoCol "Bitrate of input video is too low, bitrate is $bitRate, minimum is $minBitRate. Skipping. \"$inFile\"" "blue"
            if [[ -n $BITRATELOG ]]; then
                echo "$inFile" >> "$BITRATELOG"
            fi
            continue
        fi
        echoCol "MINBITRATE: Input Video bitrate ($bitRate kb/s) is higher than required minimum bitrate ($minBitRate kb/s <- (($frameRate)/30)*$MINBITRATE)." "green"
    fi
    VFTEMP="$FFMPEGVF"
    DETECTEDINTERLACE=0
    checkDeinterlace
    START=$(date +%s)
    echoCol "Converting \"$inFile\" to \"$ouFile\". File $(echo "$details" | grep -Po "Duration: [\d:.]+")" "brown"
    if [[ $DETECTEDINTERLACE == 1 ]]; then
        echoCol "Video has been detected to be interlaced." "brown"
    fi
    nice -n $FFMPEGNICE ffmpeg \
        -nostdin -loglevel error \
        -stats -hide_banner -y \
        -i "$inFile" \
        -vf "$VFTEMP" \
        -c:d copy -c:s copy -c:a copy \
        -c:v libx265 \
        $FFMPEGEXTRA \
        -preset "$FFMPEGPRESET" \
        -crf "$FFMPEGCRF" \
        -threads "$FFMPEGTHREADS" \
        "$ouFile"
    if [[ $? == 0 ]]; then
        ENDT=$(date -d@$(($(date +%s) - START)) -u +%Hh:%Mm:%Ss)
        origSize=$(stat --format=%s "$inFile")
        endSize=$(stat --format=%s "$ouFile")
        echoCol "Finished converting in $ENDT. Orignal size: $((origSize/1024/1024))MiB, new size: $((endSize/1024/1024))MiB." "green"
        maxSize=$((origSize-origSize*SIZECHECK/100))
        if [[ $SIZECHECK != 0 ]] && [[ $endSize -ge $maxSize ]]; then
            echoCol "New file exceeds size check threshold ($SIZECHECK% -> $((maxSize/1024/1024))MiB). Deleting new file." "red"
            rm "$ouFile"
            echo "$inFile" >> "$SKIPFILELOG"
            continue
        fi
        if [[ -n $CONVERSIONLOG ]]; then
            echo -e "[$(date)]\t$inFile\t$origSize\t$ouFile\t$endSize\t$ENDT" >> "$CONVERSIONLOG"
        fi
        if [[ $DELINFIL -eq 1 ]]; then
            if [[ $DETECTEDINTERLACE == 0 ]] || [[ $DETECTEDINTERLACE == 1 && $DEINTERLACEDELETE == 1 ]]; then
                echoCol "Deleting input file \"$inFile\"." "blue"
                rm "$inFile"
                # Check if inFile folder is empty and delete if so.
                if [[ ! $(ls -A "$(dirname "$inFile")") ]]; then
                    rmdir "$(dirname "$inFile")"
                fi
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
                echo "$inFile  ->  $ouFile" >> "$DEINTERLACELOG"
            fi
        fi
    else
        rm -f "$ouFile"
        echoCol "Failed to convert video \"$inFile\"." "red"
    fi
done
