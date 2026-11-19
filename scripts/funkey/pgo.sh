#!/bin/bash
# SPDX-License-Identifier: MIT
# Profile-guided build of the FunKey program (GCC's -fprofile-generate / -fprofile-use, upstream's ISAAC_PGO): an
# instrumented build, a training run of it under qemu-arm (no console needed: the profile is the same code's), then
# the build with the profile. All in one build folder, because GCC names the profile files after the object files'
# paths: $TFK_WORK/build-funkey-pgo-thumb (or TFK_PGO_BUILD), the profile in its pgo/. This is the build the OPK
# is made from (M4: the logic 16% faster than the same code without the profile, in Thumb-2 throughout).
#
# usage: scripts/funkey/pgo.sh [generate|train|use|all]   (default all)
#   train: the play script (scripts/device/bundle.sh's play.txt: the title, then 12 rooms on each of floors 1-3)
#          headless with pictures drawn at 240x240, so that the renderer is in the profile too
# Then: scripts/funkey/make-opk.sh $TFK_WORK/build-funkey-pgo-thumb
set -euo pipefail
source "$(dirname "$0")/../env.sh"
build="${TFK_PGO_BUILD:-$TFK_WORK/build-funkey-pgo-thumb}"
pgo="$build/pgo"
step="${1:-all}"

if [ "$step" = generate ] || [ "$step" = all ]; then
    rm -rf "$pgo"
    TFK_BUILD_DIR="$build" bash "$TFK_REPO/scripts/build.sh" funkey -DISAAC_PGO=generate -DISAAC_PGO_DIR="$pgo"
fi
if [ "$step" = train ] || [ "$step" = all ]; then
    [ -f "$TFK_WORK/device/play.txt" ] || { echo "pgo.sh: no play.txt: scripts/device/bundle.sh" >&2; exit 1; }
    run="$build/train"
    rm -rf "$run" "$pgo"; mkdir -p "$run"
    cp "$build/isaac" "$run/"
    grep -v ' shot ' "$TFK_WORK/device/play.txt" > "$run/play.txt"
    t0=$(date +%s)
    (cd "$run" && SDL_AUDIODRIVER=dummy timeout -k 10 7200 qemu-arm -cpu cortex-a7 -L "$TFK_FUNKEY_SYSROOT" ./isaac \
        --headless --size 240x240 --script play.txt "$TFK_WORK/game/Isaac.exe" > out.txt 2> log.txt) || { tail -n 5 "$run/log.txt"; exit 1; }
    echo "training run: $(( $(date +%s) - t0 )) s, $(grep -c '' "$run/log.txt") log lines; profile files: $(find "$pgo" -name '*.gcda' | wc -l)"
fi
if [ "$step" = use ] || [ "$step" = all ]; then
    [ -d "$pgo" ] || { echo "pgo.sh: no profile in $pgo (train first)" >&2; exit 1; }
    TFK_BUILD_DIR="$build" bash "$TFK_REPO/scripts/build.sh" funkey -DISAAC_PGO=use -DISAAC_PGO_DIR="$pgo"
fi
