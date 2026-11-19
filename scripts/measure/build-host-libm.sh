#!/bin/bash
# SPDX-License-Identifier: MIT
# Build musl 1.2.1's maths functions for this PC (x86-64), $TFK_WORK/host-libm/libmuslm.a, for the PC reference build
# that scripts/measure/same-game.sh compares the FunKey build against (scripts/build.sh host-ref).
#
# Why: the FunKey build takes its maths functions from musl 1.2.1 (libfkm.a, the console's own C library version built
# correctly), the PC build from glibc. The two round sin, cos, atan2, pow... differently in the last bit now and then:
# the game plays the same, but every enemy's state no longer matches digit for digit, and a real difference (a compiler
# flag, a fused multiply-add) would hide among those. With the same maths code on both sides, any difference left is
# the FunKey build's.
#
# usage: scripts/measure/build-host-libm.sh   (in WSL; does nothing when the archive is up to date)
set -euo pipefail
source "$(dirname "$0")/../env.sh"

version=1.2.1
sha1=031062cf1a3c3e81e3dbae5ad2edbeff02ca198f  # musl-cross-make's hashes/musl-1.2.1.tar.gz.sha1
out="$TFK_WORK/host-libm"
lib="$out/libmuslm.a"
stamp="$(sha256sum < "${BASH_SOURCE[0]}" | cut -d' ' -f1) $(gcc --version | head -n 1)"
if [ -f "$lib" ] && [ "$(cat "$out/stamp" 2> /dev/null)" = "$stamp" ]; then
    exit 0
fi
mkdir -p "$out"
tarball=""
for candidate in "$TFK_WORK/funkey/musl-cross-make/sources/musl-$version.tar.gz" \
    "$TFK_SHARED/funkey/musl-cross-make/sources/musl-$version.tar.gz" "$out/musl-$version.tar.gz"; do
    if [ -f "$candidate" ]; then
        tarball="$candidate"
        break
    fi
done
if [ -z "$tarball" ]; then
    tarball="$out/musl-$version.tar.gz"
    curl -fsSL -o "$tarball.part" "https://musl.libc.org/releases/musl-$version.tar.gz"
    mv -f "$tarball.part" "$tarball"
fi
echo "$sha1  $tarball" | sha1sum -c --quiet - || { echo "$tarball isn't musl $version's release" >&2; exit 1; }

build="$out/build"
rm -rf "$build"
mkdir -p "$build"
tar -xzf "$tarball" -C "$build"
src="$build/musl-$version"
# -fPIE: the PC build is a position-independent executable. Like build-libm.sh: musl's own flags for its maths (no
# fused multiply-adds, -frounding-math), -O2.
(cd "$src" && CC=gcc CFLAGS="-O2 -fPIE" ./configure --target=x86_64-linux-musl --disable-shared) \
    > "$out/configure.log" 2>&1 || { tail -n 20 "$out/configure.log" >&2; exit 1; }
printf 'include Makefile\nprint-maths:\n\t@echo $(filter obj/src/math/%%,$(ALL_OBJS))\n' > "$build/maths.mk"
objs="$(make -s -C "$src" -f "$build/maths.mk" print-maths)"
make -C "$src" -j"$(nproc)" $objs > "$out/make.log" 2>&1 || { grep -m 20 -E 'error|Error' "$out/make.log" >&2; exit 1; }
rm -f "$lib.tmp"
(cd "$src" && ar rcs "$lib.tmp" $objs)
mv -f "$lib.tmp" "$lib"
echo "$stamp" > "$out/stamp"
rm -rf "$build"
echo "$lib: musl $version's maths for x86-64, $(ar t "$lib" | wc -l) objects"
