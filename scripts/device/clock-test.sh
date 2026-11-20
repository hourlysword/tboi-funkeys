#!/bin/sh
# SPDX-License-Identifier: MIT
# On the console (scripts/device/fk.sh --push it to /mnt/FunKey/isaac-dev, then run it): OVERCLOCK in the FunKey menu.
# An OPK is started as the menu starts it (opkrun, so its launcher runs too), but on the test folder's data: HOME is
# a folder in /tmp whose isaac is /mnt/FunKey/isaac-dev. The menu is driven through the button daemon (fkgpiod's FIFO:
# KEYPRESS <key>). Two starts: the first (no launcher.cfg: the system's clock) turns OVERCLOCK on, the second (started
# overclocked) turns it off again. The CPU clock is read at each step into out/clock-test/result.txt, the screen
# grabbed into out/clock-test/*.raw (240x240 RGB565); launcher.cfg is removed again at the end.
#
# usage: clock-test.sh [OPK]   (default: isaac_funkey-s.opk in the test folder)
dev=/mnt/FunKey/isaac-dev
opk="${1:-$dev/isaac_funkey-s.opk}"
out=$dev/out/clock-test
fifo=/tmp/fkgpiod.fifo
home=/tmp/isaac-clock-test
rm -rf $out "$home"; mkdir -p $out "$home"
ln -s $dev "$home/isaac"
rm -f $dev/launcher.cfg
frontend=$(pgrep -x frontend | head -n 1)
restore() { [ -n "$frontend" ] && kill -CONT "$frontend" 2> /dev/null; rm -rf "$home"; }
trap restore EXIT INT TERM
[ -n "$frontend" ] && kill -STOP "$frontend"
pkill -x gmenu2x; pkill -x retrofe
sleep 1
export PATH="/usr/local/sbin:$PATH"
clock() { echo "$1: CPU clock $($dev/cpuclock) MHz" >> $out/result.txt; }
press() { echo "KEYPRESS $1" > $fifo; sleep "${2:-0.6}"; }
grab() { head -c 115200 /dev/fb0 > $out/$1.raw; }
gone() {
    for i in 1 2 3 4 5 6 7 8 9 10; do pidof isaac > /dev/null || return 0; sleep 1; done
    echo "STILL RUNNING after $1" >> $out/result.txt
}
clock "before"
echo "volume $(volume get), brightness $(brightness get) before" >> $out/result.txt

# 1: the first start, at the system's clock; OVERCLOCK on in the menu
HOME="$home" opkrun "$opk" > $out/opkrun-1.txt 2>&1 &
sleep 25
clock "first start, playing"
press KEY_Q 1.2                                          # the menu, on VOLUME
press KEY_U 0.8; press KEY_U 0.8; grab 1-overclock-off   # up: EXIT GAME, then OVERCLOCK (OFF)
press KEY_R 1.5; grab 2-overclock-on; clock "OVERCLOCK on"
press KEY_Q 3.0; grab 3-game; clock "back in the game"
press KEY_Q 1.0; press KEY_D 0.8; press KEY_A 0.6; press KEY_A 3.0   # the menu (on OVERCLOCK), EXIT GAME, A, A
gone "the first EXIT GAME"
clock "after the first start"
echo "launcher.cfg: $(cat $dev/launcher.cfg 2> /dev/null)" >> $out/result.txt
cp $dev/logs/launch.log $out/launch-1.log

# 2: the second start, overclocked (cpu_mhz = 1296); OVERCLOCK off again
HOME="$home" opkrun "$opk" > $out/opkrun-2.txt 2>&1 &
sleep 20
clock "second start, playing"
press KEY_Q 1.2; press KEY_U 0.8; press KEY_U 0.8; grab 4-overclock-on   # (a new start: the menu on VOLUME)
press KEY_R 1.5; grab 5-overclock-off; clock "OVERCLOCK off"
press KEY_D 0.8; press KEY_A 0.6; press KEY_A 3.0      # EXIT GAME, A, A
gone "the second EXIT GAME"
clock "after the second start"
echo "launcher.cfg: $(cat $dev/launcher.cfg 2> /dev/null)" >> $out/result.txt
cp $dev/logs/launch.log $out/launch-2.log
echo "volume $(volume get), brightness $(brightness get) after" >> $out/result.txt
rm -f $dev/launcher.cfg
restore
trap - EXIT INT TERM
cat $out/result.txt
grep -hE "CPU clock|OVERCLOCK|game ended" $out/launch-1.log $out/launch-2.log
