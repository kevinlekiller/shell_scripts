#!/bin/bash

# Don't run script if dsp module is already loaded.
if pacmd list-sinks | grep 'name: <dsp' &> /dev/null; then
    exit 0
fi
# Set the wanted audio output device. 
#OUTPUT="iec958"
OUTPUT="hdmi"
#OUTPUT="usb"
while true; do
    # Wait until the audio device loads up.
    if ! pacmd list-sinks | grep -o "name: <alsa.*$OUTPUT" &> /dev/null; then
        sleep 10
        continue
    elif pacmd list-modules | grep -o "module-suspend-on-idle" &> /dev/null; then
        # This module puts the audio device to sleep when inactive, unload it to keeo the audio device always awake.
        # This prevents pop / click noises for me, and prevents videos from playing without sound until the audio device wakes up.
        pacmd unload-module module-suspend-on-idle
    fi
    if ! pacmd list-sinks | grep 'name: <dsp' &> /dev/null; then
        # Load the dsp module.
        pacmd load-module module-ladspa-sink sink_name=dsp sink_master="$(pacmd list-sinks | grep -o "name: <alsa.*$OUTPUT.*" | cut -d \  -f2 | tr -d '<>')" plugin=ladspa_dsp label=ladspa_dsp
    fi
    sleep 120
done
