#!/bin/sh
# SPDX-License-Identifier: MIT
# On the console (scripts/device/fk.sh --push it to /mnt/FunKey/isaac-dev, then run it): the version picker driven
# through the button daemon (fkgpiod's FIFO: KEYPRESS <key>) with the installed OPK started as the menu starts it, the
# screen grabbed at each step into out/pick-test/*.raw (240x240 RGB565; scripts/measure/shots.py raw).
#
# usage: pick-test.sh [names|quit|all]   (default all)
#   names: three versions named by ISAAC_FUNKEY_PICK_TEST (one Isaac.exe is enough: the answer is only logged, the
#          game found is then played). Down three times (wrapping round), Up, A ("Loading..."); then the game, quit
#          through the menu's EXIT GAME.
#   quit:  the real path, in a folder of its own (HOME=$dev/pick-home): two stand-ins holding only the SWF header of
#          the original and of Wrath of the Lamb (8 bytes each, never loaded). Down, then Menu: back to the launcher
#          with status 0, nothing loaded.
dev=/mnt/FunKey/isaac-dev
out=$dev/out/pick-test
fifo=/tmp/fkgpiod.fifo
mode="${1:-all}"
rm -rf $out; mkdir -p $out
frontend=$(pgrep -x frontend | head -n 1)
restore() { [ -n "$frontend" ] && kill -CONT "$frontend" 2> /dev/null; }
trap restore EXIT INT TERM
[ -n "$frontend" ] && kill -STOP "$frontend"
pkill -x gmenu2x; pkill -x retrofe
sleep 1
press() { echo "KEYPRESS $1" > $fifo; sleep "${2:-0.6}"; }
grab() { head -c 115200 /dev/fb0 > $out/$1.raw; }
gone() { for i in 1 2 3 4 5; do pidof isaac > /dev/null || return 0; sleep 1; done; echo "STILL RUNNING after $1" >> $out/result.txt; }

if [ "$mode" = names ] || [ "$mode" = all ]; then
    ISAAC_FUNKEY_PICK_TEST="Original,Wrath of the Lamb,Eternal Edition" HOME=/mnt/FunKey \
        opkrun "/mnt/Native games/isaac_funkey-s.opk" > $out/opkrun.txt 2>&1 &
    sleep 5
    grab 0-picker                                  # Original, offered first
    press KEY_D 1.0; grab 1-down                   # Wrath of the Lamb, slid in
    press KEY_D 1.0; grab 2-down                   # Eternal Edition
    press KEY_D 1.0; grab 3-down-wraps             # Original again
    press KEY_U 1.0; grab 4-up                     # Eternal Edition
    press KEY_A 0.5; grab 5-loading                # A: "Loading..." (the test's answer: 2)
    sleep 25; grab 6-game                          # the game
    press KEY_Q 1.2; press KEY_U 1.0; grab 7-exit  # the menu, up from VOLUME to EXIT GAME
    press KEY_A 0.6; press KEY_A 3.0               # A, A: quit
    gone "EXIT GAME"
    cp /mnt/FunKey/isaac/logs/launch.log $out/launch.log
    grep -E "version picker|menu:|quitting|game ended" $out/launch.log
fi
if [ "$mode" = quit ] || [ "$mode" = all ]; then
    home=$dev/pick-home
    rm -rf $home; mkdir -p $home/isaac
    printf 'FWS\012\163\043\126\002' > $home/isaac/Isaac-original.swf   # (SWF length 39199603: the original)
    printf 'FWS\012\071\205\050\002' > $home/isaac/Isaac-wotl.swf       # (36209977: Wrath of the Lamb)
    HOME=$home opkrun "/mnt/Native games/isaac_funkey-s.opk" > $out/opkrun-quit.txt 2>&1 &
    sleep 4
    grab 8-real-picker                             # Original, offered first
    press KEY_D 1.0; grab 9-real-down              # Wrath of the Lamb
    press KEY_Q 1.5; grab 10-real-quit             # Menu: quit (the screen cleared)
    gone "Menu in the picker"
    cp $home/isaac/logs/launch.log $out/launch-quit.log
    grep -E "game found|version picker|SWF loaded|game ended" $out/launch-quit.log
    rm -rf $home
fi
restore
trap - EXIT INT TERM
cat $out/result.txt 2> /dev/null
