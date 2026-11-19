#!/bin/bash
# SPDX-License-Identifier: MIT
# Write the commits on the "funkey" branch of the upstream checkout as the patch series patches/isaacrecomp.
#
# usage: scripts/export-patches.sh
#
# Patches must never carry generated game code (gen*/: upstream's licence leaves it out, it is the game's own code
# translated); the export refuses a series that touches it.
set -euo pipefail
source "$(dirname "$0")/env.sh"

series="$TFK_REPO/patches/isaacrecomp"
if git -C "$TFK_UPSTREAM" diff --name-only "$TFK_UPSTREAM_COMMIT..funkey" | grep -E '^(gen[^/]*|patch[0-9]+)/'; then
    echo "export-patches: the series above touches generated game code; keep it out of the patches" >&2
    exit 1
fi
rm -rf "$series"
mkdir -p "$series"
git -C "$TFK_UPSTREAM" format-patch -q --no-numbered --no-signature --zero-commit -o "$series" "$TFK_UPSTREAM_COMMIT..funkey"
echo "$series: $(ls "$series" | wc -l) patches"
