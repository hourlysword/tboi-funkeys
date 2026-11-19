# M1: the game's logic on the console, measured

Status: **done, GO for M2** (2026-10-30). The logic takes about 10 ms per tick at 1296 MHz (17 ms at the 90th
percentile in the busiest rooms), plays exactly as on the PC, and fits in memory with the PSP's budgets.

## What was measured

The game's logic alone, with no screen and no sound device: upstream's headless mode (`--headless --norender`),
which runs every logic tick on one thread, as the FunKey will. Each tick also builds the snapshot a renderer would get
(`ISAAC_SNAPSHOT=1`), since on one core that is part of the tick's cost. Headless mode still mixes 1/30 s of sound
after every tick (`audioDumpTick`), outside the part that is timed: the console's per-tick times below are the logic
only, and the sound is counted apart (instructions under qemu). What is missing from a real frame: drawing (M2) and
presenting the picture.

The build is the FunKey build of patch 0001 (`ISAAC_FUNKEY`): upstream's Linux program with the PSP's lean loading,
its 363×272 stage (`genpsp/`), its memory limits, no helper threads, GCC 14 for the Cortex-A7, correct maths
(`libfkm.a`), everything static but the C library.

**The workload** (`scripts/measure/workload.py`, from upstream's differential tests): from the title screen into a
new run (upstream's own start script for the Eternal Edition, mouse coordinates scaled to the PSP stage), then
12 random rooms on each of floors 1–3 (the Basement, the Caves, the Depths), 10 seconds in each, moving and shooting at
random, in god mode so the run never ends. About 11,000 ticks, six minutes of play. Rooms are picked by the game's
own random generator, which headless mode seeds the same way every time: every run plays the same rooms.

**Three views of the same workload:**

1. *Same game* (`scripts/measure/same-game.sh`): every enemy's state at every tick, from the PC's lean build (x86-64)
   and from the FunKey build under qemu, compared line by line.
2. *Instructions* (`scripts/measure/qemu-armprof.sh` + `tick-cost.py`): ARM instructions executed per tick, under qemu
   with the armprof plugin from my other FunKey S projects; and the functions they go to.
3. *The console* (`scripts/device/logic.sh`): the same binary on the FunKey, at 1008 and 1296 MHz, with the CPU time
   of the game's thread for every tick and its memory every 2 s.

## Results

### The workload

The Eternal Edition starts its runs with upstream's `tests/start_game.txt` (its differential tests'
`start_eternal.txt` stays on the title screen with this build: the first round of measurements had no enemies at all
and was thrown away). 12,580 ticks: the title until tick 1000, then floor 1 (ticks 1000–4660), floor 2 (4660–8620),
floor 3 (8620–12580); 0 to 19 enemies at once.

### Same game

Every enemy's state at every tick (63,207 enemy states over the 12,580 ticks) from the FunKey build under qemu and
from the lean PC build:

- against upstream's PC build as it is (glibc's maths functions): the same game (same enemies, same events, same
  number of states), but 2,981 lines differ **in the last digit** of a double (`xbew=0.426476203475634` against
  `...635`). glibc and musl round `sin`, `cos`, `atan2`... differently now and then;
- against the PC build with musl 1.2.1's maths functions (`scripts/build.sh host-ref`,
  `scripts/measure/build-host-libm.sh`): **identical on every line**. So the FunKey build computes exactly what the PC
  does with the same maths code: no fused multiply-add, no flag or ARM-specific difference.

`same-game.sh` now compares against `host-ref`, and every later speed change (compiler options, Thumb-2, PGO, the
allocator) has to keep it identical.

### The PC, for reference

The lean PC build (x86-64, PSP stage, upstream's PC memory limits) on this machine *(PC; the qemu runs were going at
the same time, so a little noisy)*:

| Phase | Mean | Median | 90th pct | 99th pct | Max |
|---|---|---|---|---|---|
| title | 0.14 ms | 0.07 | 0.18 | 0.47 | 30.1 |
| floor 1 | 0.44 | 0.35 | 0.61 | 1.53 | 13.0 |
| floor 2 | 0.47 | 0.38 | 0.69 | 1.42 | 51.5 |
| floor 3 | 0.51 | 0.38 | 0.68 | 3.04 | 21.2 |

The maxima are room loads (a new room builds its layers and dozens of objects in one tick).

### Instructions (qemu)

The FunKey build under qemu with armprof, same workload *(qemu)*. The game writes a mark at the start and at the end of
the timed part of every tick (`OFKMEM begin` / `OFKMEM tick`), so the counts cover exactly what the console's timing
covers:

| | Mean | Median | 90th pct | 99th pct | Max |
|---|---|---|---|---|---|
| logic, all ticks | 2.65 M | 2.22 | 3.28 | 5.06 | 329 (room loads 130–330) |
| logic, 10–19 enemies | 3.47 | 3.33 | 4.08 | 7.11 | 11.0 |
| between ticks (sound, script input) | 1.08 | 1.07 | 1.79 | 2.44 | 4.0 |

"Between ticks" is almost all sound: headless mode mixes 1/30 s after every tick (`fl::mix`, 12.5% of all
instructions, and the MP3 decoder `drmp3*`, about 15%). On the console the sound thread does that work on the same
core. In the profile of the whole run, the largest item of the logic is variable lookup through scopes
(`fl::getVarK`, 15.6% of all instructions), then property reads (`fl::getProp`, 7.8%). The generated game code itself is
a small share: the physics, `f210_physix`, is 2.3%.

### The console

The same binary on the console (my FunKey-OS-based firmware, kernel 4.14), menu running, frame clock as set by
`cpuclock`. CPU time of the game's thread per tick, 1296 MHz *(console)*:

| Phase | Mean | Median | 90th pct | 99th pct | Max |
|---|---|---|---|---|---|
| title | 4.6 ms | 3.6 | 6.5 | 9.2 | 530 |
| floor 1 | 10.2 | 9.1 | 12.0 | 16.9 | 437 |
| floor 2 | 10.3 | 9.6 | 13.9 | 22.0 | 545 |
| floor 3 | 9.9 | 8.8 | 13.0 | 18.1 | 280 |

By enemies on screen: none 2.4 ms mean; 1–4 10.5; 5–9 10.5; **10–19: 13.3 mean, 16.9 at the 90th percentile, 32 at
most**. Wall-clock time is about 2 ms higher on average (the menu, the system's shell loops, and swapping: see memory).

At **1008 MHz** (the stock clock) *(console)*: all ticks 11.1 ms mean (1296: 9.7), 14.6 at the 90th percentile (12.7),
22.4 at the 99th (19.8); 10–19 enemies 15.2 mean (13.3). The clock is 29% higher at 1296 MHz but the logic only 14%
faster: most of its time goes to waiting for memory, which the CPU clock doesn't speed up.

**Instructions per clock** (`scripts/measure/ipc.py`: the qemu count of the timed part and the console's CPU time
joined tick by tick, same deterministic workload, the budget build): **0.20** in ordinary ticks, 0.33–0.36 in room
loads. One of my other FunKey S projects measured 0.63 for its renderer. This code mostly waits for memory (hash
tables, a garbage-collected heap of small objects, 32 KB of L1 and about 128 KB of L2), so speed work should go after memory
traffic first.

**Sound** (not in the console's per-tick times): about 1.1 M instructions per tick under qemu. On the console the
run's time outside the timed parts was 3.1 ms per tick, sound plus the test script's input and log; sound alone is
estimated at **2–3 ms per frame**. M3 measures it on the console (`ISAAC_MIXMS=1`).

**Memory, without the PSP's budgets** (this build kept every parsed shape, an 8 MB sound cache and every decoded
bitmap): the game grew to **43 MB resident** and the system pushed **31 MB of it into swap** (zram and the card);
`MemAvailable` fell to 5 MB. The PSP's budgets (5 MB of shapes with eviction, 2 MB of sounds, 1.5 MB of bitmaps)
were then added to the FunKey build: see the next run.

**Memory, with the PSP's budgets** (the build of patch 0001: `g_shapeEvict` with 5 MB, a 2 MB sound cache,
`rasterTrim` to 1.5 MB after every tick) *(console, 1296 MHz)*: peak **37.8 MB resident, at most 30 MB of the game's
own data** (`RssAnon`), at most **1.3 MB in swap** (31 MB before), and `MemAvailable` never below 17 MB. Speed
unchanged: 9.9 ms per tick on average (9.7 before), 10–19 enemies 13.4 mean, 17.0 at the 90th percentile.

**First start:** decompressing the SWF into `saves/swf_48785821.cache` (46.5 MB on the card) and loading the game
took about 10 s *(console: the run's 24.7 s minus 10.5 s of ticks and about 4 s of sound and script)*; later starts
read the cache.

## Decision

**GO for M2.** The plan's threshold was logic at the 90th percentile under about 20 ms in busy rooms at 1296 MHz.
Measured on the console: **12.8 ms at the 90th percentile over the whole workload, 17.0 ms with 10–19 enemies on
screen**, building the snapshot for the renderer included. Sound adds an estimated 2–3 ms per frame. That leaves
about 13 ms of every 33 ms frame for drawing and presenting in the busiest rooms, and 18–20 ms in ordinary ones. It is
enough for a 240×180 compositor if it stays lean (the plan's estimate was 2–5 ms plus new graphics), and frame skip
(my choice) covers the ticks that go over.

What M1 adds to the plan:

1. **Room loads stall for 0.3–0.5 s** (up to 0.7 s at 1008 MHz; the PC takes up to 51 ms). With frame skip the
   picture would freeze that long at some room entries. Worth a profile of its own in M4: what a room load spends its
   time on (layers, shapes parsed again, the collision grid...).
2. **The code waits on memory** (0.20 instructions per clock; 29% more clock buys 14% more speed). M4's order should
   follow the profile rather than the plan's guesses: sound first (mixer `fl::mix` 12.5% and MP3 decoding about 15% of
   instructions: the PSP's 16.16 fixed-point positions and 16-bit output are a start), variable lookup through scopes
   (`fl::getVarK` 15.6%), the allocator and other C library calls (7.8%, musl's), then compiler options for the
   generated code. Regenerating the game at a FunKey stage matters less than expected: drawing into bitmaps is a few
   percent of the instructions.
3. **Memory is tight but fits:** 30 MB of the game's own data for the logic; the renderer will add its atlas (the PSP
   uses six 1 MB pages) and the screen buffers. M3 checks a long session (memory creep over 30 minutes or more) and
   adds the PSP's low-memory collection trigger (`g_gcMemPressure`) if needed.
4. **Exactness is cheap to keep:** `scripts/measure/same-game.sh` against the musl-maths PC reference, after every
   speed change.

## Files

- Console logs: `testing/m1/` (gitignored): `short-1296` (first start), `rooms-1296`, `rooms-1008`,
  `rooms-1296-budgets`, each with `log.txt`, `mem.txt`, `before.txt`, `result.txt`.
- qemu profile: `$TFK_WORK/m1/arm/rooms.prof` (+ `.marks`), read with `armprof.py` (from the
  measuring tools of my other FunKey S projects).
- Same-game logs: `$TFK_WORK/same-game/{pc,arm}/state.txt`.
