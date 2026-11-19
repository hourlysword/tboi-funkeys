#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Write a headless test script for IsaacRecomp (--headless --script): start a run, then teleport through random rooms
on several floors with random movement and shots, in god mode.

usage: workload.py --start START_SCRIPT [--scale S] [--floors N] [--rooms N] [--ticks N] [--seed N] [--balls]

  --start   upstream's tests/start_game.txt (title screen to a new run; Wrath of the Lamb and the original)
  --scale   factor for its mouse coordinates, written for the 1440x1080 stage: 363/1440 for genpsp/ (the PSP's
            363x272 stage, which the FunKey build uses), 1 for gen/
  --floors  floors to visit (1 = the Basement, 2 = the Caves, 3 = the Depths: busier rooms each time)
  --rooms   random rooms per floor (teleports), --ticks: ticks spent in each (30 ticks = 1 s)
  --balls   also dump every enemy's state each tick ("eval balls"): for comparing two builds (PC against ARM) line
            by line. Leave it out for timing runs: printing that much costs time itself.

The room teleport and god mode are the ones upstream's differential tests use (tools/difftest/gen_room.py):
_root.a.tar / telf / fra pick a random room of the floor, _root.a.lasth keeps the player from being hurt, and
_root.a.newstart moves to the next floor.
"""
import argparse
import random

ap = argparse.ArgumentParser()
ap.add_argument("--start", required=True)
ap.add_argument("--scale", type=float, default=1.0)
ap.add_argument("--floors", type=int, default=3)
ap.add_argument("--rooms", type=int, default=12)
ap.add_argument("--ticks", type=int, default=300)
ap.add_argument("--seed", type=int, default=1)
ap.add_argument("--balls", action="store_true")
a = ap.parse_args()

rng = random.Random(a.seed)
ev = []
for line in open(a.start):
    w = line.split()
    if not w:
        continue
    tick, op, args = int(w[0]), w[1], w[2:]
    if op in ("click", "mmove", "mdown", "mup"):   # stage coordinates: scaled to the build's stage
        args = ["%g" % round(float(v) * a.scale, 1) for v in args]
    ev.append((tick, " ".join([op] + args)))

t = 1000
keys = [87, 65, 83, 68, 37, 38, 39, 40]   # W A S D (move), arrows (shoot)
for floor in range(a.floors):
    if floor:
        ev.append((t, "eval call _root.a newstart 0"))
        t += 300
    ev.append((t, "eval set _root.a.lasth 100000000"))
    for _ in range(a.rooms):
        ev.append((t, "eval set _root.a.tar 0"))
        ev.append((t, "eval set _root.a.telf 100000"))
        ev.append((t, "eval set _root.a.fra 99999"))
        held = {}
        for tick in range(t + 2, t + a.ticks):
            if tick % 30 == 0:
                ev.append((tick, "eval set _root.a.lasth 100000000"))
            for k in keys:
                if held.get(k, 0) > 0:
                    held[k] -= 1
                    if held[k] == 0:
                        ev.append((tick, "up %d" % k))
                elif rng.random() < 0.04:
                    held[k] = 5 + rng.randrange(40)
                    ev.append((tick, "down %d" % k))
            if a.balls:
                ev.append((tick, "eval balls"))
        for k, v in held.items():
            if v > 0:
                ev.append((t + a.ticks, "up %d" % k))
        t += a.ticks + 5
ev.append((t, "quit"))
ev.sort(key=lambda e: e[0])
for tick, cmd in ev:
    print(tick, cmd)
