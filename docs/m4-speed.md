# M4: speed

Status: **done** (2026-11-15), the second round's build on the console. Against M3, in the 7-minute play script:
drawing a picture 14-16 -> 6-7 ms, the game's logic per tick 11.8 -> 7.5 ms, room entries over 150 ms 48 -> 21
(the worst 0.72 -> 0.52 s), 26.2 -> 29.0 pictures a second with no 5-second window under 24, peak memory 52 -> 46
MB; the game uses half the CPU (80% before). My 34-minute session on the first round's build: 29.8 pictures
a second on average, none of its 5-second windows under 20. Every change measured on the console, the logic kept identical (`scripts/measure/same-game.sh`) and
the picture checked against the plain C code (NEON paths) or upstream's renderer.

## Where the time goes (console, before M4)

`fkprof` (a whole-system sampler from my other FunKey S projects, 1000 samples a second; `PROFILE=1 scripts/device/play.sh`,
report `scripts/measure/fkreport.py`) over the 7-minute play script (floors 1-3, 12,580 ticks) at 1296 MHz,
`testing/m4/prof-base`:

| | Share of the game's CPU time |
|---|---|
| Drawing (renderer 36.6%, its copies in `memcpy` ~6%, rasterizer ~3.5%, the kernel turning each picture 2%) | ~48% |
| Logic (game code 8.6%, variable and property lookups 7.2%, the rest of the runtime ~12%, allocator 1.5%) | ~30% |
| Sound (MP3 decoding 3.7%, mixer 2.4%, ALSA's route plugin 1.4%; its own thread: 7.1% of all CPU time) | ~7.5% |

The game used 79.5% of the CPU, the system 6%, and 14% was idle (waiting for the next tick). Per tick: 27.5 ms of
the game's CPU time, 13.5 ms of it drawing each picture.

Inside the drawing, by source line (samples mapped through a `-g` build of `render_soft.cpp`, the same code):

- `drawTex` (20.1% of the game): blending 35-40%, resampling (scaled or turned graphics) ~25%, colour transforms
  ~15% (the float path divided three times per pixel).
- `renderEndFrame` (10.3%): the canvas (363x272) shrunk to the screen (240x180): half the NEON vertical pass
  (memory-bound), half the horizontal pass in plain C.
- The screen copy (RGB565 with dither, 3.6%) and the kernel's software rotation of each picture (`fbtft_rotate_270cw_soft`,
  2%; the display driver's, not ours).

A finding: two thirds of the pictures in the floors rasterized a graphic, and 1,051 of the 1,075 rasterizations at a
transform in floor 1 were the frames of an animation shown in place (a turning swirl): the renderer took "the
transform didn't change" for "nothing changed" and rasterized each new frame of the animation at its transform.

## Changes

1. **Game code at -O2 in Thumb-2** (`ISAAC_GEN_FLAGS`, the FunKey's default): the code 29% smaller, the logic per
   tick on the console (`scripts/device/logic.sh`, M1's workload, `testing/m1/m4-*`):

   | Game code | Mean | 90th pct | 99th pct | 10-19 enemies: mean | 90th pct |
   |---|---|---|---|---|---|
   | -O1, ARM (before) | 9.92 ms | 12.87 | 19.79 | 13.39 | 17.11 |
   | -O1, Thumb-2 | 9.04 | 11.46 | 17.70 | 11.84 | 14.83 |
   | -O2, ARM | 9.16 | 11.75 | 18.39 | 12.17 | 15.31 |
   | **-O2, Thumb-2** | **8.61** | **10.81** | **16.84** | **11.11** | **13.81** |

2. **Animations in place are not "still"**: a graphic is rasterized at its transform only when both its transform
   and the graphic it shows are the same as in the previous picture. Floor 1 on the PC: 354 rasterizations instead of
   1,409 (at a transform: 20 instead of 1,075), rasterizing time -66%.
3. **NEON**: the screen copy (RGB565 with the dither, 8 pixels a step), blending (8 pixels a step), the scaler's
   horizontal pass (two output pixels a step, weights in 1/128 like the vertical pass), bilinear resampling inside
   textures (into a row, then blended). The same pixels as the plain C code (PC and ARM builds compared at six ticks:
   identical). The screen copy got cheaper (3.6% of the game's time -> 2.5%), but blending and scaling did not: per
   picture they cost the same as before (console, `prof-m4a`). They wait on memory, not on arithmetic: each pass over
   the 363x272 canvas moves about 400 KB through the console's DDR2.
4. **The canvas at the picture's size** (the change that counted): the stage is drawn at 240x180 (scale 0.661)
   instead of 363x272 shrunk at the end. Shapes and texts are rasterized at their size on the screen; the game's
   stage-sized bitmaps (floor and walls, blood, gibs, the minimap: 1:1 on the stage) are drawn 1:1 from copies shrunk
   by area averaging, made again only when the bitmap changes (4% of the times they're drawn in the floors). 2.3
   times fewer pixels in every copy and blend, and no shrinking pass (in 4:3 the canvas is the picture; full screen
   stretches rows at the end). The picture against the old path: the same to the eye (1.6-2.6 levels in 255 on
   average, edges and sub-pixel positions). `ISAAC_SOFT_STAGERES=1` keeps the old path for comparisons.
5. Colour transforms without divisions (a table of 1/alpha); only the bars of the output cleared each frame; the
   mixer skips its cubic interpolation where it falls on a sample (music at the output's rate: the same result).
6. **Sound in 16-bit samples**: FunKey-OS's default device (a `route` plugin) converted every float sample (1.4% of
   the game's time in alsa-lib, 0.4% now). Writing to the codec directly (`hw:0`, as one of my other FunKey S projects does) was tried
   and dropped: the sound thread then woke far more often (+0.75 ms per tick in the kernel).
7. **Room entries**: each one draws the room's floor and walls (80-110 shapes) into the room's bitmap. The cache of
   those rasterized shapes was the PSP's 2 MB: every room rasterized them again (0.35-0.45 s on the console). With 6
   MB most rooms reuse the floor's: 40% shorter on average on the PC, many rooms near nothing. The renderer's own
   cache went from 8 to 4 MB to pay for it (at the picture's scale: as few rasterizations with 5 MB as with 8, 8%
   more with 4).
   PlutoVG rounded every path coordinate through a library call (`roundf`, 5% of a room's drawing): inline now.

## Results

The 7-minute play script on the console (1296 MHz, `fkprof` running), drawing per picture (ms, mean):

| | Title | Floor 1 | Floor 2 | Floor 3 | Pictures shown | Windows under 24/s |
|---|---|---|---|---|---|---|
| Before M4 (`prof-base`) | 30.7 | 14.2 | 16.2 | 14.9 | 26.2 a second | 13 of 84 |
| NEON, Thumb-2, animations (`prof-m4a`) | 29.2 | 12.7 | 14.6 | 13.4 | 27.5 | 8 |
| + the canvas at the picture's size (`prof-m4b`) | 16.7 | 6.8 | 7.3 | 7.6 | 28.0 | 5 |
| + 6 MB leaf cache, 5 MB renderer cache (`prof-m4c`) | 16.7 | 6.9 | 7.9 | 7.4 | 28.3 | 3 |

The game's share of the CPU went from 79.5% to 59.4% (idle 14% -> 35%); its CPU time per tick from 27.5 to 20.5 ms.
In `prof-m4b` the pictures still skipped are mostly the catching up after room entries (the stall of a room entry
under 0.5 s is caught up by skipping pictures): every window under 27 pictures a second has a room entry in it.

Room entries (ticks over 300 ms in the floors): `prof-m4b` 20 or more, `prof-m4c` 13; ticks over 150 ms 42 -> 29.
Memory in `prof-m4c` (the game's own, in RAM + swapped): 44.6 MB on average after the first minute, 49.3 at most;
available at least 3.7 MB (4.8 in `prof-m4b`), hence the renderer's cache at 4 MB rather than 5 in the build that
followed. One tick waited 1.3 s with 24 ms of CPU (swap or the card: `fkprof` rewrites its file every 15 s too).

Logic per tick (`scripts/device/logic.sh`, M1's workload): 9.92 ms on average before M4, 8.61 after; in the play
script (`prof-m4c`) the 90th percentile is about 10 ms. A picture plus its tick now take about 15-20 ms of the 33.

## Left after the first round

- Room entries: still 0.3-0.5 s for a floor's first rooms (the shapes of its floor and walls rasterized once).
- The title and menus: 17 ms a picture (large animated graphics); with their light logic still 30 a second.
- Sound: MP3 decoding 3.8% of the game's time, the mixer 2.2%.
- Logic: variable lookups (`getVarK` 4.4%), property access; profile-guided optimisation of the game code.

## Second round (2026-11-15)

1. **Room layers at the picture's scale.** The game sets its room layers' resolution itself, as quality tiers chosen
   from its display scale (640x480 at 1, 800x620 at 1.25, 1100x800 at 1.667); genpsp/ pins the PSP's (364x272 at
   0.566667), which the FunKey's picture shows at 0.661, so each layer was shrunk again whenever it changed. When the
   game creates a room layer at a tier above the picture's, the FunKey build moves its tier to the picture's (240x180
   at 0.3747): the layers are drawn 1:1, and what the game draws into them, each room's floor and walls on entering
   it included, is rasterized at the size it is seen. On the PC a room's drawing went from 13.7 to 8.9 ms on average
   (first rooms of a floor 22-34 -> 15-18 ms). The pictures: within 0.55 levels in 255 of the first round's on
   average. The logic: the same (same-game.sh, against the PC build which keeps the PSP's tier).
2. With smaller leaves, the cache of BitmapData leaves does as well with 3 MB as with 6 (PC, floors 1-2), so 3 MB;
   the renderer's cache back to 5 MB. About 3.5 MB less memory than the first round in all (the layers themselves:
   240x180 instead of 364x272, and no shrunk copies of them).
3. The SWF parser reads bit fields up to a byte at a time instead of one bit at a time (shapes are parsed when first
   drawn: 18% of a room entry's work on a floor's first rooms).
4. **Profile-guided optimisation** (`scripts/funkey/pgo.sh`, upstream's `ISAAC_PGO`): an instrumented build trained
   under qemu-arm on the play script with pictures (no console needed), then the build with that profile; code never
   run in training is optimised for size.

Not done, and why:
- Short sounds kept decoded: nearly all the MP3 decoding is the music stream (about 1,470 stereo samples a tick), and
  dr_mp3 already uses NEON for its synthesis and transforms (SIMD is only off for TCC).
- SDL's ALSA hotplug thread (1% of the CPU, it lists ALSA's devices every 5 s) only goes with SDL rebuilt with
  `SDL_ALSA_HOTPLUG_THREAD=0`; the SDL2 library is shared with the other FunKey ports' builds.

Checks (PC and qemu): the PGO build plays the same game as the PC build (same-game.sh, its room layers at the
picture's tier against the PC's at the PSP's); its pictures are the plain C build's, pixel for pixel (six ticks).
Builds ready for the console: plain (10.9 MB of code), PGO (9.1 MB), PGO with the runtime in Thumb-2 too (8.9 MB:
`TFK_ARM_MODE=-mthumb`, `TFK_PGO_BUILD`).

On the console (1296 MHz), the logic per tick (`scripts/device/logic.sh`, M1's workload, `testing/m1/r2-*`):

| Build | Mean | 90th pct | 99th pct | 10-19 enemies: mean | 90th pct |
|---|---|---|---|---|---|
| Before M4 | 9.92 ms | 12.87 | 19.79 | 13.39 | 17.11 |
| First round | 8.61 | 10.81 | 16.84 | 11.11 | 13.81 |
| Second round, no PGO | 8.43 | 10.96 | 19.68 | 11.23 | 13.88 |
| Second round, PGO | 7.42 | 9.49 | 17.90 | 9.58 | 11.75 |
| **Second round, PGO, Thumb-2 throughout** | **7.05** | **9.03** | **16.91** | **9.13** | **11.37** |

The OPK is the last (`scripts/funkey/pgo.sh`, `make-opk.sh $TFK_WORK/build-funkey-pgo-thumb`); same game and the
same pixels as the PC build. The play script with the profiler (`testing/m4/prof-r2`):

| | Before M4 | First round (`prof-m4c`) | Second round (`prof-r2`) |
|---|---|---|---|
| Drawing a picture: title / floors 1-3 | 30.7 / 14.2, 16.2, 14.9 ms | 16.7 / 6.9, 7.9, 7.4 | 15.7 / 6.3, 7.2, 6.6 |
| Logic per tick in the floors | 11.8 ms | 9.5 | 7.5 |
| Room entries over 150 ms (mean, worst) | 48 (345 ms, 720) | 29 (356, 1291) | 21 (275, 524) |
| Pictures a second; windows under 27 / under 24 | 26.2; 45 / 13 | 28.3; 16 / 3 | 29.0; 9 / 0 |
| Memory, game in RAM + swap (peak); available (least) | 52 MB; 4 MB | 51; 3 | 46; 5 |
| The game's share of the CPU (idle) | 79.5% (14%) | 59% (35%) | 50% (45%) |

My 34-minute session (first round's build, `testing/m4/user-2`): 30.0 ticks and 29.8 pictures a second on
average, every 7-minute stretch at 29.4-30.0; memory from 42 to 49 MB (RAM + swap) over the session, at least 4 MB
available; no sound errors in the log.

## Left for later

- Room entries on a floor's first rooms: still up to half a second (the floor's shapes parsed and rasterized once).
- Memory creeps by about 7 MB over half an hour (the heap's spread: the caches with budgets stay inside them).
- SDL's ALSA hotplug thread (1% of the CPU) needs SDL rebuilt (`SDL_ALSA_HOTPLUG_THREAD=0`), not in the shared
  sysroot.
