#!/bin/bash
# SPDX-License-Identifier: MIT
# Check that the FunKey build plays exactly as the PC build does: the same workload, with every enemy's state dumped at
# every tick ("eval balls": position, speed, health, animation frame...), run by the lean PC build (x86-64, the PSP
# stage, as upstream builds it with ISAAC_LEAN, with musl's maths functions like the FunKey build: build.sh host-ref) and by
# the FunKey build under qemu-arm. The two logs must be identical
# line for line. A difference means the ARM build computes something differently: maths functions (the console's libm
# is wrong; libfkm.a replaces it), fused multiply-adds, flags.
#
# usage: scripts/measure/same-game.sh [floors] [rooms per floor] [ticks per room]
#   default 3 12 300 (the M1 workload); results in $TFK_WORK/same-game/
# Runs in WSL, after scripts/build.sh host-lean, host-ref and funkey. TFK_ARM_BUILD: another FunKey build folder
# (default $TFK_WORK/build-funkey; e.g. build-funkey-pgo from scripts/funkey/pgo.sh).
set -euo pipefail
source "$(dirname "$0")/../env.sh"
floors="${1:-3}"
rooms="${2:-12}"
ticks="${3:-300}"
out="$TFK_WORK/same-game"
exe="$TFK_WORK/game/Isaac.exe"
[ -f "$exe" ] || { mkdir -p "$TFK_WORK/game"; cp "$TFK_GAME_DIR/The Binding Of Isaac/Isaac.exe" "$exe"; }

# Upstream's tests/start_game.txt starts a run in every version (scripts/device/bundle.sh).
game=$(ISAAC_NOLEAN=1 SDL_AUDIODRIVER=dummy timeout 60 "$TFK_WORK/build-host-lean/isaac" --headless --norender \
    --frames 1 "$exe" 2>&1 | sed -n 's/^game: //p' | head -n 1)
start="$TFK_UPSTREAM/tests/start_game.txt"
mkdir -p "$out/pc" "$out/arm"
python3 "$TFK_REPO/scripts/measure/workload.py" --start "$start" --scale "$(python3 -c 'print(363 / 1440)')" \
    --floors "$floors" --rooms "$rooms" --ticks "$ticks" --balls > "$out/workload.txt"
echo "$game: $(tail -n 1 "$out/workload.txt" | cut -d' ' -f1) ticks"

# Each build in its own folder (saves and the SWF cache go next to the program). Fresh saves each time.
cp "$TFK_WORK/build-host-ref/isaac" "$out/pc/isaac"
cp "${TFK_ARM_BUILD:-$TFK_WORK/build-funkey}/isaac" "$out/arm/isaac"
rm -rf "$out/pc/saves/"*.sol "$out/arm/saves/"*.sol
(cd "$out/pc" && SDL_AUDIODRIVER=dummy timeout -k 10 3600 ./isaac --headless --norender --script ../workload.txt "$exe" \
    > stdout.txt 2> log.txt) &
(cd "$out/arm" && SDL_AUDIODRIVER=dummy timeout -k 10 7200 qemu-arm -cpu cortex-a7 -L "$TFK_FUNKEY_SYSROOT" ./isaac \
    --headless --norender --script ../workload.txt "$exe" > stdout.txt 2> log.txt) &
wait
for b in pc arm; do
    grep -E '^\[(ball|eval|call)\]' "$out/$b/log.txt" > "$out/$b/state.txt" || true
    echo "$b: $(wc -l < "$out/$b/state.txt") state lines, $(grep -c '^\[ball\]' "$out/$b/state.txt") enemy states;" \
        "$(grep '^logic ticks' "$out/$b/log.txt")"
done
if [ "$(grep -c '^\[ball\]' "$out/pc/state.txt")" -lt 1000 ]; then
    echo "NOT CHECKED: fewer than 1000 enemy states (the workload didn't reach a run?)"
    exit 1
elif cmp -s "$out/pc/state.txt" "$out/arm/state.txt"; then
    echo "SAME GAME: the FunKey build's logic matches the PC build's on every line"
else
    echo "DIFFERENT: first differences (pc < > arm):"
    diff "$out/pc/state.txt" "$out/arm/state.txt" | head -n 20
    exit 1
fi
