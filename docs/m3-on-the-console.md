# M3: on the console

Status: **done** (2026-10-30). The game plays on the FunKey S from its OPK: the picture on the screen, sound on the
speaker, the buttons, quitting and power-off with the save written. Floors 1–3 run at full game speed (30 ticks a
second) with 26–30 pictures a second in most rooms; the title and menus draw 15–25.

## What was built

Patch 0003 (upstream `rt/`):

- **`rt/funkey.cpp`**, the console side, called from `main.cpp` in place of its threaded loop (`--headless` tests
  keep upstream's path):
  - **The loop, on one thread:** buttons → one logic tick → (snapshot, draw, present) → collector, on a fixed 30 Hz
    clock. When a tick and its picture take longer than 1/30 s, pictures are skipped (never the logic) until the
    clock is caught up, at least every 4th drawn; after a stall over 0.5 s (a room being built) the clock is reset
    instead of caught up. After the collector, the decoded SWF bitmaps are trimmed to 4 MB (least recently used
    first).
  - **Screen:** `/dev/fb0`, 240×240 RGB565 (fbtft over SPI). Only one page is backed although the driver reports
    more; `FBIOPAN_DISPLAY` after each picture tells the driver to send it, and a picture is handed over again every
    0.1 s when there's no new one. RGB565 with a 4×4 ordered dither (the stage's dark gradients band otherwise). The
    text console goes to graphics mode with its keyboard off while the game runs.
  - **Buttons:** FunKey-OS's button daemon's virtual keyboard. D-pad moves, X/A/B/Y shoot up/right/down/left, L bomb,
    R active item, Fn (tapped alone) card or pill, Start pause; in menus the D-pad chooses (with repeat), A confirms,
    B goes back. Menu twice within 2.5 s quits ("Press MENU again to quit" in between).
  - **Power-off:** FunKey-OS signals the PID the launcher recorded (`pid record`) and powers off 0.1 s later. A signal
    thread takes it at once (the loop may be inside a room build): cancels the scheduled power-off, starts
    `powerdown handle` ("Shutting down..."), stops the loop; `main.cpp` writes the save, then `powerdown now`. A
    watchdog powers off at 2.5 s whatever happens (the lid cuts the power at 3 s).
  - Messages through the display driver's notification overlay; a crash handler that gives the console back and
    logs the signal; a speed and memory line every 5 s in the log (`[funkey]`).
  - Test hooks: `ISAAC_FUNKEY_SCRIPT` plays a headless test script with the screen, pacing and sound of a real
    session; `ISAAC_FUNKEY_MEMLOG=N` logs memory per tick; `ISAAC_FUNKEY_NO_POWEROFF`.
- **Sound:** SDL2's ALSA output as before; the FunKey's speaker is on the right channel only, so the mix goes there
  as (L+R)/2.
- **Startup memory:** one bitmap in the Eternal Edition is 3000×3000 (35 MB decoded) and only ever shown small.
  Lossless bitmaps over 1024 pixels a side are now decoded in strips and box-averaged by a power of 2 on the way in
  (`decodeShrunk`, 750×750 here), the fill matrix scaled to match. Peak memory at startup went from 92 MB to 27 MB on
  the PC.
- Renderer: still graphics more than 1.5× the canvas's area are rasterized at their transform (was: 2× and less
  than half visible).

This repository: `opk/` (launcher `isaac.sh`, desktop entry, a generated icon),
`scripts/funkey/make-opk.sh` and `make-kit.sh`, and `scripts/device/play.sh` / `play-run.sh`, which run a test
script with the game's own loop on the console and bring back the log, memory samples, screenshots and the screen.

The launcher keeps everything in `FunKey/isaac` (the player's `Isaac.exe`, `isaac.ini`, `saves/` with the game
unpacked on first start, `logs/launch.log`), records the game's PID for the power-off, sets 1296 MHz
(`launcher.cfg` `cpu_mhz=`), switches the speaker's amplifier on, and decodes the exit status into a message.

## On the console

`scripts/device/play.sh play-1296 1296 play.txt`: the M1 workload (title, then 12 rooms on each of floors 1–3,
12,580 ticks) played by script through the game's own loop, on the screen, with sound, at 1296 MHz. My
FunKey-OS-based firmware, the menu paused for the run. 432 s.

| Part | Ticks | Logic per tick, mean / p90 | Picture (draw + present), mean / p90 | Pictures shown |
|---|---|---|---|---|
| Title, menus, intro | 999 | 3.5 / 5.4 ms | 29.9 / 45.3 ms | 79 % (24 a second) |
| Floor 1 (Basement) | 3,660 | 8.9 / 10.2 ms | 13.5 / 16.3 ms | 95 % (28.5) |
| Floor 2 | 3,960 | 8.9 / 11.8 ms | 15.4 / 17.9 ms | 91 % (27.3) |
| Floor 3 (Caves) | 3,961 | 8.4 / 11.0 ms | 14.2 / 16.3 ms | 92 % (27.7) |

- **The game keeps its speed:** 30 ticks a second in every 5-second window, except the 8 windows with a room
  build over 0.5 s (26–27 ticks a second there: the stall isn't caught up, by design).
- **Pictures:** 11,531 drawn, 1,048 skipped. In rooms a tick and its picture take about 23 ms of the 33 ms; the
  skips come from heavier ticks (p99 17 ms logic, 23–43 ms drawing), the sound thread (same core), and the catch-up
  after room builds. Present (RGB565 with dither, pan) is 1.9 ms of each picture.
- **Room builds:** 27 ticks over 250 ms, the worst 495 ms in the logic plus the first picture of the new room
  (raster cache misses), up to 660 ms in all. The biggest item left for M4.
- **Title and menus** draw 25–48 ms a picture: the large animated title paper and its texts are re-rasterized often.
- Shots taken during the run (`testing/m3/play-1296/sheet.png`): the title, Basement rooms, the boss intro, the
  Caves, all as on the PC.

The OPK itself, started with `opkrun` as the menu does (`HOME=/mnt/FunKey`), on a fresh `FunKey/isaac` holding only
`Isaac.exe`: the first-start notice, the unpack into `saves/` (46.5 MB), the intro at 25–29 pictures a second, the
clock at 1296 MHz during the game and back to 1008 after; SIGTERM saves and quits with status 0.

## Memory

On the console during the 7-minute run (`mem.txt`, every 2 s): peak RSS 45.4 MB; in RAM while playing 33–36 MB of
the game's own memory plus 4–7 MB of mapped files; the least used part goes to swap, 0 at the first minute, 13.8 MB
at the end. MemAvailable stays at 6–12 MB, 4.8 MB at its lowest. The game's memory in all (in RAM + swapped)
goes from 40 MB after the first floor's first rooms to 46–48 MB at 6–7 minutes, growing more slowly over time.

Before `decodeShrunk` the same run started at 51–65 MB of swap (the 3000×3000 bitmap); that is gone.

The same script on the PC (`build-host-funkey`, `ISAAC_FUNKEY_MEMLOG`, the game's own counts per tick): the caches
with budgets stay inside them for the whole run (parsed shapes 3.6–5.1 MB of 5, sounds 0.6–2.0 of 2, rasters
6.1–8.1 of 8, frame buffers 1.0); the number of live objects goes up and down with each collection (4,000–21,000),
no trend. So the slow growth on the console is not in those caches; likely the heap's spread (musl's malloc with
many short-lived objects) and the caches without a counter in the log (still graphics at their transform, decoded
bitmaps). For M4: a 30-minute run to see where it settles, and the allocator item, which was already on the list.

## Same game

`scripts/measure/same-game.sh` on the M3 build (the FunKey build under qemu against the PC build with musl's maths):
12,580 ticks, 63,207 enemy states, identical on every line. The loop changes nothing in the logic.

## Test kit

`scripts/funkey/make-kit.sh`: `out/isaac-kit.zip` holds `Native games/isaac_funkey-s.opk` (5.2 MB). No game files:
the player copies their own `Isaac.exe` into `FunKey/isaac`. Installed on the development console with `FunKey/isaac` set up.

## My first play test

Two floors and a death, 7 minutes (`FunKey/isaac/logs/launch.log`): "for the most part the game felt pretty good";
sound fluent; room-entry pauses at most about a second; the death screen and the way back to the menu work. In busy
rooms the log shows the logic at 16–18 ms a tick and drawing at 17–20 ms: 20–25 pictures a second at full game
speed, felt as slowdown (M4). A first try earlier ran while another program was using the console's memory (3–8
pictures a second, the clock and swap fought over); not representative.

One bug, found during testing: the bottom of every room was a flat band of one colour, sometimes with a door on it. The
game makes the room's background bitmap `gridys - 75` pixels tall, 75 being the HUD's height in game units, right at
its scale 1 but 57 units short at the lean builds' 0.566667 (upstream's PSP build has the same): the bottom wall was
cut off, the stage's colour showed, and a bottom door was drawn over it. Patch 0004 sizes that bitmap for the HUD at
the room scale (364×197 → 364×230) in the BitmapData constructor; the bottom wall now matches upstream's full PC
build (`testing/m3/wallfix/compare-*.png`), and the logic is unchanged (same-game identical).

## Left for M4 and M5

- Room builds (0.3–0.7 s) and the title and menus (25–48 ms a picture): the first M4 items.
- Memory over a long session (where the 40 → 47 MB settles); a lower raster cache budget if it doesn't.
- Blurred shadows (title, cutscenes) are drawn sharp or not at all, as on the PSP.
- M5: the FunKey menu (volume, brightness, picture mode 4:3 or full, frame skip, quit), the version picker with the
  buttons (now: the oldest version found starts, or `game = eternal|wotl|og` in `isaac.ini`), readability at 240 px.
