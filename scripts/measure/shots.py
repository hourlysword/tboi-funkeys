#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Turn screenshots (PPM, as the game writes them with a script's "shot") into PNG files, and compare two sets.

usage: shots.py png DIR...                       every .ppm in the folders -> .png next to it
       shots.py raw DIR...                       every .raw (the console's screen: 240x240 RGB565) -> .png
       shots.py diff A.ppm B.ppm [OUT.png]       how far apart two shots are (mean and max difference per channel,
                                                 share of pixels off by more than 16), and a picture of where
       shots.py sheet OUT.png A.ppm B.ppm ...    the shots side by side (same height), for looking at them at once
       shots.py zoom OUT.png A.ppm [K [X0,Y0,X1,Y1]]  a shot (or a part of it) K times larger (3), pixel for pixel

Plain Python: no imaging library needed (zlib for the PNG).
"""
import struct
import sys
import zlib


def read_ppm(path):
    with open(path, "rb") as f:
        data = f.read()
    parts, pos = [], 0
    while len(parts) < 4:   # magic, width, height, maxval (comments not used by the game)
        while data[pos:pos + 1].isspace():
            pos += 1
        end = pos
        while not data[end:end + 1].isspace():
            end += 1
        parts.append(data[pos:end])
        pos = end
    pos += 1
    if parts[0] != b"P6":
        raise SystemExit("%s: not a binary PPM" % path)
    w, h = int(parts[1]), int(parts[2])
    return w, h, data[pos:pos + w * h * 3]


def write_png(path, w, h, rgb):
    raw = b"".join(b"\0" + rgb[y * w * 3:(y + 1) * w * 3] for y in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    cmd = sys.argv[1]
    if cmd == "png":
        import glob
        import os
        for d in sys.argv[2:]:
            for p in sorted(glob.glob(os.path.join(d, "*.ppm"))):
                w, h, rgb = read_ppm(p)
                write_png(p[:-4] + ".png", w, h, rgb)
    elif cmd == "diff":
        wa, ha, a = read_ppm(sys.argv[2])
        wb, hb, b = read_ppm(sys.argv[3])
        if (wa, ha) != (wb, hb):
            raise SystemExit("different sizes: %dx%d and %dx%d" % (wa, ha, wb, hb))
        n = wa * ha
        total, worst, off = 0, 0, 0
        out = bytearray(n * 3)
        for i in range(n):
            d = max(abs(a[i * 3 + k] - b[i * 3 + k]) for k in range(3))
            total += sum(abs(a[i * 3 + k] - b[i * 3 + k]) for k in range(3))
            worst = max(worst, d)
            if d > 16:
                off += 1
            v = min(255, d * 4)
            out[i * 3:i * 3 + 3] = bytes((v, v, v))
        print("mean %.2f per channel, max %d, %.1f%% of pixels off by more than 16" % (total / (n * 3), worst, 100.0 * off / n))
        if len(sys.argv) > 4:
            write_png(sys.argv[4], wa, ha, bytes(out))
    elif cmd == "sheet":
        shots = [read_ppm(p) for p in sys.argv[3:]]
        h = max(s[1] for s in shots)
        w = sum(s[0] for s in shots) + 4 * (len(shots) - 1)
        rgb = bytearray(w * h * 3)
        x0 = 0
        for sw, sh, px in shots:
            for y in range(sh):
                rgb[(y * w + x0) * 3:(y * w + x0 + sw) * 3] = px[y * sw * 3:(y + 1) * sw * 3]
            x0 += sw + 4
        write_png(sys.argv[2], w, h, bytes(rgb))
    elif cmd == "raw":
        import glob
        import os
        for d in sys.argv[2:]:
            for p in sorted(glob.glob(os.path.join(d, "*.raw"))):
                raw = open(p, "rb").read()
                w = h = 240
                if len(raw) < w * h * 2:
                    continue
                rgb = bytearray()
                for i in range(w * h):
                    v = raw[i * 2] | raw[i * 2 + 1] << 8
                    rgb += bytes(((v >> 11) * 255 // 31, ((v >> 5) & 63) * 255 // 63, (v & 31) * 255 // 31))
                write_png(p[:-4] + ".png", w, h, bytes(rgb))
    elif cmd == "zoom":
        sw, sh, px = read_ppm(sys.argv[3])
        k = int(sys.argv[4]) if len(sys.argv) > 4 else 3
        x0, y0, x1, y1 = (int(v) for v in sys.argv[5].split(",")) if len(sys.argv) > 5 else (0, 0, sw, sh)
        w, h = (x1 - x0) * k, (y1 - y0) * k
        rgb = bytearray()
        for y in range(y0, y1):
            row = b"".join(px[(y * sw + x) * 3:(y * sw + x) * 3 + 3] * k for x in range(x0, x1))
            rgb += row * k
        write_png(sys.argv[2], w, h, bytes(rgb))
    else:
        raise SystemExit(__doc__)


main()
