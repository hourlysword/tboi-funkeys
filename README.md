# tboi-funkeys (The Binding of Isaac - Funkey S)

This project is a port and adaptation of [IsaacRecomp](https://github.com/whylurking/IsaacRecomp), the
native C++ recompilation of the Flash game, to the [FunKey S](https://www.funkey-project.com/). 

## Features

- **Full game speed:** Runs at about 29 fps on average, even in the busier rooms.
- **Version Support:** Supports the original, *Wrath of the Lamb* and the *Eternal Edition*. You can
  add more than one version to the folder and you'll get asked which version you'd like to play when it loads up.
- **Sound:** music and effects are supported.
- **Display Modes:** You can switch between 4:3 with black bars, or stretch the picture.
- **FunKey menu** RetroFE style menu built with the following options: volume, brightness, picture mode, an FPS counter, and exit
  game. Game pauses while this menu is open.
- **Achievements/Unlocks:** Unlocks and statistics are saved when you exit, and even when you power off
  mid-game!
- **Stability:** Memory stays consistent over the course of long playing sessions.
- **Launchers:** An entry is added to both RetroFE and Gmenu2x and game supports being launched from either menu.

**NOTE** The game is not included and never will be. You'll need your own copy of *The Binding of Isaac* from
Steam (the original, *Wrath of the Lamb* or the *Eternal Edition*). Copy `Isaac.exe` to the console yourself,
and this port pulls what it needs from it. This repository holds absolutely no game code either: upstream's code translated from
the game stays in the upstream checkout, and the changes from this project are a patch series on upstream's engine (`rt/`).

## Install

1. Copy `isaac_funkey-s.opk` and `isaac_funkey-s.png` (its picture in RetroFE) into the **Native games** folder of the
   FunKey's USB share.
2. Create the folder `FunKey/isaac` and copy `Isaac.exe` from your Steam game into it (Steam: right-click the game,
   Manage, Browse local files; `Isaac.exe`, not `Binding_of_Isaac.exe`). You can add different versions if you want, just rename the executables (`Isaac-Eternal.exe`...): the program asks which version you want to play when it starts, and suggest you're last played version when you boot it up again.
3. Start *The Binding of Isaac* from GMenu2X, or `isaac_funkey-s` in RetroFE's Native games. The very first start
   unpacks the game into `FunKey/isaac/saves` (about 15 seconds); any launches after that boot up quicker.

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
second, top left) and EXIT GAME (A, then A again: the game's save is written). 

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

hourlysword.dev@gmail.com: bugs, suggestions, rights-holder requests. feel free raise an issue here to submit bugs/suggestions as well!

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
