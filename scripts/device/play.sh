#!/bin/bash
# SPDX-License-Identifier: MIT
# Play a test script with the game's own loop on the FunKey's screen, and bring the results back (M3). Runs on Windows
# (Git Bash: WSL can't reach the console's USB network), after scripts/device/bundle.sh in WSL.
#
# usage: scripts/device/play.sh <label> <MHz> <workload> [NAME=value ...]
#   e.g. scripts/device/play.sh play-1296 1296 rooms.txt
#   PROFILE=1: fkprof (a whole-system sampling profiler, TFK_FKPROF_BIN) runs next to the game: fkprof.txt in the
#     results, read with scripts/measure/fkreport.py. TFK_RESULTS: where the results go (default testing/m3).
#   TFK_DEVICE_BUNDLE: another bundle folder; TFK_MENU_OFF_OK=1: run although no menu is running on the console;
#   NO_TICKMARKS=1: no per-tick lines in the log (long runs: the log is kept in the console's RAM until the end).
#   TFK_BIN: the program to run on the console instead of the bundle's, e.g. one in an OPK mounted on the console
#     (squashfs, as players run it: its pages are read and decompressed block by block, unlike from the card).
#
# Copies the bundle into /mnt/FunKey/isaac-dev (Isaac.exe the first time), stops the menu for the run (play-run.sh
# puts it back), and copies out/<label> into testing/m3/<label>, with the last picture as a PNG.
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
label="${1:?usage: play.sh <label> <MHz> <workload> [NAME=value ...]}"
mhz="${2:?usage}"
workload="${3:?usage}"
shift 3
fk="$repo/scripts/device/fk.sh"
dev="${TFK_DEVICE_BUNDLE:-//wsl.localhost/Debian/root/tboi-funkeys-work/device}"
dir=/mnt/FunKey/isaac-dev
exe="${TFK_GAME_EXE:-$repo/game files/The Binding Of Isaac/Isaac.exe}"
res="$repo/${TFK_RESULTS:-testing/m3}"
fkprof="${TFK_FKPROF_BIN:-}"
[ -z "${PROFILE:-}" ] || [ -f "$fkprof" ] || { echo "play.sh: PROFILE=1 needs TFK_FKPROF_BIN, the fkprof binary" >&2; exit 1; }

[ -f "$dev/isaac" ] || { echo "play.sh: no bundle in $dev (scripts/device/bundle.sh in WSL)" >&2; exit 1; }
busy=$("$fk" 'for p in /proc/[0-9]*; do r=$(awk "/^VmRSS/ {print \$2}" $p/status 2> /dev/null); a=$(tr "\0" " " < $p/cmdline 2> /dev/null | cut -c1-120); [ -n "$r" ] && [ "$r" -gt 4096 ] && case "$a" in *gmenu2x*|*retrofe*) ;; *) echo "$r kB: $a" ;; esac; done
menu=$(pidof gmenu2x retrofe); if [ -z "$menu" ]; then echo "the menu is not running"; else for m in $menu; do [ "$(awk "{print \$3}" /proc/$m/stat)" = T ] && echo "the menu is paused (pid $m)"; done; fi; true')
# TFK_MENU_OFF_OK=1: no menu running is fine (none was when we came, and play-run.sh starts none)
[ "${TFK_MENU_OFF_OK:-}" = 1 ] && busy=$(printf '%s\n' "$busy" | grep -v '^the menu is not running$' || true)
if [ -n "$busy" ]; then
    echo "play.sh: the console is busy:" >&2
    echo "$busy" >&2
    exit 2
fi
"$fk" --push "$dev/isaac" "$dev/cpuclock" "$repo/scripts/device/play-run.sh" "$dev/$workload" "$dir"
"$fk" "chmod +x $dir/isaac $dir/cpuclock $dir/play-run.sh"
size=$(stat -c %s "$exe")
if [ "$("$fk" "wc -c < $dir/Isaac.exe 2> /dev/null | tr -d ' ' || echo 0")" != "$size" ]; then
    echo "copying Isaac.exe ($size bytes) to the console"
    "$fk" --push "$exe" "$dir"
fi
prefix=""
if [ -n "${PROFILE:-}" ]; then
    "$fk" --push "$fkprof" "$dir"
    "$fk" "chmod +x $dir/fkprof"
    prefix="TFK_FKPROF=1"
fi
[ -n "${NO_TICKMARKS:-}" ] && prefix="$prefix TFK_NO_TICKMARKS=1"   # (long runs: no per-tick lines in the log)
[ -n "${TFK_BIN:-}" ] && prefix="$prefix TFK_BIN=$TFK_BIN"
"$fk" "$prefix sh $dir/play-run.sh $label $mhz $dir/$workload $*"
mkdir -p "$res"
rm -rf "$res/$label"
"$fk" --pull "$dir/out/$label" "$res"
# the screen at the end (RGB565, 240x240) as a PNG
"${PYTHON:-python}" - "$res/$label/fb.raw" "$res/$label/fb.png" << 'EOF' || true
import struct, sys, zlib
raw = open(sys.argv[1], "rb").read()
w = h = 240
if len(raw) >= w * h * 2:
    rows = []
    for y in range(h):
        row = bytearray(b"\0")
        for x in range(w):
            v = raw[(y * w + x) * 2] | raw[(y * w + x) * 2 + 1] << 8
            row += bytes(((v >> 11) * 255 // 31, ((v >> 5) & 63) * 255 // 63, (v & 31) * 255 // 31))
        rows.append(bytes(row))
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    open(sys.argv[2], "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(b"".join(rows))) + chunk(b"IEND", b""))
EOF
echo "results: ${res#$repo/}/$label"
