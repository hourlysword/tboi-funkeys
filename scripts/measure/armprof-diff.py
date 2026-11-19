#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""The difference of two armprof profiles (scripts/measure/qemu-armprof.sh) of the same build: what the longer run did
beyond the shorter one, e.g. one tick (a run that quits at tick T, and one that quits at T + 1). Writes a profile in the
same format (blocks with a positive difference of executions), for armprof.py
(from the measuring tools of my other FunKey S projects); copies PROFILE.maps.

usage: armprof-diff.py SHORT.prof LONG.prof OUT.prof
"""
import shutil
import sys


def read(path):
    blocks = {}
    for line in open(path):
        v = line.split()
        if len(v) >= 3:
            blocks[(v[0], v[1], tuple(v[3:]))] = int(v[2])
    return blocks


short, long_, out = sys.argv[1:4]
a, b = read(short), read(long_)
n = 0
with open(out, "w") as f:
    for key, execs in b.items():
        d = execs - a.get(key, 0)
        if d > 0:
            f.write("%s %s %d %s\n" % (key[0], key[1], d, " ".join(key[2])))
            n += 1
try:
    shutil.copy(long_ + ".maps", out + ".maps")
except OSError:
    pass
print("%s: %d blocks" % (out, n))
