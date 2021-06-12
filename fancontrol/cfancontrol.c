/**
 * Copyright (C) 2021  kevinlekiller
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

// gcc cfancontrol.c -o cfancontrol -Wextra -O2 -lm

#include <dirent.h>
#include <getopt.h>
#include <math.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

float interval = 1.0;
unsigned char lowTemp = 0, highTemp = 0, smoothUp = 0, smoothDown = 0;
unsigned char highFanSpeed = 0, lowFanSpeed = 0, minFanSpeed = 0, lastFanSpeed = 0;
bool silent = false;
unsigned char fanLut[99];
char buf[256];
FILE *amdgpu_temp1_input;
unsigned char amdgpu_temp1_input_offset = 20;
FILE *it8665_temp1_input;
FILE *it8665_pwm5_enable;
FILE *it8665_pwm5;

bool writeFile(FILE * fp, const char * value) {
    if (fputs(value, fp) < 0 || fseek(fp, 0, SEEK_SET) != 0){
        return false;
    }
    return true;
}

bool readFile(FILE * fp, size_t size) {
    if (fseek(fp, 0, SEEK_SET) != 0 || fgets(buf, size, fp) == NULL ||  fseek(fp, 0, SEEK_END) != 0) {
        return false;
    }
    return true;
}

unsigned char getMaxTemp() {
    int cpuTemp = 0, gpuTemp;
    if (!readFile(it8665_temp1_input, 7)) {
        return cpuTemp;
    }
    cpuTemp = atoi(buf);
    if (!readFile(amdgpu_temp1_input, 7)) {
        return cpuTemp;
    }
    gpuTemp = atoi(buf) + amdgpu_temp1_input_offset;
    return (int) round((gpuTemp > cpuTemp ? gpuTemp : cpuTemp) / 1000.0);
}

void setFanSpeed() {
    int tmpSpeed, temp =  getMaxTemp();
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
        sprintf(buf, "%d", tmpSpeed);
        writeFile(it8665_pwm5, buf);
    }
    if (!silent) {
        printf("\rHighest Temp %2d C -> Fan Speed %3d PWM", temp, tmpSpeed);
        fflush(stdout);
    }
    lastFanSpeed = tmpSpeed;
}

void cleanup() {
    if (it8665_pwm5 != NULL) {
        writeFile(it8665_pwm5_enable, "0");
        fclose(it8665_pwm5_enable);
    }
    if (it8665_pwm5 != NULL) {
        fclose(it8665_pwm5);
    }
    if (it8665_temp1_input != NULL) {
        fclose(it8665_temp1_input);
    }
    if (amdgpu_temp1_input != NULL) {
        fclose(amdgpu_temp1_input);
    }
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
    FILE * file;
    char buf2[30];
    while ((files = readdir(dir)) != NULL) {
        if (strstr(files->d_name, "hwmon")) {
            sprintf(buf2, "%s/%s/name", "/sys/class/hwmon", files->d_name);
            file = fopen(buf2, "r");
            if (file == NULL || !readFile(file, 50) || strstr(buf, name) == NULL) {
                continue;
            }
            sprintf(buf, "%s/%s", "/sys/class/hwmon", files->d_name);
            foundPath = true;
            break;
        }
    }
    closedir(dir);
    if (!foundPath) {
        fprintf(stderr, "ERROR: Could not find hwmon directory.\n");
    }
    return foundPath;
}

bool openFiles() {
    if (!getHwmonPath("it8665")) {
        return false;
    }
    char tmpPath[64];
    sprintf(tmpPath, "%s/temp1_input", buf);
    if (!fileExists(tmpPath)) {
        return false;
    }
    it8665_temp1_input = fopen(tmpPath, "r");
    if (it8665_temp1_input == NULL) {
        return false;
    }
    sprintf(tmpPath, "%s/pwm5_enable", buf);
    if (!fileExists(tmpPath)) {
        return false;
    }
    it8665_pwm5_enable = fopen(tmpPath, "r+");
    if (it8665_pwm5_enable == NULL) {
        return false;
    }
    sprintf(tmpPath, "%s/pwm5", buf);
    if (!fileExists(tmpPath)) {
        return false;
    }
    it8665_pwm5 = fopen(tmpPath, "r+");
    if (it8665_pwm5 == NULL) {
        return false;
    }
    if (!getHwmonPath("amdgpu")) {
        return false;
    }
    sprintf(tmpPath, "%s/temp1_input", buf);
    if (!fileExists(tmpPath)) {
        return false;
    }
    amdgpu_temp1_input = fopen(tmpPath, "r");
    if (amdgpu_temp1_input == NULL) {
        return false;
    }
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
    printf("Program for controling PWM chassis fans on Linux.\n");
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
    printf("   When increasing fan RPM, go up by NUM per --interval seconds. (valid: 1 to 255)\n");
    printf(" -b, --fan-smooth-down=NUM\n");
    printf("   When decreasing fan RPM, go down by NUM per --interval seconds. (valid: 1 to 255)\n");
    printf(" -c, --fan-speed-min=NUM\n");
    printf("   Fan speed when temperature is under --fan-temp-low. (valid: 0 to 10000)\n");
    printf(" -d, --fan-speed-low=NUM\n");
    printf("   Fan speed used for fan LUT calculation when temperature at --fan-temp-low. (valid: 1 to 10000)\n");
    printf(" -e, --fan-temp-low=NUM\n");
    printf("   Lowest temperature for fan LUT calculation. (valid: 1 to 99)\n");
    printf(" -f, --fan-speed-high=NUM\n");
    printf("   Fan speed used for fan LUT calculation when temperature at --fan-temp-high. (valid: 1 to 10000)\n");
    printf(" -g, --fan-temp-high=NUM\n");
    printf("   Highest temperature for fan LUT calculation. (valid: 1 to 99)\n");
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
            {0,                       0,                 0,  0 }
        };
        while (c = getopt_long(argc, argv, "a:b:c:d:e:f:g:hi:ln:s", long_options, NULL)) {
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
                case 'u':
                    break;
            }
        }
        if (geteuid() != 0) {
            fprintf(stderr, "ERROR: cfancontrol must be run as root.\n");
            return EXIT_FAILURE;
        }
        if (!openFiles()) {
            fprintf(stderr, "ERROR: Unable to open requires files.\n");
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
        writeFile(it8665_pwm5_enable, "1");
        if (!silent) {
            printf("Manual fan control enabled.\n");
        }
    }
    while (1) {
        setFanSpeed();
        sleep(interval);
    }
    return EXIT_SUCCESS;
}
