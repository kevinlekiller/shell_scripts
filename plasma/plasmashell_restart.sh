#!/bin/bash

kquitapp5 plasmashell &> /dev/null
if pgrep plasmashell$ &> /dev/null; then
    pkill plasmashell$
fi
kstart5 plasmashell &> /dev/null
