#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Draw the OPK's 32x32 icon (a big tear falling on a dark tile: nothing taken from the game) and write it as a PNG,
with nothing but the standard library.

usage: opk/make-icon.py OUT.png
"""
import math
import struct
import sys
import zlib

W = H = 32
BACKGROUND = (34, 24, 22)
TEAR = (120, 170, 230)
TEAR_DARK = (60, 100, 170)
SHINE = (235, 245, 255)


def tear_shape(x, y):
    """Inside the tear (a circle with a point on top), with a 0..1 shading from its lower right."""
    cx, cy, r = 16.0, 20.0, 8.5
    dx, dy = x + 0.5 - cx, y + 0.5 - cy
    inside = dx * dx + dy * dy <= r * r
    # the point: a triangle from the circle's sides up to (16, 4)
    if not inside and 4 <= y + 0.5 <= cy:
        half = (y + 0.5 - 4) / (cy - 4) * r * 0.95
        inside = abs(dx) <= half
    shade = max(0.0, min(1.0, (dx + dy) / (2 * r) + 0.5))
    return inside, shade


def draw():
    px = [[BACKGROUND] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            inside, shade = tear_shape(x, y)
            if inside:
                px[y][x] = tuple(int(a + (b - a) * shade) for a, b in zip(TEAR, TEAR_DARK))
    for (x, y) in ((12, 17), (12, 18), (13, 16), (13, 17), (11, 19)):   # a highlight
        px[y][x] = SHINE
    return px


def write_png(path, px):
    raw = b"".join(b"\0" + bytes(c for p in row for c in p) for row in px)
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    write_png(sys.argv[1], draw())
