#!/bin/bash
# SPDX-License-Identifier: MIT
# Run the FunKey build under qemu-arm as a Cortex-A7 with the FunKey SDK's sysroot, with the armprof plugin counting
# the ARM instructions executed. With ISAAC_TICKMARKS=1 the game writes an "OFKMEM tick ..." line after every logic
# tick, and the plugin records the count at each one in $ARMPROF_OUT.marks (scripts/measure/tick-cost.py reads it).
# The profile itself (per translation block) goes to $ARMPROF_OUT (default armprof.out); armprof.py, from the
# measuring tools of my other FunKey S projects, turns it into a per-function profile.
#
#   ISAAC_TICKMARKS=1 ISAAC_SNAPSHOT=1 ARMPROF_OUT=rooms.prof scripts/measure/qemu-armprof.sh \
#       ~/tboi-funkeys-work/build-funkey/isaac --headless --norender --script rooms-eternal.txt Isaac.exe
#   scripts/measure/tick-cost.py rooms.prof.marks
#
# The run has to end by itself (its script's "quit", or --frames): the plugin writes its files when qemu exits.
# From my other FunKey S projects (the plugin and its qemu too).
set -euo pipefail
source "$(dirname "$0")/../env.sh"
qemu="$TFK_TOOLS/qemu-10.0.3/build/qemu-arm"
plugin="$TFK_TOOLS/libarmprof.so"
[ -x "$qemu" ] && [ -f "$plugin" ] || {
	echo "qemu-armprof.sh: no $qemu or $plugin (qemu 10.0.3 built with plugins, and the armprof plugin, in TFK_TOOLS)" >&2
	exit 1
}
exec "$qemu" -cpu cortex-a7 -L "$TFK_FUNKEY_SYSROOT" -plugin "$plugin,out=${ARMPROF_OUT:-armprof.out}" "$@"
