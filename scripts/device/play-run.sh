#!/bin/sh
# SPDX-License-Identifier: MIT
# Runs on the FunKey (scripts/device/play.sh pushes and starts it): the game's own loop, on the screen, playing a test
# script instead of the buttons (ISAAC_FUNKEY_SCRIPT): the real pacing, frame skip, drawing, picture hand-over and
# sound device, measured per tick and per picture (ISAAC_TICKMARKS). The menu is stopped for the run (the game owns
# the screen) and put back afterwards, also when the run is cut short; the CPU clock likewise. The power-off is not
# taken over (ISAAC_FUNKEY_NO_POWEROFF): a power-off during the run powers off as usual.
#
# usage: play-run.sh <label> <MHz> <script> [NAME=value ...]
#   results in out/<label>/ next to this script: log.txt, mem.txt, fb.raw (the screen at the end), result.txt

here="$(cd "$(dirname "$0")" && pwd)"
label="${1:?usage: play-run.sh <label> <MHz> <script> [NAME=value ...]}"
mhz="${2:?usage}"
script="${3:?usage}"
shift 3
out="$here/out/$label"
log="/tmp/isaac-play-$label.log"
export PATH="/usr/local/sbin:$PATH"
rm -rf "$out" "$here/shots"
mkdir -p "$out" "$here/shots"   # (the scripts' "shot" lines write there)
cd "$here" || exit 1

old=$(./cpuclock)
# The menu: its loop (FunKey-OS's `frontend`) paused in memory, then the menu itself ended; at the end the loop goes on
# and starts it again. (Not /mnt/disable_frontend: a file on the card would keep the menu off after a reboot if the
# console froze during the run. Learned in the tests of my other FunKey S projects.)
frontend=$(pgrep -x frontend | head -n 1)
restore() {
    [ -n "$frontend" ] && kill -CONT "$frontend" 2> /dev/null
    ./cpuclock "$old" > /dev/null
}
trap restore EXIT INT TERM
[ -n "$frontend" ] && kill -STOP "$frontend"
pkill -x gmenu2x; pkill -x retrofe
sleep 1
[ "$mhz" -gt 0 ] && ./cpuclock "$mhz" > /dev/null
{ date; uname -a; echo "clock $(./cpuclock) MHz (was $old)"; echo "program: ${TFK_BIN:-./isaac}"; cat /proc/meminfo; cat /proc/vmstat; ps; } > "$out/before.txt" 2>&1

# The game's memory every 2 s (one background job only: BusyBox 1.32's wait hangs with two)
( while :; do
      if pid=$(pidof isaac); then
          awk '/^(VmRSS|VmHWM|RssAnon|RssFile|VmSwap):/ {printf "%s %s ", $1, $2}' "/proc/$pid/status"
          awk '/^(MemAvailable|SwapFree):/ {printf "%s %s ", $1, $2}' /proc/meminfo
          # pages it waited for (major faults), and the system's: file pages read again soon after being dropped
          # (workingset_refault: mostly program code), swap traffic
          awk '{printf "majflt %s ", $12}' "/proc/$pid/stat"
          awk '/^(pgmajfault|workingset_refault|pswpin|pswpout) / {printf "%s %s ", $1, $2}' /proc/vmstat
          echo
      fi
      sleep 2
  done ) > "$out/mem.txt" 2>&1 &
sampler=$!

# With TFK_FKPROF=1 (play.sh PROFILE=1): fkprof samples the whole system while the game runs and writes fkprof.txt
# (scripts/measure/fkreport.py reads it). It ends by itself after the game; not waited for with `wait` (see above).
prof=""
if [ -n "${TFK_FKPROF:-}" ] && [ -x ./fkprof ]; then
    ./fkprof -p isaac -o "$out/fkprof.txt" -w 30 > "$out/fkprof.log" 2>&1 &
    prof=$!
fi

t0=$(cut -d' ' -f1 /proc/uptime)
# (TFK_NO_TICKMARKS=1: without the per-tick lines, for long runs: the log is in /tmp, which is RAM)
marks="ISAAC_TICKMARKS=1"; [ -n "${TFK_NO_TICKMARKS:-}" ] && marks="ISAAC_FUNKEY_RUN=1"
# (TFK_BIN: the program from elsewhere, e.g. an OPK mounted as players run it; play.sh)
env "$@" ISAAC_HOME="$here" ISAAC_FUNKEY_SCRIPT="$script" $marks ISAAC_FUNKEY_NO_POWEROFF=1 "${TFK_BIN:-./isaac}" > "$log" 2>&1
status=$?
t1=$(cut -d' ' -f1 /proc/uptime)
kill "$sampler" 2> /dev/null
if [ -n "$prof" ]; then
    for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$prof" 2> /dev/null || break; sleep 1; done
fi
head -c $((240 * 240 * 2)) /dev/fb0 > "$out/fb.raw" 2> /dev/null
mv "$log" "$out/log.txt"
mv "$here"/shots/* "$out/" 2> /dev/null
restore
trap - EXIT INT TERM
{
    echo "label $label, script $script, environment: $*"
    echo "exit status $status, $(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.1f", b - a }') s"
    grep -E '^(game:|audio:|\[funkey\] (/dev|buttons|no screen|test script|quit|stop))' "$out/log.txt"
    grep -E '^(MemAvailable|SwapFree)' /proc/meminfo
} > "$out/result.txt"
cat "$out/result.txt"
