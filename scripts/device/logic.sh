#!/bin/bash
# SPDX-License-Identifier: MIT
# Run the game's logic on the FunKey and bring the results back (M1 of docs/porting-plan.md). Runs on Windows (Git
# Bash: WSL can't reach the console's USB network), after scripts/device/bundle.sh in WSL.
#
# usage: scripts/device/logic.sh <label> <MHz> <workload> [NAME=value ...]
#   workload: a script prepared by bundle.sh (rooms-eternal.txt, short-eternal.txt, ...)
#   e.g. scripts/device/logic.sh rooms-1296 1296 rooms-eternal.txt
#
# Copies the bundle into /mnt/FunKey/isaac-dev on the console (and the game's Isaac.exe from "game files" the first
# time), runs logic-run.sh there, and copies its out/<label> into testing/m1/<label>. Only isaac-dev is ever touched:
# the menu keeps running, and the player's own games and saves are left alone.
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
label="${1:?usage: logic.sh <label> <MHz> <workload> [NAME=value ...]}"
mhz="${2:?usage: logic.sh <label> <MHz> <workload> [NAME=value ...]}"
workload="${3:?usage: logic.sh <label> <MHz> <workload> [NAME=value ...]}"
shift 3
fk="$repo/scripts/device/fk.sh"
dev="${TFK_DEVICE_BUNDLE:-//wsl.localhost/Debian/root/tboi-funkeys-work/device}"
dir=/mnt/FunKey/isaac-dev
exe="${TFK_GAME_EXE:-$repo/game files/The Binding Of Isaac/Isaac.exe}"

[ -f "$dev/isaac" ] || { echo "logic.sh: no bundle in $dev (scripts/device/bundle.sh in WSL)" >&2; exit 1; }
# Another program on the console (another test, or a game being played) would share the CPU and memory: stop and say
# so rather than measure next to it. Anything but the menu holding more than 4 MB counts, and so does a menu that isn't
# running or is paused: other tests stop or pause it (and between two of their games nothing else may show).
busy=$("$fk" 'for p in /proc/[0-9]*; do r=$(awk "/^VmRSS/ {print \$2}" $p/status 2> /dev/null); a=$(tr "\0" " " < $p/cmdline 2> /dev/null | cut -c1-120); [ -n "$r" ] && [ "$r" -gt 4096 ] && case "$a" in *gmenu2x*|*retrofe*) ;; *) echo "$r kB: $a" ;; esac; done
menu=$(pidof gmenu2x retrofe); if [ -z "$menu" ]; then echo "the menu is not running"; else for m in $menu; do [ "$(awk "{print \$3}" /proc/$m/stat)" = T ] && echo "the menu is paused (pid $m)"; done; fi; true')
if [ -n "$busy" ]; then
    echo "logic.sh: the console is busy:" >&2
    echo "$busy" >&2
    exit 2
fi

"$fk" --push "$dev/isaac" "$dev/cpuclock" "$dev/logic-run.sh" "$dev/$workload" "$dir"
"$fk" "chmod +x $dir/isaac $dir/cpuclock $dir/logic-run.sh"
size=$(stat -c %s "$exe")
# (the console's BusyBox stat has no -c: wc counts the bytes)
if [ "$("$fk" "wc -c < $dir/Isaac.exe 2> /dev/null | tr -d ' ' || echo 0")" != "$size" ]; then
    echo "copying Isaac.exe ($size bytes) to the console"
    "$fk" --push "$exe" "$dir"
fi
"$fk" "sh $dir/logic-run.sh $label $mhz $dir/$workload $*"
mkdir -p "$repo/testing/m1"
rm -rf "$repo/testing/m1/$label"
"$fk" --pull "$dir/out/$label" "$repo/testing/m1"
echo "results: testing/m1/$label"
