# SPDX-License-Identifier: MIT
# Common settings for the tboi-funkeys scripts. Source this file from bash, on Linux (in WSL: as root).
#
# The repository (this checkout, TFK_REPO) holds our patches, scripts and docs; it may sit on Windows (/mnt/c). The
# upstream IsaacRecomp checkout and every build live in TFK_WORK, which must be on a Linux filesystem (in WSL: under
# $HOME, not /mnt/c): the generated game code is thousands of large files, and building through /mnt/c is many times
# slower.
#
# Adapted from my other FunKey S projects.

TFK_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TFK_WORK="${TFK_WORK:-$HOME/tboi-funkeys-work}"

# Upstream IsaacRecomp, pinned to a commit. Our changes are a patch series in patches/isaacrecomp, applied on a
# "funkey" branch (scripts/fetch-upstream.sh, scripts/export-patches.sh).
TFK_UPSTREAM_URL="https://github.com/whylurking/IsaacRecomp.git"
TFK_UPSTREAM_COMMIT="a2cfc669c999f2503001e8331ee27b084dfec0a8"   # v1.5.0, 2026-10-30
TFK_UPSTREAM="$TFK_WORK/IsaacRecomp"

# The player's game: the Steam Isaac.exe (one or several versions), never committed. scripts/build.sh and the test
# scripts look in "game files" next to this repository unless TFK_GAME_DIR says otherwise.
TFK_GAME_DIR="${TFK_GAME_DIR:-$TFK_REPO/game files}"

# Tools shared with my other FunKey S projects, used when they are there: TFK_SHARED (default ~/funkey-shared) holds
# funkey/FunKey-sdk-2.3.0, funkey/gcc14, funkey/musl-cross-make/sources and tools/qemu-10.0.3; otherwise each is
# looked for under TFK_WORK.
TFK_SHARED="${TFK_SHARED:-$HOME/funkey-shared}"

# FunKey SDK (FunKey-OS 2.3.0: GCC 10.2, musl 1.2.1 and the console's libraries in its sysroot, plus a static SDL2
# 2.30.9 built into it) and GCC 14 for the same target.
if [ -z "${TFK_FUNKEY_SDK:-}" ]; then
    if [ -d "$TFK_SHARED/funkey/FunKey-sdk-2.3.0" ]; then
        TFK_FUNKEY_SDK="$TFK_SHARED/funkey/FunKey-sdk-2.3.0"
    else
        TFK_FUNKEY_SDK="$TFK_WORK/funkey/FunKey-sdk-2.3.0"
    fi
fi
if [ -z "${TFK_FUNKEY_GCC:-}" ]; then
    if [ -x "$TFK_SHARED/funkey/gcc14/bin/arm-linux-musleabihf-gcc" ]; then
        TFK_FUNKEY_GCC="$TFK_SHARED/funkey/gcc14"
    else
        TFK_FUNKEY_GCC="$TFK_WORK/funkey/gcc14"
    fi
fi
TFK_FUNKEY_SYSROOT="$TFK_FUNKEY_SDK/arm-funkey-linux-musleabihf/sysroot"
TFK_FUNKEY_BIN="$TFK_FUNKEY_SDK/bin/arm-funkey-linux-musleabihf"
# Correct maths functions, linked into every FunKey program in place of the console's (FunKey-OS builds its C library
# with -Ofast and floor/round/... are wrong there; for this game that would change its logic: Math.floor and friends
# decide positions, damage and random rolls). Built by scripts/funkey/build-libm.sh, in ARM mode like the rest of this
# port.
TFK_FUNKEY_LIBM="${TFK_FUNKEY_LIBM:-$TFK_WORK/funkey/libfkm/libfkm.a}"

# The speed measurement's QEMU with plugin support and the armprof plugin, which counts the ARM instructions executed
# (scripts/measure/qemu-armprof.sh), from my other FunKey S projects.
if [ -z "${TFK_TOOLS:-}" ]; then
    if [ -x "$TFK_SHARED/tools/qemu-10.0.3/build/qemu-arm" ]; then
        TFK_TOOLS="$TFK_SHARED/tools"
    else
        TFK_TOOLS="$TFK_WORK/tools"
    fi
fi
