# M2: a picture, on the PC first

Status: **done** (2026-10-30). A software renderer draws the game the same as upstream's OpenGL renderer (rooms
within about 1 level in 255 per channel), minus blurred shadows; drawing a floor 1 room takes about 5 M ARM
instructions per frame, roughly 8–10 ms on the console (estimated; M3 measures it).

## What was built

Patch 0002 (upstream `rt/`):

- **`rt/render_soft.cpp`**, a software renderer with the `render.h` interface, used by every `ISAAC_FUNKEY` build in
  place of `render.cpp` (OpenGL). Modelled on upstream's PSP renderer (`render_psp.cpp`): one thread, the frame drawn
  right after the tick that built the snapshot, no GPU-side layers.
  - **The scene is drawn at the stage's own resolution** (363×272 with `genpsp/`), in stage pixels, then scaled
    once to the output. The game's layers (floor, creep, blood: BitmapData of the stage's size) and most sprites are
    then copied 1:1, not resampled; and the final scaling gives both picture modes for free (240×180 in the middle of
    the FunKey's screen, or the whole 240×240 with `g_softStretch`).
  - Shapes, texts and morphs are rasterized with upstream's PlutoVG path (`raster.cpp`) at the scale they are shown
    at, keyed by 1/32-octave steps, and kept in an 8 MB cache (least recently used dropped). Drawn 1:1 (mirroring
    included, the position rounded to the pixel) when the transform is a translation; otherwise resampled
    (bilinear) through the inverse transform.
  - Graphics far bigger than the stage (one overlay is 1705×1705 at this scale: 11.6 MB, 26 ms to rasterize) are
    rasterized only where they show, at their place (`rasterizeSrcAt`, new in `raster.cpp`), in a 2 MB cache of
    their own. Without that the overlay pushed everything else out of the cache every frame.
  - BitmapData are drawn from the game's own pixels (`SnapNode::bmPx`, as on the PSP: `snapshot.cpp` no longer copies
    them for a FunKey build).
  - Colour transforms per pixel with the same maths as `render.cpp`'s shader; masks with an 8-bit stencil (mask
    pixels with alpha ≥ 0.5, like the PSP's GE path).
  - Not done, as on the PSP: blur filters, interpolation between ticks, preloading, the controller focus "ink"
    (a frame is drawn around the selected option instead).
  - The output is scaled by area averaging; diagnostics text (overlay, version picker, loading screen) is drawn on
    the output at its resolution with upstream's 5×7 font.
- **`main.cpp`'s headless mode renders without a window** in a FunKey build (`--headless --size WxH --script ...`,
  `shot` commands write PPM or BMP), and brackets each frame with `OFKMEM dbegin` / `OFKMEM draw` lines for qemu's
  armprof and `scripts/measure/tick-cost.py`.

The single-thread play loop for the console (input, frame skip, the screen, sound) moved to M3, where it meets the
console's own input and display code: on the PC the renderer is exercised through upstream's headless test mode,
which already has scripted input and screenshots.

## Same picture as OpenGL

`scripts/build.sh host-funkey` builds the FunKey configuration for the PC. The same workload (title, menus, two
floors of random rooms) was run by it and by upstream's lean PC build with its OpenGL renderer (Mesa's llvmpipe under
Xvfb, `ISAAC_CPUBITMAPS=1` so the layers are drawn on the CPU as here), both at 363×272, with screenshots at the same
eleven ticks *(PC)*:

| Screen | Mean difference per channel | Pixels off by more than 16 |
|---|---|---|
| rooms (6 shots) | 0.68–1.13 | 1.2–2.3% |
| title, menus (5 shots) | 0.98–4.39 | 1.0–8.4% |

In rooms the two are the same to the eye; the pixels that differ are anti-aliased edges and sprites placed on the
nearest pixel. The menus differ most where upstream draws blurred drop shadows (the title screen's notes, the bomb),
which this renderer leaves out. Side-by-side pictures and difference maps: `testing/m2/soft/pair-*.png`,
`diff-*.png` (gitignored).

## Cost

Measured under qemu with armprof *(qemu)*: the FunKey build drawing every frame at 240×240 (4:3 with bars), a workload
of the title, floor 1 (six random rooms), the trip to floor 2 and six rooms there, 4,960 ticks. "Draw" is everything
between `OFKMEM dbegin` and `OFKMEM draw`: drawing the snapshot and scaling it to the output (the snapshot itself is
built outside, and was part of M1's logic numbers). Millions of ARM instructions per frame:

| Version | Floor 1, median | 90th pct | Floor 2 rooms, median | 90th pct | Title, median |
|---|---|---|---|---|---|
| first working version | 15.4 | 16.3 | 16.9 | 48.4 | 49.5 |
| + runs (below) | 6.7 | 7.8 | 8.3 | 46.9 | 44.4 |
| + still graphics at their transform, scaler reordered with NEON | **5.0** | **6.3** | **6.2** | **11.0** | 14.8 |

The trip between two floors (a cutscene) is 20 M per frame; room loads 120–330 M once (rasterizing a new room's
graphics). On the console that is roughly **8–10 ms per frame in floor 1 rooms and 10–17 ms in floor 2's** if the
drawing code runs at 0.5 instructions per clock (the logic ran at 0.2, being memory-bound; drawing streams through
memory and should do better, but only M3 measures it).

What the profile showed, and what was done:

1. **A dozen stage-sized layers per room** (floor, walls, shadows, lighting, the HUD band, the overlay), all drawn
   1:1 but pixel by pixel, transparent pixels included. Each graphic's rows are now indexed once into runs
   (`buildRuns`): stretches that hold pixels, opaque (copied with `memcpy`) or not (blended); gaps of 4 transparent
   pixels or more are skipped. For rasterized graphics the runs are built with the raster; for BitmapData whenever
   their version changes (`SnapNode::bmVersion`, new), unless they change every frame. 15.4 → 6.7 M in floor 1.
2. **Large graphics stretched or turned slightly** (a room overlay at 0.984 × 1.0, the trip screen's backgrounds),
   which can't be copied 1:1 from a raster made at one scale, were resampled in full every frame. When such a graphic
   (4,096 pixels or more on the stage) has the same transform as in the previous frame, it is now rasterized right at
   that transform, where it shows, and copied 1:1 from then on; moving ones are still resampled. Floor 2's 90th
   percentile 46.9 → 11 M, the title 44 → 15 M.
3. **Scaling to the output**: vertical pass first over whole rows (NEON on the console, 16 bytes per step), then the
   horizontal pass over the 180 output rows only. 4.9 → 1.9 M.

What is left, by the profile: `drawTex` 6.1 M per frame on average (blending, and the resampled sprites: rotated or
squashed ones), the scaler 1.9 M, rasterizing new graphics 0.65 M. NEON blending and an RGB565 output written by the
scaler itself are the next steps, in M4 with console timings.

## Memory

Not measured on the console yet (M3). The renderer keeps: rasterized graphics up to 8 MB (`ISAAC_SOFT_CACHE_KB` to
change it), graphics rasterized at their transform up to 3 MB, the stage canvas (395 KB), its stencil (99 KB), the
output (230 KB at 240×240), the scaler's rows (264 KB), and the runs. At 37.8 MB for the logic in M1, the total could
reach 50 MB at worst; M3 measures it on the console and lowers the cache budget if the system starts swapping.

## Same game

The ARM build with the renderer still plays exactly like the musl-maths PC reference (`scripts/measure/same-game.sh`,
every enemy's state at every tick): the renderer doesn't touch the logic.
