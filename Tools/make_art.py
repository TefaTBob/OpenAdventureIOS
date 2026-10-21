#!/usr/bin/env python3
"""
make_art.py — bakes the ink-sketch layer of the cave map into map_art.json.

    python3 make_art.py          # after make_map.py

For every room: its chamber outline (or a clearing, above ground), rock
hatching along its walls, a sketch of what the game describes there, the
items lying there at the start, and small terrain marks round about. For
every passage: tunnel walls (or a trail, above ground), their hatching, and
short stubs used while one end is still unexplored.

Everything is placed once, for the whole cave, so nothing ever moves as the
map fills in. The app shows a room's drawings once you've seen the room, and
a passage once you've seen both ends.

Coordinates are written in tenths of a point at zoom 1 (128 pt per grid unit).
"""
import json
import math
from pathlib import Path

import numpy as np
import yaml
from PIL import Image, ImageDraw

import sketches as K

HERE = Path(__file__).parent
RES = HERE.parent / "OpenAdventure" / "Resources"
UNIT = 128.0
TW = 5.0                     # half tunnel width, pt
NEXP = 3.2                   # chamber squareness (superellipse exponent)
DIAG = 0.5 ** (1 / NEXP)     # where a diagonal port sits, as a fraction of the half box
COLORS = ['ink', 'soft', 'blue', 'red', 'green', 'gold', 'brown']
V = {'n': (0, -1), 's': (0, 1), 'e': (1, 0), 'w': (-1, 0), 'ne': (1, -1), 'nw': (-1, -1), 'se': (1, 1), 'sw': (-1, 1)}

doc = json.loads((RES / "cave_map.json").read_text())
Y = yaml.safe_load((HERE / "adventure.yaml").read_text())
LOCS = dict(Y['locations'])
NAMES = list(LOCS)
rooms = {r['id']: r for r in doc['rooms']}
bw, bh = doc['box']['w'] * UNIT, doc['box']['h'] * UNIT
B = doc['bounds']
OX, OY = (B['x0'] - 1.5) * UNIT, (B['y0'] - 1.5) * UNIT
MW, MH = int((B['x1'] - B['x0'] + 3) * UNIT), int((B['y1'] - B['y0'] + 3) * UNIT)


def key(rid):
    return NAMES[rid][4:]


def kind(r):
    c = LOCS[NAMES[r['id']]].get('conditions') or {}
    if r['region'] in ('maze-alike', 'maze-different'):
        return 'maze'
    if r['region'] in ('forest', 'surface'):
        return 'surface'
    if 'FLUID' in c:
        return 'water'
    return 'cave'


def C(r):
    return (r['x'] * UNIT, r['y'] * UNIT)


def port(r, p):
    v = V[p]
    cx, cy = C(r)
    f = DIAG if (v[0] and v[1]) else 1.0
    return (cx + v[0] * bw / 2 * f, cy + v[1] * bh / 2 * f)


def chamber(r, grow=0.0):
    seed = r['id']
    cx, cy = C(r)
    a, b = bw / 2 + grow, bh / 2 + grow
    ctrl = [K.noise(seed, k) for k in range(9)]
    ctrl[8] = ctrl[0]
    pts = []
    for i in range(64):
        th = i / 64 * 2 * math.pi
        u = th / (2 * math.pi) * 8
        k = int(u)
        f = u - k
        j = 1 + 0.07 * (ctrl[k] * (1 - f) + ctrl[k + 1] * f) + 0.012 * K.noise(seed, 100 + i)
        co, si = math.cos(th), math.sin(th)
        pts.append((cx + a * j * math.copysign(abs(co) ** (2 / NEXP), co),
                    cy + b * j * math.copysign(abs(si) ** (2 / NEXP), si)))
    return pts


def unitv(a, b):
    d = math.hypot(b[0] - a[0], b[1] - a[1])
    return ((b[0] - a[0]) / d, (b[1] - a[1]) / d) if d > 1e-6 else (0, -1)


def densify(pts, step):
    out = [pts[0]]
    for i in range(1, len(pts)):
        a, b = pts[i - 1], pts[i]
        n = max(1, int(math.hypot(b[0] - a[0], b[1] - a[1]) / step))
        out += [(a[0] + (b[0] - a[0]) * j / n, a[1] + (b[1] - a[1]) * j / n) for j in range(1, n + 1)]
    return out


def offset(pts, d):
    out = []
    for i, p in enumerate(pts):
        a, b = (pts[0], pts[1]) if i == 0 else ((pts[-2], pts[-1]) if i == len(pts) - 1 else (pts[i - 1], pts[i + 1]))
        L = math.hypot(b[0] - a[0], b[1] - a[1]) or 1
        out.append((p[0] - (b[1] - a[1]) / L * d, p[1] + (b[0] - a[0]) / L * d))
    return out


def route(c):
    ra, rb = rooms[c['a']], rooms[c['b']]
    pa, pb = port(ra, c['aPort']), port(rb, c['bPort'])
    va, vb = V[c['aPort']], V[c['bPort']]
    na, nb = math.hypot(*va), math.hypot(*vb)
    s = 0.16 * UNIT
    return [pa, (pa[0] + va[0] / na * s, pa[1] + va[1] / na * s), (pb[0] + vb[0] / nb * s, pb[1] + vb[1] / nb * s), pb]


def tunnel(pts, va, vb, seed):
    """two wobbly walls, and the paper strip between them that opens them into the rooms"""
    na, nb = math.hypot(*va), math.hypot(*vb)
    ext = [(pts[0][0] - va[0] / na * 4, pts[0][1] - va[1] / na * 4)] + pts + [(pts[-1][0] - vb[0] / nb * 4, pts[-1][1] - vb[1] / nb * 4)]
    dp = densify(ext, 6)
    pen = K.Pen(seed)
    pen.line(offset(dp, TW), 1.15, 'ink', 0.8, 10)
    pen.line(offset(dp, -TW), 1.15, 'ink', 0.8, 10)
    ext2 = [(pts[0][0] - va[0] / na * 7, pts[0][1] - va[1] / na * 7)] + pts + [(pts[-1][0] - vb[0] / nb * 7, pts[-1][1] - vb[1] / nb * 7)]
    dp2 = densify(ext2, 6)
    fill = offset(dp2, TW - 1.4) + offset(dp2, -(TW - 1.4))[::-1]
    return [s[0] for s in pen.strokes], fill


def stub(r, p, length, seed):
    v = V[p]
    n = math.hypot(*v)
    a = port(r, p)
    q = (a[0] + v[0] / n * length, a[1] + v[1] / n * length)
    walls, fill = tunnel([a, q], v, (-v[0], -v[1]), seed)
    return a, q, walls, fill


# ------------------------------------------------------------------ geometry
outlines, fills = {}, {}
for r in doc['rooms']:
    pen = K.Pen(r['id'])
    pts = chamber(r)
    pen.line(pts, 1.5, 'ink', 0.5, 6, closed=True)
    outlines[r['id']] = pen.strokes[0][0]
    fills[r['id']] = chamber(r, -1.6)

conns = []
for i, c in enumerate(doc['connections']):
    ra, rb = rooms[c['a']], rooms[c['b']]
    seed = c['a'] * 1009 + c['b']
    e = {'i': i}
    if not c['portal'] and c['a'] != c['b']:
        pts = route(c)
        e['route'] = pts
        if kind(ra) == 'surface' and kind(rb) == 'surface':
            pen = K.Pen(seed)
            pen.line(densify(pts, 6), 1.0, 'soft', 0.6, 8)
            e['trail'] = pen.strokes[0][0]
        else:
            e['walls'], e['fill'] = tunnel(pts, V[c['aPort']], V[c['bPort']], seed)
    ends = []
    for r, p in ((ra, c['aPort']), (rb, c['bPort'])):
        L = (0.26 if c['portal'] else 0.3) * UNIT
        a, q, walls, fill = stub(r, p, L, seed + r['id'])
        ends.append({'a': a, 'q': q, 'walls': walls, 'fill': fill, 'surface': kind(r) == 'surface'})
    e['ends'] = ends
    conns.append(e)

# ------------------------------------------------------------------ free-space mask (1 px = 1 pt)
mask = Image.new('L', (MW, MH), 0)
md = ImageDraw.Draw(mask)


def M(p):
    return (p[0] - OX, p[1] - OY)


def mpoly(pts, grow=0):
    q = [M(p) for p in pts]
    md.polygon(q, fill=255)
    if grow:
        md.line(q + [q[0]], fill=255, width=int(grow * 2), joint='curve')


def mline(pts, width):
    md.line([M(p) for p in pts], fill=255, width=int(width), joint='curve')


def mrect(x0, y0, x1, y1):
    a, b = M((x0, y0)), M((x1, y1))
    md.rectangle([a, b], fill=255)


for r in doc['rooms']:
    mpoly(chamber(r), grow=7)
for e in conns:
    if 'route' in e:
        mline(densify(e['route'], 4), TW * 2 + 12 if 'walls' in e else 10)
    for end in e['ends']:
        mline([end['a'], end['q']], TW * 2 + 10)
        q, a = end['q'], end['a']
        t = (q[0] + (q[0] - a[0]) * 0.25, q[1] + (q[1] - a[1]) * 0.25)
        mrect(t[0] - 8, t[1] - 8, t[0] + 8, t[1] + 8)

# command tags (estimated size; the app measures the real text)
for e, c in zip(conns, doc['connections']):
    if 'route' not in e:
        continue
    pts = e['route']
    outdoor = 'trail' in e
    for txt, at, nxt, flip in ((c['aTag'], pts[0], pts[1], False), (c['bTag'], pts[3], pts[2], True)):
        if not txt:
            continue
        ux, uy = unitv(at, nxt)
        tw_, th = len(txt) * 6.0 + 2, 13
        hw = 3 if outdoor else TW + 1.5
        along = 4 + abs(ux) * tw_ / 2 + abs(uy) * th / 2
        nx, ny = -uy, ux
        if ny > 0.2 or (abs(ny) <= 0.2 and nx < 0):
            nx, ny = -nx, -ny
        if flip:
            nx, ny = -nx, -ny
        clear = hw + abs(nx) * tw_ / 2 + abs(ny) * th / 2
        cx, cy = at[0] + ux * along + nx * clear, at[1] + uy * along + ny * clear
        mrect(cx - tw_ / 2 - 3, cy - th / 2 - 2, cx + tw_ / 2 + 3, cy + th / 2 + 2)
# "to Somewhere" on portal stubs and the "you are here" note above every room
for e, c in zip(conns, doc['connections']):
    if c['portal']:
        for end, other in ((e['ends'][0], rooms[c['b']]), (e['ends'][1], rooms[c['a']])):
            q = end['q']
            w = len('to ' + other['label']) * 5.6
            v = unitv(end['a'], q)
            x0 = q[0] if v[0] > 0.3 else (q[0] - w if v[0] < -0.3 else q[0] - w / 2)
            mrect(x0 - 2, q[1] - 9, x0 + w + 2, q[1] + 9)
for r in doc['rooms']:
    cx, cy = C(r)
    mrect(cx - 34, cy - bh / 2 - 26, cx + 30, cy - bh / 2 - 8)

amask = np.asarray(mask).copy()


def freept(x, y):
    X, Y_ = int(x - OX), int(y - OY)
    return 0 <= X < MW and 0 <= Y_ < MH and not amask[Y_, X]


def free(x0, y0, x1, y1):
    a = np.asarray(mask)
    X0, Y0, X1, Y1 = int(x0 - OX), int(y0 - OY), int(math.ceil(x1 - OX)), int(math.ceil(y1 - OY))
    if X0 < 0 or Y0 < 0 or X1 >= MW or Y1 >= MH:
        return False
    return not a[Y0:Y1, X0:X1].any()


# ------------------------------------------------------------------ sketches beside rooms
art = {r['id']: [] for r in doc['rooms']}       # (pen, dx, dy)
items_at = {}
for o in Y['objects']:
    k, v = list(o.items())[0] if isinstance(o, dict) else o
    if k in K.ITEMS and isinstance(v.get('locations'), str):
        items_at.setdefault(v['locations'], []).append(k)
room_of_loc = {NAMES[l]: r['id'] for r in doc['rooms'] for l in r['locs']}
room_items = {}
for loc, ks in items_at.items():
    if loc in room_of_loc:
        room_items.setdefault(room_of_loc[loc], []).extend(ks)


def place(r, pen, rings):
    """nearest free spot round the room (a ring at a time) for the sketch's box"""
    x0, y0, x1, y1 = K.bounds(pen, 1.5)
    w, h = x1 - x0, y1 - y0
    cx, cy = C(r)
    rx0, ry0 = (bw / 2 + w * 0.5), (bh / 2 + h * 0.5)
    for dist in rings:
        for k in range(40):
            a = k / 40 * 2 * math.pi + 0.15 + (r['id'] % 7) * 0.4
            x = cx + math.cos(a) * rx0 * dist - (x0 + x1) / 2
            y = cy + math.sin(a) * ry0 * dist - (y0 + y1) / 2
            if free(x + x0, y + y0, x + x1, y + y1):
                mrect(x + x0, y + y0, x + x1, y + y1)
                return (x, y)
    return None


def scaled(pen, f):
    out = K.Pen(pen.seed)
    out.strokes = [([(x * f, y * f) for x, y in pts], max(0.45, w * (0.55 + 0.45 * f)), c, d) for pts, w, c, d in pen.strokes]
    out.texts = [(s, x * f, y * f, size * (f if s in CAPTIONS else max(f, 0.9) ** 0.5), rot, c, b) for s, x, y, size, rot, c, b in pen.texts]
    return out


CAPTIONS = set(K.ITEM_CAPTION.values())


def place_scaled(r, pen, sizes):
    rings = (1.0, 1.1, 1.2, 1.35, 1.5)
    for f in sizes:
        p2 = scaled(pen, f)
        at = place(r, p2, rings if f > min(sizes) else rings + (1.7, 1.9, 2.1))
        if at:
            return p2, at
    return None, None


def with_caption(fn, caption, seed):
    pen = K.draw(fn, seed)
    if caption:
        _, _, _, yb = K.bounds(pen, 0)
        pen.text(caption, 0, yb + 5, 7, 0, 'soft')
    return pen


def priority(r):
    k = key(r['id'])
    if r['id'] in room_items:
        return 0
    if k in K.SCENES:
        return 1
    return 2


missed = []
for r in sorted(doc['rooms'], key=lambda r: (priority(r), r['id'])):
    k = key(r['id'])
    fn = K.scene_for(k, r['region'])
    if fn:
        pen, at = place_scaled(r, K.draw(fn, r['id'] * 13 + 1), (1.45, 1.25, 1.05, 0.85))
        if at:
            art[r['id']].append((pen, at))
        else:
            missed.append(('scene', k))
    for j, item in enumerate(room_items.get(r['id'], [])):
        pen, at = place_scaled(r, with_caption(K.ITEMS[item], K.ITEM_CAPTION[item], r['id'] * 17 + j), (1.35, 1.15, 0.95, 0.8))
        if at:
            art[r['id']].append((pen, at))
        else:
            missed.append(('item', item))

# ------------------------------------------------------------------ rock hatching (round whatever the sketches left free)
amask = np.asarray(mask).copy()


def hatch_along(pts, seed, sign, start):
    out = []
    dp = densify(pts, 3.2)
    for i in range(1, len(dp) - 1):
        if K.noise(seed, i) < -0.32:
            continue
        a, b = dp[i - 1], dp[i + 1]
        L = math.hypot(b[0] - a[0], b[1] - a[1]) or 1
        nx, ny = -(b[1] - a[1]) / L * sign, (b[0] - a[0]) / L * sign
        L0 = 2.0 + start
        L1 = L0 + 3.5 + 5 * (K.noise(seed, i + 500) + 0.5)
        p0 = (dp[i][0] + nx * L0, dp[i][1] + ny * L0)
        p1 = (dp[i][0] + nx * L1, dp[i][1] + ny * L1)
        if not (freept(*p1) and freept((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2)):
            continue
        tilt = 0.35 * K.noise(seed, i + 900)
        p1 = (p1[0] - ny * tilt * 4, p1[1] + nx * tilt * 4)
        out.append(([p0, p1], 0.8, 'soft', None))
    return out


room_hatch, conn_hatch = {}, {}
for r in doc['rooms']:
    if kind(r) != 'surface':
        ch = chamber(r)
        room_hatch[r['id']] = hatch_along(ch + [ch[0]], r['id'] * 31, -1, 2.5)
for e in conns:
    if 'walls' in e:
        dp = densify(e['route'], 6)
        seed = e['i'] * 7 + 3
        conn_hatch[e['i']] = hatch_along(dp, seed, 1, TW + 2) + hatch_along(dp, seed + 1, -1, TW + 2)

# hatching zone counts as taken for the sketches
hm = Image.new('L', (MW, MH), 0)
hd = ImageDraw.Draw(hm)
for r in doc['rooms']:
    if kind(r) != 'surface':
        hd.polygon([M(p) for p in chamber(r, 12)], fill=255)
for e in conns:
    if 'walls' in e:
        hd.line([M(p) for p in densify(e['route'], 4)], fill=255, width=int(TW * 2 + 22), joint='curve')
mask.paste(255, mask=hm)

# ------------------------------------------------------------------ terrain marks
symbols, sym_index = [], {}
for kd, fns in K.MARKS.items():
    for j, fn in enumerate(fns):
        for v in range(3):
            pen = K.draw(fn, 700 + j * 11 + v * 101 + len(kd))
            sym_index.setdefault(kd, []).append(len(symbols))
            symbols.append(pen)
marks = {r['id']: [] for r in doc['rooms']}
centres = [(C(r), r) for r in doc['rooms']]
step = 17.0
reach = bw * 1.15
gy = OY + 10
while gy < OY + MH:
    gx = OX
    while gx < OX + MW:
        jx = gx + K.noise(int(gx), int(gy)) * step * 0.8
        jy = gy + K.noise(int(gy), int(gx) + 3) * step * 0.8
        best, bd = None, 1e9
        for (px, py), r in centres:
            d = math.hypot((jx - px) * 0.7, jy - py)
            if d < bd:
                bd, best = d, r
        dense = 0.3 if kind(best) == 'surface' else 0.0
        if bd <= reach and K.noise(int(jx), int(jy)) <= dense:
            opts = sym_index[kind(best)]
            si = opts[int((K.noise(int(jx) + 1, int(jy)) + .5) * len(opts)) % len(opts)]
            x0, y0, x1, y1 = K.bounds(symbols[si], 0.5)
            if free(jx + x0, jy + y0, jx + x1, jy + y1):
                marks[best['id']].append((si, jx, jy))
                mrect(jx + x0 - 1, jy + y0 - 1, jx + x1 + 1, jy + y1 + 1)
        gx += step
    gy += step

# ------------------------------------------------------------------ export
def q(v):
    return int(round(v * 10))


def enc_stroke(pts, w, c, dash, dx=0.0, dy=0.0):
    d = dash or (0, 0)
    out = [COLORS.index(c), q(w), q(d[0]), q(d[1])]
    for x, y in pts:
        out += [q(x + dx), q(y + dy)]
    return out


def enc_pts(pts):
    out = []
    for x, y in pts:
        out += [q(x), q(y)]
    return out


def enc_text(t, dx=0.0, dy=0.0):
    s, x, y, size, rot, c, bold = t
    return [s, q(x + dx), q(y + dy), q(size), q(rot), COLORS.index(c), 1 if bold else 0]


out_rooms = []
for r in doc['rooms']:
    rid = r['id']
    strokes, texts = [], []
    for pen, (x, y) in art[rid]:
        strokes += [enc_stroke(*s, dx=x, dy=y) for s in pen.strokes]
        texts += [enc_text(t, x, y) for t in pen.texts]
    out_rooms.append({
        'id': rid,
        'kind': kind(r),
        'outline': enc_pts(outlines[rid]),
        'fill': enc_pts(fills[rid]),
        'hatch': [enc_stroke(*s) for s in room_hatch.get(rid, [])],
        'art': strokes,
        'text': texts,
        'marks': [[si, q(x), q(y)] for si, x, y in marks[rid]],
    })
out_conns = []
for e in conns:
    o = {'i': e['i']}
    if 'walls' in e:
        o['walls'] = [enc_pts(w) for w in e['walls']]
        o['fill'] = enc_pts(e['fill'])
        o['hatch'] = [enc_stroke(*s) for s in conn_hatch.get(e['i'], [])]
    if 'trail' in e:
        o['trail'] = enc_pts(e['trail'])
    o['ends'] = [{'walls': [enc_pts(w) for w in end['walls']], 'fill': enc_pts(end['fill']),
                  'tip': enc_pts([end['q']])} for end in e['ends']]
    out_conns.append(o)
out = {
    'scale': 10, 'unit': UNIT, 'tunnel': TW, 'diag': DIAG, 'colors': COLORS,
    'symbols': [{'strokes': [enc_stroke(*s) for s in p.strokes], 'text': [enc_text(t) for t in p.texts]} for p in symbols],
    'rooms': out_rooms,
    'connections': out_conns,
}
path = RES / "map_art.json"
path.write_text(json.dumps(out, separators=(',', ':')))
n_art = sum(len(v) for v in art.values())
print(f"wrote {path.name}: {path.stat().st_size // 1024} KB, {n_art} sketches, "
      f"{sum(len(v) for v in marks.values())} marks, {len(symbols)} mark symbols")
if missed:
    print("no room for:", ", ".join(f"{a} {b}" for a, b in missed))
