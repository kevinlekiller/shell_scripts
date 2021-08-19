### chassisfancontrol.sh
This script was used for a few years to control the PWM fans using the it87 Super I/O chip on the motherboard.
 
### cfancontrol.c
This was a rewrite of chassisfancontrol.sh in C to reduce CPU usage.

### updateit87.sh
This script was used to install / update the it87 kernel driver module using DKMS.

### ccpfc.c
This was a rewrite of cfancontrol.c for the Corsair Commander Pro, with more fine grained control.
