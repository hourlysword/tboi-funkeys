#!/bin/bash
# SPDX-License-Identifier: MIT
# Build correct maths functions for the FunKey S, $TFK_FUNKEY_LIBM ($TFK_WORK/funkey/libfkm/libfkm.a), which the game
# links in whole (cmake/funkey-static.cmake). FunKey-OS builds its C library with -Ofast, and its maths functions are
# wrong whatever flags a program is built with: on the console floor(-3.5) = -3.5, round(2.6) = 2.6, and ceil, rint,
# roundf and lroundf are wrong too (9 of 18 checks fail; none with this archive; the SDK's copy of the library is the
# same). The game's ActionScript calls them through Math.floor, Math.round and friends, so wrong results there would
# change the game's logic, not only a picture.
# This is the same code built correctly: musl 1.2.1's src/math (the console's own C library version) with musl's own
# flags for it (-std=c99, so no fused multiply-adds, -frounding-math -fexcess-precision=standard), at -O2 with the
# FunKey's CPU flags. From my other FunKey S projects.
#
# usage: scripts/funkey/build-libm.sh
# build.sh runs it for FunKey builds. It does nothing when the archive was built by this version of the script with the
# same compiler. The source is musl-cross-make's download (build-gcc.sh), or is downloaded.
set -euo pipefail
source "$(dirname "$0")/../env.sh"

version=1.2.1
sha1=031062cf1a3c3e81e3dbae5ad2edbeff02ca198f  # musl-cross-make's hashes/musl-1.2.1.tar.gz.sha1
# GCC 14 when there is one (it makes faster code), otherwise the SDK's GCC 10: either suits both FunKey builds.
if [ -x "$TFK_FUNKEY_GCC/bin/arm-linux-musleabihf-gcc" ]; then
    bin="$TFK_FUNKEY_GCC/bin/arm-linux-musleabihf"
else
    bin="$TFK_FUNKEY_SDK/bin/arm-funkey-linux-musleabihf"
fi
[ -x "$bin-gcc" ] || { echo "no FunKey compiler: scripts/funkey/get-sdk.sh" >&2; exit 1; }
# cmake/funkey.cmake's TFK_ARM_FLAGS.
cflags="-O2 -march=armv7ve -mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard -marm"
lib="$TFK_FUNKEY_LIBM"
out="$(dirname "$lib")"

stamp="$(sha256sum < "${BASH_SOURCE[0]}" | cut -d' ' -f1) $("$bin-gcc" --version | head -n 1)"
if [ -f "$lib" ] && [ "$(cat "$out/stamp" 2> /dev/null)" = "$stamp" ]; then
    exit 0
fi
mkdir -p "$out"

# The source: musl-cross-make's download (here, or in the tools shared with my other FunKey S projects, TFK_SHARED), or
# downloaded.
tarball=""
for candidate in "$TFK_WORK/funkey/musl-cross-make/sources/musl-$version.tar.gz"     "$TFK_SHARED/funkey/musl-cross-make/sources/musl-$version.tar.gz" "$out/musl-$version.tar.gz"; do
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
(cd "$src" && CC="$bin-gcc" CFLAGS="$cflags" ./configure --target=arm-linux-musleabihf --disable-shared) \
    > "$out/configure.log" 2>&1 || { tail -n 20 "$out/configure.log" >&2; exit 1; }
# Only the maths objects, as musl's Makefile lists them: its ARM versions (VFP instructions for fabs, sqrt, fma) in
# place of the generic ones.
printf 'include Makefile\nprint-maths:\n\t@echo $(filter obj/src/math/%%,$(ALL_OBJS))\n' > "$build/maths.mk"
objs="$(make -s -C "$src" -f "$build/maths.mk" print-maths)"
[ -n "$objs" ] || { echo "musl's Makefile lists no maths objects" >&2; exit 1; }
make -C "$src" -j"$(nproc)" $objs > "$out/make.log" 2>&1 || { grep -m 20 -E 'error|Error' "$out/make.log" >&2; exit 1; }
rm -f "$lib.tmp"
(cd "$src" && "$bin-ar" rcs "$lib.tmp" $objs)
mv -f "$lib.tmp" "$lib"
echo "$stamp" > "$out/stamp"
rm -rf "$build"

# What the archive takes from elsewhere: only libgcc's float to 64-bit conversions and the C library's fenv functions
# (assembly, unharmed by -Ofast).
defined="$("$bin-nm" -g --defined-only "$lib" | awk 'NF == 3 {print $3}' | sort -u)"
needs="$("$bin-nm" -g --undefined-only "$lib" | awk '{print $2}' | sort -u | comm -23 - <(echo "$defined"))"
echo "$lib: musl $version's maths, $(echo $objs | wc -w) objects, $(echo "$defined" | wc -l) symbols," \
    "$("$bin-size" -t "$lib" | awk 'END {print $1}') bytes of code; needs" $needs
