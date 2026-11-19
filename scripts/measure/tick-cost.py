#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Cost of every logic tick, from the game's per-tick lines (ISAAC_TICKMARKS=1).

usage: tick-cost.py FILE [--phases 0:title,1000:floor1,...] [--field ms|cpu] [--mhz 1296 --ipc 0.63]

FILE is either
  - an armprof marks file (qemu-armprof.sh's ARMPROF_OUT.marks: "<instructions so far> OFKMEM tick N ents E ..."),
    which gives exact ARM instructions per tick, or
  - the game's log from a run on the console or the PC ("OFKMEM tick N ents E ms T cpu C ..." lines), which gives the
    time each tick took: --field ms is the wall-clock time, --field cpu (the default) the time the CPU spent on the
    game's thread, which other programs running at the same time (the menu, the system's shell loops) don't change.

Prints, per phase (ranges of ticks, named by --phases), the mean, median, 90th / 99th percentile and maximum, and the
same against the number of enemies on screen. With instruction counts, --mhz and --ipc turn them into an estimate of
milliseconds on the console (IPC 0.63 is what one of my other FunKey S projects measured at a real 1296 MHz; this game's code may differ:
M1 compares the estimate with the console's own timing).
"""
import argparse
import collections
import re

ap = argparse.ArgumentParser()
ap.add_argument("file")
ap.add_argument("--phases", default="0:start")
ap.add_argument("--field", choices=("ms", "cpu"), default="cpu")
ap.add_argument("--mhz", type=float, default=1296)
ap.add_argument("--ipc", type=float, default=0.63)
a = ap.parse_args()

line_re = re.compile(r"^(?:(\d+) )?OFKMEM tick (\d+) ents (-?\d+)(?: ms ([\d.]+))?(?: cpu ([\d.]+))?")
begin_re = re.compile(r"^(\d+) OFKMEM begin (\d+)")
dbegin_re = re.compile(r"^(\d+) OFKMEM dbegin (\d+)")
draw_re = re.compile(r"^(?:(\d+) )?OFKMEM draw (\d+) ms ([\d.]+) cpu ([\d.]+)")
rows = []   # (tick, ents, cost): cost = instructions (marks file) or ms (log)
draws = []  # (tick, cost) of drawing a frame and finishing it (runs with a renderer: "dbegin" / "draw" lines)
outside = []   # (marks files with "begin" lines) instructions between a tick's end and the next tick's start
prev = None
begin = None
dbegin = None
drawn = 0   # (marks) instructions of drawing since the last tick: not counted as "between ticks"
kind = None
for line in open(a.file, errors="replace"):
    b = begin_re.match(line)
    if b:   # the timed part of the tick starts here (builds from 2026-10-30 on)
        begin = int(b.group(1))
        if prev is not None:
            outside.append(begin - prev - drawn)
        drawn = 0
        continue
    b = dbegin_re.match(line)
    if b:
        dbegin = int(b.group(1))
        continue
    d = draw_re.search(line)
    if d:
        if d.group(1) is not None:
            if dbegin is not None:
                draws.append((int(d.group(2)), int(d.group(1)) - dbegin))
                drawn += int(d.group(1)) - dbegin
            dbegin = None
        else:
            draws.append((int(d.group(2)), float(d.group(4) if a.field == "cpu" else d.group(3))))
        continue
    m = line_re.search(line)
    if not m:
        continue
    count, tick, ents = m.group(1), int(m.group(2)), int(m.group(3))
    ms = m.group(5) if a.field == "cpu" and m.group(5) is not None else m.group(4)
    if count is not None:
        kind = "instructions"
        c = int(count)
        if begin is not None:   # exactly the part the console's timing covers
            rows.append((tick, ents, c - begin))
        elif prev is not None:   # older logs: everything from the previous tick's line (sound and input included)
            rows.append((tick, ents, c - prev))
        prev = c
        begin = None
    elif ms is not None:
        kind = "ms"
        rows.append((tick, ents, float(ms)))
if not rows:
    raise SystemExit("no OFKMEM tick lines in " + a.file)

phases = []
for p in a.phases.split(","):
    start, name = p.split(":", 1)
    phases.append((int(start), name))
phases.sort()


def phase_of(tick):
    name = phases[0][1]
    for start, n in phases:
        if tick >= start:
            name = n
    return name


def pct(v, q):
    v = sorted(v)
    return v[min(len(v) - 1, int(q * (len(v) - 1) + 0.5))]


def fmt(x):
    if kind == "instructions":
        return "%7.2f M" % (x / 1e6)
    return "%7.2f ms" % x


def est(x):
    if kind != "instructions":
        return ""
    return "  ~%5.1f ms" % (x / (a.mhz * 1e6 * a.ipc) * 1e3)


def report(title, vals):
    print("%-14s %6d ticks  mean %s%s  median %s  p90 %s%s  p99 %s  max %s%s" % (
        title, len(vals), fmt(sum(vals) / len(vals)), est(sum(vals) / len(vals)), fmt(pct(vals, 0.5)),
        fmt(pct(vals, 0.9)), est(pct(vals, 0.9)), fmt(pct(vals, 0.99)), fmt(max(vals)), est(max(vals))))


by_phase = collections.OrderedDict()
for start, name in phases:
    by_phase[name] = []
for tick, ents, cost in rows:
    by_phase[phase_of(tick)].append(cost)
print("cost per logic tick (%s%s)" % (kind, ", console estimate at %g MHz, IPC %g" % (a.mhz, a.ipc)
                                       if kind == "instructions" else ""))
for name, vals in by_phase.items():
    if vals:
        report(name, vals)
report("all", [c for _, _, c in rows])
if outside:
    report("between ticks", outside)
    print("  (\"between ticks\": the script's input and mixing 1/30 s of sound, outside the timed part of each tick)")
if draws:
    print("\ncost per frame drawn (drawing the snapshot, then scaling it to the output):")
    by_phase = collections.OrderedDict((name, []) for _, name in phases)
    for tick, cost in draws:
        by_phase[phase_of(tick)].append(cost)
    for name, vals in by_phase.items():
        if vals:
            report(name, vals)
    report("all", [c for _, c in draws])

print("\nby enemies on screen (the game's _root.a.ball list):")
buckets = collections.OrderedDict()
for lo, hi in ((0, 0), (1, 4), (5, 9), (10, 19), (20, 39), (40, 10 ** 6)):
    vals = [c for _, e, c in rows if lo <= e <= hi]
    if vals:
        report("%d-%s" % (lo, hi if hi < 10 ** 6 else "+"), vals)
