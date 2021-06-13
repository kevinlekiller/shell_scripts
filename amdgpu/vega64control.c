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

/**
* This program can be used to control the P-States / fanspeed and set a custom
* power play table on a AMD vega 64 (and probably 56) GPU.
* This program was created because using pp_od_clk_voltage doesn't work
* properly, if you set the voltages to maximum 950mV for example, the voltage
* will still get up to 1200mV.
* Modyfying the pp_table also doesn't work properly, the voltage often stays
* stuck, the HBM clock speed doesn't go back down, the SOC P-State usually
* is stuck at 5.
* 
* This program will increase/decrease the GPU/SOC/VRAM P-States based on GPU load.
* It will keep increasing the P-States if the GPU load is 50% or more.
* It will only lower the P-States if the GPU load has been lower than 50% for a period of time.
*/

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

unsigned char iters = 0, lowTemp = 0, highTemp = 0, stuckIterChk = 60, stuckIters = 0;
unsigned char gpuLoadCheck = 50, iterLimit = 10, gpuPstate = 0, socPstate = 0, vramPstate = 0;
unsigned char maxGpuState = 7, maxSocState = 7, maxVramState = 3, smoothUp = 0, smoothDown = 0;
unsigned short highFanSpeed = 0, lowFanSpeed = 0, minFanSpeed = 0, lastFanSpeed = 0;
bool fanSpeedControl, pstateControl = false, silent = false;
float interval = 1.0;
const char * user_pp_table;
int fanLut[99];
FILE * gpu_busy_percent;
FILE * power_dpm_force_performance_level;
FILE * pp_dpm_mclk;
FILE * pp_dpm_sclk;
FILE * pp_dpm_socclk;
FILE * fan1_enable;
FILE * fan1_target;
FILE * temp1_input;
char buf[256];
char pp_table[39];

bool writeFile(FILE * fp, const char * value) {
    if (fputs(value, fp) < 0 || fseek(fp, 0, SEEK_SET) != 0){
        return false;
    }
    return true;
}

bool readFile(FILE * fp, size_t size) {
    if (fseek(fp, 0, SEEK_SET) != 0 || fread(buf, 1, size, fp) < 1) {
        return false;
    }
    return true;
}

void cleanup() {
    if (fanSpeedControl) {
        if (!silent) {
            printf("\nEnabling automatic fan control\n");
        }
        writeFile(fan1_enable, "0");
    }
    if (pstateControl) {
        if (!silent) {
            printf("Enabling automatic P-State control.\n");
        }
        writeFile(power_dpm_force_performance_level, "auto");
    }
    if (gpu_busy_percent != NULL) {
        fclose(gpu_busy_percent);
    }
    if (power_dpm_force_performance_level != NULL) {
        fclose(power_dpm_force_performance_level);
    }
    if (pp_dpm_mclk != NULL) {
        fclose(pp_dpm_mclk);
    }
    if (pp_dpm_sclk != NULL) {
        fclose(pp_dpm_sclk);
    }
    if (pp_dpm_socclk != NULL) {
        fclose(pp_dpm_socclk);
    }
    if (fan1_enable != NULL) {
        fclose(fan1_enable);
    }
    if (fan1_target != NULL) {
        fclose(fan1_target);
    }
    if (temp1_input != NULL) {
        fclose(temp1_input);
    }
    exit(EXIT_SUCCESS);
}

void setVramPstate() {
    switch (socPstate) { // This is how my GPU behaves, might vary based on pp_table.
        case 7:
        case 6:
            vramPstate = 3;
            break;
        case 5:
        case 4:
        case 3:
        case 2:
            vramPstate = 2;
            break;
        case 1:
            vramPstate = 1;
            break;
        case 0:
        default:
            vramPstate = 0;
            break;
    }
    sprintf(buf, "%d", vramPstate);
    writeFile(pp_dpm_mclk, buf);
}

void setPPTable() {
    sprintf(buf, "cp \"%s\" \"%s\"", user_pp_table, pp_table);
    system(buf);
    if (fanSpeedControl) { // Setting the pp_table seems to reset fan1_enable to 0 sometimes.
        writeFile(fan1_enable, "1");
        lastFanSpeed = 0;
    }
}

void setPstates() {
    if (!readFile(gpu_busy_percent, 4)) {
        return;
    }
    if (atoi(buf) >= gpuLoadCheck) {
        iters = 0;
        if (socPstate < maxSocState) {
            iters = 1;
            socPstate++;
            sprintf(buf, "%d", socPstate);
            writeFile(pp_dpm_socclk, buf);
            if (vramPstate < maxVramState) {
                setVramPstate();
            }
        }
        if (gpuPstate < maxGpuState) {
            iters = 1;
            gpuPstate++;
            sprintf(buf, "%d", gpuPstate);
            writeFile(pp_dpm_sclk, buf);
        }
        if (!silent && iters) {
            printf("\nIncreased P-States: GPU %d ; SOC %d ; VRAM %d\n", gpuPstate, socPstate, vramPstate);
        }
        iters = 0;
    } else if (gpuPstate > 0 || socPstate > 0) {
        if (iters++ <= iterLimit) {
            return;
        }
        iters = 0;
        if (socPstate > 0) {
            socPstate--;
            sprintf(buf, "%d", socPstate);
            writeFile(pp_dpm_socclk, buf);
            setVramPstate();
        }
        if (gpuPstate > 0) {
            gpuPstate--;
            sprintf(buf, "%d", gpuPstate);
            writeFile(pp_dpm_sclk, buf);
        }
        if (!silent) {
            printf("\nDecreased P-States: GPU %d ; SOC %d ; VRAM %d\n", gpuPstate, socPstate, vramPstate);
        }
    // Check if VRAM P-State is stuck, copying the pp_table seems to fix the issue.
    } else if (user_pp_table != NULL && stuckIters++ >= stuckIterChk) {
        if (readFile(pp_dpm_mclk, 13) && strncmp("0: 167Mhz *", buf, 11) != 0) {
            if (!silent) {
                printf("\nVRAM P-State Stuck, copying pp_table.\n");
            }
            setPPTable();
            vramPstate = 0;
        }
        stuckIters = 0;
    }
}

void setFanSpeed() {
    if (!readFile(temp1_input, 7)) {
        return;
    }
    int tmpSpeed, gpuTemp =  (int) round(atof(buf) / 1000.0);
    if (gpuTemp < lowTemp) {
        tmpSpeed = minFanSpeed;
    } else if (fanLut[gpuTemp]) {
        tmpSpeed = fanLut[gpuTemp];
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
        writeFile(fan1_target, buf);
    }
    if (!silent) {
        printf("\rGpu Temp %2d C -> Fan Speed %4d RPM", gpuTemp, tmpSpeed);
        fflush(stdout);
    }
    lastFanSpeed = tmpSpeed;
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

bool checkFiles(char * devPath, char * hwmonPath) {
    char tmpPath[64];
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
        } else if (strcmp(devFiles[i], "pp_table") == 0) {
            sprintf(pp_table, "%s", tmpPath);
        } else if (!pstateControl) {
            break;
        } else if (strcmp(devFiles[i], "gpu_busy_percent") == 0) {
            gpu_busy_percent = fopen(tmpPath, "r");
            if (gpu_busy_percent == NULL) {
                return false;
            }
        } else if (strcmp(devFiles[i], "power_dpm_force_performance_level") == 0) {
            power_dpm_force_performance_level = fopen(tmpPath, "r+");
            if (power_dpm_force_performance_level == NULL) {
                return false;
            }
        } else if (strcmp(devFiles[i], "pp_dpm_mclk") == 0) {
            pp_dpm_mclk = fopen(tmpPath, "r+");
            if (pp_dpm_mclk == NULL) {
                return false;
            }
        } else if (strcmp(devFiles[i], "pp_dpm_sclk") == 0) {
            pp_dpm_sclk = fopen(tmpPath, "r+");
            if (pp_dpm_sclk == NULL) {
                return false;
            }
        } else if (strcmp(devFiles[i], "pp_dpm_socclk") == 0) {
            pp_dpm_socclk = fopen(tmpPath, "r+");
            if (pp_dpm_socclk == NULL) {
                return false;
            }
        }
    }
    if (!fanSpeedControl) {
        return true;
    }
    arrSize = sizeof(hwmonFiles) / sizeof(hwmonFiles[0]);
    for (i = 0; i < arrSize; i++) {
        
        sprintf(tmpPath, "%s/%s", hwmonPath, hwmonFiles[i]);
        if (!fileExists(tmpPath)) {
            return false;
        } else if (strcmp(hwmonFiles[i], "fan1_enable") == 0) {
            fan1_enable = fopen(tmpPath, "r+");
            if (fan1_enable == NULL) {
                return false;
            }
        } else if (strcmp(hwmonFiles[i], "fan1_target") == 0) {
            fan1_target = fopen(tmpPath, "r+");
            if (fan1_target == NULL) {
                return false;
            }
        } else if (strcmp(hwmonFiles[i], "temp1_input") == 0) {
            temp1_input = fopen(tmpPath, "r");
            if (temp1_input == NULL) {
                return false;
            }
        }
    }
    return true;
}

bool getDevPath(char * devPath, int gpuID) {
    sprintf(devPath, "/sys/class/drm/card%d/device", gpuID);
    return dirExists(devPath, true);
}

bool getHwmonPath(char * devPath, char * hwmonPath) {
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
            break;
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
    printf(" -h, --help\n");
    printf("   Displays this information.\n");
    printf(" -s, --silent\n");
    printf("   Output nothing to stdout.\n");
    printf(" -d, --gpu-id=NUM\n");
    printf("   GPU id.\n");
    printf(" -c, --pstate-control\n");
    printf("   Enable P-State control.\n");
    printf(" -e, --pstate-gpu-max=NUM\n");
    printf("   Maximum GPU P-State. (valid: 1 to 7) (default: 7)\n");
    printf(" -f, --pstate-soc-max=NUM\n");
    printf("   Maximum SOC P-State. (valid: 1 to 7) (default: 7)\n");
    printf(" -g, --pstate-vram-max=NUM\n");
    printf("   Maximum VRAM P-State. (valid: 1 to 3) (default: 3)\n");
    printf(" -l, --pstate-load=NUM\n");
    printf("   Percentage ; If the load of the GPU is equal or higher than this, raise the P-States. (valid: 1 to 100) (default: 50)\n");
    printf(" -r, --pstate-decrease-loops=NUM\n");
    printf("   How many loops in a row the GPU load must be under --pstate-load before lowering the P-States. (valid: 1 to 255) (default: 10)\n");
    printf(" -p, --pptable=FILE\n");
    printf("   Modified powerplay table to apply.\n");
    printf(" -t, --pstate-check-stuck=NUM\n");
    printf("   Every NUM loops, if the VRAM P-State is at the minimum, check if it's stuck at a higher P-State.\n");
    printf("   The pp_table will be re-applied to force the P-State down. Requires --pptable and --pstate-control. (valid: 1 to 255) (default: 60) \n");
    printf(" -i, --interval=FLOAT\n");
    printf("   Loop pause time. (valid: 0.05 to 60) (default: 1.0)\n");
    printf(" -n, --niceness=NUM\n");
    printf("   Set the process priority (niceness). (valid: -20 to 19)\n");
    printf(" -u, --fan-print-lut\n");
    printf("   Print fan LUT and exit.\n");
    printf(" -a, --fan-smooth-up=NUM\n");
    printf("   When increasing fan RPM, go up by NUM per --interval seconds. (valid: 1 to 255)\n");
    printf(" -b, --fan-smooth-down=NUM\n");
    printf("   When decreasing fan RPM, go down by NUM per --interval seconds. (valid: 1 to 255)\n");
    printf(" -v, --fan-speed-min=NUM\n");
    printf("   Fan speed when temperature is under --fan-temp-low. (valid: 0 to 10000)\n");
    printf(" -w, --fan-speed-low=NUM\n");
    printf("   Fan speed used for fan LUT calculation when temperature at --fan-temp-low. (valid: 1 to 10000)\n");
    printf(" -x, --fan-temp-low=NUM\n");
    printf("   Lowest temperature for fan LUT calculation. (valid: 1 to 99)\n");
    printf(" -y, --fan-speed-high=NUM\n");
    printf("   Fan speed used for fan LUT calculation when temperature at --fan-temp-high. (valid: 1 to 10000)\n");
    printf(" -z, --fan-temp-high=NUM\n");
    printf("   Highest temperature for fan LUT calculation. (valid: 1 to 99)\n");
    printf("Examples:\n");
    printf(" Show fan LUT with minimum 500RPM at 40C, maximum 1600RPM at 55C, 400RPM under 40c.\n");
    printf("  ./vega64control --fan-speed-low=500 --fan-speed-high=1600 --fan-temp-low=40 --fan-temp-high 55 --fan-speed-min=400 --fan-print-lut\n");
    printf(" Apply pp_table, control P-States.\n");
    printf("  ./vega64control --pptable=/etc/default/pp_table --pstate-control\n");
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
        int c, gpuID = 0;
        static struct option long_options[] = {
            {"help",                  no_argument,       0, 'h'},
            {"silent",                no_argument,       0, 's'},
            {"gpu-id",                required_argument, 0, 'd'},
            {"pstate-control",        no_argument,       0, 'c'},
            {"pstate-gpu-max",        required_argument, 0, 'e'},
            {"pstate-soc-max",        required_argument, 0, 'f'},
            {"pstate-vram-max",       required_argument, 0, 'g'},
            {"pstate-load",           required_argument, 0, 'l'},
            {"pstate-decrease-loops", required_argument, 0, 'r'},
            {"pptable",               required_argument, 0, 'p'},
            {"pstate-check-stuck",    required_argument, 0, 't'},
            {"interval",              required_argument, 0, 'i'},
            {"niceness",              required_argument, 0, 'n'},
            {"fan-print-lut",         no_argument,       0, 'u'},
            {"fan-smooth-up",         required_argument, 0, 'a'},
            {"fan-smooth-down",       required_argument, 0, 'b'},
            {"fan-speed-min",         required_argument, 0, 'v'},
            {"fan-speed-low",         required_argument, 0, 'w'},
            {"fan-temp-low",          required_argument, 0, 'x'},
            {"fan-speed-high",        required_argument, 0, 'y'},
            {"fan-temp-high",         required_argument, 0, 'z'},
            {0,                       0,                 0,  0 }
        };
        while (c = getopt_long(argc, argv, "a:b:cd:e:f:g:hi:l:n:p:r:st:uv:w:x:y:z:", long_options, NULL)) {
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
                    pstateControl = true;
                    break;
                case 'd':
                    gpuID = atoi(optarg);
                    if (gpuID < 0 || gpuID > 1024) {
                        fprintf(stderr, "ERROR: Wrong --gpu-id passed.\n");
                        return EXIT_FAILURE;
                    }
                    break;
                case 'e':
                    maxGpuState = (unsigned char) atoi(optarg);
                    if (maxGpuState > 7) {
                        fprintf(stderr, "ERROR: --pstate-gpu-max must be between 0 and 7.\n");
                        return EXIT_FAILURE;
                    }
                    break;
                case 'f':
                    maxSocState = (unsigned char) atoi(optarg);
                    if (maxSocState > 7) {
                        fprintf(stderr, "ERROR: --pstate-soc-max must be between 0 and 7.\n");
                        return EXIT_FAILURE;
                    }
                    break;
                case 'g':
                    maxVramState = (unsigned char) atoi(optarg);
                    if (maxVramState > 3) {
                        fprintf(stderr, "ERROR: --pstate-vram-max must be between 0 and 3.\n");
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
                    gpuLoadCheck = (unsigned char) atoi(optarg);
                    if (gpuLoadCheck > 100 || gpuLoadCheck < 1) {
                        fprintf(stderr, "ERROR: --pstate-load must be between 1 and 100.\n");
                        return EXIT_FAILURE;
                    }
                    break;
                case 'n':
                    int niceness = atoi(optarg);
                    if (niceness < -20 || niceness > 19) {
                        fprintf(stderr, "ERROR: --niceness must be -20 to 19.\n");
                        return EXIT_FAILURE;
                    }
                    nice(niceness);
                    break;
                case 'p':
                    user_pp_table = optarg;
                    if (!fileExists(user_pp_table)) {
                        return EXIT_FAILURE;
                    }
                    break;
                case 'r':
                    iterLimit = (unsigned char) atoi(optarg);
                    if (iterLimit == 0) {
                        fprintf(stderr, "ERROR: --pstate-decrease-loops must be between 1 and 255.\n");
                        return EXIT_FAILURE;
                    }
                    break;
                case 's':
                    silent = true;
                    break;
                case 't':
                    stuckIterChk = (unsigned char) atoi(optarg);
                    if (stuckIterChk == 0) {
                        fprintf(stderr, "ERROR: --pstate-check-stuck must be between 1 and 255.\n");
                        return EXIT_FAILURE;
                    }
                    break;
                case 'u':
                    printLut = true;
                    break;
                case 'v':
                    minFanSpeed = (unsigned short) atoi(optarg);
                    break;
                case 'w':
                    lowFanSpeed = (unsigned short) atoi(optarg);
                    break;
                case 'x':
                    lowTemp = (unsigned char) atoi(optarg);
                    if (lowTemp == 0 || lowTemp > 99) {
                        fprintf(stderr, "ERROR: --fan-temp-low must be between 1 and 99.\n");
                        return EXIT_FAILURE;
                    }
                    break;
                case 'y':
                    highFanSpeed = (unsigned short) atoi(optarg);
                    break;
                case 'z':
                    highTemp = (unsigned char) atoi(optarg);
                    if (highTemp == 0 || highTemp > 99) {
                        fprintf(stderr, "ERROR: --fan-temp-high must be between 1 and 99.\n");
                        return EXIT_FAILURE;
                    }
                    break;
            }
        }
        if (geteuid() != 0) {
            fprintf(stderr, "ERROR: vega64control must be run as root.\n");
            return EXIT_FAILURE;
        }
        char devPath[30];
        char *devPathptr = devPath;
        if (!getDevPath(devPathptr, gpuID)) {
            return EXIT_FAILURE;
        }
        char hwmonPath[45];
        char *hwmonPathptr = hwmonPath;
        if (!getHwmonPath(devPathptr, hwmonPathptr)) {
            fprintf(stderr, "ERROR: Could not find hwmon path for GPU.\n");
            return EXIT_FAILURE;
        }
        fanSpeedControl = highFanSpeed > 0 && highTemp > 0;
        if (!checkFiles(devPathptr, hwmonPathptr)) {
            fprintf(stderr, "ERROR: Could not open a required file.\n");
            return EXIT_FAILURE;
        }
        if (fanSpeedControl) {
            if (minFanSpeed >= lowFanSpeed) {
                fprintf(stderr, "ERROR: --fan-speed-min must be less than --fan-speed-low.\n");
                return EXIT_FAILURE;
            }
            if (lowFanSpeed >= highFanSpeed) {
                fprintf(stderr, "ERROR: --fan-speed-low must be less than -fan-speed-high.\n");
                return EXIT_FAILURE;
            }
            if (lowFanSpeed == 0 || highFanSpeed > 10000) {
                fprintf(stderr, "ERROR: Fan speed values must be between 0 and 10000.\n");
                return EXIT_FAILURE;
            }
            mkFanLut(printLut);
            if (printLut) {
                return EXIT_SUCCESS;
            }
            writeFile(fan1_enable, "1");
            if (!silent) {
                printf("Manual fan control enabled.\n");
            }
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
            setPPTable();
        }
    }
    while (pstateControl || fanSpeedControl) {
        if (fanSpeedControl) {
            setFanSpeed();
        }
        if (pstateControl) {
            setPstates();
        }
        sleep(interval);
    }
    return EXIT_SUCCESS;
}
