#!/bin/bash

if [[ $(pacmd list-sinks | grep -o 'name: <dsp') != "" ]]; then
   exit 0
fi

OUTPUT="iec958"
#OUTPUT="hdmi"
#OUTPUT="usb"

while [[ $(pacmd list-sinks | grep -o "name: <alsa.*$OUTPUT.*") == "" ]]; do
   sleep 5
done

pacmd load-module module-ladspa-sink sink_name=dsp sink_master=$(pacmd list-sinks | grep -o "name: <alsa.*$OUTPUT.*" | cut -d \  -f2 | tr -d '<>') plugin=ladspa_dsp label=ladspa_dsp
