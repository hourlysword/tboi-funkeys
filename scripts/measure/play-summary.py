#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""A play run on the console in a few lines (scripts/device/play.sh's results folder): the game's own 5-second lines
(pictures a second, page faults), its long ticks (over 150 ms: room entries, new floors) and the memory samples
(play-run.sh's mem.txt, every 2 s: the program's memory, its major page faults, the system's refaults and swap).

usage: play-summary.py RESULTS_DIR...   e.g. play-summary.py testing/m7/lock0 testing/m7/lock1
"""
import os
import re
import sys

WIN = re.compile(r"\[funkey\] ([\d.]+) s: ([\d.]+) ticks/s, ([\d.]+) pictures/s .*?logic ([\d.]+) ms.*?draw ([\d.]+),"
                 r".*?worst tick (\d+) ms \| rss (\d+) MB, swap (\d+) MB, available (\d+) MB(?:, page faults (\d+))?")
LONG = re.compile(r"\[funkey\] long tick (\d+): (\d+) ms: logic (\d+).*?(?:; page faults (\d+))?$")


def pairs(line):   # "Key: value Key value ..." -> {key: int}
    t = line.replace(":", " ").split()
    out = {}
    for k, v in zip(t[0::2], t[1::2]):
        try:
            out[k] = int(v)
        except ValueError:
            pass
    return out


def summary(d):
    log = open(os.path.join(d, "log.txt"), errors="replace").read().splitlines()
    wins, longs = [], []
    for line in log:
        m = WIN.search(line)
        if m:
            wins.append([float(x) if x is not None else 0.0 for x in m.groups()])
            continue
        m = LONG.search(line)
        if m:
            longs.append([int(x) if x is not None else 0 for x in m.groups()])
    print(f"== {d}")
    for line in log:
        if "kept in memory" in line or "left to the kernel" in line or "CPU clock" in line:
            print("  " + line.strip())
    # (the first window holds the start: the title screen is drawn every tick, so it is left out of the averages)
    w = wins[1:] if len(wins) > 2 else wins
    if w:
        secs = sum(x[0] for x in w)
        pics = sum(x[0] * x[2] for x in w) / secs
        logic = sum(x[0] * x[3] for x in w) / secs
        draw = sum(x[0] * x[4] for x in w) / secs
        faults = [x[9] for x in w]
        print(f"  {len(w)} windows, {secs:.0f} s: {pics:.1f} pictures/s (lowest {min(x[2] for x in w):.1f}, "
              f"{sum(1 for x in w if x[2] < 24)} under 24), logic {logic:.1f} ms/tick, draw {draw:.1f} ms/picture")
        print(f"  page faults: {sum(faults):.0f} in all, {sum(faults) / secs:.1f}/s, most in 5 s {max(faults):.0f}; "
              f"rss up to {max(x[6] for x in w):.0f} MB, swap up to {max(x[7] for x in w):.0f} MB, "
              f"available down to {min(x[8] for x in w):.0f} MB")
    if longs:
        ms = [x[1] for x in longs]
        pf = [x[3] for x in longs]
        print(f"  long ticks: {len(longs)} over 150 ms, {sum(1 for x in ms if x > 300)} over 300 ms, mean {sum(ms) / len(ms):.0f} ms, "
              f"longest {max(ms)} ms; page faults in them: {sum(pf)} ({sum(pf) / len(pf):.1f} a tick)")
        worst = sorted(longs, key=lambda x: -x[3])[:4]
        print("    most faults: " + ", ".join(f"tick {x[0]} {x[1]} ms {x[3]} faults" for x in worst))
    mem = os.path.join(d, "mem.txt")
    if os.path.exists(mem):
        rows = [pairs(line) for line in open(mem, errors="replace") if line.strip()]
        rows = [r for r in rows if "VmRSS" in r]
        if rows:
            def rng(k):
                v = [r[k] for r in rows if k in r]
                return (min(v), max(v)) if v else (0, 0)

            def delta(k):
                v = [r[k] for r in rows if k in r]
                return v[-1] - v[0] if v else 0
            print(f"  memory samples: {len(rows)}; RSS {rng('VmRSS')[1] >> 10} MB at most, code and files in it (RssFile) "
                  f"{rng('RssFile')[0] >> 10}-{rng('RssFile')[1] >> 10} MB, swap up to {rng('VmSwap')[1] >> 10} MB, "
                  f"available down to {rng('MemAvailable')[0] >> 10} MB")
            print(f"  over the run: the program's major faults {delta('majflt')}, the system's {delta('pgmajfault')}; "
                  f"refaults {delta('workingset_refault')}; swapped in {delta('pswpin')} pages, out {delta('pswpout')}")


for d in sys.argv[1:] or ["."]:
    summary(d)
