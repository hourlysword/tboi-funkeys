#!/bin/bash
# SPDX-License-Identifier: MIT
# A kit for testers, out/isaac-kit.zip (scripts/funkey/make-opk.sh first): the OPK with the picture RetroFE shows for
# it in Native games, named like it (opk/make-retrofe.py), the license notices (licenses/,
# scripts/funkey/licenses.sh), and the notes in docs-private/ when there are any (that folder stays on this computer;
# the kit is built without them). No game files.
#
# usage: scripts/funkey/make-kit.sh
set -euo pipefail
source "$(dirname "$0")/../env.sh"
out="$TFK_REPO/out"
[ -f "$out/isaac_funkey-s.opk" ] || { echo "no $out/isaac_funkey-s.opk: scripts/funkey/make-opk.sh" >&2; exit 1; }
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/Native games"
cp "$out/isaac_funkey-s.opk" "$stage/Native games/"
python3 "$TFK_REPO/opk/make-retrofe.py" "$stage/Native games/isaac_funkey-s.png" 60
for note in "$TFK_REPO"/docs-private/*.txt; do [ -f "$note" ] && cp "$note" "$stage/"; done
bash "$TFK_REPO/scripts/funkey/licenses.sh" "$stage/licenses"
rm -f "$out/isaac-kit.zip"
(cd "$stage" && zip -q -r "$out/isaac-kit.zip" .)
echo "$out/isaac-kit.zip: $(du -h "$out/isaac-kit.zip" | cut -f1)"
unzip -l "$out/isaac-kit.zip"
