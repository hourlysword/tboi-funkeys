#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Where the game spends its time on the console: a report of fkprof's samples (a whole-system sampling
profiler from my other FunKey S projects, 1000 samples a second; scripts/device/play.sh with PROFILE=1 runs it next to the game).

usage: fkreport.py fkprof.txt isaac.nm [libc.nm]
  isaac.nm: `nm -n -S -C` of the unstripped FunKey build (build-funkey/isaac, not the OPK's stripped copy)
  libc.nm:  the same of the SDK's libc.so (the console's is the same file), for the C library's functions

From fkprof's own report script, with this game's areas.
"""
import bisect
import collections
import re
import sys

# function name patterns -> area of the program (the first match wins)
AREAS = [
    ('drawing: renderer', r'^fl::\(anonymous namespace\)::(drawTex|drawNode|drawChildren|scaleCanvas|scaleImage|layerFor|axisFor|rasterFor|bigRasterFor|bitmapRuns|buildRuns|cacheTrim|stillTransform|canvasBox|fillWin|drawText)|^fl::render|^fl::(funkeyPlay|fbPresent)'),
    ('recompiled game code', r'^fl::(eternal|wotl|og)::'),
    ('variable lookup (scopes)', r'^fl::(getVarK|setVarK|getVar|setVar|findVar|scopeLookup)\b'),
    ('property access', r'^fl::(getMemK|setMemK|getMem|setMem|getProp|setProp|tryGetProp|hasProp|delProp)\b|PropMap|^fl::(intern|internWeak)\b'),
    ('calls and the AVM runtime', r'^fl::(callMethodK|callFunK|callMethod|callFun|newMethod|invoke|runActions|runFrame|runIntervals|toNum|toStr|toInt32|truthy|add2|less2|sub|mul|divv|notv|eq|strict|concat|mkstr)\b|^fl::Act'),
    ('garbage collector', r'^fl::(gc|mark|sweep|Gc)|^fl::.*::(mark|trace)\b'),
    ('display list, timelines', r'^fl::(MovieClip|DisplayObject|Sprite|placeObject|gotoFrame|advance|spriteEnsure|timeline|clip)|^fl::.*(Frame|Timeline|Place)'),
    ('snapshot for the renderer', r'^fl::(buildSnapshot|snap|Snap|addNode)'),
    ('drawing: rasterizer (shapes, bitmaps)', r'^plutovg|^fl::(raster|bitmapDraw|bd_|Bitmap)|^fl::.*(raster|Raster)'),
    ('sound: mixer', r'^fl::(mix|audio|sound|Sound|Channel|resample)'),
    ('sound: MP3 / ADPCM decoding', r'mp3|^drmp3|^fl::(adpcm|decode)|^L3_|^L12_'),
    ('SWF loading, shapes parsed', r'^fl::(swf|Swf|parse|load|decode|inflate|lean)|^inflate|^zlib|crc32|adler32'),
    ('SDL', r'^SDL_|^SDL'),
    ('C++ library', r'^std::|^operator (new|delete)|^__cxa|^__gnu'),
]


def area_of(name):
    for area, pat in AREAS:
        if re.search(pat, name):
            return area
    if name.startswith('fl::'):
        return 'runtime: other'
    return 'other'


def load_syms(path, base=0):
    syms = []
    for line in open(path, errors='replace'):
        m = re.match(r'^([0-9a-f]+) (?:([0-9a-f]+) )?([tTwWiI]) (.+)$', line.rstrip('\n'))
        if m:
            syms.append((int(m.group(1), 16) + base, int(m.group(2) or '0', 16), m.group(4)))
    syms.sort()
    return syms


def lookup(syms, addrs, pc):
    i = bisect.bisect_right(addrs, pc) - 1
    if i < 0:
        return None
    a, size, name = syms[i]
    if size and pc >= a + size:
        return None
    return name


def parse(path):
    head, sections, cur = [], collections.OrderedDict(), None
    for line in open(path, errors='replace'):
        line = line.rstrip('\n')
        m = re.match(r'^\[(.+?)\]', line)
        if m:
            cur = m.group(1)
            sections[cur] = [line]
            continue
        (head if cur is None else sections[cur]).append(line)
    return head, sections


def pct(n, total):
    return 100.0 * n / total if total else 0.0


def main():
    head, sec = parse(sys.argv[1])
    syms = load_syms(sys.argv[2])
    addrs = [s[0] for s in syms]
    m = re.search(r'samples (\d+) target (\d+)', ' '.join(head))
    total, target = (int(m.group(1)), int(m.group(2))) if m else (0, 0)
    print('== fkprof: %s' % ' | '.join(l for l in head if l))

    def table(name):
        rows = []
        for l in sec.get(name, [])[1:]:
            p = l.split(None, 3)
            if len(p) == 4 and p[0].isdigit():
                rows.append((int(p[0]), int(p[1]), p[2], p[3]))
        return rows

    print('\n== CPU time by process (%d samples, 1 ms each)' % total)
    for n, k, pid, name in table('processes')[:10]:
        print('  %5.1f%%  %-16s pid %-5s (%.0f%% of it in the kernel)' % (pct(n, total), name, pid, pct(k, n)))
    print('\n== The game\'s threads (share of all CPU time)')
    for n, k, tid, name in table('target threads')[:8]:
        print('  %5.1f%%  %-16s tid %-5s (%.0f%% in the kernel)' % (pct(n, total), name, tid, pct(k, n)))

    maps = []
    for l in sec.get('maps', [])[1:]:
        mm = re.match(r'^([0-9a-f]+)-([0-9a-f]+) (\S+) ([0-9a-f]+) \S+ \d+\s*(.*)$', l)
        if mm:
            maps.append((int(mm.group(1), 16), int(mm.group(2), 16), mm.group(3), int(mm.group(4), 16), mm.group(5).strip()))
    libc, libc_addrs = [], []
    if len(sys.argv) > 3:   # the C library at its load address (its first mapping: offset 0)
        for s, e, perms, off, path in maps:
            if re.search(r'(libc\.so|ld-musl)', path) and off == 0:
                libc = load_syms(sys.argv[3], base=s)
                libc_addrs = [x[0] for x in libc]
                break

    areas, funcs = collections.Counter(), collections.Counter()
    user = 0
    for l in sec.get('user', [])[1:]:
        p = l.split()
        if len(p) != 2 or not p[0].isdigit():
            continue
        n, pc = int(p[0]), int(p[1], 16)
        user += n
        name = lookup(syms, addrs, pc)
        if name:
            funcs[name] += n
            areas[area_of(name)] += n
            continue
        where = '?'
        for s, e, perms, off, path in maps:
            if s <= pc < e:
                where = path.split('/')[-1] if path else 'anonymous memory'
                break
        lname = lookup(libc, libc_addrs, pc) if libc else None
        if lname:
            funcs['libc: ' + lname] += n
            areas['C library (musl)'] += n
        else:
            funcs['(%s)' % where] += n
            areas['libraries: ' + where] += n

    print('\n== Where the game spends its time (share of its samples, %d)' % target)
    for a, n in areas.most_common():
        print('  %5.1f%%  %s' % (pct(n, target), a))
    print('  %5.1f%%  kernel (system calls, page faults, interrupts while the game ran)' % pct(target - user, target))

    print('\n== Busiest functions')
    for f, n in funcs.most_common(40):
        print('  %5.1f%%  %-70s %s' % (pct(n, target), f[:70], area_of(f) if not f.startswith(('libc', '(')) else ''))

    rows = []
    for l in sec.get('kernel', [])[1:]:
        p = l.split()
        if len(p) == 3 and p[0].isdigit():
            rows.append((int(p[0]), int(p[1]), p[2]))
    print('\n== Kernel functions while the game ran')
    for n, t, s in [r for r in rows if r[1] == 1][:15]:
        print('  %5.1f%%  %s' % (pct(n, target), s))

    print('\n== Memory')
    for l in sec.get('vmstat delta', [])[1:]:
        if l.strip():
            print('  ' + l)
    status = '\n'.join(sec.get('status', []))
    for key in ('VmRSS', 'VmSwap', 'VmHWM'):
        mm = re.search(r'^%s:\s+(\d+) kB' % key, status, re.M)
        if mm:
            print('  %s %s kB' % (key, mm.group(1)))


if __name__ == '__main__':
    main()
