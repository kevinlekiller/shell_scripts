#!/bin/bash

# Get around stupid no paste restriction ; Linux with X

# Get location of username / password box by putting mouse over and running
# the following command:
# xdotool getmouselocation --shell
# Then change the numbers in the xdotool commands based on what you got,
# and change the MyUsername / MyPassword, quote them if needed.

# Username

xdotool mousemove 1871 1215 click 1
str=MyUsername
for (( i=0; i<${#str}; i++ )); do
    xdotool key "${str:$i:1}"
done

# Password

xdotool mousemove 1850 1264 click 1
str=MyPassword
for (( i=0; i<${#str}; i++ )); do
    xdotool key "${str:$i:1}"
done
