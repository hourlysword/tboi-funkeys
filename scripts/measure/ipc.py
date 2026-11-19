#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Instructions per clock of the game on the console: the same deterministic workload measured twice, under qemu
(instructions per tick: qemu-armprof.sh's marks file) and on the console (CPU time per tick: the game's log from
scripts/device/logic.sh), joined tick by tick.

usage: ipc.py MARKS LOG MHZ [--phases 0:title,1000:floor1,...]

IPC = instructions / (CPU time x clock). Ticks over 100 ms (room loads) are reported apart: their cost is
mostly memory traffic, which an instruction count doesn't see.
"""
import argparse
import re

ap = argparse.ArgumentParser()
ap.add_argument("marks")
ap.add_argument("log")
ap.add_argument("mhz", type=float)
ap.add_argument("--phases", default="0:all")
a = ap.parse_args()

mark_re = re.compile(r"^(\d+) OFKMEM tick (\d+) ")
begin_re = re.compile(r"^(\d+) OFKMEM begin (\d+)")
log_re = re.compile(r"OFKMEM tick (\d+) ents (-?\d+) ms ([\d.]+) cpu ([\d.]+)")
insns, begin = {}, None
for line in open(a.marks, errors="replace"):
    b = begin_re.match(line)
    if b:
        begin = int(b.group(1))
        continue
    m = mark_re.match(line)
    if m:
        c, t = int(m.group(1)), int(m.group(2))
        if begin is not None:   # only the timed part (marks files with "begin" lines: builds from 2026-10-30 on)
            insns[t] = c - begin
        begin = None
if not insns:
    raise SystemExit("ipc.py: no 'OFKMEM begin' marks in %s: the instruction counts must cover what the console "
                     "timed (an older build counted the sound too)" % a.marks)
cpu = {}
for line in open(a.log, errors="replace"):
    m = log_re.search(line)
    if m:
        cpu[int(m.group(1))] = float(m.group(4))

phases = sorted((int(p.split(":", 1)[0]), p.split(":", 1)[1]) for p in a.phases.split(","))


def phase(t):
    n = phases[0][1]
    for s, name in phases:
        if t >= s:
            n = name
    return n


acc = {}
for t in sorted(set(insns) & set(cpu)):
    key = (phase(t), cpu[t] > 100)
    i, ms = acc.get(key, (0, 0.0))
    acc[key] = (i + insns[t], ms + cpu[t])
print("%-10s %-10s %12s %10s %6s" % ("phase", "ticks", "M instr", "CPU s", "IPC"))
for (name, slow), (i, ms) in acc.items():
    print("%-10s %-10s %12.1f %10.2f %6.2f" % (name, "loads" if slow else "normal", i / 1e6, ms / 1e3,
                                             i / (ms / 1e3 * a.mhz * 1e6) if ms else 0))
