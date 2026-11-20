# M8: on upstream v1.7.0 (safer saves, Continuum)

Status: **done** (2026-11-19). The patch series now applies to upstream's v1.7.0 (`b156559`, 2026-11-16) instead of
v1.5.0 (`a2cfc66`), with patch 0012 for what 1.7.0 needed. The game plays exactly as before; what players get is
upstream's safer saving and its Continuum mod, on by default here.

## What upstream changed

Between v1.5.0 and v1.7.0 the game's translated code (`gen*/`) did not change at all: only the engine (`rt/`), the mods
and the tools. For this port:

- **Saves.** The save is read strictly: a file cut short (a power cut, a full card) is kept as `<save>.corrupt` and
  never written over, where before it was loaded halfway and the next save wrote that half over the file. Saves are
  written to `<save>.tmp` and then renamed over the save, and a whole `.tmp` is used when the save itself is missing or
  damaged.
- **Continuum**, a new mod: Rebirth's "Continue". On the pause screen, "Exit to main menu" asks "Are you sure you want
  me to die?"; "No", in a room with no enemies left, saves the run (`saves/continuum_<game>.txt`) and goes to the main
  menu, and the next Start there goes straight back into it, in that room, with everything the player had.
- More mods, all off: Challenge Lab, Marksman, GoodSaac; The Gone and others updated.
- Sound: a game with no output device goes on without sound (and SDL's audio is started on its own, so a device that
  fails no longer closes the program); a stream's silent frames are silent, as in Flash.
- The game: an Eternal Edition fix (an empty item pedestal could be pushed across the room); the main menu's paper
  sheets no longer let clicks through to the menu under them.
- For other platforms, not used here: OpenGL ES, a lower rendering height on PCs, touch fixes, the "frame" crop of the
  game's 3000x3000 border overlay (our renderer draws only what is on the screen anyway; the crop changes nothing here).

## The move

`git rebase` of the 11 patches onto v1.7.0: one conflict (`rt/raster.cpp`, patch 0002: upstream's frame crop and our
`rasterizeSrcAt` added at the same place; both kept), the rest applied by itself. Upstream's loop gained no per-tick
calls that `funkeyPlay` would need. Patch 0012:

- `renderSetOutput`, new in the renderer's interface (the GL renderer's lower rendering height), an empty one in the
  software renderer, which draws at the size it is given.
- Continuum keeps the room pieces on the card: the card cache turned itself off with any mod on (some change shapes);
  Continuum only writes a run's variables down and puts them back, so it no longer counts.
- Continuum on by default on the FunKey: when its file is first put in the mods folder (a new player, or one coming
  from 1.0.0, which didn't have it), it is turned on; from then on `FunKey/isaac/mods/mods.txt` has the player's choice
  (`[continuum]`, `on = 0` turns it off).
- Test scripts work the game's menus as the FunKey's buttons do: `nav up|down|left|right|confirm|back`.

`scripts/env.sh` pins v1.7.0; the series applied to a clean v1.7.0 gives the same tree as the branch it was exported
from.

## Checks

- **Pictures** (PC, the FunKey configuration and loop, the 7-minute play script): the seven shots of the v1.5.0-based
  build and the v1.7.0-based one are the same, pixel for pixel.
- **The same game** (`scripts/measure/same-game.sh`): the ARM build under qemu and the PC build agree on every enemy's
  state, 63,207 lines over 12,580 ticks.
- **Saves from 1.0.0** (PC): two saves written by 1.0.0 on the console (582 and 701 bytes) load whole and are written
  back byte for byte; a save cut to 300 bytes is kept as `.corrupt` and the game starts with an empty one.
- **Continuum with the FunKey's buttons** (PC, `nav`): Start pauses (P); Down, Down, A on "Exit to main menu"; the
  question comes with "No" selected; A: "run saved (floor 1, room 35, 174 variables)" and the main menu; A on Start:
  "run resumed", the same room, the same pickups. (Start itself, which sends Enter in the menus, does nothing on the main
  menu, as in 1.0.0: A starts a run.)
- **Continuum on by default** (PC): a new player and one coming from 1.0.0 (the mods folder 1.0.0 made) get it added
  and turned on; one who set `on = 0` keeps it off; a second start keeps it as it is; the card cache stays on in all.

On the console, the 1.1.0 OPK (the program from it mounted as squashfs, cold, as in M7):

- **Continuum** (`scripts/device/bundle.sh`'s `continuum.txt`, `testing/m8/continuum`): added and turned on in the
  test folder's mods by the default, the card cache on; saved and resumed as on the PC ("floor 1, room 35, 174
  variables"), the screen at each step the same.
- **Speed** (the 7-minute play script at 1008 MHz, OVERCLOCK's new default, Continuum on; `testing/m7/v170-1008`):
  29.1 pictures a second (lowest 5 s: 24.2), logic 7.6 ms a tick, drawing 8.0 ms a picture; 17 ticks over 150 ms (6 over
  300); memory at most 44 MB, 7 MB available at the lowest. The v1.5.0-based build in the same run: 29.1 (24.5), 7.5,
  7.8, 19 (7), 44 MB. Single long ticks differ by up to 60 ms either way between the two (a new floor's 625 and 618 ms
  against 673 and 679), as much as runs of the same build do.
- **OVERCLOCK** (`clock-test.sh` from the new default): the first start left at 1008 MHz and OFF, ON took it to 1296;
  the second start at 1296 (`cpu_mhz = 1296`), OFF took it to 1008; the console's clock back after each.
