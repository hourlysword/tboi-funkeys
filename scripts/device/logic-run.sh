#!/bin/sh
# SPDX-License-Identifier: MIT
# Runs on the FunKey (scripts/device/logic.sh pushes and starts it): the game's logic headless, with no screen and no
# sound (--headless --norender), one line per tick with its wall-clock and CPU time (ISAAC_TICKMARKS), the snapshot a
# renderer would get built every tick (ISAAC_SNAPSHOT), the CPU clock set for the run and put back after it, and the
# game's memory sampled every 2 s. M1 of docs/porting-plan.md.
#
# usage: logic-run.sh <label> <MHz, 0 = leave the clock> <script> [NAME=value ...]
#   results in out/<label>/ next to this script: log.txt (the game's log), mem.txt, before.txt, result.txt
#   NAME=value: more environment for the game (e.g. ISAAC_GCMINLIVE=30000)
#
# The menu is left running: tick-cost.py reads the CPU time of the game's own thread, which other programs don't
# change. The game's log goes to /tmp (RAM) while it runs, so that writing it doesn't slow the ticks down.

here="$(cd "$(dirname "$0")" && pwd)"
label="${1:?usage: logic-run.sh <label> <MHz> <script> [NAME=value ...]}"
mhz="${2:?usage: logic-run.sh <label> <MHz> <script> [NAME=value ...]}"
script="${3:?usage: logic-run.sh <label> <MHz> <script> [NAME=value ...]}"
shift 3
out="$here/out/$label"
log="/tmp/isaac-logic-$label.log"
export PATH="/usr/local/sbin:$PATH"

rm -rf "$out"
mkdir -p "$out"
cd "$here" || exit 1
old=$(./cpuclock)
[ "$mhz" -gt 0 ] && ./cpuclock "$mhz" > /dev/null
{ date; uname -a; echo "clock $(./cpuclock) MHz (was $old)"; cat /proc/meminfo; cat /proc/swaps; ps; } > "$out/before.txt" 2>&1

# The game's memory every 2 s. One background job only: BusyBox 1.32's wait hangs when there are two.
( while :; do
      if pid=$(pidof isaac); then
          awk '/^(VmRSS|VmHWM|RssAnon|RssFile|VmSwap):/ {printf "%s %s ", $1, $2}' "/proc/$pid/status"
          awk '/^(MemAvailable|SwapFree):/ {printf "%s %s ", $1, $2}' /proc/meminfo
          echo
      fi
      sleep 2
  done ) > "$out/mem.txt" 2>&1 &
sampler=$!

t0=$(cut -d' ' -f1 /proc/uptime)
env "$@" ISAAC_TICKMARKS=1 ISAAC_SNAPSHOT=1 SDL_AUDIODRIVER=dummy \
    ./isaac --headless --norender --script "$script" "$here/Isaac.exe" > "$log" 2>&1
status=$?
t1=$(cut -d' ' -f1 /proc/uptime)
kill "$sampler" 2> /dev/null
./cpuclock "$old" > /dev/null

mv "$log" "$out/log.txt"
{
    echo "label $label, script $script, environment: $*"
    echo "exit status $status, $(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.1f", b - a }') s"
    grep -E '^(game:|SWF loaded|logic ticks|\[mem\])' "$out/log.txt"
    grep -E '^(MemAvailable|SwapFree)' /proc/meminfo
} > "$out/result.txt"
cat "$out/result.txt"
