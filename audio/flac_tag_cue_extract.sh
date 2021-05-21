#!/bin/bash

# Extract cuesheet from vorbis tags in flac files. (for example a flac 
# file containing a whole album with the cue embedded in the tags).

<<About
    Extract embedded cue sheet from tags in flac files. Requires metaflac.
    Deletes existing cue file if found.

    Copyright (C) 2016  kevinlekiller
    
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
About

echo "Warning, this deletes existing cue files if they exist. (does not modify the flac file or embedded cue sheet)"

while read file; do
    filename=$(basename "$file")
    cuefile="$(dirname "$file")/"${filename%.flac}".cue"
    if [[ -f $cuefile ]]; then
        rm "$cuefile"
    fi
    filename=$(echo $filename | sed 's/&/\\&/g')
    tags=$(metaflac --export-tags-to=- "$file" | perl -p0e 's/^.*cuesheet=//s' | perl -p0e 's/\n\n.+$//s' | sed "s/FILE \".*.wav\" WAVE/FILE \"$filename\" FLAC/g" | sed "s/\(REM GENRE \)\([^\"].*\)[\r\n]/\1\"\2\"/g" | sed "s/\(REM COMMENT \)\([^\"].*\)[\r\n]/\1\"\2\"/g")
    if [[ ! $tags ]]; then
        echo "ERROR: Could not get tags from: $file"
        exit 1
    fi
    echo "$tags" > "$cuefile"
    if [[ ! -f $cuefile ]]; then
        echo "ERROR: Could not write tags for: $file"
        exit 1
    fi
    echo -n "."
done < <(find "$@" -type f -iregex ".*\.flac$")
echo ""
