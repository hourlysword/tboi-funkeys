#!/bin/sh
# SPDX-License-Identifier: MIT
# On the console (scripts/device/fk.sh --push it to /mnt/FunKey/isaac-dev, then run it): starts the installed OPK as the
# menu does (opkrun, HOME=/mnt/FunKey), grabs the screen after 45 s, stops the game with SIGTERM (it saves and quits)
# and puts the menu back. The game's own log is FunKey/isaac/logs/launch.log; this writes out/launch-test/.
dev=/mnt/FunKey/isaac-dev
out=$dev/out/launch-test
rm -rf $out; mkdir -p $out
frontend=$(pgrep -x frontend | head -n 1)
restore() { [ -n "$frontend" ] && kill -CONT "$frontend" 2> /dev/null; }
trap restore EXIT INT TERM
[ -n "$frontend" ] && kill -STOP "$frontend"
pkill -x gmenu2x; pkill -x retrofe
sleep 1
echo "clock before: $($dev/cpuclock) MHz" > $out/result.txt
t0=$(cut -d' ' -f1 /proc/uptime)
HOME=/mnt/FunKey opkrun "/mnt/Native games/isaac_funkey-s.opk" > $out/opkrun.txt 2>&1 &
sleep 45
head -c 115200 /dev/fb0 > $out/fb.raw
pid=$(pidof isaac)
echo "after $(awk -v a="$t0" '{printf "%.0f", $1 - a}' /proc/uptime) s: isaac pid $pid, clock $($dev/cpuclock) MHz" >> $out/result.txt
grep -E 'VmHWM|VmRSS|VmSwap' /proc/$pid/status >> $out/result.txt 2>/dev/null
kill -TERM $pid 2> /dev/null
for i in 1 2 3 4 5 6 7 8 9 10; do sleep 1; pidof isaac > /dev/null || break; done
pidof isaac > /dev/null && echo "STILL RUNNING after SIGTERM" >> $out/result.txt
sleep 1
echo "clock after: $($dev/cpuclock) MHz" >> $out/result.txt
cp /mnt/FunKey/isaac/logs/launch.log $out/
restore
trap - EXIT INT TERM
cat $out/result.txt
