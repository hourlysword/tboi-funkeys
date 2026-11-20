# M5: the FunKey menu, RetroFE, the version picker

Status: **done** (2026-11-15), installed on the console: the menu, the RetroFE entry, the version picker; text
checked at 240 px (nothing to change); the kit (`scripts/funkey/make-kit.sh`).

## The menu (Menu)

Patch 0007 (`rt/funkey.cpp`, "the menu"). In the style of FunKey-OS's own emulators' menus, as my other FunKey S projects
have it (the code here is written for this game):

- One item at a time in a light grey (236) 180x140 box with rounded corners in the middle of the screen, the game
  behind darkened by black at 100/255, 20x13 arrows above and below, dark grey (85) text in FunKey-OS's Open Sans
  Bold (`/usr/games/menu_resources`), 22 for the item and 16 for its value; volume and brightness as ten bars across
  100x20 pixels; the next item sliding in 30 pixels a picture at 50 pictures a second. Without the font (a PC), the
  5x7 dots the renderer uses for its overlay.
- Up and Down choose the item; Left and Right change its value (held: again after 0.5 s, then every 0.1 s); A asks
  "Are you sure ?" for EXIT GAME and A again quits (the game's save written, as before); B takes the question back
  or closes the menu; Menu closes it.
- **VOLUME** and **BRIGHTNESS**: FunKey-OS's own, through its `volume` and `brightness` commands (which keep them
  for the next start), in steps of 10; one command at a time, the last value asked for in the end.
- **ASPECT RATIO**: `4:3` (black bars above and below) or `STRETCHED` (the whole screen: the 240x180 picture's rows
  stretched to 240); the game behind the menu is drawn again in its new shape.
- **SHOW FPS**: the pictures drawn in the last second, top left.
- **OVERCLOCK** (added in M7): the CPU at 1296 MHz while the game runs, or at the console's own clock, the default
  ([m7-clock-and-code.md](m7-clock-and-code.md)).
- **EXIT GAME**.
- The game waits: its ticks stop, its sound pauses (`audioSetPaused`, the music resumes where it was), the
  speaker's amplifier is off (as FunKey-OS's emulators do); the game's clock skips the time spent in the menu, and
  the buttons still held when it closes reach the game only once let go. A power-off closes it at once.
- ASPECT RATIO and SHOW FPS are kept in `FunKey/isaac/isaac.ini` (`funkey_aspect`, `funkey_fps`).

It replaces Menu pressed twice to quit.

Checked: on the PC, the test script's `menushot` (`testing/m5/menu`); on the console, `scripts/device/menu-test.sh`
drives the menu through FunKey-OS's button daemon (`KEYPRESS` on `/tmp/fkgpiod.fifo`) with the installed OPK and
grabs the screen at each step (`testing/m5/menu-test`): every item, Left on volume and brightness and back (the
console's 90% and 50% as before), STRETCHED with SHOW FPS ("30 FPS" over the game), EXIT GAME's question, B taking
it back, A A quitting with status 0. The logic is untouched (same-game.sh identical).

## RetroFE

RetroFE's Native games collection (`/usr/games/collections/Native games/settings.conf`) lists every OPK in
`/mnt/Native games` (its `include.txt` is empty) and shows, as the item's picture (`media.artwork_front`), a PNG
named like the OPK next to it; its layouts (FunKey, KoiGlass) show it at 60x60. RetroFE starts the OPK through
`native_launch.sh` (opkrun, the PID recorded, no file given: the launcher needs none) and frees its graphics
meanwhile (`unloadSDL = true`).

So the entry is `isaac_funkey-s.png`, 60x60, next to the OPK: drawn by `opk/make-retrofe.py` (a tear with a highlight
and ISAAC under it, on a transparent background like the other native games' pictures; no game art), put in the kit
by `scripts/funkey/make-kit.sh` and installed on the console with the OPK. The item's name is the OPK's file name.

## The version picker

Patch 0008 (`rt/funkey.cpp`, "the version picker", and `rt/main.cpp`). FunKey/isaac can hold several versions of the
game under different names (`Isaac.exe`, `Isaac-Eternal.exe`...): upstream finds one of each (by the length of the
SWF inside) and, on a PC, asks which to open in its window. The FunKey has no window, so before the game is loaded
its screen asks, in the menu's style on black:

- One version at a time in the box: its name in capitals (on two lines when too wide: WRATH OF / THE LAMB), and
  "Press A to play" under it; the arrows above and below.
- Up and Down slide the others in (wrapping round; held: again after 0.5 s, then every 0.1 s); A or Start plays the
  one shown ("Loading..." in the box, without the arrows, until the game shows); Menu quits back to the launcher. A
  power-off meanwhile powers off at once.
- The choice is kept in `isaac.ini` (`game = og`, `wotl` or `eternal`, as upstream does) and offered first the next
  time. Upstream's names: Original, Wrath of the Lamb, Eternal Edition.
- One version (the usual case): no question, as before. Test scripts never get one.

The screen and the buttons are opened by the picker when it shows, by the play loop otherwise (`ioOpen`); the picker
and the menu share their drawing.

Checked: on the PC, `ISAAC_FUNKEY_PICK_SHOTS=<prefix>` draws each version's picture and "Loading..." without waiting
for a button (`testing/m5/pick`), also on the real path: `Isaac.exe` and a stand-in holding only the original's SWF
header in the folder, `game = eternal` in isaac.ini: both found, Eternal Edition offered first, taken, kept and
loaded. On the console, `scripts/device/pick-test.sh` (one `Isaac.exe` is enough: `ISAAC_FUNKEY_PICK_TEST` names
three versions and the answer is only logged) drives it through fkgpiod's FIFO with the installed OPK: Down three
times wraps round to the first, Up, A shows "Loading..." and answers 2 (Eternal Edition), the game starts, EXIT GAME
quits with status 0 (`testing/m5/pick-test`). Its `quit` part takes the real path in a folder of its own, with two
8-byte stand-ins holding only the SWF headers of the original and of Wrath of the Lamb: both found, Original offered
first, Down shows WRATH OF / THE LAMB, Menu goes back to the launcher with status 0, the screen cleared, nothing
loaded (`testing/m5/pick-quit`). Logic untouched: same-game.sh identical.

## Readability at 240 px

Item names and pickup text, checked on the PC with upstream's GenesisConsole mod (`give 1`, `give 12` from the test
script, in a test folder with `[genesis] on = 1` and its badge off), screenshots at 240x240 in both shapes
(`testing/m5/pickup`; `scripts/measure/shots.py zoom` enlarges one pixel for pixel). Heights of the capitals:

| Text | 4:3 | STRETCHED |
|---|---|---|
| The item's name across the top (THE SAD ONION, MAGIC MUSHROOM) | 6 px | 7 px |
| Its line, bottom right (TEARS UP!, ALL STATS UP!) | 4 px | 5 px |
| The floor's name, bottom left (CELLAR I) | 4 px | 5 px |

All white on black and anti-aliased: the names read well, the corner lines are small but legible, and STRETCHED
makes everything a third taller. The renderer already draws them as vectors at the picture's scale (0.661 of the
game's 363x272 stage), as sharp as 240 pixels allow, so nothing changed. Upstream's mods (StatOn, PillLog, Itemnomicon...) stay off by default; `FunKey/isaac/mods/
mods.txt` turns them on.

## The release zip

`scripts/funkey/make-release.sh <version>` after `scripts/funkey/pgo.sh` and `scripts/funkey/make-opk.sh
$TFK_WORK/build-funkey-pgo-thumb`: `out/tboi-funkeys-<version>.zip` with `Native games/isaac_funkey-s.opk` (the
license notices inside it, in `licenses/`) and its RetroFE picture `Native games/isaac_funkey-s.png`. The install
steps and the controls are in the README.
