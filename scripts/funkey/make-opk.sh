#!/bin/bash
# SPDX-License-Identifier: MIT
# Package the FunKey build as an OPK (a squashfs image the FunKey launcher mounts at /opk and runs from): the game
# program (stripped), its launcher script, the CPU clock tool, an icon, the desktop entry and the license notices
# (licenses/, scripts/funkey/licenses.sh).
#
# Nothing of the game's goes in: the player copies their own Isaac.exe into FunKey/isaac on the console.
#
# usage: scripts/funkey/make-opk.sh [build directory] [output.opk]
#   build directory: default $TFK_WORK/build-funkey (scripts/build.sh funkey)
#   output:          default $TFK_REPO/out/isaac_funkey-s.opk
#
# Adapted from my other FunKey S projects.
set -euo pipefail
source "$(dirname "$0")/../env.sh"

build="${1:-$TFK_WORK/build-funkey}"
out="${2:-$TFK_REPO/out/isaac_funkey-s.opk}"
elf="$build/isaac"
[ -f "$elf" ] || { echo "no FunKey build in $build: scripts/build.sh funkey" >&2; exit 1; }

"$TFK_REPO/scripts/funkey/check-elf.sh" "$elf"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
chmod 755 "$stage"
"$TFK_FUNKEY_BIN-strip" -o "$stage/isaac" "$elf"
install -m 755 "$TFK_REPO/opk/isaac.sh" "$stage/isaac.sh"
install -m 644 "$TFK_REPO/opk/isaac.funkey-s.desktop" "$stage/"
"$TFK_FUNKEY_BIN-gcc" -O2 -Wall -Wextra -Werror -s -o "$stage/cpuclock" "$TFK_REPO/scripts/funkey/cpuclock.c"
python3 "$TFK_REPO/opk/make-icon.py" "$stage/isaac.png"
bash "$TFK_REPO/scripts/funkey/licenses.sh" "$stage/licenses"
# (a version line: which upstream commit and patches the program was built from)
{
    echo "IsaacRecomp $(git -C "$TFK_UPSTREAM" rev-parse --short "$TFK_UPSTREAM_COMMIT") + $(git -C "$TFK_UPSTREAM" rev-list --count "$TFK_UPSTREAM_COMMIT"..HEAD) patches ($(git -C "$TFK_UPSTREAM" rev-parse --short HEAD)$(git -C "$TFK_UPSTREAM" diff --quiet HEAD -- . ':!gen*' || echo ", changed"))"
    echo "tboi-funkeys $(git -C "$TFK_REPO" rev-parse --short HEAD 2> /dev/null || echo '?')$(git -C "$TFK_REPO" diff --quiet HEAD 2> /dev/null || echo ', changed')"
    date -u '+built %Y-%m-%d %H:%M UTC'
} > "$stage/version.txt"

mkdir -p "$(dirname "$out")"
rm -f "$out"
"$TFK_FUNKEY_SDK/bin/mksquashfs" "$stage" "$out" -all-root -noappend -no-exports -no-xattrs -quiet
echo "$out: $(du -h "$out" | cut -f1)"
ls -l "$stage"
cat "$stage/version.txt"
