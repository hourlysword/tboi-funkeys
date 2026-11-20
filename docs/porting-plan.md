# Porting plan

Status: M0–M6 done (2026-11-15), 1.0.0 released; M7 and M8 done (2026-11-19). M4 (docs/m4-speed.md): the game plays on
the console at full speed, 29 pictures a second on average in the floors (busy rooms included), drawing a picture 6–7
ms and the logic 7.5 ms a tick, room entries mostly under 0.3 s. M5 (docs/m5-menu.md): the FunKey menu (both picture
modes), the RetroFE entry, the version picker, text checked at 240 px, the kit. M6 (docs/m6-rooms-memory.md): shorter
room entries, memory that no longer creeps up. M7 (docs/m7-clock-and-code.md): OVERCLOCK in the menu. M8
(docs/m8-upstream-1.7.md): the patches on upstream v1.7.0 (safer saves, Continuum). Upstream:
[whylurking/IsaacRecomp](https://github.com/whylurking/IsaacRecomp) at `b156559` (v1.7.0, 2026-11-16; 1.0.0 was built
on `a2cfc66`, v1.5.0), fetched into `$TFK_WORK/IsaacRecomp` by `scripts/fetch-upstream.sh` (a reference clone from the
planning also sits in `IsaacRecomp/`, ignored by git).

Numbers are marked *(upstream)* when they come from upstream's NOTES.md, *(console)* when measured on a FunKey in
my other FunKey S projects, and *(estimate)* when they are guesses that a milestone below will replace with a measurement.

## Goal

Play the Flash *Binding of Isaac* (Original, Wrath of the Lamb, Eternal Edition) on the FunKey S through
IsaacRecomp, with sound, from GMenu2X, using the player's own Steam `Isaac.exe`. The game's logic must stay exactly
as upstream has it: 30 ticks per second, bit-identical physics. Target: 30 fps at 1296 MHz on early floors, and busy
rooms still playable (see the frame-skip question at the end).

## What upstream already gives us

The first look at this project assumed the low-memory, single-core path would have to be invented. It doesn't:
upstream started a **PSP port** for v1.5 and kept its code although the port itself was shelved. That code is the
starting point.

| Upstream piece | What it gives the FunKey port | Where |
|---|---|---|
| The game's ActionScript 2 compiled ahead of time to C++ | no interpreter; one `namespace` per version | `gen/`, `gen720/`, `genpsp/` |
| A small stage: 363×272, room layers 364×272 (`patchhd.py --scale 0.566667`, `gen.py --room-scale 0.566667`) | game code already generated for a small screen, usable as-is to bring the port up | `genpsp/` |
| Lean SWF loading (`FL_LEAN`) | the SWF is decompressed once into a cache file; **3.2 MB in RAM instead of 36** *(upstream)*; shapes parsed on demand (5 MB LRU), sprite timelines on first use, sounds read from the file when played | `rt/swfload.cpp` |
| A single-thread main loop | input → logic tick → snapshot → GC → render → present, 30 Hz pacing, scripted test input, performance log | `rt/main_psp.cpp` (431 lines) |
| A renderer with no GPU-side layers | shapes rasterized on the CPU (PlutoVG) into atlas pages, BitmapData drawn from its own pixels, colour transforms, masks with a stencil, no blur, a per-frame rasterization budget (~10 ms) | `rt/render_psp.cpp` (449 lines) |
| A large-block arena | blocks of 64 KB and more kept apart from the small objects (on the PSP a 300 KB request failed with 11 MB free) | `rt/psp_alloc.cpp` |
| Small-memory settings | GC at 15,000 objects with growth 1.4, 1 MB pixel pool, 2 MB leaf cache, 24 sound channels, a PCM cache for short sounds, 512 KB VM stack | `rt/platform.cpp`, `rt/audio.cpp`, `rt/core.h` |
| Logic without a renderer | `--headless --norender` runs the game with no window and no GPU; `--script`, `--monkey SEED`, `ISAAC_TICKMS=1` (cost of every tick); OpenGL is only loaded at run time, so nothing GL is needed at link time | `rt/main.cpp`, `rt/render.cpp` |
| Determinism checks | the same seed gives the same logic on x86 and aarch64 (qemu); differential tests against a patched Ruffle | `cmake/aarch64-linux-test.cmake`, `tools/difftest/` |

**Why the PSP port was shelved, and why that does not carry over.** On a real PSP it showed one frame every 2–4 s:
logic took 25–95 ms per tick in rooms, and drawing 140–280 ms per frame (1–3 ms in the PPSSPP emulator) *(upstream)*. The logic
cost came mostly from **double-precision maths in software**: the PSP's FPU is single precision, every AVM number is
a double, and over half the CPU went into libgcc's soft-float routines before upstream switched to compiler-rt's
*(upstream)*. The FunKey's Cortex-A7 has VFPv4 with doubles in hardware and runs at about four times the PSP's
333 MHz. The drawing cost was the PSP's GPU path on hardware, which a CPU compositor writing 240×180 pixels does
not pay.

**What is left to write:** a CPU compositor (same interface as `render_psp.cpp`), the FunKey main loop and console
plumbing, the build and packaging, and the speed work.

## Expected cost on the console

The budget is **33.3 ms per frame on one core** (30 fps, logic and drawing in the same frame, no interpolation).

| Part | What we know | FunKey estimate |
|---|---|---|
| Logic + GC | Switch (Cortex-A57 at 1020 MHz, 960×720 stage, layers drawn on the GPU): floor 1 about 2.5 ms per tick; busy rooms on floors 2–3 5–7.5 ms plus GC 40–64 ms per second *(upstream)* | The A7 at 1296 MHz is roughly 2–3× slower than that core on this kind of pointer-heavy code (in-order, 32 KB L1, about 128 KB L2, DRAM about 0.8 GB/s *(console, my other FunKey S projects)*): **5–8 ms on floor 1, 15–30 ms in busy rooms**, plus the BitmapData drawing the Switch does on its GPU *(estimate)* |
| Drawing | 240×180 = 43,200 pixels; maybe 4–6 layers deep (floor, creep, shadows, entities, HUD) | 2–5 ms with bilinear blends, plus rasterizing new graphics when a room is entered (budgeted per frame) *(estimate)* |
| Sound | MP3 music (dr_mp3) and up to 24 mixed channels, on its own thread | 1–3 ms per frame's worth *(estimate)* |
| Present | 240×240 RGB565 to `/dev/fb0` | under 0.5 ms *(console, my other FunKey S projects)* |

So floor 1 at 30 fps looks reachable, and **busy rooms are the risk**. M1 measures the logic on the console before
any renderer is written.

**Measured in M1** ([m1-logic-measured.md](m1-logic-measured.md)): the logic takes 9.9 ms per tick at 1296 MHz on
average and 17 ms at the 90th percentile with 10–19 enemies, better than the estimate above; sound about 2–3 ms; room
loads stall 0.3–0.5 s.

## Architecture

```
        GMenu2X + opkrun (OPK mounted at /opk)
                         |
                         v  opk/isaac.sh (1296 MHz, data dir, logs, PID for the power-off)
 +-----------------------------------------------------------------------------+
 | isaac: the FunKey build of IsaacRecomp (game on one thread)                 |
 |  rt/main_funkey.cpp (from main_psp.cpp): version picker; input -> logic     |
 |    tick at 30 Hz -> snapshot -> GC -> draw -> present; upstream's headless, |
 |    script and screenshot options for tests on PC, under qemu and on device  |
 |  rt/render_soft.cpp (from render_psp.cpp): CPU compositor                   |
 |    shapes (PlutoVG) -> atlas pages; affine bilinear blits, Flash colour     |
 |    transforms, stencil masks; 32-bit frame -> RGB565                        |
 |  rt/funkey/: fbdev + FBIOPAN, evdev keys, power-off takeover, CPU clock,    |
 |    overlay messages, the FunKey menu (as in my other projects)              |
 +----------------------+--------------------------------+---------------------+
                        |                                |
   upstream runtime, unchanged where possible:     audio.cpp's mixer -> SDL2 audio
   core, display, builtins, swfload (FL_LEAN),     (static, ALSA loaded at run time);
   raster, snapshot, GC, menus, mods               (L+R)/2 to the right channel
                        |
   generated game code: genpsp/ to start, later a FunKey stage (see M4)
   Every binary links libfkm.a: the console's libm gets floor/ceil/round wrong
```

## Decisions (proposed)

* **Upstream pinned, our changes as a patch series** (the workflow of my other FunKey S projects): `scripts/env.sh` names the
  commit; the work tree is `$TFK_WORK/IsaacRecomp` in WSL on a `funkey` branch; this repo keeps
  `patches/isaacrecomp/`, scripts and docs. Upstream moves fast (v1.5.0 landed today), so the pin matters.
* **One build option, `ISAAC_FUNKEY`.** Upstream's Linux build plus `FL_LEAN`, `genpsp/`, small limits, no
  threads for rasterization, no GL, SDL2 for sound only. The `__PSP__` choices that are really "one core, little
  memory" (24 channels, the smaller VM stack, menu focus search every 4th tick, leaf cache eviction, no worker
  threads) move behind a shared macro so both ports use them. The PSP-only parts (GE pixel order, sceGu, the
  launcher, the weak per-game tables) stay PSP-only.
* **One binary with all three versions.** On the PSP they didn't fit together. On Linux code is paged in from the
  OPK on demand, so only the chosen version's code (5–7 MB of text on the PSP *(upstream)*) is loaded. M1 checks
  this; if the page cache thrashes, fall back to one binary per version as on the PSP.
* **Toolchain:** GCC 14 `arm-linux-musleabihf` with the FunKey SDK's sysroot, reused from my other FunKey S projects
  (`TFK_SHARED`, `scripts/env.sh`); C++ runtime static; only `libc.so` needed, plus `libasound.so.2` loaded at run
  time; `check-elf.sh` enforces it. SDL2 2.30.9 static, built as in my other FunKey S projects (dummy video, evdev,
  ALSA loaded at run time), the same SDL2 version upstream builds for Android.
* **Floating point exactly as upstream:** hardware doubles, `-ffp-contract=off` (already in upstream's CMake), and
  **no `-ffast-math` anywhere in the runtime or the generated code**, unlike some renderers in my other FunKey S projects. With
  the console's broken libm, `Math.floor` would change the game's logic, not just a picture, so `libfkm.a` is
  linked whole and the build refuses libc maths imports.
* **Picture (my choice, 2026-10-30):** the stage drawn at 240×180 in the middle of the screen with 30-pixel bars
  (4:3), the default and the first one built. A "full" mode stretches it to 240×240 by drawing with a taller stage
  matrix (shapes stay sharp because they are rasterized at the final transform); both chosen in the FunKey menu. If
  keeping both turns out to be hard, 4:3 only.
* **Busy rooms (my choice):** frame skip by default. The logic always runs its 30 ticks per second; when a frame
  can't be drawn in time, it isn't (M4).
* **No interpolation, no blur.** Draw once per tick (alpha 1, as `main_psp.cpp` does) and keep `filters = 0`; a cheap
  low-resolution blur for the cutscenes can come later if it fits.
* **Controls** (upstream's Switch layout by button position):

  | FunKey | In play | Menus / pause |
  |---|---|---|
  | D-pad | move | choose |
  | X / A / B / Y | shoot up / right / down / left | A confirm, B back |
  | L | bomb | |
  | R | active item | |
  | Fn | card / pill | |
  | Start | pause | pause / resume |
  | Menu | FunKey menu | FunKey menu |

* **Data on the card:** `/mnt/FunKey/isaac/` (`HOME=/mnt/FunKey` under the launchers): `Isaac.exe` (one or
  several versions), `isaac.ini`, `saves/` (upstream's `.sol` saves, which copy to and from PC, Switch and Android,
  plus the decompressed SWF cache, about 36 MB), `logs/`.
* **Licence and privacy:** our runtime changes are MIT like upstream's `rt/`. Upstream's licence excludes the
  generated game code (`gen*/`, which includes `genpsp/` and any stage we generate), so it is never committed here
  (`export-patches.sh` refuses a series that touches it) and the game files stay out of git. Local git for now, a
  private GitHub repo later (my choice).
* **Test game:** my Steam copy is the **Eternal Edition** (the current Steam download with Wrath of the Lamb is the
  Eternal Edition update; IsaacRecomp recognises it by its content). Measurements use it; the original and Wrath of
  the Lamb are supported by the same binary.

### Taken from my other FunKey S projects

| Finding (on the console) | Here |
|---|---|
| FunKey-OS's libm is wrong (built with `-Ofast`): floor, ceil, round | `libfkm.a` linked whole, maths imports refused |
| Only `libc.so` is sure to exist (DrUm78's firmware dropped libvorbis) | everything static, ALSA loaded at run time |
| `struct input_event` is 16 bytes on the console, 24 in the SDK headers | `cmake/funkey-include/linux/input.h` |
| 1296 MHz needs the K=2, M=1 PLL factors (the old ones ran at ~780 MHz) | set by the launcher, restored at exit |
| fbtft backs one page; FBIOPAN once per frame sends only new frames | present with a pan per frame |
| Speaker on the right channel only; codec at 44062.5 Hz; the amplifier buzzes | mix at the device's rate (upstream already does), (L+R)/2 to the right, amp off while the menu is open |
| Power-off gives 0.1 s; the lid 3 s | signal thread, flush the save (`sharedObjectFlushAll`), exit |
| The in-game menu I rate best | volume, brightness, picture mode, frame skip, quit, power off |
| GCC on ARM32 misaligns returned `alignas(16)` temporaries (SIGBUS with NEON) | watch for it in the compositor's NEON code |
| A7 tuning: prefetch ~48 bytes ahead, interleave NEON chains, avoid per-pixel float | compositor blends and RGB565 conversion |
| A FunKey-like VM: memory cap, fake buttons, screen dumps | every build before the console |
| Instruction counts per function under qemu; sampling on the console | M1 and M4 |
| Profile-guided optimisation: +4–5% | M4 |

## Milestones

### M0: ground work

- [x] Repository layout like my other FunKey S projects: `docs/`, `scripts/` (`env.sh`, `fetch-upstream.sh`,
      `export-patches.sh`, `build.sh host|host-lean|funkey`), `scripts/funkey/` (libfkm, check-elf, cpuclock),
      `cmake/` (toolchain, static linking, `input.h`), `scripts/measure/`, `scripts/device/`. `game files/` and the
      reference clone are gitignored. The OPK scripts come with M3
- [x] Host build (x86-64 Linux in WSL) of upstream unchanged, run headless with my `Isaac.exe` (2026-10-30): it is
      the **Eternal Edition**; a run starts, floor 1 logic about 0.2–0.4 ms per tick on this PC. Builds take about
      2 minutes each (4 jobs)
- [x] Host build with `FL_LEAN` and `genpsp/`: plays the same; the 46.5 MB SWF is decompressed once into
      `saves/swf_48785821.cache`, 3.2 MB of it kept in memory. Test scripts' clicks are scaled from the 1440×1080
      stage to 363×272 (`scripts/measure/workload.py --scale`); the Eternal Edition starts its runs with upstream's
      `tools/difftest/start_eternal.txt`

### M1: the game's logic on the console, measured (done 2026-10-30, **GO**: [m1-logic-measured.md](m1-logic-measured.md))

- [x] Patch 0001, `ISAAC_FUNKEY`: upstream's `main.cpp` path with the settings above plus the PSP's memory budgets;
      cross-compiles at the first attempt (zlib then made static); `check-elf.sh` passes (only `libc.so`); 15 MB of
      text for all three versions
- [x] Same game on ARM as on the PC: every enemy's state at every tick of a 12,580-tick workload (floors 1–3, random
      rooms, god mode) identical to a PC build with the same maths functions (musl's; glibc's differ in the last digit
      now and then). `scripts/measure/same-game.sh`
- [x] Under qemu with the armprof plugin: 2.65 M instructions per tick for the logic (3.3 M at the 90th percentile),
      1.1 M for the sound; variable lookup (`getVarK`) the largest single item
- [x] On the console over SSH, headless, menu running (the game thread's CPU time is measured): **9.9 ms per tick at
      1296 MHz, 12.8 at the 90th percentile, 17.0 with 10–19 enemies**; 11.1 at 1008 MHz; room loads stall
      0.3–0.5 s; 0.20 instructions per clock (memory-bound). Memory with the PSP's budgets: peak 37.8 MB, 30 MB of the
      game's own data, 1.3 MB in swap. One binary with all three versions is fine
- [x] **Decision: GO to M2.** About 13 ms of each frame left for drawing in the busiest rooms (sound included),
      18–20 ms in ordinary ones. New for M4: room-load stalls, sound first, then variable lookup and the allocator

### M2: a picture, on the PC first (done 2026-10-30: [m2-software-renderer.md](m2-software-renderer.md))

- [x] Patch 0002: `rt/render_soft.cpp`, the `render.h` interface on the CPU, modelled on `render_psp.cpp`. The scene
      is drawn at the stage's resolution (363×272) and scaled once to the output, which gives both picture modes
      (`g_softStretch` for the full screen); rasterized graphics cached by scale, drawn 1:1 or resampled; per-row
      runs so transparent stretches cost nothing; still, stretched graphics rasterized at their transform; Flash
      colour transforms as upstream's shader; masks with an 8-bit stencil; BitmapData drawn from their own pixels;
      the focus outline, overlay, loading and version-picker screens at the output's resolution
- [x] Headless screenshots from the software renderer (`--headless --size WxH --script`, upstream's `shot`
      command), and `scripts/build.sh host-funkey` for the PC
- [x] Checked against upstream's GL renderer (Mesa under Xvfb, same ticks): rooms within about 1 level in 255 per
      channel, menus within 2.5–4.5 (blurred shadows left out)
- [x] Drawing cost under qemu: 5.0 M instructions per frame in floor 1 rooms (median), 6.2 M on floor 2, 11 M at
      the 90th percentile there; the trip between floors 20 M, the title 15 M
- [x] The single-thread play loop (frame skip) moved to M3: it is where the console's input, screen and sound come
      in; the PC test path is upstream's headless mode

### M3: on the console

Done 2026-10-30: [m3-on-the-console.md](m3-on-the-console.md).

- [x] `rt/funkey.cpp` (patch 0003): the play loop on one thread (buttons → logic tick → snapshot → draw → present →
      collector), the logic always at 30 ticks per second, pictures skipped when behind (at most 3 in a row); a room
      build over 0.5 s resets the clock instead of being caught up
- [x] `/dev/fb0` in RGB565 (dithered) with a pan per picture, console tty muted; buttons from the button daemon's
      keyboard; sound through SDL2/ALSA on the right channel (the speaker's); power-off with the save written; 1296 MHz;
      crash handler; a speed and memory line every 5 s
- [x] Launcher, OPK, a kit for testers; checked on the console itself (the 46 MB is real there) rather than in
      the VM: a 7-minute scripted run on floors 1–3 and the OPK started as the menu starts it
- [x] First start: the SWF unpacked into `saves/` (46.5 MB) behind a notice; the 3000×3000 bitmap decoded shrunk
      (startup memory 92 → 27 MB on the PC)
- [ ] My play test: feel, sound, quitting, power-off, a long session

### M4: speed to 30 fps

Each item measured before and after, in rough order of expected value:

0. **Room builds** (0.3–0.7 s each, 27 ticks over 250 ms in the 7-minute run) and **the title and menus** (25–48 ms
   a picture): the two things a player notices most after M3. Then where memory settles in a 30-minute session
   (in RAM + swapped grew 40 → 47 MB over 7 minutes, the budgeted caches flat).
1. **Allocator.** The game makes many short-lived small objects (49–254 garbage objects per tick in the Caves even
   after upstream's string cache *(upstream)*); musl 1.2.1's malloc is slow at that. Try a fast small-object
   allocator behind the same `--wrap` hooks `psp_alloc.cpp` uses, keeping its large-block arena.
2. **Compiler options for the generated code.** Upstream builds `gen*/` at `-O1` to save compile time; try `-O2`,
   `-Os` and Thumb-2 (5–7 MB of code per version against a 32 KB instruction cache).
3. **A FunKey stage.** Regenerate the game code at 240×180 (`patchhd.py --scale 0.375`,
   `gen.py --room-scale 0.375`): the room layers become 240×180 instead of 364×272, 2.3× fewer pixels in every
   floor, creep and blood draw and clear. Needs FFDec (Java) and the SWF from my `Isaac.exe`; the result stays
   local.
4. **Frame skip when behind.** The logic never skips (the game keeps its exact speed); the compositor draws every
   other tick while the frame time is over budget. The alternative is the PSP's choice: the game slows down, as
   Flash did on a slow PC. See the questions below.
5. **Compositor:** NEON blends and RGB565 conversion (from my other FunKey S projects), an axis-aligned path, plain copies at 1:1,
   the per-frame rasterization budget tuned.
6. **GC settings** for one thread (collection threshold, growth, sweep time per tick).
7. **Profile-guided optimisation.**

### M5: polish

- [x] The FunKey menu on Menu (docs/m5-menu.md, patch 0007): VOLUME, BRIGHTNESS, ASPECT RATIO (4:3 or STRETCHED),
      SHOW FPS, EXIT GAME, in the style of FunKey-OS's emulators' menus; the game and its sound wait meanwhile
- [x] RetroFE: the OPK in Native games with its 60x60 picture next to it (`opk/make-retrofe.py`)
- [x] The version picker with the FunKey's buttons when several `Isaac*.exe` are present (patch 0008), in the menu's
      style; the choice kept in isaac.ini
- [x] Readability at 240 px: item names 6 px high (7 STRETCHED), their lines and the floor's name 4 px (5): legible,
      nothing changed; upstream's mods (StatOn, PillLog...) stay off by default
- [x] Power-off saves everything the game saves; a run in progress is lost, because the Flash game has no mid-run
      save (Instant Play can only reopen the title)
- [x] Docs and the release zip (`scripts/funkey/make-release.sh`: the OPK and its RetroFE picture)

### M6: room entries and memory (after M5)

- [x] Where a long tick goes, and memory part by part every minute, in the game's log (docs/m6-rooms-memory.md)
- [x] Fewer shapes parsed again: hit-test edges only when needed, parsed shapes trimmed (patch 0009); room entries
      over 150 ms 18 -> 12, over 300 ms 6 -> 2, parsing halved
- [x] The memory creep: sprite timelines dropped above 3 MB when no clip uses them; clip names given by scripts
      interned weakly (the game's sound clips `sz<n>`)
- [x] The pieces of rooms drawn before kept on the card (patch 0010, `saves/leaves_*`, up to 16 MB): other rooms after
      one session, entries over 150 ms 11 -> 4; the same rooms, none
- [ ] The level generation when a floor starts (about 0.4 s of the game's own logic, once per floor): left

### M7: the CPU clock in the menu

- [x] OVERCLOCK in the FunKey menu (docs/m7-clock-and-code.md, patch 0011): 1296 MHz or the console's own clock (the
      default), switched at once and kept in `launcher.cfg`; the launcher always puts the console's clock back. At
      1008 MHz the play script still averages 29.1 pictures a second (29.3 at 1296); room entries and a new floor's
      pause are longer
- [x] Page faults in the game's log; keeping the program's code in memory (`mlock2`) measured: no gain, less memory
      free, not kept

### M8: on upstream v1.7.0

- [x] The patches moved onto v1.7.0 (docs/m8-upstream-1.7.md, patch 0012): the game's code unchanged; safer saves
      (read strictly, written through a `.tmp`, a damaged one kept as `.corrupt`); sound without a device
- [x] Continuum (leave a run, carry on with it later) on by default, the room pieces still kept on the card with it
- [x] Checked: the same pictures as before, the same game on ARM as on the PC, 1.0.0's saves load as they are,
      Continuum with the FunKey's buttons; on the console Continuum, the speed (29.1 pictures a second at 1008 MHz, as
      before) and OVERCLOCK

## Memory budget

* Available: 45.5–46.5 MB on FunKey-OS *(console)*; my FunKey-OS-based firmware adds about 1.9 MB and zram ahead of the 128 MB swap.
* The PSP build was made to fit about 41 MB of heap, including a 24 MB arena for large blocks, the 3.2 MB lean SWF,
  5 MB of parsed shapes, 2 MB of sounds and six 1 MB atlas pages *(upstream)*.
* Added on the FunKey: the binary's code pages (file-backed, reclaimable; the chosen version plus the runtime, about
  7–9 MB touched *(estimate)*), the SWF cache file's pages (file-backed), the 240×240 buffers (under 0.5 MB).
* Aim: under 30 MB of anonymous memory while playing, checked in M1 and with the VM's memory cap.

## Risks

1. **Logic speed in busy rooms** (the main one). M1 measures it on the console before the compositor is written.
2. **Memory and fragmentation** with musl's allocator: the PSP's arena and M4's allocator item.
3. **Floating-point drift** (libm, contraction, compiler flags) would change the game's behaviour. Seed
   comparisons against x86 in M1 and after every speed change.
4. **Small text** at 240×180.
5. **First start:** decompressing the SWF (36 MB on the card) may take a while.

## Questions answered (2026-10-30)

1. My `Isaac.exe`: the Eternal Edition (identified by M0's PC build).
2. Busy rooms below 30 fps: frame skip by default.
3. Picture: 4:3 with bars first; full screen as a menu option if both can be kept.
4. Repository: local git now, private GitHub repo later.
5. Fn is card / pill.
