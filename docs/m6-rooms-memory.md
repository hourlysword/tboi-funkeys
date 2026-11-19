# M6: room entries and memory

Status: **done** (2026-11-15), patches 0009 and 0010, installed on the console. What M4 left: a floor's first rooms
still took up to half a second to enter, and the game's memory crept up by about 7 MB over half an hour. Now: room
entries over 150 ms are fewer and shorter (12 instead of 18 in the play script, 2 instead of 6 over 300 ms), fewer
still once the pieces of rooms drawn before are on the card (4 instead of 11 in other rooms after one session, none
with the same rooms), and the memory levels off at about 45 MB. The logic is unchanged: same-game.sh identical, also
between the new PC build and a console build from before these changes.

## Measuring

Two lines in the game's log (`FunKey/isaac/logs/launch.log`), on the console as on a PC:

- `long tick`: any tick over 150 ms (`ISAAC_FUNKEY_SLOWMS`), with what it was spent on: the logic, of it
  BitmapData.draw (the pieces rasterized, how long, how many reused; shape and timeline parsing, of it the reads
  from the game file), the picture, the collector.
- `memory at tick`: every minute of play (1800 ticks, `ISAAC_FUNKEY_MEMEVERY`): RAM and swap, the collector's objects,
  interned strings, parsed shapes and timelines, sounds, the renderer's cache, the leaves, morph shapes, bitmap
  surfaces (and on a PC the heap in use). `ISAAC_FUNKEY_CENSUS=1` (testing) first collects everything, so that only
  what is alive counts, adds the collected heap by kind, and lists the interned strings by pattern at the end.

`ISAAC_FUNKEY_NOWAIT=1` (testing) plays a test script without waiting for the clock: on the PC the 7-minute play
script takes 12 s.

## Room entries

On the console (the 7-minute play script, `testing/m6/m6-base`), the 18 ticks over 150 ms after the title averaged
261 ms: 201 of them drawing the room's floor and walls into its bitmap (BitmapData.draw: 55 pieces rasterized on
average), and 118 of those parsing shapes. Six were over 300 ms, the worst 422.

- The pieces are cached with their position to 1/64 pixel; at whole pixels only 27% fewer would be rasterized on
  the PC, and with an unlimited cache 13% fewer: nearly all are pieces seen for the first time.
- Parsing: 1,306 shape parses in the run for 719 different shapes. Parsed shapes have a 5 MB budget, and half of a
  parsed shape was the second copy of its edges kept for exact hit tests, which the game asked for twice in the whole
  run; their vectors also kept the slack of their growth. Now the edges for hit tests are made only when a hit test
  needs them (`shapeEnsureHit`), and every vector is trimmed: the same budget holds about twice as many shapes, and
  the run parses 809 times (90 again) instead of 1,306, reading 1.3 MB from the game file instead of 2.1. Joining a
  shape's edges into paths used a hash multimap (an allocation per edge): a sorted array now. The pictures are the
  same, pixel for pixel.

The same run on the console afterwards (`testing/m6/m6-r1`):

| | Before (`m6-base`) | After (`m6-r1`) |
|---|---|---|
| Ticks over 150 ms after the title | 18 | 12 |
| over 300 ms; the worst | 6; 422 ms | 2; 418 ms |
| Their mean: all / drawing the room / of it parsing | 261 / 201 / 118 ms | 231 / 165 / 66 ms |
| Parsing in the whole run | 4.2 s | 2.2 s (reading the game file: 0.66 s of it, 797 reads) |
| Pictures a second (mean of the 5-second windows) | 29.2 | 29.3 |

What is left (`armprof`, instructions under qemu, a run that stops before the tick against one that stops after it):

- A room entry (110 pieces new to the floor): 109 M instructions, 37% the rasterizer's core (PlutoVG's FreeType
  gray rasterizer: the rooms' floor and wall shapes have thousands of edges), 17% parsing shapes, 14% converting and
  transforming paths, 5% filling spans. Upstream already gave the rasterizer a 2 MB pool (no bands).
- The two ticks over 400 ms are the game's own level generation when a floor starts (273 M instructions: its frame
  script, variable lookups `getVarK` 16.5%, property access): once per floor, when it starts, followed by the first
  room's entry (together about 0.6 s). The lookups are already a tight walk up the scope chain; left as it is.

## The pieces kept on the card

What is left of a room entry is mostly rasterizing pieces seen for the first time. They are now also kept on the card
(`raster.cpp`, FunKey builds): each piece rasterized is compressed (zlib, level 1) and appended to
`saves/leaves_<SWF length>.data`, listed in `.index` (16 bytes a piece, read when the game starts into a table in
memory), and a piece needed again, in a later room or session, is read back from there instead of being parsed and
rasterized.

- Its key holds no pointer: the character's id and kind (shapes, morphs at their ratio, static text; dynamic text
  changes and is left out), the matrix, the colour transform and the offset to 1/64 pixel. Only characters of the game
  file itself (a shape drawn by script has none).
- Both files are for one build of the program (its linker build ID, `-Wl,--build-id`) and one game file (the SWF's
  length), both in the files' header: another build or game starts them afresh. Off with mods (some change shapes)
  and with `ISAAC_NO_LEAFDISK=1`. Up to 16 MB; a piece read back is checked (its key, a CRC) and rasterized again if it
  doesn't match. The pixels first, then the index entry: a power cut leaves at worst entries that are skipped.
- New pieces wait in a queue (up to 512 KB of pixels) and are compressed and written in the time left before the next
  tick (4 ms at most a tick), so a room's entry doesn't wait for them.

On the PC: pictures read back identical to the ones rasterized. With the same rooms again, 3,180 pieces come from the
card (1.8 MB, 0.5 KB each on average) and almost nothing is rasterized. With other rooms each time (eight sessions of
three floors, different seeds), the share found on the card goes 14, 20, 33, 41, 39, 34, 49, 40% while the card grows
by about 0.5 MB a session: rooms are built from many combinations of pieces and places (rounding positions to 1/8 or
1/4 pixel changes nothing). AddressSanitizer: five long sessions without an error. The logic: same-game.sh identical.

On the console, the 7-minute play script (`testing/m6/m7-*`); the last two play other rooms (another seed):

| Run | Ticks over 150 ms after the title | Of them room entries (median, worst) | Drawing rooms in all | Pieces from the card |
|---|---|---|---|---|
| Without the card (`m6-r1`) | 12 | 11 (198, 335 ms) | 4.4 s | - |
| Empty card (`m7-cold`) | 11 | 9 (170, 356 ms) | 4.2 s | 428 (read again in the same run) |
| The same rooms again (`m7-warm`) | 1 | 0 | 1.8 s | 3,176 of 3,176 |
| Other rooms, without the card (`m7-other-nocard`) | 11 | 11 (212, 344 ms) | 4.3 s | - |
| Other rooms, the card of one session before (`m7-other`) | 4 | 4 (190, 271 ms) | 2.9 s | 900 of 3,647 |

A piece read back costs 0.2-0.4 ms on the console (0.5 KB on average), against 1-3 ms rasterized; the pieces found
again are mostly the large ones every room of a floor shares (880 KB for the 900 found, 819 KB for the 2,747 new),
which is why a quarter of them takes away two thirds of the long entries. Writing: 2,749 pieces (1.5 MB) in 2.4 s of the time between ticks over the cold run, with no change
to its room entries or its pictures a second (29.3).

## Memory

On the PC, a 22-minute workload (8 floors, 15 rooms each) with only what is alive counted: the collector's objects
stay at about 1,100, the caches with budgets inside them, but the heap in use grows from 30.5 to 42 MB. Two causes:

- **Sprite timelines** (2.5 -> 10.9 MB): a sprite's frames and placements are parsed when its first clip is made and
  were kept for good, for every kind of enemy, effect or item seen. Now (`spriteEnsure`) the timelines of sprites with
  no clip left, none made in the last 2 seconds, are dropped above 3 MB, least recently used first, and parsed again
  from the same tags when needed. With it the heap in use stays at 32-35 MB over the 22 minutes, for twice as many
  timeline parses (1,857 instead of 905).
- **Interned strings** (3,300 -> 12,000): the game's sound function makes an empty clip named `sz` and a counter for
  every sound it plays, and those names stayed interned for good. Upstream already interns the automatic instance
  names weakly (freed with their clip); script-given clip names now are too (`atomOfWeak`), pinned only if a script
  uses one as a key: about 3,500 throughout. One catch, found as a crash in a later test (a clip's name freed under
  it): the collector frees garbage a little at a time over the following ticks, and the game's names come back ("sz1"
  again once its counter starts over), so a weak name found again while it still waited to be freed was freed under its
  new clip. `internWeak` now keeps a name it hands out again through the sweep in progress.

On the console, the game's own memory (RssAnon + VmSwap, sampled every 2 s by `play-run.sh`):

| Run | After 3 min | After 7 min | At the end | Peak |
|---|---|---|---|---|
| Play script, before (`m6-base`) | 38.1 MB | 43.7 MB, rising | (7 min) | 44.7 |
| Play script, after (`m6-r1`) | 38.8 | 41.8 | (7 min) | 43.4 |
| 5 floors of 15 rooms, 14 minutes, after (`m6-long`) | 42.2 | 42.4 | 44.8 | 44.8 |

In the long run the timelines stay at 2.0-2.9 MB (936 parsed, 596 dropped), the interned strings at 3,100-3,900; what
still rose was the parsed shapes filling their 5 MB budget (2.2 MB after a minute, 4.9 at the end), which stops there.
29.4 pictures a second on average; 17 of the 75 room entries over 150 ms (median 177 ms, the worst 318).
`NO_TICKMARKS=1 scripts/device/play.sh ...` runs without the per-tick lines (the log stays in the console's RAM
until the end).
