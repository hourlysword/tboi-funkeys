#!/bin/bash
# SPDX-License-Identifier: MIT
# Prepare what scripts/device/logic.sh copies to the console, in $TFK_WORK/device: the FunKey build stripped (the
# unstripped one stays in build-funkey for symbols), cpuclock, logic-run.sh, and the M1 workloads (scripts/measure/
# workload.py) for the PSP stage the FunKey build uses. Runs in WSL, after scripts/build.sh funkey.
#
# usage: scripts/device/bundle.sh
set -euo pipefail
source "$(dirname "$0")/../env.sh"

dev="$TFK_WORK/device"
mkdir -p "$dev"
"$TFK_FUNKEY_BIN-strip" -o "$dev/isaac" "$TFK_WORK/build-funkey/isaac"
"$TFK_FUNKEY_BIN-gcc" -O2 -Wall -o "$dev/cpuclock" "$TFK_REPO/scripts/funkey/cpuclock.c"
cp "$TFK_REPO/scripts/device/logic-run.sh" "$dev/"

# Upstream's tests/start_game.txt starts a run in every version, the Eternal Edition included (its difftest
# start_eternal.txt, for the Ruffle harness, doesn't with this build: checked 2026-10-30). Mouse coordinates are for the
# 1440x1080 stage: scaled to genpsp's 363x272.
scale=$(python3 -c 'print(363 / 1440)')
start="$TFK_UPSTREAM/tests/start_game.txt"
# Floors 1-3, 12 random rooms each, 10 s per room: about 12,600 ticks (7 minutes of play)
python3 "$TFK_REPO/scripts/measure/workload.py" --start "$start" --scale "$scale" --floors 3 --rooms 12 \
    --ticks 300 > "$dev/rooms.txt"
# The title and the first rooms only (the first start, quick checks)
python3 "$TFK_REPO/scripts/measure/workload.py" --start "$start" --scale "$scale" --floors 1 --rooms 2 \
    --ticks 150 > "$dev/short.txt"
# For scripts/device/play.sh: the same rooms, with the picture saved now and then (play-run.sh's shots folder)
cp "$dev/rooms.txt" "$dev/play.txt"
for t in 400 1100 2500 4000 6000 9500 12000; do echo "$t shot /mnt/FunKey/isaac-dev/shots/s$t.ppm" >> "$dev/play.txt"; done
sort -n -s -k1,1 "$dev/play.txt" -o "$dev/play.txt"
cp "$TFK_REPO/scripts/device/play-run.sh" "$dev/"
rm -f "$dev"/rooms-*.txt "$dev"/short-*.txt
ls -la "$dev"
