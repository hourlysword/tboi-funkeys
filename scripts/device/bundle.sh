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
# Continuum (upstream's mod; play.sh ... continuum.txt ISAAC_MODS=continuum): the start, then the run left from the
# pause screen with "No" in the first room and taken up again with A on Start, as the FunKey's D-pad and A work the menus
awk '$1 < 1000 && $2 != "shot"' "$dev/play.txt" > "$dev/continuum.txt"
cat >> "$dev/continuum.txt" << 'EOF'
1100 shot /mnt/FunKey/isaac-dev/shots/c1-room.ppm
1110 down 80
1112 up 80
1160 nav down
1190 nav down
1220 nav confirm
1250 shot /mnt/FunKey/isaac-dev/shots/c2-question.ppm
1260 nav right
1290 nav confirm
1400 shot /mnt/FunKey/isaac-dev/shots/c3-menu.ppm
1420 nav confirm
1600 shot /mnt/FunKey/isaac-dev/shots/c4-resumed.ppm
1601 eval continuum state
1700 quit
EOF
cp "$TFK_REPO/scripts/device/play-run.sh" "$dev/"
rm -f "$dev"/rooms-*.txt "$dev"/short-*.txt
ls -la "$dev"
