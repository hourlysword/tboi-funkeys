#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""The picture RetroFE shows for the OPK in its Native games collection: a PNG named like the OPK next to it in
/mnt/Native games (the collection's media.artwork_front; its layouts show it at 60x60). Drawn here, no game art: a
big tear with a highlight, and the word ISAAC under it, on a transparent background like the other native games'.

usage: make-retrofe.py out.png [size]   (default 60)
Plain Python: drawn 4 times bigger and averaged down (smooth edges), written as an RGBA PNG with zlib.
"""
import math
import struct
import sys
import zlib

OUT = sys.argv[1] if len(sys.argv) > 1 else 'isaac-retrofe.png'
N = int(sys.argv[2]) if len(sys.argv) > 2 else 60
SS = 4                      # supersampling
W = N * SS

# 5x7 capitals for the word
GLYPHS = {
    'I': ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '#####'],
    'S': ['.####', '#....', '#....', '.###.', '....#', '....#', '####.'],
    'A': ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
    'C': ['.####', '#....', '#....', '#....', '#....', '#....', '.####'],
}


def tear(x, y, cx, cy, R, m=1.3):
    """Inside a tear pointing up, centred on (cx, cy), 2R tall: the teardrop curve x = R sin(t) sin(t/2)^m,
    y = -R cos(t) (the tip at the top, round at the bottom)."""
    v = (y - cy) / R
    if v < -1 or v > 1:
        return False
    t = math.acos(-v)
    return abs(x - cx) <= R * math.sin(t) * math.sin(t / 2) ** m


def main():
    px = [[(0, 0, 0, 0)] * W for _ in range(W)]
    s = W / 60.0                                  # the drawing is laid out on 60 units
    cx, cy, R = 30 * s, 21 * s, 20 * s            # the tear: from 1 to 41 units down
    out_w = 2.4 * s                               # outline thickness
    light, dark, line = (196, 232, 255), (52, 132, 216), (22, 36, 70)
    for y in range(W):
        for x in range(W):
            if tear(x, y, cx, cy, R):
                # body: lighter towards the top left
                t = max(0.0, min(1.0, ((x - (cx - R)) * 0.35 + (y - (cy - R)) * 0.75) / (2.1 * R)))
                c = tuple(int(light[k] + (dark[k] - light[k]) * t) for k in range(3))
                # highlight: an ellipse on the round part, up and to the left
                hx, hy = (x - (cx - 6.5 * s)) / (3.0 * s), (y - (cy + 6 * s)) / (5.5 * s)
                if hx * hx + hy * hy <= 1:
                    c = (245, 252, 255)
                inner = tear(x, y, cx, cy + out_w * 0.35, R - out_w)
                px[y][x] = (c + (255,)) if inner else (line + (255,))
    # the word, 2 units per glyph pixel, white with a dark outline
    word, gw, gap = 'ISAAC', 2.0 * s, 2.0 * s
    total = len(word) * 5 * gw + (len(word) - 1) * gap
    x0, y0 = (W - total) / 2, 44 * s
    def on(x, y):
        gx = int((x - x0) // (5 * gw + gap));
        if gx < 0 or gx >= len(word): return False
        lx = x - x0 - gx * (5 * gw + gap)
        col, row = int(lx // gw), int((y - y0) // gw)
        if not (0 <= col < 5 and 0 <= row < 7): return False
        return GLYPHS[word[gx]][row][col] == '#'
    o = int(1.4 * s)
    for y in range(int(y0) - o - 1, min(W, int(y0 + 7 * gw) + o + 1)):
        for x in range(max(0, int(x0) - o - 1), min(W, int(x0 + total) + o + 1)):
            if on(x, y):
                px[y][x] = (255, 255, 255, 255)
            elif any(on(x + dx, y + dy) for dx in (-o, 0, o) for dy in (-o, 0, o)):
                px[y][x] = line + (255,)
    # average down (premultiplied, then back)
    rows = []
    for Y in range(N):
        row = bytearray(b'\x00')
        for X in range(N):
            acc = [0, 0, 0, 0]
            for y in range(Y * SS, Y * SS + SS):
                for x in range(X * SS, X * SS + SS):
                    r_, g, b, a = px[y][x]
                    acc[0] += r_ * a; acc[1] += g * a; acc[2] += b * a; acc[3] += a
            a = acc[3] // (SS * SS)
            if acc[3]:
                row += bytes([acc[0] // acc[3], acc[1] // acc[3], acc[2] // acc[3], a])
            else:
                row += bytes([0, 0, 0, 0])
        rows.append(bytes(row))
    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', N, N, 8, 6, 0, 0, 0)) +
           chunk(b'IDAT', zlib.compress(b''.join(rows), 9)) + chunk(b'IEND', b''))
    open(OUT, 'wb').write(png)


if __name__ == '__main__':
    main()
