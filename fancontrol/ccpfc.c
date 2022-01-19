/**
 * Copyright (C) 2021-2022  kevinlekiller
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

/**
 * Chassis & CPU fan control using CORSAIR Commander Pro
 *
 * Compile: gcc ccpfc.c -o ccpfc -Wextra -O2 -lm
 * Run : ./ccpfc --help
*/

#include <dirent.h>
#include <fcntl.h>
#include <getopt.h>
#include <math.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// CCP can only control 6 fans.
#define MAXFANS 6
// Sane limit on max amount of temp sensors to monitor.
#define MAXTSEN 8

bool silent = false;
char buf[256];
float interval = 1.0;
int fd;
unsigned char lowTemp = 0, highTemp = 0, smoothUp = 0, smoothDown = 0;
unsigned char highFanSpeed = 0, lowFanSpeed = 0, minFanSpeed = 0, lastFanSpeed = 0;
unsigned char fanLut[99];
char curFans = -1, curTsen = -1;

struct fStruct {
    char path[256];
    int offs;
};
struct fStruct fanArr[MAXFANS];
struct tStruct {
    char path[256];
    int offs;
    int thres;
};
struct tStruct tsenArr[MAXTSEN];

bool writeFile(const char * path, const char * value) {
    ssize_t size = strlen(value);
    fd = open(path, O_RDWR);
    if (fd < 0 || write(fd, value, size) != size) {
        close(fd);
        return false;
    }
    close(fd);
    return true;
}

bool readFile(const char * path, ssize_t size) {
    fd = open(path, O_RDONLY);
    if (fd < 0 || read(fd, buf, size) < 1) {
        close(fd);
        return false;
    }
    close(fd);
    return true;
}

int getMaxTemp() {
    int maxTemp = 0, senTemp = 0;
    for (int i = 0; i <= curTsen; i++) {
        if (!readFile(tsenArr[i].path, 7)) {
            continue;
        }
        senTemp = (int) round(atof(buf) / 1000.0);
        if (senTemp > tsenArr[i].thres) {
            senTemp += tsenArr[i].offs;
        }
        if (senTemp > maxTemp) {
            maxTemp = senTemp;
        }
        if (maxTemp >= highTemp) {
            break;
        }
    }
    return maxTemp;
}

void setFanSpeed() {
    int tmpSpeed, fanSpeed, temp = getMaxTemp();
    if (temp < lowTemp) {
        tmpSpeed = minFanSpeed;
    } else if (fanLut[temp]) {
        tmpSpeed = fanLut[temp];
    } else {
        tmpSpeed = highFanSpeed;
    }
    if (smoothDown && tmpSpeed < lastFanSpeed) {
        tmpSpeed = lastFanSpeed - smoothDown;
        if (tmpSpeed < minFanSpeed) {
            tmpSpeed = minFanSpeed;
        }
    } else if (smoothUp && tmpSpeed > lastFanSpeed) {
        tmpSpeed = lastFanSpeed + smoothUp;
        if (tmpSpeed > highFanSpeed) {
            tmpSpeed = highFanSpeed;
        }
    }
    if (tmpSpeed != lastFanSpeed) {
        for (int i = 0; i <= curFans; i++) {
            fanSpeed = tmpSpeed + fanArr[i].offs;
            if (fanSpeed < 0) {
                fanSpeed = 0;
            } else if (fanSpeed > 255) {
                fanSpeed = 255;
            }
            sprintf(buf, "%d", fanSpeed);
            writeFile(fanArr[i].path, buf);
        }
    }
    if (!silent) {
        printf("\rHighest Temp %2d C -> Fan Speed %3d PWM", temp, tmpSpeed);
        fflush(stdout);
    }
    lastFanSpeed = tmpSpeed;
}

void cleanup() {
    exit(EXIT_SUCCESS);
}

bool fileExists(const char * path) {
    if (path && access(path, F_OK) == 0) {
        return true;
    }
    fprintf(stderr, "ERROR: Could not find file '%s'\n", path);
    return false;
}

bool getHwmonPath(char * name) {
    bool foundPath = false;
    DIR *dir = opendir("/sys/class/hwmon");
    if (!dir) {
        fprintf(stderr, "ERROR: Could not find base hwmon directory.\n");
        return foundPath;
    }
    struct dirent *files;
    char buf2[30];
    while ((files = readdir(dir)) != NULL) {
        if (strstr(files->d_name, "hwmon")) {
            sprintf(buf2, "%s/%s/name", "/sys/class/hwmon", files->d_name);
            if (!readFile(buf2, 50) || strstr(buf, name) == NULL) {
                continue;
            }
            sprintf(buf, "%s/%s", "/sys/class/hwmon", files->d_name);
            foundPath = true;
            break;
        }
    }
    closedir(dir);
    if (!foundPath) {
        fprintf(stderr, "ERROR: Could not find hwmon directory. '%s'\n", foundPath);
    }
    return foundPath;
}

void mkFanLut(bool printLut) {
    float tdiff = (float) (highFanSpeed - lowFanSpeed) / (float) (highTemp - lowTemp);
    float curSpeed = (float) lowFanSpeed;
    int rndSpeed;
    if (!silent && printLut) {
        printf("Temp <= %2d C ; FanSpeed = %3d PWM\n", lowTemp-1, minFanSpeed);
    }
    for (int i = lowTemp; i <= highTemp; i++) {
        rndSpeed = (int) round(curSpeed);
        if (rndSpeed <= lowFanSpeed) {
            fanLut[i] = lowFanSpeed;
        } else if (rndSpeed >= highFanSpeed) {
            fanLut[i] = highFanSpeed;
        } else {
            fanLut[i] = rndSpeed;
        }
        curSpeed += tdiff;
        if (!silent && printLut) {
            printf("Temp == %2d C ; FanSpeed = %3d PWM\n", i, fanLut[i]);
        }
    }
    if (!silent && printLut) {
        printf("Temp >= %2d C ; FanSpeed = %3d PWM\n", highTemp+1, highFanSpeed);
    }
}

void printUsage() {
    printf("Program for controling PWM fans on Linux using the CORSAIR Commander Pro fan controller.\n");
    printf("Options:\n");
    printf(" -h, --help\n");
    printf("   Displays this information.\n");
    printf(" -s, --silent\n");
    printf("   Output nothing to stdout.\n");
    printf(" -i, --interval=FLOAT\n");
    printf("   Loop pause time. (valid: 0.05 to 60) (default: 1.0)\n");
    printf(" -n, --niceness=NUM\n");
    printf("   Set the process priority (niceness). (valid: -20 to 19)\n");
    printf(" -l, --fan-print-lut\n");
    printf("   Print fan LUT and exit.\n");
    printf(" -a, --fan-smooth-up=NUM\n");
    printf("   When increasing fan PWM, go up by NUM per --interval seconds. (valid: 1 to 255)\n");
    printf(" -b, --fan-smooth-down=NUM\n");
    printf("   When decreasing fan PWM, go down by NUM per --interval seconds. (valid: 1 to 255)\n");
    printf(" -c, --fan-speed-min=NUM\n");
    printf("   Fan PWM when temperature is under --fan-temp-low. (valid: 0 to 255)\n");
    printf(" -d, --fan-speed-low=NUM\n");
    printf("   Fan PWM used for fan LUT calculation when temperature at --fan-temp-low. (valid: 1 to 255)\n");
    printf(" -e, --fan-temp-low=NUM\n");
    printf("   Lowest temperature for fan LUT calculation. (valid: 1 to 99)\n");
    printf(" -f, --fan-speed-high=NUM\n");
    printf("   Fan PWM used for fan LUT calculation when temperature at --fan-temp-high. (valid: 1 to 255)\n");
    printf(" -g, --fan-temp-high=NUM\n");
    printf("   Highest temperature for fan LUT calculation. (valid: 1 to 99)\n");
    printf(" -z, --fans=\n");
    printf("   List of CORSAIR Commander Pro PWM fans to control.\n");
    printf("   Must be in this format: --fans=PWM:OFFSET\n");
    printf("   PWM is the file name of fan to control. Get a list of all files: ls /sys/bus/hid/drivers/corsair-cpro/[0-9]*/hwmon/hwmon*/pwm* | grep -o pwm[0-6]\n");
    printf("   OFFSET can be a positive or negative number to apply to the fan's PWM, (valid -128 to 128).\n");
    printf("   Example: --fans=\"pwm1:0;pwm2:5;pwm3:-10\"\n");
    printf(" -t, --temp-sensors=\n");
    printf("   List of hwmon temperature sensors.\n");
    printf("   Must be in this format: --temp-sensors=DEVICE_NAME:SENSOR_NAME:OFFSET:THRES;DEVICE_NAME:SENSOR_NAME:OFFSET:THRES\n");
    printf("   DEVICE_NAME is from the hwmon name file. Get all possible values with: cat /sys/class/hwmon/hwmon*/name\n");
    printf("   SENSOR_NAME is the file name of the temp sensor. Get a list of all files: ls /sys/class/hwmon/hwmon*/temp*_input\n");
    printf("   OFFSET If for example the sensor reads 34C, we can apply a 10C offset so the program thinks it's 44C.\n");
    printf("   THRES Only applies the OFFSET if the sensor is above THRES.\n");
    printf("    This is useful if you have a GPU and want the case fans to spin faster if the GPU is hot and the CPU is cool.\n");
    printf("   Example: --temp-sensors=\"k10temp:temp1_input:0:0;amdgpu:temp1_input:20:42\"\n");
}

int main(int argc, char **argv) {
#ifndef linux
    fprintf(stderr, "ERROR: Operating system must be Linux.\n");
    return 1;
#endif
    signal(SIGQUIT, cleanup);
    signal(SIGINT, cleanup);
    signal(SIGTERM, cleanup);
    signal(SIGHUP, cleanup);
    atexit(cleanup);
    {
        bool printLut = false;
        int c;
        static struct option long_options[] = {
            {"help",                  no_argument,       0, 'h'},
            {"silent",                no_argument,       0, 's'},
            {"interval",              required_argument, 0, 'i'},
            {"niceness",              required_argument, 0, 'n'},
            {"fan-print-lut",         no_argument,       0, 'l'},
            {"fan-smooth-up",         required_argument, 0, 'a'},
            {"fan-smooth-down",       required_argument, 0, 'b'},
            {"fan-speed-min",         required_argument, 0, 'c'},
            {"fan-speed-low",         required_argument, 0, 'd'},
            {"fan-temp-low",          required_argument, 0, 'e'},
            {"fan-speed-high",        required_argument, 0, 'f'},
            {"fan-temp-high",         required_argument, 0, 'g'},
            {"fans",                  required_argument, 0, 'z'},
            {"temp-sensors",          required_argument, 0, 't'},
            {0,                       0,                 0,  0 }
        };
        while (c = getopt_long(argc, argv, "a:b:c:d:e:f:g:hi:j:ln:st:z:", long_options, NULL)) {
            if (c == -1) {
                break;
            }
            switch (c) {
                case 'a':
                    smoothUp = (unsigned char) atoi(optarg);
                    if (smoothUp == 0) {
                        fprintf(stderr, "ERROR: --fan-smooth-up must be between 1 and 255.\n");
                        return EXIT_FAILURE;
                    }
                    break;
                case 'b':
                    smoothDown = (unsigned char) atoi(optarg);
                    if (smoothDown == 0) {
                        fprintf(stderr, "ERROR: --fan-smooth-down must be between 1 and 255.\n");
                        return EXIT_FAILURE;
                    }
                    break;
                case 'c':
                    minFanSpeed = (unsigned short) atoi(optarg);
                    break;
                case 'd':
                    lowFanSpeed = (unsigned short) atoi(optarg);
                    break;
                case 'e':
                    lowTemp = (unsigned char) atoi(optarg);
                    if (lowTemp == 0 || lowTemp > 99) {
                        fprintf(stderr, "ERROR: --fan-temp-low must be between 1 and 99.\n");
                        return EXIT_FAILURE;
                    }
                    break;
                case 'f':
                    highFanSpeed = (unsigned short) atoi(optarg);
                    break;
                case 'g':
                    highTemp = (unsigned char) atoi(optarg);
                    if (highTemp == 0 || highTemp > 99) {
                        fprintf(stderr, "ERROR: --fan-temp-high must be between 1 and 99.\n");
                        return EXIT_FAILURE;
                    }
                    break;
                case 'h':
                    printUsage();
                    return EXIT_SUCCESS;
                case 'i':
                    interval = atof(optarg);
                    if (!interval || interval < 0.05 || interval > 60.0) {
                        fprintf(stderr, "ERROR: --interval must be between 0.05 and 60.0.\n");
                        return EXIT_FAILURE;
                    }
                    break;
                case 'l':
                    printLut = true;
                    break;
                case 'n':
                    int niceness = atoi(optarg);
                    if (niceness < -20 || niceness > 19) {
                        fprintf(stderr, "ERROR: --niceness must be -20 to 19.\n");
                        return EXIT_FAILURE;
                    }
                    nice(niceness);
                    break;
                case 's':
                    silent = true;
                    break;
                case 't': {
                    char * tail1;
                    char * tok1 = strtok_r(optarg, ";", &tail1);
                    while (tok1 != NULL) {
                        if (++curTsen > MAXTSEN) {
                            fprintf(stderr, "ERROR: --temp-sensors : Exceeded maximum allowed temp sensors (%d).\n", MAXTSEN);
                            return EXIT_FAILURE;
                        }
                        char * tail2;
                        char * tok2 = strtok_r(tok1, ":", &tail2);
                        int i = 0;
                        char dev[64];
                        char sen[64];
                        while (tok2 != NULL) {
                            switch (i++) {
                                case 0:
                                    sprintf(dev, "%s", tok2);
                                    break;
                                case 1:
                                    sprintf(sen, "%s", tok2);
                                    break;
                                case 2:
                                    tsenArr[curTsen].offs = atoi(tok2);
                                    break;
                                case 3:
                                    tsenArr[curTsen].thres = atoi(tok2);
                                    break;
                                default:
                                    fprintf(stderr, "ERROR: --temp-sensors : Format exceeds maximum parameters: '%s'\n", tok1);
                                    return EXIT_FAILURE;
                            }
                            tok2 = strtok_r(NULL, ":", &tail2);
                        }
                        if (i < 4) {
                            fprintf(stderr, "ERROR: --temp-sensors : Format contains too few parameters: '%s'\n", tok1);
                            return EXIT_FAILURE;
                        }
                        if (!getHwmonPath(dev)) {
                            return EXIT_FAILURE;
                        }
                        sprintf(tsenArr[curTsen].path, "%s/%s", buf, sen);
                        if (!fileExists(tsenArr[curTsen].path)) {
                            fprintf(stderr, "File not found: %s\n", tsenArr[curTsen].path);
                            return EXIT_FAILURE;
                        }
                        tok1 = strtok_r(NULL, ";", &tail1);
                    }
                    break;
                }
                case 'z': {
                    if (!getHwmonPath("corsaircpro")) {
                        return EXIT_FAILURE;
                    }
                    char * tail1;
                    char * tok1 = strtok_r(optarg, ";", &tail1);
                    while (tok1 != NULL) {
                        if (++curFans > MAXFANS) {
                            fprintf(stderr, "ERROR: --fans : Exceeded maximum allowed fans (%d).\n", MAXFANS);
                            return EXIT_FAILURE;
                        }
                        char * tail2;
                        char * tok2 = strtok_r(tok1, ":", &tail2);
                        int i = 0;
                        char pwm[64];
                        while (tok2 != NULL) {
                            switch (i++) {
                                case 0:
                                    sprintf(pwm, "%s", tok2);
                                    break;
                                case 1:
                                    fanArr[curFans].offs = atoi(tok2);
                                    break;
                                default:
                                    fprintf(stderr, "ERROR: --fans : Format exceeds maximum parameters: '%s'\n", tok1);
                                    return EXIT_FAILURE;
                            }
                            tok2 = strtok_r(NULL, ":", &tail2);
                        }
                        if (i < 2) {
                            fprintf(stderr, "ERROR: --fans : Format contains too few parameters: '%s'\n", tok1);
                            return EXIT_FAILURE;
                        }
                        sprintf(fanArr[curFans].path, "%s/%s", buf, pwm);
                        if (!fileExists(fanArr[curFans].path)) {
                            fprintf(stderr, "File not found: %s\n", fanArr[curFans].path);
                            return EXIT_FAILURE;
                        }
                        tok1 = strtok_r(NULL, ";", &tail1);
                    }
                    break;
                }
            }
        }
        if (argc <= 1 || curFans <= 0 || curTsen <= 0) {
            printUsage();
            return EXIT_FAILURE;
        }
        if (geteuid() != 0) {
            fprintf(stderr, "ERROR: ccpfc must be run as root.\n");
            return EXIT_FAILURE;
        }
        if (minFanSpeed >= lowFanSpeed) {
            fprintf(stderr, "ERROR: --fan-speed-min must be less than --fan-speed-low.\n");
            return EXIT_FAILURE;
        }
        if (lowFanSpeed >= highFanSpeed) {
            fprintf(stderr, "ERROR: --fan-speed-low must be less than -fan-speed-high.\n");
            return EXIT_FAILURE;
        }
        if (lowFanSpeed == 0) {
            fprintf(stderr, "ERROR: Fan speed values must be between 0 and 10000.\n");
            return EXIT_FAILURE;
        }
        mkFanLut(printLut);
        if (printLut) {
            return EXIT_SUCCESS;
        }
    }
    while (1) {
        setFanSpeed();
        sleep(interval);
    }
    return EXIT_SUCCESS;
}
