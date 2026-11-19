#!/bin/bash
# SPDX-License-Identifier: MIT
# Clone IsaacRecomp at the pinned commit into $TFK_WORK/IsaacRecomp and apply this project's patch series on a
# "funkey" branch.
#
# usage: scripts/fetch-upstream.sh
#
# Work on the funkey branch of that checkout, then scripts/export-patches.sh refreshes patches/isaacrecomp. Running
# this again on an existing checkout re-applies the series from scratch (uncommitted work there is kept aside by git).
#
# Adapted from my other FunKey S projects (IsaacRecomp has no submodules).
set -euo pipefail
source "$(dirname "$0")/env.sh"

mkdir -p "$TFK_WORK"
if [ ! -d "$TFK_UPSTREAM/.git" ]; then
    git clone --no-checkout "$TFK_UPSTREAM_URL" "$TFK_UPSTREAM"
fi
git -C "$TFK_UPSTREAM" fetch -q origin "$TFK_UPSTREAM_COMMIT" 2>/dev/null ||
    git -C "$TFK_UPSTREAM" fetch -q origin
git -C "$TFK_UPSTREAM" checkout -q --detach "$TFK_UPSTREAM_COMMIT"

git -C "$TFK_UPSTREAM" checkout -q -B funkey "$TFK_UPSTREAM_COMMIT"
if compgen -G "$TFK_REPO/patches/isaacrecomp/*.patch" > /dev/null; then
    git -C "$TFK_UPSTREAM" am -q --3way "$TFK_REPO"/patches/isaacrecomp/*.patch
fi
echo "upstream ready in $TFK_UPSTREAM (branch funkey, $(git -C "$TFK_UPSTREAM" rev-list --count "$TFK_UPSTREAM_COMMIT"..funkey) patches applied)"
