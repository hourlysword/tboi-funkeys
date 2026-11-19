#!/bin/bash
# SPDX-License-Identifier: MIT
# Build IsaacRecomp from the patched upstream checkout, for the FunKey S or for this PC.
#
# usage: scripts/build.sh [target] [extra cmake args...]
#   target:  funkey (default) - cross-compile for the FunKey S (ISAAC_FUNKEY): GCC 14 for arm-linux-musleabihf with the
#                               FunKey SDK's sysroot and its static SDL2, correct maths functions (build-libm.sh, which
#                               this runs), the PSP's lean loading and small stage (genpsp/), one thread
#            host             - upstream's own Linux build for this machine (gen/, the 1440x1080 stage, worker threads):
#                               the reference the FunKey build is compared against. Headless runs only (OpenGL is
#                               loaded at run time; nothing GL is linked)
#            host-lean        - the same, with the PSP's lean loading (FL_LEAN) and its 363x272 stage (genpsp/), as
#                               the FunKey build uses them: the PC reference for the FunKey's game code
#            host-ref         - host-lean with musl 1.2.1's maths functions in place of glibc's (the FunKey build's,
#                               scripts/measure/build-host-libm.sh): the reference scripts/measure/same-game.sh
#                               compares the FunKey build against, digit for digit
#            host-funkey      - the FunKey configuration (ISAAC_FUNKEY: software renderer, one thread, PSP stage)
#                               built for this PC: headless screenshots from the software renderer
#
# The upstream checkout is $TFK_UPSTREAM (scripts/fetch-upstream.sh); the build goes to $TFK_WORK/build-<target>, or
# to TFK_BUILD_DIR (experiments: e.g. -DISAAC_GEN_FLAGS="-O2 -mthumb" in a folder of its own).
# TFK_JOBS sets the number of parallel compiles (default: 4; the generated game code takes a lot of memory per file,
# and WSL is shared with other projects' builds).
set -euo pipefail
source "$(dirname "$0")/env.sh"

target="${1:-funkey}"
shift $(( $# < 1 ? $# : 1 ))
build="${TFK_BUILD_DIR:-$TFK_WORK/build-$target}"

[ -f "$TFK_UPSTREAM/CMakeLists.txt" ] || { echo "no upstream checkout in $TFK_UPSTREAM: scripts/fetch-upstream.sh" >&2; exit 1; }

args=(-DCMAKE_BUILD_TYPE=Release)
case "$target" in
    funkey)
        [ -x "$TFK_FUNKEY_GCC/bin/arm-linux-musleabihf-gcc" ] ||
            { echo "no GCC 14 for the FunKey in $TFK_FUNKEY_GCC (arm-linux-musleabihf, built with musl-cross-make: TFK_SHARED or TFK_FUNKEY_GCC)" >&2; exit 1; }
        [ -f "$TFK_FUNKEY_SYSROOT/usr/local/lib/libSDL2.a" ] ||
            { echo "no static SDL2 in the FunKey sysroot (SDL2 2.30.9 built as a static library into the SDK's sysroot)" >&2; exit 1; }
        "$TFK_REPO/scripts/funkey/build-libm.sh"
        args+=(-DCMAKE_TOOLCHAIN_FILE="$TFK_REPO/cmake/funkey.cmake" -DFUNKEY_SDK="$TFK_FUNKEY_SDK"
            -DFUNKEY_GCC="$TFK_FUNKEY_GCC" -DFUNKEY_LIBM="$TFK_FUNKEY_LIBM" -DISAAC_FUNKEY=ON
            -DSDL2_DIR="$TFK_FUNKEY_SYSROOT/usr/local/lib/cmake/SDL2") ;;
    host)
        args+=(-DNO_SYSTEM_GL=ON) ;;
    host-lean)
        args+=(-DNO_SYSTEM_GL=ON -DISAAC_LEAN=ON -DISAAC_GEN_DIR=genpsp) ;;
    host-funkey)
        args+=(-DISAAC_FUNKEY=ON) ;;
    host-ref)
        bash "$TFK_REPO/scripts/measure/build-host-libm.sh"
        args+=(-DNO_SYSTEM_GL=ON -DISAAC_LEAN=ON -DISAAC_GEN_DIR=genpsp
            "-DCMAKE_EXE_LINKER_FLAGS=-Wl,--whole-archive $TFK_WORK/host-libm/libmuslm.a -Wl,--no-whole-archive -lm") ;;
    *) echo "unknown target: $target" >&2; exit 1 ;;
esac

cmake -S "$TFK_UPSTREAM" -B "$build" -G Ninja "${args[@]}" "$@"
# The maths archive is only named in the link flags, so the build doesn't know to link again when it changes.
if [ "$target" = funkey ] && [ "$TFK_FUNKEY_LIBM" -nt "$build/isaac" ]; then
    rm -f "$build/isaac"
fi
# -k 0: keep going past failures so one pass reports every broken file.
cmake --build "$build" --target isaac -j"${TFK_JOBS:-4}" -- -k 0

echo "built: $build/isaac"
if [ "$target" = funkey ]; then
    "$TFK_REPO/scripts/funkey/check-elf.sh" "$build/isaac"
else
    size "$build/isaac"
fi
