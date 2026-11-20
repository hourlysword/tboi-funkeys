#!/bin/sh
# SPDX-License-Identifier: MIT
# The Binding of Isaac (IsaacRecomp) on the FunKey S: the OPK's launcher.
#
# Everything the game keeps is in FunKey/isaac ($HOME/isaac on the console's USB share): the Steam game's Isaac.exe,
# which you copy there (several versions under different names too: the game asks which one), isaac.ini, saves/ (the
# save files, and the game unpacked from Isaac.exe the first time: about 46 MB) and logs/. logs/launch.log is this
# launcher's: what it found, the game's own output (a speed and memory line every 5 s, "[funkey]"), how it ended.
#
# The game runs with its PID recorded, as FunKey-OS's own launchers do, so that powering off signals it: it then
# writes its save and powers off within FunKey-OS's time budget. (A run in progress isn't kept: the original game
# has no mid-run save.)
#
# The CPU clock while it runs: the system's own, unless OVERCLOCK is on in the game's FunKey menu: then 1296 MHz, the
# highest the FunKey's kernel lists, at the same voltage as the usual 1008 MHz. The menu switches it at once and keeps
# the choice in FunKey/isaac/launcher.cfg: cpu_mhz = 0 (or no file) leaves the clock alone, cpu_mhz = <MHz> sets that
# one (480 to 1296, in steps of 48). The game gets the clock tool and the system's clock (ISAAC_FUNKEY_CPUCLOCK,
# ISAAC_FUNKEY_SYSTEM_MHZ), and the system's clock is put back when the game ends.

opk="$(cd "$(dirname "$0")" && pwd)"
export HOME="${HOME:-/mnt/FunKey}"
export PATH="$PATH:/usr/local/sbin"
data="$HOME/isaac"
logs="$data/logs"
log="$logs/launch.log"
mkdir -p "$logs"
[ -f "$log.1" ] && mv -f "$log.1" "$log.2"
[ -f "$log" ] && mv -f "$log" "$log.1"

note() {
    echo "--- $(cut -d' ' -f1 /proc/uptime) s: $*" >> "$log"
}
# A message on the screen for a while ('^' starts a new line)
tell() {
    command -v notif > /dev/null && notif set "$1" "$2"
}

{
    echo "The Binding of Isaac (IsaacRecomp) launcher, uptime $(cut -d' ' -f1 /proc/uptime) s"
    echo "OPK: $opk, started by: $(tr '\0' ' ' < "/proc/$PPID/cmdline" 2> /dev/null)"
    uname -a
    echo "--- memory"
    grep -E '^(MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo
    echo "--- storage"
    df -k /mnt | tail -n 1
    ls -la "$data" "$data/saves" 2> /dev/null
    echo "--- display"
    for f in name virtual_size bits_per_pixel stride; do
        echo "fb0 $f: $(cat "/sys/class/graphics/fb0/$f" 2> /dev/null)"
    done
    echo "--- input"
    grep -E '^(N: Name|H: Handlers)' /proc/bus/input/devices
} >> "$log" 2>&1

# The game: an .exe (or an extracted .swf) in FunKey/isaac
if ! ls "$data" | grep -qiE '\.(exe|swf)$'; then
    note "no Isaac.exe in $data"
    tell 10 "Copy Isaac.exe from the^Steam game into the^folder FunKey/isaac"
    sleep 6
    exit 1
fi
if ! ls "$data/saves" 2> /dev/null | grep -q '^swf_.*\.cache$'; then
    tell 20 "First start: unpacking^the game (about 15 s)"
    note "first start: the game will be unpacked into saves/"
fi

mhz="$(sed -n 's/^[[:space:]]*cpu_mhz[[:space:]]*=[[:space:]]*\([0-9][0-9]*\)[[:space:]]*$/\1/p' \
    "$data/launcher.cfg" 2> /dev/null | tail -n 1)"
mhz="${mhz:-0}"
if sys_mhz="$("$opk/cpuclock" 2>> "$log")"; then
    if [ "$mhz" -ne 0 ]; then
        note "CPU clock $sys_mhz MHz, for the game: $("$opk/cpuclock" "$mhz" 2>&1)"
    else
        note "CPU clock $sys_mhz MHz, left as it is (OVERCLOCK off)"
    fi
    export ISAAC_FUNKEY_CPUCLOCK="$opk/cpuclock" ISAAC_FUNKEY_SYSTEM_MHZ="$sys_mhz"
else
    sys_mhz=""
fi

# RetroFE switches the speaker's amplifier off after each game.
command -v audio_amp > /dev/null && audio_amp on

note "game started"
sync
ISAAC_HOME="$data" "$opk/isaac" >> "$log" 2>&1 &
game=$!
command -v pid > /dev/null && pid record "$game"
wait "$game"
status=$?
command -v pid > /dev/null && pid erase
# (always: OVERCLOCK in the menu may have changed it)
[ -n "$sys_mhz" ] && "$opk/cpuclock" "$sys_mhz" >> "$log" 2>&1

# Once FunKey-OS is powering off (powerdown now): nothing more, not even the log.
[ -f /run/rebooting ] && exit 0

reason=""
case "$status" in
    0) ;;
    1) reason="ended with an error" ;;
    126) reason="couldn't be run" ;;
    127) reason="couldn't start: a system library is missing" ;;
    132) reason="crashed (illegal instruction)" ;;
    134) reason="crashed (abort)" ;;
    135) reason="crashed (bus error)" ;;
    137) reason="was killed (out of memory?)" ;;
    138 | 143) ;; # SIGUSR1 (power-off), SIGTERM
    139) reason="crashed (segmentation fault)" ;;
    *) [ "$status" -gt 128 ] && reason="was killed (signal $((status - 128)))" || reason="ended with status $status" ;;
esac
note "game ended with status $status${reason:+: $reason}"
[ -n "$reason" ] && tell 6 "The game $reason^See FunKey/isaac/logs"
sync
exit "$status"
