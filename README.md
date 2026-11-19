# tboi-funkeys

A port of *The Binding of Isaac* to the FunKey S! [IsaacRecomp](https://github.com/whylurking/IsaacRecomp), the
native C++ recompilation of the Flash game, on the [FunKey S](https://www.funkey-project.com/): one Cortex-A7 core,
64 MB of RAM, no GPU and a 240×240 screen.

**Status:** M0–M6 done: the game plays on the console from an OPK, with its picture, sound and buttons, at its full
speed (30 ticks a second) and exactly as on the PC. About 29 pictures a second on average, busy rooms included
(the title and menus 30); room entries mostly under 0.25 s, and memory that stays flat in long sessions. A FunKey
menu on Menu (volume, brightness, 4:3 or stretched, FPS, exit game), a version picker when several versions of the
game are there, and an entry with its picture in RetroFE's Native games. See
[docs/porting-plan.md](docs/porting-plan.md) and the milestone write-ups: [M1](docs/m1-logic-measured.md),
[M2](docs/m2-software-renderer.md), [M3](docs/m3-on-the-console.md), [M4](docs/m4-speed.md), [M5](docs/m5-menu.md),
[M6](docs/m6-rooms-memory.md).

The game is not included and never will be: as with IsaacRecomp, you need your own copy of *The Binding of Isaac* from
Steam (the original, *Wrath of the Lamb* or the *Eternal Edition*). You copy its `Isaac.exe` to the console yourself,
and the program reads everything from it. This repository holds no game code either: upstream's code translated from
the game stays in the upstream checkout, and our changes are a patch series on upstream's engine (`rt/`).

## Install

1. Copy `isaac_funkey-s.opk` and `isaac_funkey-s.png` (its picture in RetroFE) into the **Native games** folder of the
   FunKey's USB share.
2. Create the folder `FunKey/isaac` and copy `Isaac.exe` from your Steam game into it (Steam: right-click the game,
   Manage, Browse local files; `Isaac.exe`, not `Binding_of_Isaac.exe`). Several versions can sit side by side under
   different names (`Isaac-Eternal.exe`...): the FunKey then asks which one to play when it starts, and offers the last
   one first the next time.
3. Start *The Binding of Isaac* from GMenu2X, or `isaac_funkey-s` in RetroFE's Native games. The very first start
   unpacks the game into `FunKey/isaac/saves` (about 15 s, a message says so); later starts are quicker.

## Controls

| FunKey | In play | In the game's menus |
|---|---|---|
| D-pad | move | choose |
| X / A / B / Y | shoot up / right / down / left | A confirm, B back |
| L | bomb | |
| R | active item | |
| Fn (tap alone) | card or pill | |
| Start | pause / resume | Enter |
| Menu | the FunKey menu (the game waits) | |
| Fn + A / Y, Fn + X / B | volume, brightness (the system's) | |

The FunKey menu: VOLUME, BRIGHTNESS, ASPECT RATIO (4:3, or STRETCHED across the whole screen), SHOW FPS (pictures a
second, top left) and EXIT GAME (A, then A again: the game's save is written). Up and Down choose, Left and Right
change, B or Menu close it. Powering off writes the save too; a run in progress isn't kept, as the original game has
no mid-run save.

## Layout

| Path | What |
|---|---|
| `docs/` | the plan and one write-up per milestone |
| `patches/isaacrecomp/` | our changes to upstream, as a `git am` series |
| `scripts/` | `env.sh` (paths), `fetch-upstream.sh`, `export-patches.sh`, `build.sh host\|host-lean\|host-ref\|host-funkey\|funkey` |
| `opk/` | the OPK's launcher, desktop entry and icon, and its RetroFE picture (`make-retrofe.py`) |
| `scripts/funkey/` | correct maths library, ELF checks, CPU clock, `make-opk.sh`, `make-release.sh` (the release zip), `make-kit.sh` (a kit for testers) |
| `scripts/measure/` | test workloads, tick and frame costs, ARM-vs-PC comparison, screenshots, qemu instruction counts |
| `scripts/device/` | running on the console over SSH: the logic alone (`logic.sh`), the game's own loop on the screen playing a test script (`play.sh`), the menu and the version picker driven through the button daemon (`menu-test.sh`, `pick-test.sh`) |
| `cmake/` | the FunKey toolchain |

Builds run in WSL (Debian) as root, with the FunKey SDK and a GCC 14 for the FunKey already set up (`scripts/env.sh`
says where it looks for them):

```bash
bash scripts/fetch-upstream.sh
bash scripts/build.sh host
bash scripts/build.sh funkey
bash scripts/funkey/make-opk.sh             # out/isaac_funkey-s.opk
bash scripts/funkey/make-release.sh v1.0.0  # out/tboi-funkeys-v1.0.0.zip
```

## Contact

hourlysword.dev@gmail.com: bugs, suggestions, rights-holder requests.

## Credits

- [IsaacRecomp](https://github.com/whylurking/IsaacRecomp) by whylurking: the recompiled game engine this port builds on.
- Libraries built into the program: [SDL2](https://libsdl.org), [PlutoVG](https://github.com/sammycage/plutovg),
  [dr_mp3](https://github.com/mackron/dr_libs), [stb_image](https://github.com/nothings/stb),
  [zlib](https://zlib.net) and the maths functions of [musl](https://musl.libc.org).
- Developed with the help of AI: see [docs/AI_DISCLOSURE.md](docs/AI_DISCLOSURE.md).

## License

MIT ([LICENSE](LICENSE)), the same as IsaacRecomp's engine: this repository's scripts, patches, launcher files and
documentation. The patches change IsaacRecomp's code (© whylurking, MIT) and one changes PlutoVG (MIT). *The Binding
of Isaac* is © Edmund McMillen and Florian Himsl and is not covered: none of it is here. This project is not
affiliated with or endorsed by the game's authors.
