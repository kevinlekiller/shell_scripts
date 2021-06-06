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

// gcc vega64control.c -o vega64control -Wextra -O2 -lm

#include <dirent.h>
#include <math.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

#define ITERRESET 10

int gpuID = 0, minFanSpeed = 0, lowFanSpeed = 0, highFanSpeed = 0, lowTemp = 0 , highTemp = 0;
int gpuPstate = 0, socPstate, vramPstate = 0, maxGpuState = 7, maxSocState = 7, maxVramState = 3;
int silent = 0, iters = 0, smoothUp = 0, smoothDown = 0, lastFanSpeed = 0;
bool fanSpeedControl;
float interval = 1.0;
const char * user_pp_table;
char devPath[50];
char hwmonPath[60];
int fanLut[99];
char gpu_busy_percent[100];
char power_dpm_force_performance_level[110];
char pp_dpm_mclk[100];
char pp_dpm_sclk[100];
char pp_dpm_socclk[100];
char pp_table[100];
char fan1_enable[100];
char fan1_target[100];
char temp1_input[100];
char buf[256];

void writeFile(const char * path, const char * value) {
    FILE *file = fopen(path, "r+");
    fseek(file, 0, SEEK_SET);
    fputs(value, file);
    fseek(file, 0, SEEK_SET);
    fclose(file);
}

bool readFile(const char * path, size_t size) {
    FILE *file = fopen(path, "r");
    fseek(file, 0, SEEK_SET);
    if (fgets(buf, size, file) == NULL) {
        return false;
    }
    fseek(file, 0, SEEK_END);
    fclose(file);
    return true;
}

void cleanup() {
    if (!silent) {
        printf("\n");
    }
    if (fanSpeedControl) {
        if (!silent) {
            printf("Enabling automatic fan control\n");
        }
        writeFile(fan1_enable, "0");
    }
    if (!silent) {
        printf("Enabling automatic P-State control.\n");
    }
    writeFile(power_dpm_force_performance_level, "auto");
    exit(0);
}

void setVramPstate() {
    switch (socPstate) {
        case 7:
        case 6:
            vramPstate = 3;
            break;
        case 5:
        case 4:
            vramPstate = 2;
            break;
        case 3:
        case 2:
            vramPstate = 1;
            break;
        case 1:
        case 0:
        default:
            vramPstate = 0;
            break;
    }
    if (vramPstate > maxVramState) {
        vramPstate = maxVramState;
    }
    sprintf(buf, "%d", vramPstate);
    writeFile(pp_dpm_mclk, buf);
}

void setPstates() {
    if (!readFile(gpu_busy_percent, 3)) {
        return;
    }
    if (atoi(buf) >= 50) {
        if (socPstate <= maxSocState) {
            socPstate++;
            sprintf(buf, "%d", socPstate);
            writeFile(pp_dpm_socclk, buf);
        }
        if (gpuPstate <= maxGpuState) {
            gpuPstate++;
            sprintf(buf, "%d", gpuPstate);
            writeFile(pp_dpm_sclk, buf);
        }
        setVramPstate();
        if (!silent) {
            printf ("\nIncreased P-States: GPU %d ; SOC %d ; VRAM %d\n", gpuPstate, socPstate, vramPstate);
        }
    } else if ((gpuPstate > 0 || socPstate > 0) && iters++ >= ITERRESET) {
        iters = 0;
        if (socPstate > 0) {
            socPstate--;
            sprintf(buf, "%d", socPstate);
            writeFile(pp_dpm_socclk, buf);
        }
        if (gpuPstate > 0) {
            gpuPstate--;
            sprintf(buf, "%d", gpuPstate);
            writeFile(pp_dpm_sclk, buf);
        }
        setVramPstate();
        if (!silent) {
            printf ("\nDecreased P-States: GPU %d ; SOC %d ; VRAM %d\n", gpuPstate, socPstate, vramPstate);
        }
    }
}

void setFanSpeed() {
    if (!readFile(temp1_input, 6)) {
        return;
    }
    int gpuTemp =  (int) round(atof(buf) / 1000.0);
    char fanSpeed[4] = "0";
    if (gpuTemp < lowTemp) {
        sprintf(fanSpeed, "%d", minFanSpeed);
    } else if (fanLut[gpuTemp]) {
        sprintf(fanSpeed, "%d", fanLut[gpuTemp]);
    } else {
        sprintf(fanSpeed, "%d", highFanSpeed);
    }
    int tmpSpeed = atoi(fanSpeed);
    if (smoothDown && tmpSpeed < lastFanSpeed) {
        sprintf(fanSpeed, "%d", lastFanSpeed - smoothDown);
    } else if (smoothUp && tmpSpeed > lastFanSpeed) {
        sprintf(fanSpeed, "%d", lastFanSpeed + smoothUp);
    }
    writeFile(fan1_enable, "1");
    writeFile(fan1_target, fanSpeed);
    lastFanSpeed = atoi(fanSpeed);
    if (!silent) {
        printf("\rGpu Temp %2d C -> Fan Speed %4d RPM", gpuTemp, lastFanSpeed);
        fflush(stdout);
    }
}

void mkFanLut(bool printLut) {
    float tdiff = (float) (highFanSpeed - lowFanSpeed) / (float) (highTemp - lowTemp);
    float curSpeed = (float) lowFanSpeed;
    int rndSpeed;
    if (!silent && printLut) {
        printf("Temp <= %2d C ; FanSpeed = %4d RPM\n", lowTemp-1, minFanSpeed);
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
            printf("Temp == %2d C ; FanSpeed = %4d RPM\n", i, fanLut[i]);
        }
    }
    if (!silent && printLut) {
        printf("Temp >= %2d C ; FanSpeed = %4d RPM\n", highTemp+1, highFanSpeed);
    }
}

bool dirExists(const char * path, bool showErr) {
    struct stat sb;
    if (stat(path, &sb) == 0 && S_ISDIR(sb.st_mode)) {
        return true;
    }
    if (showErr) {
        fprintf(stderr, "ERROR: Could not find directory '%s'\n", path);
    }
    return false;
}

bool fileExists(const char * path) {
    if (path && access(path, F_OK) == 0) {
        return true;
    }
    fprintf(stderr, "ERROR: Could not find file '%s'\n", path);
    return false;
}

bool checkFiles() {
    char tmpPath[100];
    const char devFiles[][35] = {
        "gpu_busy_percent",
        "power_dpm_force_performance_level",
        "pp_dpm_mclk",
        "pp_dpm_sclk",
        "pp_dpm_socclk",
        "pp_table"
    };
    const char hwmonFiles[][15] = {
        "fan1_enable",
        "fan1_target",
        "temp1_input"
    };
    int i, arrSize = sizeof(devFiles) / sizeof(devFiles[0]);
    for (i = 0; i < arrSize; i++) {
        sprintf(tmpPath, "%s/%s", devPath, devFiles[i]);
        if (!fileExists(tmpPath)) {
            return false;
        } else if (strcmp(devFiles[i], "gpu_busy_percent") == 0) {
            sprintf(gpu_busy_percent, "%s", tmpPath);
        } else if (strcmp(devFiles[i], "power_dpm_force_performance_level") == 0) {
            sprintf(power_dpm_force_performance_level, "%s", tmpPath);
        } else if (strcmp(devFiles[i], "pp_dpm_mclk") == 0) {
            sprintf(pp_dpm_mclk, "%s", tmpPath);
        } else if (strcmp(devFiles[i], "pp_dpm_sclk") == 0) {
            sprintf(pp_dpm_sclk, "%s", tmpPath);
        } else if (strcmp(devFiles[i], "pp_dpm_socclk") == 0) {
            sprintf(pp_dpm_socclk, "%s", tmpPath);
        } else if (strcmp(devFiles[i], "pp_table") == 0) {
            sprintf(pp_table, "%s", tmpPath);
        }
    }
    arrSize = sizeof(hwmonFiles) / sizeof(hwmonFiles[0]);
    for (i = 0; i < arrSize; i++) {
        sprintf(tmpPath, "%s/%s", hwmonPath, hwmonFiles[i]);
        if (!fileExists(tmpPath)) {
            return false;
        } else if (strcmp(hwmonFiles[i], "fan1_enable") == 0) {
            sprintf(fan1_enable, "%s", tmpPath);
        } else if (strcmp(hwmonFiles[i], "fan1_target") == 0) {
            sprintf(fan1_target, "%s", tmpPath);
        } else if (strcmp(hwmonFiles[i], "temp1_input") == 0) {
            sprintf(temp1_input, "%s", tmpPath);
        }
    }
    return true;
}

bool getDevPath() {
    sprintf(devPath, "/sys/class/drm/card%d/device", gpuID);
    return dirExists(devPath, true);
}

bool getHwmonPath() {
    sprintf(hwmonPath, "%s/hwmon", devPath);
    DIR *dir = opendir(hwmonPath);
    if (!dir) {
        fprintf(stderr, "ERROR: Could not find base hwmon directory.\n");
        return false;
    }
    const char * foundHwmon = "";
    struct dirent *files;
    while ((files = readdir(dir)) != NULL) {
        if (strstr(files->d_name, "hwmon")) {
            foundHwmon = files->d_name;
        }
    }
    closedir(dir);
    if (!foundHwmon) {
        fprintf(stderr, "ERROR: Could not find hwmon directory.\n");
        return false;
    }
    sprintf(hwmonPath, "%s/%s", hwmonPath, foundHwmon);
    return true;
}

void printUsage() {
    printf("Program for controling Fan / P-States on AMD Vega 64.\n");
    printf("Options:\n");
    printf(" -h\n");
    printf("   Displays this information.\n");
    printf(" -s\n");
    printf("   Output nothing to stdout.\n");
    printf(" -a [integer]\n");
    printf("   When increasing fan RPM, go up by this much per -i [float] seconds.\n");
    printf(" -b [integer]\n");
    printf("   When decreasing fan RPM, go down by this much per -i [float] seconds.\n");
    printf(" -c\n");
    printf("   Enable P-State control.\n");
    printf(" -d [integer]\n");
    printf("   GPU id\n");
    printf(" -e [integer]\n");
    printf("   Maximum GPU P-State. (valid: 1 to 7) (default: 7)\n");
    printf(" -f [integer]\n");
    printf("   Maximum SOC P-State. (valid: 1 to 7) (default: 7)\n");
    printf(" -g [integer]\n");
    printf("   Maximum VRAM P-State. (valid: 1 to 3) (default: 3)\n");
    printf(" -i [float]\n");
    printf("   Loop pause time. (valid: 0.05 to 60) (default: 1.0)\n");
    printf(" -p [FILE]\n");
    printf("   Modified powerplay table to apply.\n");
    printf(" -u\n");
    printf("   Print fan LUT and exit.\n");
    printf(" -v [integer]\n");
    printf("   Fan speed when temperature is under -x [integer]\n");
    printf(" -w [integer]\n");
    printf("   Fan speed used for fan LUT calculation when temperature at -x [integer]\n");
    printf(" -x [integer]\n");
    printf("   Lowest temperature for fan LUT calculation.\n");
    printf(" -y [integer]\n");
    printf("   Fan speed used for fan LUT calculation when temperature at -z [integer]\n");
    printf(" -z [integer]\n");
    printf("   Highest temperature for fan LUT calculation.\n");
    printf("Examples:\n");
    printf(" Show fan LUT with minimum 500RPM at 40C, maximum 1600RPM at 55C, 400RPM under 40c.\n");
    printf("  ./vega64control -w 500 -x 40 -y 1600 -z 55 -v 400 -u\n");
    printf(" Apply pp_table, control P-States\n");
    printf("  ./vega64control -p /etc/default/pp_table -c\n");
}

int main(int argc, char **argv) {
#ifndef linux
    fprintf(stderr, "ERROR: Operating system must be Linux.\n");
    return 1;
#endif
    int c;
    bool printLut = false, pstateControl = false;
    signal(SIGQUIT, cleanup);
    signal(SIGINT, cleanup);
    signal(SIGTERM, cleanup);
    signal(SIGHUP, cleanup);
    while ((c = getopt(argc, argv, "chsua:b:d:i:p:v:w:x:y:z:")) != -1) {
        switch (c) {
            case 'a':
                smoothUp = atoi(optarg);
                if (smoothUp < 1) {
                    fprintf(stderr, "ERROR: -a must be at least 1.\n");
                    return 1;
                }
                break;
            case 'b':
                smoothDown = atoi(optarg);
                if (smoothDown < 1) {
                    fprintf(stderr, "ERROR: -b must be at least 1.\n");
                    return 1;
                }
                break;
            case 'c':
                pstateControl = true;
                break;
            case 'd':
                gpuID = atoi(optarg);
                if (gpuID < 0 || gpuID > 256) {
                    fprintf(stderr, "ERROR: Wrong GPU device id passed.\n");
                    return 1;
                }
                break;
            case 'e':
                maxGpuState = atoi(optarg);
                if (maxGpuState < 0 || maxGpuState > 7) {
                    fprintf(stderr, "ERROR: GPU P-State must be between 0 and 7.\n");
                    return 1;
                }
                break;
            case 'f':
                maxSocState = atoi(optarg);
                if (maxSocState < 0 || maxSocState > 7) {
                    fprintf(stderr, "ERROR: SOC P-State must be between 0 and 7.\n");
                    return 1;
                }
                break;
            case 'g':
                maxVramState = atoi(optarg);
                if (maxVramState < 0 || maxVramState > 3) {
                    fprintf(stderr, "ERROR: VRAM P-State must be between 0 and 3.\n");
                    return 1;
                }
                break;
            case 'h':
                printUsage();
                return 0;
            case 'i':
                interval = atof(optarg);
                if (!interval || interval < 0.05 || interval > 60.0) {
                    fprintf(stderr, "ERROR: Interval must be between 0.05 and 60.0\n");
                    return 1;
                }
                break;
            case 'p':
                user_pp_table = optarg;
                if (!fileExists(user_pp_table)) {
                    return 1;
                }
                break;
            case 's':
                silent = true;
                break;
            case 'u':
                printLut = true;
                break;
            case 'v':
                minFanSpeed = atoi(optarg);
                break;
            case 'w':
                lowFanSpeed = atoi(optarg);
                break;
            case 'x':
                lowTemp = atof(optarg);
                if (lowTemp < 0 || lowTemp > 99) {
                    fprintf(stderr, "ERROR: Low temperature must be between 0 and 99\n");
                    return 1;
                }
                break;
            case 'y':
                highFanSpeed = atoi(optarg);
                break;
            case 'z':
                highTemp = atoi(optarg);
                if (highTemp < 0 || highTemp > 99) {
                    fprintf(stderr, "ERROR: Low temperature must be between 0 and 99\n");
                    return 1;
                }
                break;
        }
    }
    fanSpeedControl = highFanSpeed > 0 && highTemp > 0.0;
    if (fanSpeedControl) {
        if (minFanSpeed >= lowFanSpeed) {
            fprintf(stderr, "ERROR: Min fan speed must be less than low fan speed.\n");
            return 1;
        }
        if (lowFanSpeed >= highFanSpeed) {
            fprintf(stderr, "ERROR: Low fan speed must be less than high fan speed.\n");
            return 1;
        }
        if (lowFanSpeed < 0 || highFanSpeed > 10000) {
            fprintf(stderr, "ERROR: Fan speed values must be between 0 and 10000.\n");
            return 1;
        }
        mkFanLut(printLut);
        if (printLut) {
            return 0;
        }
        if (!silent) {
            printf("Manual fan control enabled.\n");
        }
    }
    if (geteuid() != 0) {
        fprintf(stderr, "ERROR: Must be run as root.\n");
        return 1;
    }
    if (!getDevPath()) {
        return 1;
    }
    if (!getHwmonPath()) {
        fprintf(stderr, "ERROR: Could not find hwmon path for GPU.\n");
        return 1;
    }
    if (!checkFiles()) {
        fprintf(stderr, "ERROR: Could not open a required file.\n");
        return 1;
    }
    if (pstateControl) {
        if (!silent) {
            printf("Enabling manual GPU P-State control.\n");
        }
        writeFile(power_dpm_force_performance_level, "manual");
    }
    if (user_pp_table) {
        if (!silent) {
            printf("Copying power play table: '%s' -> '%s'\n", user_pp_table, pp_table);
        }
        sprintf(buf, "cp \"%s\" \"%s\"", user_pp_table, pp_table);
        system(buf);
    }
    while (1) {
        if (fanSpeedControl) {
            setFanSpeed();
        }
        if (pstateControl) {
            setPstates();
        }
        sleep(interval);
    }
    return 0;
}
