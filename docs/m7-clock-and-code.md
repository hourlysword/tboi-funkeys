# M7: the CPU clock in the menu, and the program's code in memory

Status: **done** (2026-11-19). Patch 0011 (`rt/funkey.cpp`), `opk/isaac.sh`. The FunKey menu can turn the overclock on
and off, and it is now off unless turned on (the game runs at almost the same pictures a second without it, with
longer room entries); page faults are in the game's log; keeping the program's code in memory was measured and left
out.

## OVERCLOCK in the FunKey menu

In 1.0.0 the game always ran at 1296 MHz, the highest clock the FunKey's kernel lists (at the same voltage as the
usual 1008 MHz), and the launcher put the usual clock back when the game ended. Some players would rather not
overclock their console, even if the game runs slower, so the FunKey menu has a sixth item between SHOW FPS and EXIT
GAME, and since the game hardly needs the overclock (below), it starts off:

- **OVERCLOCK**: `OFF` (the console's own clock, untouched: the default) or `ON` (1296 MHz while the game runs, as in
  1.0.0). Left, Right or A switch it, at once: the game runs the OPK's own clock tool (`cpuclock`, the one the
  launcher uses) with the new clock.
- The choice is kept in `FunKey/isaac/launcher.cfg`, which the launcher already read in 1.0.0 (`cpu_mhz = 0` leaves
  the clock alone, `cpu_mhz = <MHz>` sets that one, 480 to 1296 in steps of 48). OFF writes `cpu_mhz = 0`, ON
  `cpu_mhz = 1296`; with no file the clock is now left alone (1.0.0: 1296).
- The launcher now always reads the console's clock first, passes it and the tool to the game
  (`ISAAC_FUNKEY_SYSTEM_MHZ`, `ISAAC_FUNKEY_CPUCLOCK`) and always puts it back when the game ends, so that turning
  OVERCLOCK on in the menu never leaves the console overclocked. The game shows ON when it starts at a clock above the
  console's own.
- Without the tool (a PC, the play tests) the item only keeps the choice.

Checked on the PC (`testing/m7/menu`: the item ON, OFF with `cpu_mhz = 0`, EXIT GAME one place lower) and on the
console with `scripts/device/clock-test.sh` (`testing/m7/clock-test`): an OPK started as the menu starts it
(`opkrun`, so its launcher runs too) on the test folder's data, two starts driven through the button daemon, the
clock read at each step. With ON as the default (the first version): the first start ran at 1296 MHz and OFF took it
to 1008 at once, where it stayed in the game; the launcher's clock after it, 1008, and `cpu_mhz = 0`. The second start
was left at 1008 ("left as it is"), showed OFF, and ON took it to 1296; after it, 1008 again and `cpu_mhz = 1296`.
Volume and brightness untouched, both games ended with status 0. The test now starts from the new default (OFF, then
ON, then OFF again), and passed so with the 1.1.0 OPK (docs/m8-upstream-1.7.md).

### What the overclock buys

The 7-minute play script on the console (the program from the OPK, cold, as below), at the two clocks
(`testing/m7/lock0`, `mhz1008`):

| | 1296 MHz (ON) | 1008 MHz (OFF) |
|---|---|---|
| Pictures a second | 29.3 (lowest 5 s: 25.9) | 29.1 (24.5) |
| Per tick: logic; per picture: drawing | 6.5 ms; 6.7 ms | 7.6 ms; 7.8 ms |
| Ticks over 150 ms (over 300) | 14 (5), mean 291 ms | 19 (7), mean 299 ms |
| A new floor's pause | 478 ms | 625 ms |

The game uses about half of each 1/30 s either way, so the pictures a second hardly change; what the overclock
shortens is the long ticks: room entries, and a new floor's pause by about a quarter. The clock is raised at the same
voltage, so it costs some battery: the console was powered over USB for these runs, so how much wasn't measured.

The M7 build itself (the code locking taken out again), the same run at 1296 MHz: 29.4 pictures a second (lowest
5 s: 25.9), 12 ticks over 150 ms (`testing/m7/final`); `clock-test.sh` passed with its OPK too.

## Measuring page faults

The 5-second line and the `long tick` lines in the game's log now end with the **page faults**: the pages the game
had to wait for (major faults, `getrusage`): its code read again from the OPK, or its data from swap.
`scripts/device/play-run.sh` also samples, every 2 s, the program's major faults and the system's
(`/proc/vmstat`: `pgmajfault`, `workingset_refault` for file pages read again soon after being dropped, `pswpin`,
`pswpout`); `scripts/measure/play-summary.py` sums a run up. `TFK_BIN` runs the program from an OPK mounted on the
console (squashfs, as players run it) instead of from the card.

## The program's code in memory: tried, not kept

The program is 8.5 MB of code (the game recompiled, the engine, SDL), read from the OPK as it runs. The OPK is gzip
squashfs in 128 KB blocks, so every page of code read again costs a whole block read and decompressed. In my other
FunKey S projects, the kernel dropping a program's code under memory pressure and reading it back thousands of times a
second was the main cost, and keeping the code in memory once it has run (`mlock2` with `MLOCK_ONFAULT`) fixed it.
The M6 runs here had little memory to spare (5 MB available at the lowest), and only 2-4 MB of the code stayed in
memory, so it was worth measuring.

The 7-minute play script on the console at 1296 MHz, the program from the OPK mounted as squashfs, each run cold (the
page cache dropped, no room pieces on the card), with and without the code kept in memory (`testing/m7/lock0`,
`lock1`):

| | Left to the kernel | Kept in memory |
|---|---|---|
| Pictures a second | 29.3 (lowest 5 s: 25.9) | 29.4 (25.6) |
| Page faults in the 7 minutes | 178 | 155 |
| Ticks over 150 ms (over 300) | 14 (5), mean 291 ms | 12 (5), mean 309 ms |
| Page faults in those ticks | 30 | 17 |
| Memory available, lowest | 8 MB | 2 MB |
| Pages swapped in / out | 282 / 966 | 346 / 1,105 |

Most of the page faults are the code being read for the first time, which keeping it in memory can't avoid; it saved
about 23 reads in 7 minutes. A new floor's pause (the ticks of 478 and 454 ms) had 4 and 2 page faults: it is the game
building the floor, as M6 found. Meanwhile the locked code left the rest of the program less memory (2 MB available at
the lowest) and it swapped more. So the code is left to the kernel, as in 1.0.0. The page faults stay in the log, to
see whether a console with less memory to spare (stock FunKey-OS) is any different.
