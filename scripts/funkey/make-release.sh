#!/bin/bash
# SPDX-License-Identifier: MIT
# The release zip for players: only what goes on the FunKey's USB share, Native games/isaac_funkey-s.opk and the
# picture RetroFE shows for it (opk/make-retrofe.py). Unzipped at the root of the share, both land in Native games.
# The license notices travel inside the OPK (licenses/, make-opk.sh); nothing of the game's goes in (players copy their
# own Isaac.exe into FunKey/isaac).
#
# usage: scripts/funkey/make-release.sh <version>   (after scripts/funkey/make-opk.sh)
#   writes out/tboi-funkeys-<version>.zip, e.g. make-release.sh v1.0.0
set -euo pipefail
source "$(dirname "$0")/../env.sh"
version="${1:?usage: make-release.sh <version, e.g. v1.0.0>}"
out="$TFK_REPO/out"
opk="$out/isaac_funkey-s.opk"
[ -f "$opk" ] || { echo "no $opk: scripts/funkey/make-opk.sh" >&2; exit 1; }
unsquashfs -l "$opk" | grep -q 'licenses/LICENSE.txt' || { echo "$opk carries no licenses/: make-opk.sh again" >&2; exit 1; }
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/Native games"
cp "$opk" "$stage/Native games/"
python3 "$TFK_REPO/opk/make-retrofe.py" "$stage/Native games/isaac_funkey-s.png" 60
zip="$out/tboi-funkeys-$version.zip"
rm -f "$zip"
(cd "$stage" && zip -q -r "$zip" .)
echo "$zip: $(du -h "$zip" | cut -f1)"
unzip -l "$zip"
