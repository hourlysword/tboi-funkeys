#!/bin/sh
# SPDX-License-Identifier: MIT
# On the console (scripts/device/fk.sh --push it to /mnt/FunKey/isaac-dev, then run it): the FunKey menu driven
# through the button daemon (fkgpiod's FIFO: KEYPRESS <key>), the installed OPK started as the menu starts it, the
# screen grabbed at each step into out/menu-test/*.raw (240x240 RGB565). Volume and brightness are changed one step and
# back (net nothing); the aspect ratio and SHOW FPS are set back too; it ends with EXIT GAME.
dev=/mnt/FunKey/isaac-dev
out=$dev/out/menu-test
fifo=/tmp/fkgpiod.fifo
rm -rf $out; mkdir -p $out
frontend=$(pgrep -x frontend | head -n 1)
restore() { [ -n "$frontend" ] && kill -CONT "$frontend" 2> /dev/null; }
trap restore EXIT INT TERM
[ -n "$frontend" ] && kill -STOP "$frontend"
pkill -x gmenu2x; pkill -x retrofe
sleep 1
export PATH="/usr/local/sbin:$PATH"
echo "volume $(volume get), brightness $(brightness get) before" > $out/result.txt
HOME=/mnt/FunKey opkrun "/mnt/Native games/isaac_funkey-s.opk" > $out/opkrun.txt 2>&1 &
press() { echo "KEYPRESS $1" > $fifo; sleep "${2:-0.6}"; }
grab() { head -c 115200 /dev/fb0 > $out/$1.raw; }
sleep 25
grab 0-game
press KEY_Q 1.2; grab 1-volume                 # Menu: the menu, on VOLUME
press KEY_L 1.0; grab 2-volume-down            # one step down
press KEY_R 1.0                                # and back
press KEY_D 0.8; grab 3-brightness             # BRIGHTNESS
press KEY_L 1.0; grab 4-brightness-down
press KEY_R 1.0
press KEY_D 0.8; press KEY_R 1.5; grab 5-aspect-stretched   # ASPECT RATIO: STRETCHED (the game behind redrawn)
press KEY_D 0.8; press KEY_R 0.8; grab 6-fps-on            # SHOW FPS: ON
press KEY_Q 3.0; grab 7-game-stretched-fps                 # closed: the game, stretched, with the FPS
press KEY_Q 1.0                                            # the menu again, on SHOW FPS
press KEY_L 0.6; press KEY_U 0.8; press KEY_L 1.2          # SHOW FPS off, ASPECT RATIO back to 4:3
press KEY_D 0.8; press KEY_D 0.8; grab 8-exit              # EXIT GAME
press KEY_A 0.8; grab 9-exit-sure                          # "Are you sure ?"
press KEY_B 0.8; grab 10-exit-back                         # B: the question taken back
press KEY_A 0.6; press KEY_A 3.0                           # A, A: quit
pid=$(pidof isaac); [ -n "$pid" ] && echo "STILL RUNNING after EXIT GAME" >> $out/result.txt
for i in 1 2 3 4 5; do pidof isaac > /dev/null || break; sleep 1; done
echo "volume $(volume get), brightness $(brightness get) after" >> $out/result.txt
grep -E "funkey_" /mnt/FunKey/isaac/isaac.ini >> $out/result.txt
cp /mnt/FunKey/isaac/logs/launch.log $out/
restore
trap - EXIT INT TERM
cat $out/result.txt
grep -E "menu|quitting|game ended" $out/launch.log
