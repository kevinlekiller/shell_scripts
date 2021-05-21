#!/usr/bin/php
<?php
/* List installed pacman packages that were installed and their deps on seperate lines.
 * Useful if you want to remove a program and all the dependencies that were pulled in with it.
 * chmod u+x pacmanhistory
 * ./pacmanhistory.php
 */
/*
    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/
$path = "/var/log/pacman.log";
if (!is_file($path)) {
        exit("File not found: $path\n");
}
$f = fopen($path,"r");
$pkgs = $matches = [];
$i = 0;
while(!feof($f))  {
        $line = fgets($f);
        if (strpos($line, "[ALPM] transaction started")) {
                $i++;
        } else if (alpmMatch()) {
                $pkgs[$matches[1]] = 0;
        } else if (alpmMatch(true)) {
                $pkgs[$matches[1]] = $i;
        }
}
$last = 1;
foreach ($pkgs as $pkg => $val) {
        if ($last != $val) {
                $last = $val;
                if ($val > 0) {
                        echo "\n";
                }
        }
        if ($val > 0) {
                echo "$pkg ";
        }
}
echo "\n";
fclose($f);
function alpmMatch($ins = false) {
        global $line, $matches;
        $ins = $ins ? "installed" : "removed";
        if (strpos($line, "[ALPM] $ins") && preg_match("#\[ALPM\] $ins (.*) \(#", $line, $matches)) {
                return true;
        }
        return false;
}
