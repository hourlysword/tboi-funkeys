#!/bin/bash
# SPDX-License-Identifier: MIT
# The license notices that go with the program wherever it goes (into the OPK and the kit): this repository's LICENSE,
# IsaacRecomp's (the engine), and the third-party code built into the binary: upstream's list (SDL2, PlutoVG, dr_mp3,
# stb_image), zlib (the FunKey SDK's 1.2.11) and musl's maths functions (libfkm.a: musl 1.2.1's src/math, with musl's
# COPYRIGHT). The game's own code that IsaacRecomp translated is covered by none of them (see IsaacRecomp-LICENSE.txt).
#
# usage: scripts/funkey/licenses.sh <folder>
set -euo pipefail
source "$(dirname "$0")/../env.sh"
dir="${1:?usage: licenses.sh <folder>}"
mkdir -p "$dir"
cp "$TFK_REPO/LICENSE" "$dir/LICENSE.txt"
cp "$TFK_UPSTREAM/LICENSE" "$dir/IsaacRecomp-LICENSE.txt"

# musl's release, as build-libm.sh finds it
tarball=""
for candidate in "$TFK_WORK/funkey/musl-cross-make/sources/musl-1.2.1.tar.gz" \
        "$TFK_SHARED/funkey/musl-cross-make/sources/musl-1.2.1.tar.gz" \
        "$(dirname "$TFK_FUNKEY_LIBM")/musl-1.2.1.tar.gz"; do
    [ -f "$candidate" ] && { tarball="$candidate"; break; }
done
[ -n "$tarball" ] || { echo "licenses.sh: no musl-1.2.1.tar.gz (scripts/funkey/build-libm.sh downloads it)" >&2; exit 1; }

{
    cat "$TFK_UPSTREAM/THIRD-PARTY-LICENSES.txt"
    echo
    echo "zlib (https://zlib.net), 1.2.11, built into the FunKey S program — zlib license, Copyright (C) 1995-2017"
    echo "Jean-loup Gailly and Mark Adler:"
    echo "  This software is provided 'as-is', without any express or implied warranty. In no event will the authors be"
    echo "  held liable for any damages arising from the use of this software. Permission is granted to anyone to use this"
    echo "  software for any purpose, including commercial applications, and to alter it and redistribute it freely,"
    echo "  subject to the following restrictions: 1. The origin of this software must not be misrepresented; you must"
    echo "  not claim that you wrote the original software. If you use this software in a product, an acknowledgment in"
    echo "  the product documentation would be appreciated but is not required. 2. Altered source versions must be"
    echo "  plainly marked as such, and must not be misrepresented as being the original software. 3. This notice may"
    echo "  not be removed or altered from any source distribution."
    echo
    echo "musl (https://musl.libc.org), its maths functions (src/math of musl 1.2.1, built into the FunKey S program as"
    echo "libfkm.a: the console's own copy computes some of them wrong) — MIT license and the notices of the code it comes"
    echo "from. musl's COPYRIGHT file:"
    tar -xzOf "$tarball" musl-1.2.1/COPYRIGHT | sed 's/^/  /'
} > "$dir/THIRD-PARTY-LICENSES.txt"
