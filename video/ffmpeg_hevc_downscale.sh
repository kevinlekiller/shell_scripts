#!/bin/bash

cat > /dev/null <<LICENSE
    Copyright (C) 2021-2022  kevinlekiller

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

# Simple script to downscale all videos in specified directory (recursively) to be re-encoded to HEVC using ffmpeg.
# If you add more videos to the directory while the script is running, they will also be processed.

# Delete input file after conversion is done. Set to 1 to enable.
DELINFIL=${DELINFIL:-1}
# File extension to use on the output file.
# Affects which container ffmpeg will use.
OUTPUTEXTENSION=${OUTPUTEXTENSION:-mkv}
# Skip files / folders which contain this word in the name.
SKIPFILEMATCH=${SKIPFILEMATCH:-SKIPIT}
# Desired height of the output video in pixels.
OUTHEIGHT=${OUTHEIGHT:-720}
# Minimum allowed bitrate of input video @30fps
# If the video is 60fps for example, then this value is doubled.
# Set to 1 to disable.
MINBITRATE=${MINBITRATE:-3000}
# If a file is too low res, log it here, it will be skipped on the next run.
BITRATELOG=${BITRATELOG:-~/.config/ffmpeg_downscale_$OUTHEIGHT.bitrate}
# Minimun input video height in pixels to convert video.
MININHEIGHT=${MININHEIGHT:-800}
# If a file is too low res, log it here, it will be skipped on the next run.
LOWLOG=${LOWLOG:-~/.config/ffmpeg_downscale_$OUTHEIGHT.low}
# File to store paths to files that have been already converted to
# speed up conversion if script has already been run.
SKIPFILELOG=${SKIPFILELOG:-~/.config/ffmpeg_downscale_$OUTHEIGHT.done}
# Niceness to set ffmpeg to, 19 is lowest priority.
FFMPEGNICE=${FFMPEGNICE:-19}
# Set the amount of threads used by ffmpeg. Setting to 0, ffmpeg will automatically use the optimal amount of threads.
FFMPEGTHREADS=${FFMPEGTHREADS:-0}
# lixb265 CRF value ; ffmpeg default is 28, lower number results in higher image quality
FFMPEGCRF=${FFMPEGCRF:-21}
# libx265 preset value ; ffmpeg default is medium ; see x265 manual for valid values
FFMPEGPRESET=${FFMPEGPRESET:-slow}
# Extra options to send to ffmpeg.
# You can limit the amount of threads x265 uses with the pools parameter
# For example -x265-params log-level=error:aq-mode=3:pools=2
# https://x265.readthedocs.io/en/master/cli.html
# https://x265.readthedocs.io/en/master/presets.html
# https://forum.doom9.org/showthread.php?t=16881
FFMPEGEXTRA=${FFMPEGEXTRA:--x265-params log-level=error:me=umh:rc-lookahead=30:aq-mode=3}
# -vf options to set to ffmpeg. ; lanczos results in a bit sharper downscaling
FFMPEGVF=${FFMPEGVF:--vf scale=-2:$OUTHEIGHT:flags=lanczos}
# Scales the video to DAR (display aspect ratio) if SAR (sample aspect ratio) and DAR are different.
# For example, with OUTHEIGHT at 720, a 1440x1080 Bluray with an SAR of 4:3 and a DAR of 16:9 will be scaled to 1280x720.
# If the option is set empty, the video will retain the original SAR ; using the above example
# of 1440x1080, SAR 4:3 and DAR 16:9,the output video will be scaled to 960x720.
ASPECTCHANGE=${ASPECTCHANGE:-1}
# -c:v options
FFMPEGCV=${FFMPEGCV:--c:v libx265}
# -c:s options, set to copy to avoid re-encoding.
# srt assures compatibility with matroska.
FFMPEGCS=${FFMPEGCS:--c:s srt}
# -c:a options, set to copy to avoid re-encoding.
FFMPEGCA=${FFMPEGCA:--c:a libopus -b:a 64k -vbr on -compression 10 -frame_duration 60 -ac 2}
# Log converted files to this file:
CONVERSIONLOG=${CONVERSIONLOG:-~/.config/ffmpeg_downscale_$OUTHEIGHT.tsv}
# Checks if video is interlaced and deinterlaces it.
# Set the vf filter to pass to ffmpeg to enable. Set empty to disable deinterlacing.
FFMPEGVFD=${FFMPEGVFD:--vf estdif,scale=-2:$OUTHEIGHT:flags=lanczos}
# If the file name contains this word, the file will be deinterlaced.
# If not, the script will atempt to detect interlacing with the settings provided below.
DEINTERLACEKEYWORD=${DEINTERLACEKEYWORD:-_DEINT_}
# Set the amount of video frames to check for interlacing.
# More frames increases accuracy, but takes longer to process.
# Set to 0 to disable interlacing detection.
DEINTERLACEFRAMES=${DEINTERLACEFRAMES:-600}
# Set the threshold percentage to enable interlacing.
# For example, if set to 40, then if 33% of the frames are interlaced, the
# deinterlacing vf filter will be enabled.
DEINTERLACETHRES=${DEINTERLACETHRES:-40}
# Log of files that have been deinterlaced.
DEINTERLACELOG=${DEINTERLACELOG:-~/.config/ffmpeg_downscale_$OUTHEIGHT.deint}
# (If DELINFIL is enabled) Delete input files after deinterlacing. Set to 1 to enable.
DEINTERLACEDELETE=${DEINTERLACEDELETE:-0}
# The new file must be at least this percentage smaller than the original file.
# Deletes the new file and add the original file to SKIPFILELOG
# For example if this is set to 5, the original file is 1000MiB, the new file will be deleted if it's 950MiB or bigger.
# Set to 0 to disable
SIZECHECK=${SIZECHECK:-5}
# Check the file's extension against a (case insensitive) regex.
# If the file does not match this regex it will be skipped.
# Set to "" to disable.
EXTREGEX=${EXTREGEX:-"\.(3gp|3g2|avi|flv|m2t|m2ts|m4v|mov|mp4|mpg|mpeg|mkv|vob|webm|wmv)$"}

if [[ ! -d $1 ]]; then
    echo "Supply folder as first argument."
    exit 1
fi

trap catchExit SIGHUP SIGINT SIGQUIT SIGTERM
function catchExit() {
    if [[ $success == 0 && -f $ouFile ]]; then
        rm -f "$ouFile"
    fi
    exit 0
}

echoColors=$(tput colors 2> /dev/null)
[[ -n $echoColors && $echoColors -ge 8 ]] && echoColors=1 || echoColors=0
function echoCol {
    curTime=$(date +'%Y %b %d %H:%M:%S')
    if [[ $echoColors != 1 ]]; then
        echo "[$curTime] $1"
        return
    fi
    case $2 in
        red) echo -ne "\e[31m";;
        green) echo -ne "\e[32m";;
        brown) echo -ne "\e[33m";;
        blue) echo -ne "\e[34m";;
    esac
    echo -e "[$curTime] $1\e[0m"
}

if [[ ! $FFMPEGTHREADS =~ ^[0-9]+$ ]] || [[ $FFMPEGTHREADS -lt 0 ]]; then
    echoCol "Error: FFMPEGTHREADS must be a number at minimum 0." red
    exit 1
fi
if [[ ! $FFMPEGNICE =~ ^[0-9]+$ ]] || [[ $FFMPEGNICE -gt 19 ]] || [[ $FFMPEGNICE -lt 0 ]]; then
    echoCol "Error: FFMPEGNICE must be a number between 0 and 19." red
    exit 1
fi
if [[ ! $MINBITRATE =~ ^[0-9]+$ ]] || [[ $MINBITRATE -lt 1 ]]; then
    echoCol "Error: MINBITRATE must be a number at minimum 1." red
    exit 1
fi
if [[ ! $MININHEIGHT =~ ^[0-9]+$ ]] || [[ $MININHEIGHT -lt 1 ]]; then
    echoCol "Error: MININHEIGHT must be a number at minimum 1." red
    exit 1
fi
if [[ ! $OUTHEIGHT =~ ^[0-9]*[02468]$ ]] || [[ $OUTHEIGHT -lt 2 ]]; then
    echoCol "Error: OUTHEIGHT must be a number divisible by 2 and at minimum 2." red
    exit 1
fi
if [[ $DEINTERLACETHRES -gt 100 || $DEINTERLACETHRES -lt 1 ]]; then
    echoCol "Error: DEINTERLACETHRES must be a number from 1 to 100." red
    exit 1
fi
if [[ $DEINTERLACEFRAMES -lt 0 ]]; then
    echoCol "Error: DEINTERLACEFRAMES must be at minimum 0." red
    exit 1
fi
if [[ -n $CONVERSIONLOG ]] && [[ ! -f $CONVERSIONLOG ]]; then
    echo -e "Time\tInput File\tInput File Size\tOutput File\tOutput File Size\tConversion time" > "$CONVERSIONLOG"
fi
if [[ ! $SIZECHECK =~ ^[0-9]+$ ]] || [[ $SIZECHECK -lt 1 ]]; then
    SIZECHECK=0
fi
if [[ $SIZECHECK -gt 100 ]]; then
    SIZECHECK=100
fi

cd "$1" || exit

DEINTERLACETHRES=$(bc -l <<< "($DEINTERLACEFRAMES*0.$DEINTERLACETHRES)+0.5" | cut -d\. -f1)
if [[ ! $DEINTERLACETHRES =~ ^[0-9]+$ ]]; then
    $DEINTERLACETHRES=1
fi
function checkDeinterlace {
    if [[ $DEINTERLACEFRAMES == 0 ]]; then
        return
    fi
    idetData="$(ffmpeg -nostdin -y -hide_banner -vf select="between(n\,900\,$((900+$DEINTERLACEFRAMES))),setpts=PTS-STARTPTS",idet -frames:v $DEINTERLACEFRAMES -an -f null - -i "$inFile" 2>&1)"
    for frameType in "Single" "Multi"; do
        NTFF=$(echo "$idetData" | grep -Poi "$frameType frame detection:\s*TFF:\s*\d+" | grep -Po "\d+")
        NBFF=$(echo "$idetData" | grep -Poi "$frameType frame detection:.+?BFF:\s*\d+" | grep -Po "BFF:\s*\d+" | grep -Po "\d+")
        if [[ $((NTFF+NBFF)) -ge $DEINTERLACETHRES ]]; then
            INTERLACED=1
            return
        fi
    done
}

shopt -s globstar nocasematch
while true; do
    filesProcessed=0
    for inFile in **; do
        if [[ ! -f $inFile ]]; then
            continue
        fi
        if [[ $EXTREGEX != "" ]] && [[ ! $inFile =~ ${EXTREGEX} ]]; then
            echoCol "Skipping file \"$inFile\". Does not match EXTREGEX." "blue"
            continue
        fi
        if [[ $inFile =~ $SKIPFILEMATCH ]]; then
            echoCol "Skipping file \"$inFile\". Matched on \"$SKIPFILEMATCH\"." "blue"
            continue
        fi
        # Remove resolution from filename, add new resolution / codec name.
        ouFile=$(echo "$inFile" | sed -E "s/[^A-Za-z0-9][0-9]{3,4}[pрPiI]([^A-Za-z0-9])/\1/g" | sed -E "s/\.[^\.]+$/ ${OUTHEIGHT}p HEVC.$OUTPUTEXTENSION/" | sed -E "s/ +/ /g")
        success=0
        # If both the input and output files are still the same name, append _.
        if [[ "$inFile" == "$ouFile" ]]; then
            ouFile="$(echo "$ouFile" | sed "s/\.$OUTPUTEXTENSION$/_.$OUTPUTEXTENSION/")"
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
        details=$(ffprobe -hide_banner -select_streams v:0 -show_entries stream=width,height,codec_name,r_frame_rate "$inFile" 2>&1)
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
        height=$(echo "$details" | grep -m1 -Po "height=\d+" | cut -d= -f2)
        width=$(echo "$details" | grep -m1 -Po "width=\d+" | cut -d= -f2)
        if [[ $height == "" ]] || [[ $height -le $MININHEIGHT ]]; then
            echoCol "Resolution of input video is too low: height is $height, minimum is $MININHEIGHT. Skipping. \"$inFile\"" "blue"
            if [[ -n $LOWLOG ]]; then
                echo "$inFile" >> "$LOWLOG"
            fi
            continue
        fi
        if [[ $MINBITRATE -gt 1 ]]; then
            bitRate=$(echo "$details" | grep -m1 -Po "Duration: .*? bitrate: \d+" | grep -o "bitrate: [0-9]*" | cut -d\  -f2)
            frameRate=$(echo "$details" | grep -m1 -Po "r_frame_rate=[\d/]+" | cut -d= -f2)
            minBitRate=$(bc -l <<< "((($frameRate)/30)*$MINBITRATE)+0.5" | cut -d\. -f1)
            if [[ $bitRate =~ ^[0-9]*$ ]] && [[ $frameRate =~ ^[0-9]*\/[0-9]*$ ]] && [[ $bitRate -lt $minBitRate ]]; then
                echoCol "Bitrate of input video is too low, bitrate is $bitRate, minimum is $minBitRate. Skipping. \"$inFile\"" "blue"
                if [[ -n $BITRATELOG ]]; then
                    echo "$inFile" >> "$BITRATELOG"
                fi
                continue
            fi
            echoCol "MINBITRATE: Input Video bitrate ($bitRate kb/s) is higher than required minimum bitrate ($minBitRate kb/s <- (($frameRate)/30)*$MINBITRATE)." "green"
        fi
        INTERLACED=0
        if [[ -n $FFMPEGVFD ]]; then
            [[ $inFile =~ $DEINTERLACEKEYWORD ]] && INTERLACED=1 || checkDeinterlace
        fi
        [[ $INTERLACED == 1 ]] && VFTEMP=$FFMPEGVFD || VFTEMP=$FFMPEGVF
        SAR=$(echo "$details" | grep -Po "SAR \d+:\d+" | cut -d\  -f2)
        DAR=$(echo "$details" | grep -Po "DAR \d+:\d+" | cut -d\  -f2)
        if [[ $ASPECTCHANGE == 1 && $SAR != $DAR && $SAR =~ ^[0-9]+:[0-9]+$ && $DAR =~ ^[0-9]+:[0-9]+$ ]]; then
            LDAR=$(echo "$DAR" | cut -d\: -f1)
            RDAR=$(echo "$DAR" | cut -d\: -f2)
            oWidth=$(bc -l <<< "($OUTHEIGHT/$RDAR*$LDAR)+0.5" | cut -d\. -f1)
            if [[ $oWidth =~ [0-9]+ ]]; then
                # libx265 needs a number divisible by 2.
                if [[ $oWidth =~ [13579]$ ]]; then
                    ((--oWidth))
                fi
                VFTEMP="$(echo "$VFTEMP" | sed -E "s/-?[0-9]+:$OUTHEIGHT/$oWidth:$OUTHEIGHT/") -aspect $DAR"
            fi
        fi
        [[ $SAR == "" ]] && SAR="N/A"
        [[ $DAR == "" ]] && DAR="N/A"
        START=$(date +%s)
        echoCol "Converting \"$inFile\" to \"$ouFile\". $(echo "$details" | grep -Po "Duration: [\d:.]+") ; Resolution: ${width}x${height} (SAR: $SAR | DAR: $DAR) ; Video is$(if [[ $INTERLACED == 0 ]]; then echo " not"; fi) interlaced." "brown"
        ffmpegCmd=(
            nice -n $FFMPEGNICE
            ffmpeg -nostdin -loglevel error -stats -hide_banner -y
            -i "$inFile"
            $VFTEMP
            -c:d copy
            $FFMPEGCS
            $FFMPEGCA
            $FFMPEGCV
            $FFMPEGEXTRA
            -preset $FFMPEGPRESET
            -crf $FFMPEGCRF
            -threads $FFMPEGTHREADS
            "$ouFile"
        )
        echoCol "$(echo "${ffmpegCmd[@]}" | xargs)" "brown"
        "${ffmpegCmd[@]}"
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
            success=1
            if [[ -n $CONVERSIONLOG ]]; then
                echo -e "[$(date)]\t$inFile\t$origSize\t$ouFile\t$endSize\t$ENDT" >> "$CONVERSIONLOG"
            fi
            if [[ $DELINFIL -eq 1 ]]; then
                if [[ $INTERLACED == 0 ]] || [[ $INTERLACED == 1 && $DEINTERLACEDELETE == 1 ]]; then
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
            if [[ $INTERLACED == 1 && -n $DEINTERLACELOG ]]; then
                if [[ $DEINTERLACEDELETE == 1 ]]; then
                    echo "$ouFile" >> "$DEINTERLACELOG"
                else
                    echo "$inFile  ->  $ouFile" >> "$DEINTERLACELOG"
                fi
            fi
            ((++filesProcessed))
        else
            rm -f "$ouFile"
            echoCol "Failed to convert video \"$inFile\"." "red"
        fi
    done
    if [[ $filesProcessed == 0 ]]; then
        break
    fi
    echoCol "Processed $filesProcessed files." "green"
    echoCol "Sleeping 5 seconds to check for new files." "green"
    sleep 5
done
