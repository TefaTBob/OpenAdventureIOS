"""Pen-and-ink sketches for the cave map.

Each sketch is drawn around (0, 0) in points (y grows downward) by
recording strokes on a Pen. The map generator places the sketches beside
the rooms they belong to and bakes the strokes into map_art.json; the app
only replays them.

Scenes follow the game's own room descriptions; items are the things you
find lying in a place when the game starts.
"""
import math

M64 = (1 << 64) - 1


def noise(seed, i):
    """Deterministic noise in -0.5…0.5 (same hash as the app's Pencil.noise)."""
    h = ((seed * 73856093) & M64) ^ ((i * 19349663) & M64) ^ 0x5bd1e995
    h ^= h >> 33; h = (h * 0xff51afd7ed558ccd) & M64; h ^= h >> 33
    h = (h * 0xc4ceb9fe1a85ec53) & M64; h ^= h >> 33
    return (h % 10000) / 10000 - 0.5


INK, SOFT, BLUE, RED, GREEN, GOLD, BROWN = 'ink', 'soft', 'blue', 'red', 'green', 'gold', 'brown'


class Pen:
    def __init__(self, seed=1):
        self.seed = seed
        self.k = 0
        self.strokes = []   # (points, width, colour, dash)
        self.texts = []     # (text, x, y, size, rotation degrees, colour, bold)

    def n(self):
        self.k += 1
        return noise(self.seed, self.k)

    # -- primitives ---------------------------------------------------
    def line(self, pts, w=1.0, c=INK, wob=0.5, step=5.0, dash=None, closed=False):
        pts = list(pts)
        if closed:
            pts = pts + [pts[0]]
        out = [self._j(pts[0], wob * 0.4)]
        for i in range(1, len(pts)):
            a, b = pts[i - 1], pts[i]
            L = math.hypot(b[0] - a[0], b[1] - a[1])
            if L < 0.01:
                continue
            nx, ny = -(b[1] - a[1]) / L, (b[0] - a[0]) / L
            m = max(1, int(L / step))
            for j in range(1, m + 1):
                t = j / m
                off = self.n() * wob * (0.4 if j == m else 1)
                out.append((a[0] + (b[0] - a[0]) * t + nx * off, a[1] + (b[1] - a[1]) * t + ny * off))
        if closed:
            out[-1] = out[0]
        self.strokes.append((out, w, c, dash))

    def _j(self, p, a):
        return (p[0] + self.n() * a, p[1] + self.n() * a)

    def seg(self, x0, y0, x1, y1, w=0.8, c=INK, wob=0.25):
        self.line([(x0, y0), (x1, y1)], w, c, wob)

    def ell(self, cx, cy, rx, ry, a0=0.0, a1=360.0, w=1.0, c=INK, wob=0.4, n=None, rot=0.0):
        n = n or max(8, int(abs(a1 - a0) / 12))
        cr, sr = math.cos(math.radians(rot)), math.sin(math.radians(rot))
        pts = []
        for i in range(n + 1):
            a = math.radians(a0 + (a1 - a0) * i / n)
            x, y = math.cos(a) * rx, math.sin(a) * ry
            pts.append((cx + x * cr - y * sr, cy + x * sr + y * cr))
        self.line(pts, w, c, wob, step=4)
        return pts

    def text(self, s, x, y, size=7.0, rot=0.0, c=INK, bold=False):
        self.texts.append((s, x, y, size, rot, c, bold))

    def hatch(self, poly, angle=45, gap=2.4, w=0.55, c=SOFT, jitter=0.35):
        """Shade inside a polygon with parallel strokes."""
        a = math.radians(angle)
        dx, dy = math.cos(a), math.sin(a)
        nx, ny = -dy, dx
        ds = [p[0] * nx + p[1] * ny for p in poly]
        lo, hi = min(ds), max(ds)
        d = lo + gap * 0.5
        while d < hi:
            xs = []
            for i in range(len(poly)):
                p, q = poly[i], poly[(i + 1) % len(poly)]
                dp, dq = p[0] * nx + p[1] * ny, q[0] * nx + q[1] * ny
                if (dp - d) * (dq - d) < 0:
                    t = (d - dp) / (dq - dp)
                    x, y = p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t
                    xs.append(x * dx + y * dy)
            xs.sort()
            for i in range(0, len(xs) - 1, 2):
                s0, s1 = xs[i] + 0.4, xs[i + 1] - 0.4
                if s1 - s0 > 0.8:
                    j0, j1 = self.n() * jitter * gap, self.n() * jitter * gap
                    self.seg(dx * s0 + nx * (d + j0), dy * s0 + ny * (d + j0),
                             dx * s1 + nx * (d + j1), dy * s1 + ny * (d + j1), w, c, 0.15)
            d += gap

    # -- little vocabulary --------------------------------------------
    def tuft(self, x, y, s=4.0, c=SOFT):
        for k, dx in enumerate((-0.35, 0, 0.35)):
            self.seg(x + dx * s * 0.6, y, x + dx * s * 1.3 + self.n() * s * 0.2, y - s * (0.8 + 0.3 * (k == 1)), 0.6, c, 0.1)

    def ground(self, x0, x1, y, c=SOFT, tufts=True):
        self.line([(x0, y), (x1, y)], 0.7, c, 0.6)
        if tufts:
            x = x0 + 3
            while x < x1 - 2:
                if self.n() > -0.1:
                    self.tuft(x, y, 3 + self.n() * 1.5)
                x += 6 + self.n() * 4

    def wave(self, x, y, w=14, h=1.6, c=BLUE, lw=0.7):
        n = 8
        self.line([(x - w / 2 + w * i / n, y - math.sin(i / n * 2 * math.pi * 1.5) * h) for i in range(n + 1)], lw, c, 0.1, step=2)

    def rock(self, x, y, r, c=INK, shade=True):
        pts = []
        for i in range(9):
            a = math.pi + i / 8 * math.pi
            rr = r * (1 + 0.22 * self.n())
            pts.append((x + math.cos(a) * rr, y + math.sin(a) * rr * 0.75))
        pts = [(x - r * 1.05, y)] + pts[1:-1] + [(x + r * 1.05, y)]
        self.line(pts, 0.85, c, 0.3)
        self.seg(x - r * 1.1, y, x + r * 1.1, y, 0.6, SOFT, 0.2)
        if shade:
            for k in range(3):
                t = 0.3 + k * 0.2
                self.seg(x + r * t, y - r * 0.55 * (1 - t) - 0.5, x + r * (t + 0.15), y - 0.6, 0.5, SOFT, 0.1)

    def mist(self, x, y, w=24, rows=3, c=SOFT):
        for k in range(rows):
            yy = y + k * 3.2
            xs = x - w / 2 + (k % 2) * 3
            self.line([(xs + i * w / 10, yy + math.sin(i * 1.2 + k) * 1.1) for i in range(9)], 0.6, c, 0.2, step=3)

    def sparkle(self, x, y, r=2.5, c=GOLD):
        self.seg(x - r, y, x + r, y, 0.5, c, 0)
        self.seg(x, y - r, x, y + r, 0.5, c, 0)

    def shadow(self, x, y, w):
        for k in range(4):
            xx = x - w / 2 + k * w / 4 + 1
            self.seg(xx, y + 0.8, xx + 2.4, y + 2.6, 0.5, SOFT, 0.1)


# ======================================================================
# Items (about 22 pt across)
# ======================================================================

def it_keys(p):
    p.ell(-4, -3, 4, 4, w=0.9)
    for k, (ang, ln) in enumerate(((60, 11), (110, 9))):
        a = math.radians(ang)
        x0, y0 = -4 + math.cos(a) * 4, -3 + math.sin(a) * 4
        x1, y1 = x0 + math.cos(a) * ln, y0 + math.sin(a) * ln
        p.ell(x0 + math.cos(a) * 2.2, y0 + math.sin(a) * 2.2, 2.2, 2.2, w=0.8)
        p.seg(x0 + math.cos(a) * 4.4, y0 + math.sin(a) * 4.4, x1, y1, 0.9)
        bx, by = -math.sin(a), math.cos(a)
        p.line([(x1 - math.cos(a) * 1, y1 - math.sin(a) * 1), (x1 - math.cos(a) * 1 + bx * 2.2, y1 - math.sin(a) * 1 + by * 2.2),
                (x1 - math.cos(a) * 3 + bx * 2.2, y1 - math.sin(a) * 3 + by * 2.2), (x1 - math.cos(a) * 3, y1 - math.sin(a) * 3)], 0.8, wob=0.1)


def it_lamp(p):
    # brass lantern: bail, cap, glass with flame, base
    p.ell(0, -10, 3.5, 3, 180, 360, 0.8)
    p.line([(-4, -7), (4, -7), (3, -5), (-3, -5)], 0.9, closed=True, wob=0.2)
    p.line([(-3.5, -5), (-4, 4), (4, 4), (3.5, -5)], 0.9, wob=0.25)
    for x in (-1.5, 1.5):
        p.seg(x, -5, x * 1.15, 4, 0.5, SOFT)
    p.line([(0, 1.5), (-1, -0.5), (0, -3), (1, -0.5), (0, 1.5)], 0.7, GOLD, 0.1)
    p.line([(-5, 4), (5, 4), (5, 7), (-5, 7)], 0.9, closed=True, wob=0.2)
    p.hatch([(1.5, 4.3), (5, 4.3), (5, 6.8), (1.5, 6.8)], 60, 1.3)
    p.shadow(0, 7, 10)


def it_food(p):
    # a loaf on a cloth
    pts = p.ell(0, 0, 9, 5, 180, 360, 1.0)
    p.seg(-9, 0, 9, 0, 1.0)
    for x in (-4, 0, 4):
        p.line([(x - 1.5, -3.6), (x + 1.5, -1.6)], 0.7, wob=0.1)
    p.hatch([(3, -3.5), (8.5, -1.5), (8.5, -0.3), (3, -0.3)], 70, 1.4)
    p.line([(-11, 0.5), (11, 0.5), (8, 3.5), (-12, 3)], 0.6, SOFT, closed=True)


def it_bottle(p):
    p.line([(-1.5, -11), (-1.5, -7), (-4.5, -3), (-4.5, 8), (4.5, 8), (4.5, -3), (1.5, -7), (1.5, -11)], 0.9, wob=0.2)
    p.line([(-2, -11.5), (2, -11.5)], 1.1, BROWN, 0.1)
    p.seg(-2.6, -1, -2.6, 6, 0.6, SOFT)
    p.hatch([(1.8, -2), (4.3, -2.5), (4.3, 7.8), (1.8, 7.8)], 80, 1.3)
    p.shadow(0, 8, 9)


def it_cage(p):
    # wicker cage: dome of ribs on a base ring, with a ring handle
    p.ell(0, 6, 8, 2.4, w=0.9)
    for k in range(7):
        x = -8 + k * 16 / 6
        top = -7 + abs(x) * abs(x) * 0.09
        p.line([(x, 6 + math.sqrt(max(0, 1 - (x / 8) ** 2)) * 2.4 * (1 if k % 2 else -1) * 0.2), (x * 0.95, top), (0, -8)], 0.6, BROWN, 0.15)
    for yy, rr in ((0, 7.7), (-4, 6)):
        p.ell(0, yy, rr, 1.8, 0, 180, 0.6, BROWN)
    p.ell(0, -10, 1.8, 1.8, w=0.8)
    p.shadow(0, 8.5, 14)


def it_rod(p):
    p.line([(-10, 5), (8, -5)], 1.6, INK, 0.2)
    # rusty star on the end
    cx, cy = 9.5, -6
    pts = []
    for i in range(11):
        r = 3 if i % 2 == 0 else 1.3
        a = -math.pi / 2 + i * math.pi / 5
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    p.line(pts, 0.7, BROWN, 0.1)


def it_bird(p):
    # little bird perched on a twig
    p.ell(0, 0, 5.5, 4, 150, 390, 0.9)
    p.ell(-5.8, -3.4, 2.6, 2.4, w=0.9)
    p.ell(-6.3, -3.9, 0.4, 0.4, w=0.8, n=6)
    p.line([(-8.3, -3.4), (-10.6, -2.6), (-8.2, -2.4)], 0.8, wob=0.05)
    p.line([(-1, -1.5), (3, -2.5), (5.5, 0.5)], 0.7, SOFT, 0.2)     # wing
    p.line([(5, -0.5), (10, -3), (10.5, -1.5), (5.5, 1.5)], 0.8, wob=0.1)  # tail
    for x in (-1.5, 1):
        p.seg(x, 3.6, x - 0.5, 6.4, 0.7)
    p.line([(-9, 6.5), (9, 6.2)], 0.9, BROWN, 0.4)
    p.seg(5, 6.3, 8, 4.5, 0.6, BROWN)


def it_pillow(p):
    p.line([(-10, -5), (0, -6.5), (10, -5), (11, 0), (10, 5), (0, 6), (-10, 5), (-11, 0)], 1.0, closed=True, wob=0.5)
    for (x, y) in ((-10, -5), (10, -5), (10, 5), (-10, 5)):
        p.seg(x, y, x + math.copysign(2, x), y + math.copysign(1.5, y), 0.7, GOLD)
    p.hatch([(2, 1), (9.5, -3.5), (10, 4.5), (2, 5.2)], 35, 1.6)
    p.line([(-6, -1), (-2, 0.5)], 0.5, SOFT)


def it_clam(p):
    # a giant clam, shell slightly open
    top = [(-12, 1), (-9, -6), (-3, -9), (3, -9), (9, -6), (12, 1)]
    p.line(top, 1.1, wob=0.3)
    p.line([(-12, 1), (-6, 3), (0, 2), (6, 3), (12, 1)], 0.9, wob=0.2)
    p.line([(-12, 2), (-9, 6), (-3, 8), (3, 8), (9, 6), (12, 2)], 1.1, wob=0.3)
    for k in range(-3, 4):
        p.seg(k * 3.2, 1.5, k * 2.4, -8 + abs(k) * 0.7, 0.5, SOFT, 0.1)
        p.seg(k * 3.2, 3.4, k * 2.6, 7.4 - abs(k) * 0.5, 0.45, SOFT, 0.1)
    p.shadow(0, 8.5, 20)


def it_magazine(p):
    p.line([(-8, -10), (8, -9), (7, 10), (-9, 9)], 0.9, closed=True, wob=0.3)
    p.text('Spelunker', -0.5, -6, 4.2, 3)
    p.text('Today', -0.5, -2.2, 4.2, 3)
    p.ell(-0.5, 4, 4, 3, w=0.6, c=SOFT)
    p.seg(-3, 4.5, 2, 3, 0.5, SOFT)


def it_urn(p):
    p.line([(-4, -10), (4, -10)], 0.9, wob=0.1)
    p.line([(-3, -10), (-3, -7), (-8, -3), (-8, 3), (-4, 8), (4, 8), (8, 3), (8, -3), (3, -7), (3, -10)], 1.0, wob=0.3)
    p.line([(-5, 8), (5, 8), (5, 9.5), (-5, 9.5)], 0.8, closed=True, wob=0.1)
    p.ell(0, -1, 7, 1.5, 0, 180, 0.5, SOFT)
    p.hatch([(3, -6), (7.6, -2.5), (7.6, 3), (4, 7.6), (2.5, 7.6)], 70, 1.4)


def it_rabbitfoot(p):
    p.line([(-3, -9), (3, -9), (4, -2), (6, 4), (3, 8), (-4, 8), (-6, 4), (-4, -2)], 0.9, closed=True, wob=0.6, step=3)
    for k in range(5):
        p.seg(-3 + k * 1.5, -6 + k * 2.5, -1 + k * 1.5, -4 + k * 2.5, 0.5, SOFT, 0.2)
    p.line([(-3, -9), (-2.5, -11.5), (2.5, -11.5), (3, -9)], 0.7, BROWN, 0.1)


def it_nugget(p):
    pts = [(-8, 2), (-7, -3), (-3, -6), (2, -5), (7, -3), (8, 2), (4, 5), (-4, 5)]
    p.line(pts, 1.0, GOLD, 0.5, closed=True)
    p.line([(-3, -6), (-1, 0), (4, 5)], 0.6, GOLD, 0.2)
    p.line([(-1, 0), (7, -3)], 0.6, GOLD, 0.2)
    p.hatch([(-1, 0), (7, -3), (8, 2), (4, 5)], 60, 1.4, c=GOLD)
    p.sparkle(-6, -6)
    p.shadow(0, 5, 14)


def it_diamonds(p):
    for k, (x, y, s) in enumerate(((-6, 1, 1.0), (4, 2, 0.85), (-0.5, -5, 0.7))):
        top = [(x - 4 * s, y - 2 * s), (x - 2 * s, y - 4.5 * s), (x + 2 * s, y - 4.5 * s), (x + 4 * s, y - 2 * s)]
        p.line(top + [(x, y + 4 * s), top[0]], 0.8, BLUE, 0.1)
        p.seg(x - 4 * s, y - 2 * s, x + 4 * s, y - 2 * s, 0.6, BLUE, 0.05)
        p.line([(x - 2 * s, y - 4.5 * s), (x - 1 * s, y - 2 * s), (x, y + 4 * s), (x + 1 * s, y - 2 * s), (x + 2 * s, y - 4.5 * s)], 0.45, BLUE, 0.05)
    p.sparkle(8, -5, 2.5, BLUE)


def it_silver(p):
    def bar(x, y):
        p.line([(x - 6, y), (x + 6, y), (x + 4, y - 3), (x - 4, y - 3)], 0.9, closed=True, wob=0.1)
        p.line([(x - 6, y), (x - 6, y + 2), (x + 6, y + 2), (x + 6, y)], 0.9, wob=0.1)
        p.hatch([(x - 6, y + 0.3), (x + 6, y + 0.3), (x + 6, y + 1.8), (x - 6, y + 1.8)], 0, 0.9)
    bar(-4, 5); bar(5, 5); bar(0.5, 0)
    p.sparkle(9, -4, 2.2, SOFT)


def it_jewelry(p):
    # a necklace hanging in a loop, with a jewelled pendant
    pts = [(math.cos(math.radians(a)) * 9, -6 + math.sin(math.radians(a)) * 9) for a in range(-10, 191, 10)]
    p.line(pts, 0.6, GOLD, 0.1, step=2)
    for i in range(1, len(pts) - 1, 2):
        p.ell(pts[i][0], pts[i][1], 1.0, 1.0, w=0.6, c=GOLD, n=6)
    p.line([(0, 3), (-2.6, 6), (0, 10), (2.6, 6), (0, 3)], 0.9, RED, 0.05)
    p.seg(-2.6, 6, 2.6, 6, 0.5, RED, 0)
    p.sparkle(5, 8, 2, RED)


def it_coins(p):
    for k, (x, y) in enumerate(((-6, 3), (1, 4), (7, 2), (-2, -1), (4, -3))):
        p.ell(x, y, 4, 1.6, w=0.9, c=GOLD)
        p.seg(x - 4, y, x - 4, y + 1.2, 0.8, GOLD)
        p.seg(x + 4, y, x + 4, y + 1.2, 0.8, GOLD)
        p.ell(x, y + 1.2, 4, 1.6, 0, 180, 0.8, GOLD)
    p.ell(-2, -1, 1.6, 0.6, w=0.5, c=GOLD)
    p.sparkle(-9, -5)


def it_eggs(p):
    # golden eggs in a twig nest
    for x, y in ((-4, -2), (3, -2.5), (0, -5)):
        p.ell(x, y, 3, 4, w=0.9, c=GOLD)
        p.seg(x + 1.2, y - 2, x + 2, y + 1, 0.5, GOLD)
    for k in range(7):
        p.line([(-11 + k * 0.5, -1 + k * 0.8), (0, 4 + k * 0.3), (11 - k * 0.5, -1 + k * 0.8)], 0.55, BROWN, 0.6, step=3)
    p.sparkle(8, -8)


def it_trident(p):
    p.seg(0, -9, 0, 12, 1.1)
    p.line([(-6, -12), (-6, -6), (6, -6), (6, -12)], 1.0, wob=0.2)
    for x in (-6, 0, 6):
        p.line([(x - 1.2, -11), (x, -14), (x + 1.2, -11)], 0.8, wob=0.05)
    for x, c in ((-3, RED), (3, BLUE), (0, GREEN)):
        p.ell(x, -6, 1.2, 1.2, w=0.7, c=c, n=6)


def it_vase(p):
    p.line([(-3, -11), (-3, -8), (-7, -3), (-7, 4), (-3, 10), (3, 10), (7, 4), (7, -3), (3, -8), (3, -11)], 1.0, wob=0.2)
    p.ell(0, -11, 3, 1, w=0.8)
    # blue willow-pattern decoration
    p.line([(-5, 0), (-2, -2), (1, 0), (4, -2), (6, 0)], 0.6, BLUE, 0.2)
    p.line([(-5, 3), (-2, 5), (1, 3), (4, 5), (6, 3)], 0.6, BLUE, 0.2)
    p.ell(0, -5, 1.5, 1.5, w=0.5, c=BLUE, n=6)
    p.shadow(0, 10, 9)


def it_emerald(p):
    pts = [(-6, -2), (-3, -7), (3, -7), (6, -2), (3, 7), (-3, 7)]
    p.line(pts, 1.0, GREEN, 0.15, closed=True)
    p.line([(-3, -2), (3, -2), (2, 3), (-2, 3)], 0.6, GREEN, 0.05, closed=True)
    for a, b in ((0, 0), (1, 1), (3, 2), (5, 3)):
        p.seg(pts[a][0], pts[a][1], [(-3, -2), (3, -2), (2, 3), (-2, 3)][b][0], [(-3, -2), (3, -2), (2, 3), (-2, 3)][b][1], 0.45, GREEN, 0.05)
    for k in range(8):
        a = k / 8 * 2 * math.pi + 0.3
        p.seg(math.cos(a) * 9, math.sin(a) * 9, math.cos(a) * 12, math.sin(a) * 12, 0.5, GREEN, 0.05)


def it_pyramid(p):
    p.line([(-9, 6), (0, -9), (9, 6), (-9, 6)], 1.0, wob=0.15)
    p.line([(0, -9), (3, 8.5), (9, 6)], 0.8, wob=0.15)
    p.seg(-9, 6, 3, 8.5, 0.8)
    p.hatch([(0, -8), (8.5, 5.8), (3.2, 8.2)], 75, 1.3)
    p.sparkle(-6, -6, 2.4, SOFT)


def it_spices(p):
    p.line([(-7, 8), (-8, -2), (-4, -6), (-5, -9), (5, -9), (4, -6), (8, -2), (7, 8)], 1.0, BROWN, 0.5, closed=True)
    p.line([(-4.5, -6), (4.5, -6)], 0.8, BROWN, 0.2)
    for x, y in ((-2, -10), (1, -11), (3, -10)):
        p.ell(x, y, 0.6, 0.6, w=0.6, c=RED, n=5)
    p.hatch([(3, -4), (7.5, -1), (6.8, 7.5), (3, 7.5)], 60, 1.4)


def it_chain(p):
    for k in range(6):
        x = -11 + k * 4.4
        y = math.sin(k * 0.9) * 2
        if k % 2 == 0:
            p.ell(x, y, 2.8, 1.6, w=0.8, c=GOLD)
        else:
            p.ell(x, y, 0.9, 1.8, w=0.8, c=GOLD)


def it_ruby(p):
    p.line([(-7, -2), (-4, -6), (4, -6), (7, -2), (0, 8), (-7, -2)], 1.0, RED, 0.15)
    p.seg(-7, -2, 7, -2, 0.6, RED)
    p.line([(-4, -6), (-2, -2), (0, 8), (2, -2), (4, -6)], 0.5, RED, 0.05)
    p.hatch([(2, -2), (7, -2), (0, 8)], 60, 1.2, c=RED)
    p.sparkle(-7, -7, 2.4, RED)


def it_sapphire(p):
    pts = []
    for i in range(11):
        r = 7 if i % 2 == 0 else 3
        a = -math.pi / 2 + i * math.pi / 5
        pts.append((math.cos(a) * r, math.sin(a) * r))
    p.line(pts, 0.9, BLUE, 0.1)
    p.ell(0, 0, 9.5, 9.5, w=0.6, c=BLUE)


def it_statuette(p):
    # an ebony figure: head, robed body, base
    p.ell(0, -9, 2.4, 2.8, w=0.9)
    p.line([(-2, -6.5), (-4.5, 0), (-3.5, 7), (3.5, 7), (4.5, 0), (2, -6.5)], 0.9, wob=0.2)
    p.line([(-5, 7), (5, 7), (5, 9.5), (-5, 9.5)], 0.9, closed=True, wob=0.1)
    p.hatch([(-2, -6), (2, -6), (4.3, 0), (3.3, 6.8), (-3.3, 6.8), (-4.3, 0)], 30, 1.0, c=INK, w=0.5)


def it_plant(p):
    p.line([(0, 8), (0.5, 2), (-0.5, -4), (0, -9)], 0.9, GREEN, 0.3)
    for k, (y, s) in enumerate(((3, 1), (-1, -1), (-5, 1))):
        p.line([(0, y), (5 * s, y - 3), (8 * s, y - 2), (4 * s, y + 0.5), (0, y)], 0.7, GREEN, 0.2)
    p.ground(-8, 8, 8)


def it_tablet(p):
    p.line([(-9, 8), (-9, -6), (-6, -10), (6, -10), (9, -6), (9, 8)], 1.0, wob=0.3)
    for k in range(5):
        y = -6 + k * 3
        p.line([(-6, y), (6, y)], 0.5, SOFT, 0.5, dash=(2, 1))
    p.ground(-12, 12, 8, tufts=False)


ITEMS = {
    'KEYS': it_keys, 'LAMP': it_lamp, 'FOOD': it_food, 'BOTTLE': it_bottle, 'CAGE': it_cage,
    'ROD': it_rod, 'BIRD': it_bird, 'PILLOW': it_pillow, 'CLAM': it_clam, 'MAGAZINE': it_magazine,
    'URN': it_urn, 'RABBITFOOT': it_rabbitfoot, 'NUGGET': it_nugget, 'OBJ_51': it_diamonds,
    'OBJ_52': it_silver, 'OBJ_53': it_jewelry, 'COINS': it_coins, 'EGGS': it_eggs,
    'TRIDENT': it_trident, 'VASE': it_vase, 'EMERALD': it_emerald, 'PYRAMID': it_pyramid,
    'OBJ_63': it_spices, 'CHAIN': it_chain, 'RUBY': it_ruby, 'SAPPH': it_sapphire,
    'OBJ_69': it_statuette,
}
ITEM_CAPTION = {
    'KEYS': 'keys', 'LAMP': 'lamp', 'FOOD': 'food', 'BOTTLE': 'bottle', 'CAGE': 'cage', 'ROD': 'rod',
    'BIRD': 'bird', 'PILLOW': 'pillow', 'CLAM': 'clam', 'MAGAZINE': 'magazine', 'URN': 'urn',
    'RABBITFOOT': 'rabbit foot', 'NUGGET': 'gold', 'OBJ_51': 'diamonds', 'OBJ_52': 'silver',
    'OBJ_53': 'jewelry', 'COINS': 'coins', 'EGGS': 'golden eggs', 'TRIDENT': 'trident',
    'VASE': 'Ming vase', 'EMERALD': 'emerald', 'PYRAMID': 'pyramid', 'OBJ_63': 'spices',
    'CHAIN': 'gold chain', 'RUBY': 'ruby', 'SAPPH': 'sapphire', 'OBJ_69': 'statuette',
}


# ======================================================================
# Scenes (about 44–56 pt across)
# ======================================================================

def sc_brick_building(p):
    # small brick building with the stream flowing out and down a gully
    p.line([(-16, -4), (8, -4), (8, 12), (-16, 12), (-16, -4)], 1.1, wob=0.3)
    p.line([(-19, -3), (-4, -14), (11, -3)], 1.1, wob=0.3)
    p.line([(-14, -5.5), (-4, -12.5), (6, -5.5)], 0.5, SOFT, 0.3)
    for row in range(5):
        y = -1 + row * 3
        p.line([(-16, y), (8, y)], 0.4, SOFT, 0.3)
        for col in range(5):
            x = -14 + col * 5 + (row % 2) * 2.5
            p.seg(x, y, x, y + 3, 0.4, SOFT, 0.1)
    p.line([(-8, 12), (-8, 4), (-3, 4), (-3, 12)], 0.9, wob=0.15)
    p.hatch([(-7.7, 4.3), (-3.3, 4.3), (-3.3, 11.8), (-7.7, 11.8)], 90, 1.1, c=INK, w=0.45)
    p.line([(2, 1), (6, 1), (6, 5), (2, 5)], 0.8, closed=True, wob=0.1)
    p.seg(4, 1, 4, 5, 0.5); p.seg(2, 3, 6, 3, 0.5)
    # stream out of the building
    for k in range(2):
        p.line([(8, 9 + k * 2.5), (14, 11 + k * 3), (18, 16 + k * 2), (24, 18 + k * 2)], 0.7, BLUE, 0.4)
    p.ground(-22, 6, 12)
    tree(p, 17, -2, 14)


def tree(p, x, y, s, c=INK):
    """a round deciduous tree, trunk base at (x, y + s/2)"""
    p.line([(x - 0.8, y + s * 0.5), (x - 0.5, y), (x + 0.5, y), (x + 0.9, y + s * 0.5)], 0.8, c, 0.2)
    pts = []
    for i in range(15):
        a = i / 14 * 2 * math.pi
        rr = 1 + 0.16 * p.n()
        pts.append((x + math.cos(a) * s * 0.38 * rr, y - s * 0.15 + math.sin(a) * s * 0.32 * rr))
    p.line(pts, 0.85, c, 0.35)
    for k in range(4):
        a = 0.2 + k * 0.35
        p.seg(x + math.cos(a) * s * 0.18, y - s * 0.12 + math.sin(a) * s * 0.12,
              x + math.cos(a) * s * 0.3, y - s * 0.1 + math.sin(a) * s * 0.18, 0.5, SOFT, 0.05)


def pine(p, x, y, s, c=INK):
    p.seg(x, y + s * 0.5, x, y + s * 0.3, 0.8, c)
    for k in range(3):
        yy = y - s * 0.45 + k * s * 0.24
        w = s * (0.14 + k * 0.08)
        p.line([(x - w, yy + s * 0.24), (x, yy), (x + w, yy + s * 0.24)], 0.8, c, 0.15)
        p.seg(x + w * 0.2, yy + s * 0.12, x + w * 0.7, yy + s * 0.22, 0.5, SOFT, 0.05)


def sc_well(p):
    # the well house's spring: a stone well head under a little roof
    p.line([(-12, -2), (-12, 10)], 1.0, wob=0.2)
    p.line([(12, -2), (12, 10)], 1.0, wob=0.2)
    p.ell(0, -2, 12, 3.2, w=1.0)
    p.ell(0, 10, 12, 3.2, 0, 180, 1.0)
    for row in range(3):
        y = 1 + row * 3.2
        p.ell(0, y, 12, 3.2, 0, 180, 0.4, SOFT)
        for col in range(4):
            x = -9 + col * 6 + (row % 2) * 3
            p.seg(x, y + 2.6, x, y + 5.6, 0.4, SOFT, 0.1)
    p.ell(0, -2, 9, 2, w=0.6, c=BLUE)
    p.wave(0, -1.6, 10, 0.6)
    for x in (-10, 10):
        p.seg(x, -3, x, -17, 1.0)
    p.line([(-14, -15), (0, -23), (14, -15)], 1.1, wob=0.2)
    p.hatch([(0, -22), (13, -15.3), (5, -15.3)], 70, 1.4)
    p.seg(-10, -12, 10, -12, 0.8)
    p.seg(2, -12, 2, -5, 0.5)
    p.line([(0, -5), (4, -5), (3.6, -2.5), (0.4, -2.5)], 0.7, BROWN, closed=True, wob=0.1)


def sc_hill_road(p):
    p.line([(-26, 10), (-14, 0), (-4, -4), (6, -3), (16, 3), (26, 9)], 1.0, wob=0.6)
    # road running over the hill
    p.line([(-10, 12), (-4, 2), (-1, -3.6)], 0.7, SOFT, 0.3)
    p.line([(4, 12), (2, 2), (1, -3.6)], 0.7, SOFT, 0.3)
    p.seg(-2.5, 6, -1.8, 3, 0.5, SOFT); p.seg(-1, 10, -0.5, 7, 0.5, SOFT)
    tree(p, -18, -6, 13); pine(p, 16, -6, 15); pine(p, 22, -3, 11)
    # the building in the distance
    p.line([(-26, -9), (-21, -9), (-21, -6), (-26, -6)], 0.5, SOFT, closed=True, wob=0.05)
    p.line([(-27, -9), (-23.5, -11.5), (-20, -9)], 0.5, SOFT, 0.05)


def sc_stream_valley(p):
    for k in range(2):
        p.line([(-24, -10 + k * 5), (-12, -5 + k * 4), (-2, -6 + k * 5), (10, 1 + k * 4), (24, 3 + k * 5)], 0.8, BLUE, 0.6)
    for x, y in ((-14, -2), (2, -1), (12, 9), (-6, -10)):
        p.rock(x, y, 3.2)
    p.wave(-3, -2.5, 6, 0.6); p.wave(15, 5, 6, 0.6)
    pine(p, -20, -16, 12); tree(p, 19, -9, 13)


def sc_road_end(p):
    p.line([(26, 6), (8, 3), (-6, 2)], 0.7, SOFT, 0.4)
    p.line([(26, 13), (8, 9), (-6, 6)], 0.7, SOFT, 0.4)
    p.line([(-6, 2), (-9, 4), (-6, 6)], 0.6, SOFT, 0.3)
    for x, y, s in ((-16, -2, 16), (-6, -10, 14), (6, -9, 13), (-22, 8, 12)):
        (pine if (x // 3) % 2 else tree)(p, x, y, s)
    p.ground(-26, 26, 14)


def sc_cliff(p):
    # forest thins to a cliff; a small ledge across the chasm to the west
    p.line([(26, -6), (6, -6), (4, 0), (6, 6), (3, 12), (5, 18)], 1.1, wob=0.5)
    p.hatch([(6, -5.6), (4.4, 0), (6.4, 6), (3.4, 12), (5.4, 18), (9, 18), (9, -5.6)], 80, 1.6)
    p.line([(-26, -2), (-16, -2), (-14, 3), (-17, 10), (-15, 18)], 1.1, wob=0.5)
    p.line([(-16, -2), (-12, -2), (-12, 0), (-15, 0.5)], 0.9, wob=0.1)   # the ledge
    p.hatch([(-26, -1.6), (-16.4, -1.6), (-14.4, 3), (-17.4, 10), (-15.4, 18), (-26, 18)], 80, 2.2)
    pine(p, 18, -14, 13); pine(p, 24, -12, 10)
    p.mist(-5, 14, 12, 2)


def sc_slit(p):
    for k in range(3):
        p.line([(-24, -8 + k * 3), (-12, -5 + k * 2), (-3, -1 + k * 0.6), (0, 0.5)], 0.7, BLUE, 0.4)
    p.line([(0, -1), (2, 0.5), (0, 2)], 0.9, wob=0.05)
    p.seg(-1, 0.5, 6, 0.5, 1.4, INK)
    p.line([(-26, 8), (-8, 6), (6, 6), (24, 10)], 0.8, SOFT, 0.5)
    p.line([(-26, -12), (-8, -10), (6, -6), (24, -8)], 0.8, SOFT, 0.5)
    for x, y in ((10, -2), (18, 4), (-16, 3)):
        p.rock(x, y, 2.6)


def sc_grate(p):
    # the 20-foot depression, a steel grate set in concrete, locked
    p.ell(0, 2, 26, 12, 190, 350, 0.9)
    for k in range(12):
        a = math.radians(195 + k * 13)
        x, y = math.cos(a) * 26, 2 + math.sin(a) * 12
        p.seg(x, y, x * 0.82, 2 + (y - 2) * 0.6, 0.5, SOFT, 0.1)
    # concrete frame in perspective
    fr = [(-13, 1), (13, 1), (16, 11), (-16, 11)]
    p.line(fr, 1.0, closed=True, wob=0.2)
    p.line([(-10, 3), (10, 3), (12, 9), (-12, 9)], 0.9, closed=True, wob=0.1)
    p.hatch([(-13, 1), (-10, 3), (-12, 9), (-16, 11)], 80, 1.5, c=SOFT)
    for k in range(1, 7):
        t = k / 7
        p.seg(-10 + 20 * t, 3, -12 + 24 * t, 9, 0.8, INK, 0.05)
    p.seg(-11, 6, 11, 6, 0.7, INK, 0.05)
    # padlock hanging from the front bar
    p.ell(3, 11.3, 1.7, 2, 180, 360, 0.8)
    p.line([(1, 11.5), (5, 11.5), (5.3, 16), (0.7, 16)], 0.9, closed=True, wob=0.05)
    p.ell(3, 13.4, 0.5, 0.6, w=0.6, n=5)
    p.seg(3, 13.8, 3, 15, 0.5)
    # dry streambed leading in
    p.line([(-30, -14), (-20, -8), (-12, -6)], 0.6, SOFT, 0.5, dash=(2, 1.5))
    p.line([(-27, -17), (-17, -11), (-9, -8)], 0.6, SOFT, 0.5, dash=(2, 1.5))
    p.rock(-24, -10, 2)


def sc_below_grate(p):
    # looking up at the grate: bars against daylight, light falling in
    p.line([(-11, -14), (11, -14), (11, -4), (-11, -4)], 1.0, closed=True, wob=0.1)
    for k in range(1, 5):
        x = -11 + k * 22 / 5
        p.seg(x, -14, x, -4, 0.8, INK, 0.05)
    p.seg(-11, -9, 11, -9, 0.7)
    for k in range(5):
        x = -9 + k * 4.5
        p.line([(x, -3), (x * 1.5, 12)], 0.5, GOLD, 0.1, dash=(2, 2))
    p.ground(-18, 18, 13, tufts=False)
    p.rock(-13, 13, 2.5); p.rock(12, 13, 2)


def sc_cobbles(p):
    for k in range(18):
        x = -22 + (k % 9) * 5.4 + (k // 9) * 2.6 + p.n() * 1.4
        y = 2 + (k // 9) * 4.5 + p.n()
        p.ell(x, y, 2.4 + p.n() * 0.8, 1.6, w=0.7, c=INK if k % 3 else SOFT)
    p.line([(-26, -4), (-10, -6), (10, -6), (26, -4)], 0.9, wob=0.5)
    p.hatch([(-26, -10), (26, -10), (26, -4.5), (10, -6.5), (-10, -6.5), (-26, -4.5)], 70, 2)
    p.text('dim light', 18, -14, 5, -4, SOFT)
    p.line([(26, 0), (30, 0)], 0.6, GOLD, 0.1)
    p.line([(26, 3), (30, 4)], 0.6, GOLD, 0.1)


def sc_debris(p):
    # mud and debris washed in, with the scrawl
    p.line([(-24, 10), (-14, 2), (-4, -1), (8, 0), (18, 4), (26, 10)], 1.0, BROWN, 0.6)
    for k in range(9):
        x = -18 + k * 4.5 + p.n() * 2
        y = 4 + p.n() * 2.5
        p.seg(x, y, x + 4 + p.n() * 2, y - 1.5 + p.n() * 2, 0.7, BROWN, 0.1)
    p.line([(-6, 3), (-3, 1), (-1, 3), (-3, 5), (-6, 3)], 0.6, GREEN, 0.15)  # a leaf
    p.line([(10, 5), (12, 2), (14, 5), (12, 7), (10, 5)], 0.6, GREEN, 0.15)
    p.text('MAGIC WORD', 0, -11, 5.5, -3, INK)
    p.text('XYZZY', 0, -5.5, 8, -3, INK, True)


def sc_awkward(p):
    p.line([(-24, -12), (-8, -6), (8, 2), (24, 10)], 1.0, wob=0.6)
    p.line([(-24, -2), (-8, 4), (8, 10), (24, 16)], 1.0, wob=0.6)
    p.hatch([(-24, -12), (24, 10), (24, 6), (-24, -16)], 15, 2.0)
    p.rock(-6, 1, 2); p.rock(10, 7, 1.6)


def sc_flowstone(p):
    # walls of frozen orange stone rivers, thirty feet high
    p.line([(-24, -16), (24, -16)], 0.9, wob=0.4)
    for k in range(8):
        x = -21 + k * 6
        L = 14 + p.n() * 10 + (k % 3) * 4
        p.line([(x, -16), (x + 1.2, -16 + L * 0.4), (x - 0.8, -16 + L * 0.7), (x + 0.6, -16 + L)], 0.8, GOLD, 0.4)
        p.ell(x + 0.6, -16 + L + 1, 1, 0.8, w=0.6, c=GOLD, n=6)
        if k % 2:
            p.seg(x + 2.3, -15, x + 2.6, -16 + L * 0.6, 0.5, BROWN)
    p.ground(-24, 24, 16, tufts=False)


def sc_steps_pit(p):
    # small pit breathing white mist; rough stone steps lead down
    p.ell(-6, 4, 12, 5, w=1.0)
    p.hatch([(-17, 4), (5, 4), (3, 7), (-6, 8.8), (-15, 7)], 0, 1.3)
    p.mist(-6, -6, 18, 3)
    for k in range(4):
        x = 10 + k * 3.5
        y = 8 - k * 4
        p.line([(x, y), (x, y - 4), (x + 4, y - 4)], 0.9, wob=0.2)
    p.line([(9, 9), (24, 9)], 0.7, SOFT, 0.3)


def sc_staircase(p):
    # the wide stone staircase going down, mist swaying, cold wind
    for k in range(6):
        y = -10 + k * 4
        w = 10 + k * 3
        p.line([(-w, y), (w, y)], 0.9, wob=0.3)
        p.seg(-w, y, -w - 1.5, y + 4, 0.6, SOFT); p.seg(w, y, w + 1.5, y + 4, 0.6, SOFT)
    p.hatch([(-10, -10), (-8, -10), (-25, 14), (-27, 14)], 60, 1.5)
    p.mist(0, -20, 34, 3)
    p.line([(-20, 18), (-10, 16), (0, 18), (10, 15)], 0.5, SOFT, 0.6)  # cold wind
    p.ell(26, -14, 8, 6, 180, 360, 0.8)   # the dome behind


def sc_fissure(p):
    p.line([(-14, -18), (-8, -10), (-11, -2), (-6, 6), (-10, 18)], 1.1, wob=0.4)
    p.line([(4, -18), (9, -10), (6, -2), (11, 6), (7, 18)], 1.1, wob=0.4)
    p.hatch([(-14, -18), (4, -18), (9, -10), (6, -2), (11, 6), (7, 18), (-10, 18), (-6, 6), (-11, -2), (-8, -10)], 90, 1.2, c=INK, w=0.4)
    p.mist(-2, -8, 32, 2); p.mist(-2, 8, 32, 2)


def sc_note(p):
    # crude note on the wall
    p.line([(-14, -10), (14, -11), (13, 9), (-15, 10)], 0.9, closed=True, wob=0.4)
    p.text("You won't", -0.5, -5, 5.5, -2)
    p.text('get it up', -0.5, 0, 5.5, -2)
    p.text('the steps', -0.5, 5, 5.5, -2)
    p.ell(-12, -8.5, 0.8, 0.8, w=0.6, n=5)


def sc_snake(p):
    # the fierce green snake, coiled
    for k, r in enumerate((13, 9.5, 6)):
        p.ell(0, 4 + k * -0.5, r, r * 0.45, 0, 360, 1.0, GREEN, 0.4)
        p.ell(0, 4 + k * -0.5, r, r * 0.45, 0, 180, 0.5, SOFT)
    p.line([(4, 1), (8, -6), (6, -12), (1, -14)], 1.2, GREEN, 0.2)
    p.ell(-1.5, -14, 3.6, 2.4, w=1.1, c=GREEN)
    p.ell(-2.5, -14.8, 0.5, 0.5, w=0.8, n=5)
    p.line([(-5, -13.6), (-8, -13.6), (-10, -15), (-8, -13.6), (-10, -12.4)], 0.6, RED, 0.05)
    for k in range(6):
        x = -10 + k * 4
        p.seg(x, 5.5, x + 1.5, 7.5, 0.5, GREEN, 0.05)


def sc_twopit(p, slabs=False, plant=True):
    p.line([(-26, -2), (-18, -2)], 1.0)
    p.ell(-10, -2, 8, 4, 0, 180, 1.0)
    p.line([(-2, -2), (2, -2)], 1.0)
    p.ell(10, -2, 8, 4, 0, 180, 1.0)
    p.line([(18, -2), (26, -2)], 1.0)
    p.hatch([(-18, -2), (-2, -2), (-6, 1.5), (-14, 1.5)], 0, 1.2)
    p.hatch([(2, -2), (18, -2), (14, 1.5), (6, 1.5)], 0, 1.2)
    p.ell(-16, -14, 4, 3, w=0.9)   # the large hole in the wall above the west pit
    p.hatch([(-19, -14), (-13, -14), (-14, -12), (-18, -12)], 0, 1.0, c=INK, w=0.4)
    if plant:
        for s in (-1, 1):
            p.line([(-10, -2), (-10 + s * 2, -6), (-10 + s * 4, -7)], 0.7, GREEN, 0.2)
    if slabs:
        for k in range(4):
            x = 6 + k * 4
            p.line([(x, -5), (x + 3.5, -4), (x + 3, -3), (x - 0.5, -4)], 0.6, wob=0.1, closed=True)


def sc_oil_pool(p):
    p.ell(0, 0, 22, 10, 180, 360, 1.0)
    p.ell(0, 0, 22, 4, 0, 180, 1.0)
    p.ell(8, 1, 7, 2.2, w=0.8)
    p.hatch([(1.5, 1), (8, -1.2), (14.5, 1), (8, 3.2)], 0, 0.8, c=INK, w=0.45)
    p.text('oil', 8, 7, 5.5, 0, SOFT)


def sc_hole_floor(p):
    p.ell(0, 0, 11, 4.5, w=1.1)
    p.hatch([(-10, 0), (10, 0), (7, 3.2), (0, 4.3), (-7, 3.2)], 0, 1.0, c=INK, w=0.45)
    p.line([(-24, 0), (-14, 0)], 0.8, wob=0.3)
    p.line([(14, 0), (24, 0)], 0.8, wob=0.3)


def sc_y2(p):
    p.line([(-14, 8), (-12, -2), (-6, -9), (6, -10), (13, -3), (15, 8)], 1.1, wob=0.5)
    p.line([(-16, 8), (17, 8)], 0.8, SOFT, 0.3)
    p.text('Y2', 0, -1, 11, 0, INK, True)
    p.hatch([(8, -8), (13, -3), (15, 7.6), (10, 7.6)], 70, 1.5)
    for x in (-24, 22):
        p.rock(x, 8, 2.2)


def sc_jumble(p):
    for k, (x, y, r) in enumerate(((-12, 6, 6), (0, 4, 8), (12, 7, 5), (-6, -5, 5), (7, -6, 6), (0, -14, 4))):
        p.rock(x, y, r)
    for k in range(4):
        x = -16 + k * 10
        p.line([(x, 10), (x + 2, 13), (x + 1, 16)], 0.5, wob=0.3)


def sc_window(p):
    # low window on the huge pit; a shadowy figure across in the same window
    p.line([(-12, 10), (-12, -4)], 1.1, wob=0.2)
    p.ell(0, -4, 12, 10, 180, 360, 1.1)
    p.line([(12, -4), (12, 10)], 1.1, wob=0.2)
    p.line([(-15, 10), (15, 10)], 1.0, wob=0.2)
    p.hatch([(-11.5, -4), (11.5, -4), (11.5, 9.6), (-11.5, 9.6)], 45, 2.6, c=SOFT, w=0.4)
    p.mist(0, 5, 18, 2)
    # the figure
    p.ell(0, -6, 1.8, 2, w=0.9)
    p.line([(-2.5, 4), (-2, -3.5), (2, -3.5), (2.5, 4)], 1.0, wob=0.2)
    p.hatch([(-2.2, -3.2), (2, -3.2), (2.4, 3.8), (-2.4, 3.8)], 20, 0.9, c=INK, w=0.5)


def sc_dusty(p):
    for x, y, r in ((-14, 6, 4), (-4, 8, 3), (12, 7, 4.5), (18, -4, 3)):
        p.rock(x, y, r)
    p.ell(0, -4, 9, 3.5, w=1.0)
    p.hatch([(-8, -4), (8, -4), (5, -1.2), (-5, -1.2)], 0, 1.0, c=INK, w=0.45)
    for k in range(10):
        p.ell(-22 + k * 4.5 + p.n() * 2, 13 + p.n() * 2, 0.4, 0.3, w=0.5, c=SOFT, n=4)


def sc_small_pit(p, stream=False):
    p.ell(0, -2, 12, 5, w=1.0)
    p.hatch([(-11, -2), (11, -2), (8, 1.5), (0, 3), (-8, 1.5)], 0, 1.1, c=INK, w=0.45)
    if stream:
        p.wave(0, 9, 22, 1.2)
        p.wave(0, 12, 18, 1.0)
    else:
        for k in range(3):
            p.seg(14 + k * 3, -6 + k * 3, 17 + k * 3, -6 + k * 3, 0.8)


def sc_column_pit(p):
    p.ell(0, 6, 18, 6, w=1.0)
    p.hatch([(-17, 6), (17, 6), (12, 10), (0, 11.8), (-12, 10)], 0, 1.3, c=INK, w=0.45)
    p.line([(-14, 4), (-15, -20)], 1.2, GOLD, 0.6)
    p.line([(-9, 2.5), (-9.5, -20)], 1.2, GOLD, 0.6)
    for k in range(5):
        y = -16 + k * 4
        p.ell(-12, y, 3, 0.9, 0, 180, 0.6, GOLD)


def sc_holes(p):
    for k, (x, y, rx) in enumerate(((-16, -6, 5), (-2, -10, 4), (12, -4, 6), (-10, 6, 4), (6, 8, 5), (20, 8, 3))):
        p.ell(x, y, rx, rx * 0.45, w=0.9)
        p.hatch([(x - rx * 0.8, y), (x + rx * 0.8, y), (x + rx * 0.5, y + rx * 0.35), (x - rx * 0.5, y + rx * 0.35)], 0, 0.9, c=INK, w=0.4)


def sc_swiss(p):
    p.line([(-18, 10), (-18, -8), (14, -10), (18, 10)], 1.1, wob=0.4)
    p.line([(-18, 10), (18, 10)], 0.9)
    for x, y, r in ((-10, -2, 3), (-2, 4, 2), (6, -4, 3.4), (12, 4, 2), (-12, 6, 1.5), (2, -7, 1.6)):
        p.ell(x, y, r, r * 0.8, w=0.8)
        p.hatch([(x - r * 0.7, y - r * 0.1), (x + r * 0.7, y - r * 0.1), (x + r * 0.4, y + r * 0.6), (x - r * 0.4, y + r * 0.6)], 0, 0.8, c=INK, w=0.4)


def sc_slab(p):
    p.line([(-24, 4), (-18, -4), (20, -6), (26, 3), (-24, 4)], 1.1, wob=0.3)
    p.line([(-24, 4), (-24, 8), (26, 7), (26, 3)], 1.0, wob=0.3)
    p.hatch([(-24, 4.3), (26, 3.3), (26, 6.8), (-24, 7.8)], 0, 1.1)
    for x, y, r in ((-28, -6, 4), (-22, -10, 3), (28, -6, 4), (24, -11, 3)):
        p.rock(x, y, r)


def sc_giant_room(p):
    p.line([(-26, -16), (-26, 12)], 0.9, wob=0.5)
    p.text('FEE FIE', 0, -9, 8, -4, INK, True)
    p.text('FOE FOO', 2, -1, 8, -4, INK, True)
    p.text('[sic]', 18, 6, 5, -4, SOFT)
    p.line([(-26, 12), (26, 12)], 0.7, SOFT, 0.5)
    for k in range(5):
        p.seg(-25, -12 + k * 5, -22, -10 + k * 5, 0.5, SOFT)


def sc_cavein(p):
    for k in range(10):
        x = -14 + (k % 5) * 7 + p.n() * 2
        y = 8 - (k // 5) * 6 + p.n() * 2
        p.rock(x, y, 4 - (k // 5) + p.n())
    p.line([(-20, 12), (20, 12)], 0.7, SOFT)
    p.line([(-20, -14), (-14, -8), (-16, -2)], 0.5, wob=0.3)
    p.line([(14, -14), (18, -6)], 0.5, wob=0.3)


def sc_door(p):
    # a massive rusty iron door
    p.line([(-11, 16), (-11, -10), (0, -18), (11, -10), (11, 16)], 1.2, wob=0.2)
    p.line([(-8, 16), (-8, -8.5), (0, -15), (8, -8.5), (8, 16)], 0.9, wob=0.2)
    for y in (-6, 10):
        p.line([(-11, y), (-4, y), (-4, y + 2.5), (-11, y + 2.5)], 0.8, BROWN, 0.1)
    for x in (-5, 5):
        for y in (-4, 2, 8, 13):
            p.ell(x, y, 0.6, 0.6, w=0.6, n=5)
    p.ell(5.5, 4, 1.4, 1.4, w=0.8)
    p.hatch([(2, -12), (7.6, -8.3), (7.6, 15.6), (2, 15.6)], 70, 1.7, c=BROWN)
    p.ground(-20, 20, 16, tufts=False)


def sc_waterfall(p):
    p.line([(-16, -16), (-6, -14), (6, -15), (16, -13)], 1.0, wob=0.4)
    p.hatch([(-16, -22), (16, -22), (16, -13.4), (6, -15.4), (-6, -14.4), (-16, -16.4)], 75, 2.2)
    for k in range(6):
        x = -7 + k * 2.8
        p.line([(x, -14), (x + 0.6, -6), (x - 0.3, 2), (x + 0.4, 6)], 0.6, BLUE, 0.3)
    # the roaring whirlpool
    pts = []
    for i in range(48):
        a = i / 48 * 4 * math.pi
        r = 2 + i * 0.32
        pts.append((math.cos(a) * r, 11 + math.sin(a) * r * 0.32))
    p.line(pts, 0.8, BLUE, 0.15, step=2)
    p.sparkle(-12, -6, 2, BLUE); p.sparkle(13, -4, 1.6, BLUE)


def sc_soft_room(p):
    # heavy curtains on the walls, thick pile carpet, moss on the ceiling
    p.line([(-24, -16), (24, -16)], 0.9, GREEN, 0.6)
    for k in range(8):
        x = -21 + k * 6
        p.seg(x, -15, x - 1, -13, 0.5, GREEN)
    for k in range(7):
        x = -22 + k * 7.3
        p.line([(x, -14), (x + 2, -4), (x - 1, 6), (x + 1, 12)], 0.8, RED, 0.5)
    p.line([(-24, -14), (24, -14)], 1.0, BROWN, 0.2)
    p.line([(-24, 12), (24, 12), (20, 16), (-20, 16)], 0.8, closed=True, wob=0.4)
    p.hatch([(-23, 12.4), (23, 12.4), (19.6, 15.6), (-19.6, 15.6)], 80, 0.9, c=SOFT)


def sc_drawings(p):
    # ancient oriental cave drawings
    p.line([(-26, -14), (26, -16), (26, 14), (-26, 14)], 0.9, SOFT, 0.6, closed=True)
    # a running deer
    p.line([(-18, -2), (-12, -4), (-8, -3), (-6, -6)], 0.9, BROWN, 0.2)
    p.line([(-6, -6), (-5, -9), (-7, -10)], 0.7, BROWN, 0.1)
    p.line([(-5, -9), (-3, -11)], 0.7, BROWN, 0.1)
    for x0, x1 in ((-17, -20), (-15, -13), (-10, -12), (-9, -6)):
        p.seg(x0, -2.5, x1, 3, 0.8, BROWN)
    # hunters
    for x in (6, 14):
        p.ell(x, -6, 1.4, 1.4, w=0.8, c=BROWN, n=6)
        p.line([(x, -4.6), (x, 1), (x - 2, 6)], 0.8, BROWN, 0.1)
        p.seg(x, 1, x + 2, 6, 0.8, BROWN)
        p.seg(x - 3, -2, x + 3, -4, 0.8, BROWN)
        p.seg(x + 3, -8, x - 5, 4, 0.6, BROWN)
    # sun
    p.ell(18, -10, 2.4, 2.4, w=0.7, c=RED)
    for k in range(8):
        a = k / 8 * 2 * math.pi
        p.seg(18 + math.cos(a) * 3.4, -10 + math.sin(a) * 3.4, 18 + math.cos(a) * 5, -10 + math.sin(a) * 5, 0.5, RED, 0)
    p.line([(-20, 9), (-10, 8), (0, 10), (10, 8), (20, 9)], 0.6, BROWN, 0.3, dash=(2, 1.5))


def sc_misty_cavern(p):
    p.line([(-26, -10), (-12, -14), (6, -14), (24, -10)], 1.0, wob=0.4)
    p.line([(-24, -4), (-10, -8), (8, -8), (22, -4)], 0.7, SOFT, 0.4, dash=(3, 2))
    p.mist(0, 2, 40, 4)
    for x in (-8, 6):
        p.text('splash', x, 16, 4.5, -8 if x < 0 else 6, SOFT)


def sc_glow_tunnel(p):
    p.line([(-24, -4), (0, -2.5), (16, -1.5)], 0.9, wob=0.3)
    p.line([(-24, 4), (0, 2.5), (16, 1.5)], 0.9, wob=0.3)
    p.ell(19, 0, 3, 3, w=0.8, c=GREEN)
    for k in range(7):
        a = -math.pi / 2 + k / 6 * math.pi
        p.seg(19 + math.cos(a) * 4.5, math.sin(a) * 4.5, 19 + math.cos(a) * 8, math.sin(a) * 8, 0.5, GREEN, 0.05)
    p.text('tight squeeze', -8, -9, 4.5, 0, SOFT)


def sc_arch(p):
    p.line([(-16, 14), (-16, -2)], 1.1, wob=0.3)
    p.ell(0, -2, 16, 14, 180, 360, 1.1)
    p.line([(16, -2), (16, 14)], 1.1, wob=0.3)
    p.line([(-11, 14), (-11, -2)], 0.7, wob=0.3)
    p.ell(0, -2, 11, 9.5, 180, 360, 0.7)
    p.line([(11, -2), (11, 14)], 0.7, wob=0.3)
    # coral and debris blocking the old passage
    for x, y in ((-4, 8), (2, 6), (6, 10)):
        p.line([(x, y + 6), (x, y), (x - 2, y - 3)], 0.7, RED, 0.2)
        p.seg(x, y + 1, x + 2.5, y - 2, 0.7, RED)
    p.rock(-6, 13, 3); p.rock(5, 13, 2.6)


def sc_shells(p):
    # sedimentary rock with bits of shell embedded in it
    for k in range(4):
        y = -10 + k * 6.5
        p.line([(-26, y + p.n() * 2), (-8, y + 1 + p.n() * 2), (8, y - 1 + p.n() * 2), (26, y + p.n() * 2)], 0.6, SOFT, 0.6)
    for k, (x, y, s) in enumerate(((-16, -3, 1), (-3, 4, 1.15), (9, -4, 0.9), (17, 8, 1.0), (-13, 10, 0.8), (3, -11, 0.75))):
        if k % 2:
            # coiled snail shell
            pts = [(x + math.cos(a) * (0.3 + a * 0.42) * s, y + math.sin(a) * (0.3 + a * 0.42) * s) for a in [i * 0.3 for i in range(27)]]
            p.line(pts, 0.75, INK, 0.05, step=1.5)
        else:
            # scallop: fan of ribs from the hinge, with two little ears
            fan = [(x + math.cos(math.radians(a)) * 4.4 * s, y + 1.5 * s - math.sin(math.radians(a)) * 4.4 * s) for a in range(10, 171, 16)]
            p.line([(x, y + 1.5 * s)] + fan + [(x, y + 1.5 * s)], 0.8, wob=0.1)
            for (fx, fy) in fan[1:-1]:
                p.seg(x, y + 1.5 * s, fx, fy, 0.4, SOFT, 0.05)
            p.line([(x - 2 * s, y + 1.5 * s), (x - 2 * s, y + 3 * s), (x + 2 * s, y + 3 * s), (x + 2 * s, y + 1.5 * s)], 0.6, wob=0.05)


def sc_sign(p, lines, w=30):
    h = 5 + len(lines) * 5.5
    p.line([(-w / 2, -h / 2), (w / 2, -h / 2 - 1), (w / 2 + 1, h / 2), (-w / 2, h / 2 + 0.5)], 1.0, closed=True, wob=0.4)
    for k, s in enumerate(lines):
        p.text(s, 0, -h / 2 + 5.2 + k * 5.5, 4.6, -1.5)
    return h


def sc_construction(p):
    h = sc_sign(p, ['Cave under construction', 'beyond this point.', 'Proceed at own risk.', '[Witt Construction Co.]'], 52)
    # "a sign in midair": little floating marks
    for x in (-18, 18):
        p.seg(x, h / 2 + 3, x, h / 2 + 6, 0.5, SOFT)
    p.line([(-26, 18), (-20, 16), (-14, 18)], 0.6, SOFT)
    p.line([(18, 16), (22, 14), (26, 17)], 0.6, SOFT)
    # remnants of digging: a shovel
    p.seg(-24, 6, -16, 15, 0.9, BROWN)
    p.line([(-16, 15), (-15, 18), (-12, 17), (-14, 14)], 0.8, closed=True, wob=0.1)


def sc_bear_sign(p):
    sc_sign(p, ['Caution!', 'Bear in room!'], 30)
    p.seg(-8, -9, -12, -17, 0.6); p.seg(8, -10, 12, -17, 0.6)


def sc_witts_end(p):
    for k in range(10):
        a = k / 10 * 2 * math.pi + 0.15
        r0, r1 = 6, 17 + (k % 2) * 4
        x0, y0, x1, y1 = math.cos(a) * r0, math.sin(a) * r0 * 0.7, math.cos(a) * r1, math.sin(a) * r1 * 0.7
        p.seg(x0, y0, x1, y1, 0.8)
        b = math.atan2(y1 - y0, x1 - x0)
        p.line([(x1 + math.cos(b + 2.6) * 2.6, y1 + math.sin(b + 2.6) * 2.6), (x1, y1), (x1 + math.cos(b - 2.6) * 2.6, y1 + math.sin(b - 2.6) * 2.6)], 0.8, wob=0.05)
    p.text('ALL', 0, 0.5, 5.5, 0, INK, True)


def sc_mirror(p):
    # the dwarves' enormous two-sided mirror, hanging from unseen heights
    for x in (-8, 8):
        p.line([(x, -24), (x, -12)], 0.6, wob=0.2, dash=(1.6, 1))
    p.line([(-10, -12), (10, -12), (10, 12), (-10, 12)], 1.1, closed=True, wob=0.2)
    p.line([(-8.5, -10.5), (8.5, -10.5), (8.5, 10.5), (-8.5, 10.5)], 0.6, closed=True, wob=0.1)
    for k in range(3):
        p.seg(-6 + k * 4, -6 + k, -2 + k * 4, -9 + k, 0.5, SOFT)
    p.mist(0, 18, 30, 2)
    p.line([(-24, -20), (-24, 20)], 0.8, wob=0.6)
    p.line([(24, -20), (24, 20)], 0.8, wob=0.6)


def sc_stalactite(p):
    p.line([(-20, -18), (20, -18)], 1.0, wob=0.5)
    p.line([(-7, -18), (-4, -6), (-2, 6), (0, 16), (2, 6), (4, -6), (8, -18)], 1.1, wob=0.3)
    for k in range(5):
        y = -15 + k * 6
        p.ell(0, y, 6 - k * 1.2, 1, 0, 180, 0.5, SOFT)
    p.hatch([(1, -17.6), (7.6, -17.6), (3.6, -6), (1.6, 6), (0.4, 14)], 80, 1.3)
    for x in (-15, 13):
        p.line([(x - 2, -18), (x, -12), (x + 2, -18)], 0.8, wob=0.1)
    p.ground(-20, 20, 20, tufts=False)


def sc_reservoir(p):
    # large underground lake, white mist rising, stream falling from a hole
    p.ell(-2, 6, 26, 9, w=1.0)
    for k, (x, y, w) in enumerate(((-12, 3, 10), (2, 6, 14), (-6, 10, 10), (12, 9, 8))):
        p.wave(x, y, w, 1.0)
    p.ell(20, -14, 3, 2, w=0.9)
    p.hatch([(17.5, -14), (22.5, -14), (21.5, -12.6), (18.5, -12.6)], 0, 0.8, c=INK, w=0.4)
    p.line([(19, -12), (16, -6), (14, 0), (13, 4)], 0.7, BLUE, 0.2)
    p.line([(21, -12), (18, -5), (16, 0), (15, 4)], 0.7, BLUE, 0.2)
    p.mist(-4, -10, 30, 3)


def sc_res_bottom(p):
    for x in (-20, 20):
        s = 1 if x < 0 else -1
        p.line([(x, 18), (x + s * 2, 0), (x, -18)], 1.0, BLUE, 0.6)
        for k in range(6):
            y = -15 + k * 6
            p.wave(x - s * 5, y, 9, 1.0)
    p.line([(-14, 18), (14, 18)], 0.7, SOFT)
    p.mist(0, -4, 20, 3)


def sc_shore(p):
    p.line([(-26, -2), (-10, -6), (8, -4), (26, -8)], 1.0, wob=0.6)
    for k, (x, y) in enumerate(((-14, -12), (2, -12), (16, -14), (-6, -17))):
        p.wave(x, y, 10, 1.0)
    for x, y in ((-18, 4), (10, 3)):
        p.rock(x, y, 2.4)


def sc_repository_ne(p):
    # bottles, a nursery of young beanstalks, oysters, black rods
    for k in range(4):
        x = -22 + k * 4
        p.line([(x - 1, -2), (x - 1, -5), (x - 2, -7), (x - 2, -12), (x + 2, -12), (x + 2, -7), (x + 1, -5), (x + 1, -2)], 0.6, wob=0.1)
    for k in range(3):
        x = -2 + k * 5
        p.line([(x, 0), (x + 0.5, -6), (x - 0.5, -12)], 0.7, GREEN, 0.3)
        p.line([(x + 0.3, -7), (x + 3, -9), (x + 0.4, -8.5)], 0.6, GREEN, 0.1)
    for k in range(3):
        x = 16 + k * 5
        p.ell(x, -4, 2.4, 1.4, w=0.7)
    for k in range(4):
        p.seg(-20 + k * 2, 6, -4 + k * 2, 2, 0.9)
    p.ground(-26, 28, 7, tufts=False)
    p.text('torches', 16, 14, 4.5, 0, SOFT)


def sc_repository_sw(p):
    # pit of snakes, wicker cages of sulking birds, pillows
    p.ell(-14, 4, 10, 4, w=1.0)
    for k in range(3):
        p.line([(-20 + k * 5, 4), (-18 + k * 5, 1), (-16 + k * 5, 3), (-15 + k * 5, 0)], 0.7, GREEN, 0.1)
    for k in range(3):
        x = 4 + k * 8
        p.ell(x, 4, 3.2, 1, w=0.6, c=BROWN)
        p.ell(x, 0, 3.2, 4, 180, 360, 0.6, BROWN)
        p.seg(x - 1, 0, x - 1, 4, 0.4, BROWN); p.seg(x + 1, 0, x + 1, 4, 0.4, BROWN)
        p.ell(x, 2.4, 1, 0.8, w=0.6, n=6)
    p.line([(-6, 12), (0, 11), (6, 12), (6, 15), (-6, 15)], 0.7, RED, closed=True, wob=0.3)


def sc_troll_bridge(p, troll=True):
    # a rickety wooden bridge over the misty chasm
    p.line([(-26, 0), (-14, 0), (-14, 14)], 1.0, wob=0.3)
    p.line([(26, 0), (14, 0), (14, 14)], 1.0, wob=0.3)
    pts = [(-14 + 28 * i / 10, 0 + math.sin(i / 10 * math.pi) * 3) for i in range(11)]
    p.line(pts, 0.9, BROWN, 0.1)
    p.line([(x, y - 5) for x, y in pts], 0.6, BROWN, 0.2)
    for x, y in pts[1:-1]:
        p.seg(x, y, x, y - 5, 0.5, BROWN)
    p.mist(0, 10, 22, 2)
    if troll:
        # a burly troll at the bridge head
        x, y = -20, -6
        p.ell(x, y - 8, 3, 3.2, w=1.0)
        p.line([(x - 2.4, y - 10.5), (x - 4.5, y - 13)], 0.8)
        p.line([(x + 2.4, y - 10.5), (x + 4.5, y - 13)], 0.8)
        p.ell(x - 1, y - 8.5, 0.5, 0.5, w=0.7, n=5)
        p.line([(x - 4, y - 5), (x - 6, y + 2), (x - 4, y + 6), (x + 4, y + 6), (x + 6, y + 2), (x + 4, y - 5), (x - 4, y - 5)], 1.0, wob=0.4)
        p.line([(x - 5, y - 3), (x - 9, y + 3), (x - 8, y + 6)], 0.9, wob=0.2)
        p.line([(x + 5, y - 3), (x + 8, y), (x + 9, y - 4)], 0.9, wob=0.2)
        p.seg(x - 2.5, y + 6, x - 3, y + 6, 0.9); p.seg(x + 2.5, y + 6, x + 3, y + 6, 0.9)
        p.hatch([(x + 1, y - 4.5), (x + 4, y - 4.5), (x + 5.6, y + 2), (x + 3.6, y + 5.6), (x + 1, y + 5.6)], 60, 1.2)
        p.text('troll', x, y + 11, 4.5, 0, SOFT)


def sc_dragon(p):
    # a huge green fierce dragon on a Persian rug
    p.line([(-26, 10), (22, 8), (26, 18), (-22, 20)], 0.9, RED, closed=True, wob=0.3)
    p.line([(-22, 12), (21, 10.5), (23.5, 16.5), (-19.5, 18)], 0.5, GOLD, closed=True, wob=0.2)
    for k in range(6):
        p.seg(-26 + k * 0.6, 10 + k * 1.7, -28.5 + k * 0.6, 10.5 + k * 1.7, 0.5, GOLD)
    # body
    body = [(-14, 8), (-16, 0), (-10, -6), (0, -7), (8, -3), (10, 4), (6, 9)]
    p.line(body, 1.2, GREEN, 0.4)
    p.line([(-14, 8), (6, 9)], 0.6, GREEN, 0.3)
    # neck and head
    p.line([(-10, -6), (-14, -12), (-15, -18)], 1.2, GREEN, 0.3)
    p.line([(-6, -7), (-9, -13), (-11, -18)], 1.1, GREEN, 0.3)
    p.line([(-16, -18), (-18, -21), (-13, -23), (-6, -21), (-5, -19), (-11, -18)], 1.1, GREEN, 0.2)
    p.ell(-13, -21, 0.6, 0.6, w=0.9, n=5)
    p.line([(-15, -23), (-17, -27)], 0.8, GREEN)
    p.line([(-12, -23.5), (-12, -27.5)], 0.8, GREEN)
    p.line([(-5, -19.5), (-1, -20), (2, -18), (-1, -18.5), (2, -16)], 0.6, RED, 0.15)   # flame
    # wing
    p.line([(-4, -7), (2, -18), (10, -22), (12, -14), (16, -16), (14, -8), (8, -3)], 1.0, GREEN, 0.3)
    for t in (0.35, 0.6):
        p.seg(-4 + 14 * t, -7 - 15 * t, 2 + 12 * t, -6 + 3 * t, 0.5, GREEN)
    # tail curling round
    p.line([(10, 4), (16, 6), (20, 2), (18, -3), (21, -5), (19, -4)], 1.0, GREEN, 0.3)
    # legs and claws
    for x in (-12, 2):
        p.line([(x, 8), (x - 1, 12), (x + 2, 12.5)], 1.0, GREEN, 0.15)
    for k in range(6):
        p.line([(-10 + k * 3, -1), (-9 + k * 3, -3), (-8 + k * 3, -1)], 0.5, GREEN, 0.05)
    p.hatch([(0, -7), (8, -3), (10, 4), (6, 8.6), (0, 8.6)], 55, 1.6, c=GREEN, w=0.45)


def sc_rumble(p, warm=False):
    p.line([(-26, -6), (26, -6)], 1.0, wob=0.5)
    p.line([(-26, 6), (26, 6)], 1.0, wob=0.5)
    c = RED if warm else SOFT
    for k in range(3):
        x = 14 + k * 4
        p.line([(x, -3), (x + 1.5, -1), (x, 1), (x + 1.5, 3)], 0.6, c, 0.05)
    if warm:
        for k in range(4):
            x = -18 + k * 7
            p.line([(x, -12), (x + 1.5, -15), (x, -18), (x + 1.5, -21)], 0.6, RED, 0.1)
    p.text('rumble' if not warm else 'warm', -6, 0.5, 5, 0, SOFT)


def sc_fork(p):
    p.line([(-26, -3), (-4, -3), (14, -16), (24, -18)], 0.9, wob=0.4)
    p.line([(-26, 4), (-4, 4), (14, 14), (24, 18)], 0.9, wob=0.4)
    p.line([(6, 2), (16, -8), (24, -10)], 0.9, wob=0.4)
    p.line([(6, 2), (16, 7), (24, 10)], 0.9, wob=0.4)
    p.text('NE', 18, -21, 4.5, 0, SOFT)
    p.text('SE', 18, 21, 4.5, 0, SOFT)


def sc_volcano(p):
    # far below, an active volcano throwing up gouts of molten lava
    p.line([(-26, 14), (-8, -4), (-3, -6), (3, -6), (8, -4), (26, 14)], 1.1, wob=0.4)
    p.hatch([(3, -6), (8, -4), (26, 14), (10, 14)], 70, 1.8)
    for k in range(5):
        a = math.radians(-150 + k * 30)
        p.line([(0, -7), (math.cos(a) * 6, -7 + math.sin(a) * 10), (math.cos(a) * 11, -7 + math.sin(a) * 12 + 4)], 0.8, RED, 0.3)
    for k in range(9):
        x, y = p.n() * 34, -16 + p.n() * 16
        p.ell(x, y, 0.5, 0.5, w=0.6, c=RED, n=4)
    p.line([(-2, -5), (-5, 2), (-3, 8), (-7, 14)], 0.8, RED, 0.3)
    p.line([(2, -5), (4, 3), (2, 9), (5, 14)], 0.8, RED, 0.3)
    p.line([(-30, -18), (-26, -24)], 0.5, SOFT)


def sc_boulders(p):
    for x, y, r in ((-12, 6, 8), (4, 7, 9), (16, 5, 6), (-4, -5, 6), (10, -6, 5)):
        p.rock(x, y, r)
    for k in range(3):
        x = -20 + k * 4
        p.line([(x, -10), (x + 1.4, -13), (x, -16), (x + 1.4, -19)], 0.6, RED, 0.1)


def sc_limestone(p):
    p.line([(-26, -16), (26, -16)], 0.9, wob=0.4)
    p.line([(-26, 16), (26, 16)], 0.9, wob=0.4)
    for k, x in enumerate((-18, -8, 2, 12, 20)):
        L = 8 + (k % 3) * 4
        p.line([(x - 1.5, -16), (x - 0.5, -16 + L * 0.5), (x - 1, -16 + L), (x + 1, -16 + L), (x + 0.5, -16 + L * 0.5), (x + 1.5, -16)], 0.8, wob=0.2)
        M = 6 + ((k + 1) % 3) * 3
        p.line([(x - 2, 16), (x - 1, 16 - M * 0.6), (x, 16 - M), (x + 1, 16 - M * 0.6), (x + 2, 16)], 0.8, wob=0.2)
        p.ell(x, 16 - M - 1, 1.2, 1, w=0.6, n=6)


def sc_bear(p):
    # a ferocious cave bear chained to the far wall
    x, y = 0, 0
    p.line([(-14, 6), (-15, -2), (-10, -8), (2, -9), (10, -5), (12, 2), (11, 8)], 1.2, BROWN, 0.6, step=3)
    p.ell(-15, -6, 5, 4.4, w=1.1, c=BROWN)
    p.ell(-17.5, -10, 1.4, 1.4, w=0.9, c=BROWN, n=6)
    p.ell(-12.5, -10.5, 1.4, 1.4, w=0.9, c=BROWN, n=6)
    p.ell(-17, -6, 0.5, 0.5, w=0.8, n=5)
    p.ell(-19.5, -4.6, 1.2, 0.9, w=0.8, n=6)
    for xx in (-11, -5, 5, 10):
        p.line([(xx, 4), (xx - 0.5, 9), (xx + 2.5, 9.5)], 1.0, BROWN, 0.2)
    p.seg(-14, 6, 11, 8, 0.7, BROWN)
    for k in range(8):
        p.seg(-8 + k * 2.6, -7 + (k % 3), -7 + k * 2.6, -4 + (k % 3), 0.5, BROWN, 0.05)
    # golden chain from collar to the wall
    for k in range(5):
        xx = 6 + k * 3.6
        if k % 2 == 0:
            p.ell(xx + 8, -10 + k * 0.5, 1.8, 1, w=0.8, c=GOLD)
        else:
            p.ell(xx + 8, -10 + k * 0.5, 0.6, 1.2, w=0.8, c=GOLD)
    p.line([(28, -18), (28, 10)], 1.0, wob=0.4)
    p.text('bear', -4, 15, 5, 0, SOFT)


def sc_vending(p):
    p.line([(-9, 16), (-9, -16), (9, -16), (9, 16)], 1.1, wob=0.2)
    p.line([(-6, -12), (6, -12), (6, 2), (-6, 2)], 0.8, closed=True, wob=0.1)
    for k in range(3):
        y = -9 + k * 4
        p.seg(-5, y, 5, y, 0.5, SOFT)
        for j in range(3):
            p.line([(-3.5 + j * 3.5, y - 0.5), (-3.5 + j * 3.5, y - 2.5)], 0.9, RED if j == 1 else BROWN, 0.05)
    p.line([(-5, 6), (5, 6), (5, 10), (-5, 10)], 0.8, closed=True, wob=0.1)
    p.seg(7, -4, 7, 0, 1.2)
    p.text('Batteries', 0, -14, 3.6, 0)
    p.ground(-14, 14, 16, tufts=False)


def sc_ogre(p):
    x = 0
    p.ell(x, -12, 4.4, 4.8, w=1.1)
    p.line([(x - 3, -13.5), (x - 1, -12.5)], 0.8)
    p.line([(x + 1, -12.5), (x + 3, -13.5)], 0.8)
    p.line([(x - 2.4, -9.5), (x - 1.6, -10.4), (x - 0.5, -9.5), (x + 0.6, -10.4), (x + 1.6, -9.5), (x + 2.4, -10.4)], 0.6, wob=0.05)
    p.line([(x - 6, -7), (x - 10, 4), (x - 7, 14), (x + 7, 14), (x + 10, 4), (x + 6, -7), (x - 6, -7)], 1.2, wob=0.5)
    p.line([(x - 7, -5), (x - 14, 4), (x - 13, 8)], 1.1, wob=0.2)
    p.line([(x + 7, -5), (x + 12, 2), (x + 16, -2)], 1.1, wob=0.2)
    # a club
    p.line([(x + 15, -1), (x + 19, -12), (x + 22, -13), (x + 21, -9), (x + 16.5, 0)], 1.0, BROWN, 0.2)
    p.line([(x - 4, 14), (x - 5, 18)], 1.1)
    p.line([(x + 4, 14), (x + 5, 18)], 1.1)
    p.hatch([(x + 1, -6.6), (x + 6, -6.6), (x + 9.6, 4), (x + 6.6, 13.6), (x + 1, 13.6)], 60, 1.4)
    p.text('ogre', x - 14, 16, 5, 0, SOFT)


def sc_bones(p):
    # remains of several earlier adventurers at the cliff's base
    p.ell(-8, 4, 4.5, 4, w=1.0)
    p.ell(-9.8, 3.6, 1.1, 1.3, w=0.8, n=6)
    p.ell(-6.2, 3.6, 1.1, 1.3, w=0.8, n=6)
    p.line([(-10, 8), (-10, 9.6), (-6, 9.6), (-6, 8)], 0.8, wob=0.05)
    for (x0, y0, x1, y1) in ((-2, 10, 14, 6), (0, 4, 12, 12), (16, 10, 24, 8)):
        p.seg(x0, y0, x1, y1, 1.0)
        for (x, y) in ((x0, y0), (x1, y1)):
            p.ell(x, y - 0.6, 0.8, 0.8, w=0.7, n=5)
            p.ell(x, y + 0.6, 0.8, 0.8, w=0.7, n=5)
    p.line([(-24, -18), (-22, -6), (-24, 4), (-22, 14)], 1.1, wob=0.5)
    p.hatch([(-30, -18), (-24, -18), (-22, -6), (-24, 4), (-22, 14), (-30, 14)], 80, 1.8)
    p.ground(-22, 26, 14, tufts=False)


def sc_cliff_face(p):
    p.line([(-6, -22), (-2, -10), (-6, 0), (-1, 10), (-5, 22)], 1.2, wob=0.5)
    p.hatch([(-14, -22), (-6, -22), (-2, -10), (-6, 0), (-1, 10), (-5, 22), (-14, 22)], 75, 1.6)
    for y in (-14, -4, 6, 16):
        p.line([(-3, y), (1, y), (0, y + 1.5)], 0.8, wob=0.05)
    p.text('footholds', 12, -2, 4.5, 0, SOFT)


def sc_ledge(p):
    p.line([(-22, -20), (-18, -6), (-6, -6), (-4, -3), (-18, -3), (-20, 20)], 1.1, wob=0.4)
    p.hatch([(-30, -20), (-22, -20), (-18, -3), (-20, 20), (-30, 20)], 80, 1.8)
    p.hatch([(-18, -5.6), (-6, -5.6), (-4.4, -3.4), (-18, -3.4)], 0, 0.9, c=SOFT)
    p.mist(8, 10, 24, 2)
    for x in (12, 20):
        pine(p, x, -16, 12)
    p.text('clearing', 16, -5, 4.5, 0, SOFT)


def sc_maze(p, different=False):
    # a little labyrinth doodle
    s = 3.6
    walls = [((0, 0), (8, 0)), ((8, 0), (8, 8)), ((8, 8), (0, 8)), ((0, 8), (0, 2)),
             ((2, 2), (6, 2)), ((6, 2), (6, 6)), ((6, 6), (2, 6)), ((2, 6), (2, 4)), ((2, 4), (4, 4)),
             ((0, 4), (1, 4)), ((4, 6), (4, 8)), ((6, 4), (8, 4))]
    for (a, b) in walls:
        p.seg((a[0] - 4) * s, (a[1] - 4) * s, (b[0] - 4) * s, (b[1] - 4) * s, 0.8 if not different else 0.7, INK, 0.3)
    p.text('all different' if different else 'all alike', 0, 19, 4.6, 0, SOFT)
    if different:
        p.text('?', 9 * s * 0.5, -5 * s, 7, 10, SOFT)


def sc_narrow(p):
    p.line([(-26, -3), (14, -3)], 0.9, wob=0.3)
    p.line([(-26, 3), (14, 3)], 0.9, wob=0.3)
    p.ell(18, 0, 4, 5, w=1.0)
    for k in range(5):
        a = k / 5 * 2 * math.pi
        x, y = 22 + math.cos(a) * 4, math.sin(a) * 5
        p.line([(x, y), (x + 3 * math.cos(a), y + 2 * math.sin(a) - 1.5), (x + 4.5 * math.cos(a), y + 3 * math.sin(a)), (x, y)], 0.6, GREEN, 0.1)


def sc_incline(p):
    p.line([(-24, -14), (-10, -14), (16, 14), (26, 14)], 1.1, wob=0.4)
    p.hatch([(-10, -13.6), (16, 14), (16, 18), (-10, 18)], 15, 1.8)
    p.text('no way back up', 6, -8, 4.5, 40, SOFT)


def sc_damp(p):
    for k in range(6):
        x = -18 + k * 7.4
        y = -6 + (k % 2) * 6
        p.line([(x, y - 3), (x - 1.4, y + 0.5), (x, y + 1.8), (x + 1.4, y + 0.5), (x, y - 3)], 0.7, BLUE, 0.05)
    p.line([(-24, -14), (24, -14)], 0.9, wob=0.4)
    p.text('damp', 0, 12, 5, 0, SOFT)


def sc_ragged(p):
    pts = []
    for k in range(14):
        pts.append((-26 + k * 4, -6 + (4 if k % 2 else 0) + k * 0.6))
    p.line(pts, 0.9, wob=0.15)
    pts = []
    for k in range(14):
        pts.append((-26 + k * 4, 6 - (4 if k % 2 else 0) + k * 0.6))
    p.line(pts, 0.9, wob=0.15)


def sc_hewn(p):
    p.line([(-4, -22), (-4, 22)], 1.0, wob=0.6)
    p.line([(4, -22), (4, 22)], 1.0, wob=0.6)
    for k in range(8):
        y = -18 + k * 5
        s = -1 if k % 2 else 1
        p.line([(s * 4, y), (s * 7, y + 1), (s * 6, y + 2.5)], 0.7, wob=0.05)
    # a pick
    p.seg(12, -6, 16, 8, 0.9, BROWN)
    p.ell(12, -6, 6, 2.5, 180, 360, 1.0, rot=20)


def sc_cul_de_sac(p):
    p.ell(0, 0, 10, 8, 200, 520, 1.1)
    p.text('8 ft', 0, 0.8, 5, 0, SOFT)


def sc_dead_end(p):
    p.line([(-12, -6), (12, -6)], 0.9, wob=0.2)
    p.line([(-12, 6), (12, 6)], 0.9, wob=0.2)
    p.line([(12, -6), (12, 6)], 1.4, wob=0.1)
    for k in range(3):
        p.seg(12, -4 + k * 4, 15, -2 + k * 4, 0.5, SOFT)
    p.text('dead end', -2, 0.8, 4.6, 0, SOFT)


def sc_long_hall(p):
    p.line([(-26, -8), (26, -3)], 0.9, wob=0.4)
    p.line([(-26, 8), (26, 3)], 0.9, wob=0.4)
    p.line([(-20, -7.4), (-20, 7.4)], 0.5, SOFT, 0.3)
    p.text('very long', 4, 0.8, 5, 0, SOFT)


def sc_tall_canyon(p):
    for x in (-8, 8):
        p.line([(x, -22), (x * 1.1, 0), (x, 22)], 1.0, wob=0.6)
    p.hatch([(-14, -22), (-8, -22), (-8.8, 0), (-8, 22), (-14, 22)], 85, 1.8)
    p.text('tall', 0, 0, 5, -90, SOFT)


def sc_slope(p):
    p.line([(-26, 12), (26, -12)], 1.0, wob=0.6)
    for x, y, r in ((-12, 5, 3), (2, -1, 2.4), (14, -7, 2)):
        p.rock(x, y, r)
    p.hatch([(-26, 12.4), (26, -11.6), (26, 16), (-26, 16)], 15, 2.4)


def sc_forest(p):
    for k, (x, y, s) in enumerate(((-14, 0, 18), (0, -6, 22), (13, 2, 17), (-4, 10, 12), (22, -8, 13))):
        (pine if k % 2 == 0 else tree)(p, x, y, s)
    p.ground(-24, 26, 11)


def sc_wide_place(p):
    p.line([(-4, -22), (-4, -8), (-12, 0), (-4, 8), (-4, 22)], 1.0, wob=0.3)
    p.line([(4, -22), (4, -8), (12, 0), (4, 8), (4, 22)], 1.0, wob=0.3)


def sc_crossover(p):
    p.line([(-4, -22), (-4, -4)], 1.0); p.line([(4, -22), (4, -4)], 1.0)
    p.line([(-4, 4), (-4, 22)], 1.0); p.line([(4, 4), (4, 22)], 1.0)
    p.line([(-22, -2), (22, -2)], 0.7, SOFT); p.line([(-22, 2.5), (22, 2.5)], 0.7, SOFT)
    p.text('high', 9, -14, 4.5, 0, SOFT); p.text('low', 15, 7, 4.5, 0, SOFT)


def sc_plover(p):
    p.ell(0, 0, 16, 11, w=1.0)
    for k in range(10):
        a = k / 10 * 2 * math.pi
        p.seg(math.cos(a) * 4, math.sin(a) * 3, math.cos(a) * 13, math.sin(a) * 8.5, 0.5, GREEN, 0.1)
    p.text('eerie green light', 0, 16, 4.5, 0, SOFT)


def sc_tablet_scene(p):
    it_tablet(p)


def sc_steep(p):
    sc_slope(p)


SCENES = {
    'START': sc_brick_building, 'HILL': sc_hill_road, 'BUILDING': sc_well, 'VALLEY': sc_stream_valley,
    'ROADEND': sc_road_end, 'CLIFF': sc_cliff, 'SLIT': sc_slit, 'GRATE': sc_grate,
    'BELOWGRATE': sc_below_grate, 'COBBLE': sc_cobbles, 'DEBRIS': sc_debris, 'AWKWARD': sc_awkward,
    'BIRDCHAMBER': sc_flowstone, 'PITTOP': sc_steps_pit, 'MISTHALL': sc_staircase,
    'EASTBANK': sc_fissure, 'WESTBANK': sc_fissure, 'NUGGET': sc_note, 'KINGHALL': sc_snake,
    'WESTEND': lambda p: sc_twopit(p), 'EASTEND': lambda p: sc_twopit(p, slabs=True),
    'EASTPIT': sc_oil_pool, 'WESTPIT': it_plant, 'FLOORHOLE': sc_hole_floor, 'Y2': sc_y2,
    'JUMBLE': sc_jumble, 'WINDOW1': sc_window, 'WINDOW2': sc_window, 'BROKEN': sc_hole_floor,
    'SMALLPITBRINK': sc_small_pit, 'SMALLPIT': lambda p: sc_small_pit(p, True), 'DUSTY': sc_dusty,
    'PITBRINK': sc_column_pit, 'LONGEAST': sc_long_hall, 'LONGWEST': sc_long_hall,
    'CROSSOVER': sc_crossover, 'COMPLEX': sc_damp, 'BEDQUILT': sc_holes, 'SWISSCHEESE': sc_swiss,
    'SLAB': sc_slab, 'GIANTROOM': sc_giant_room, 'CAVEIN': sc_cavein, 'IMMENSE': sc_door,
    'WATERFALL': sc_waterfall, 'SOFTROOM': sc_soft_room, 'ORIENTAL': sc_drawings,
    'MISTY': sc_misty_cavern, 'ALCOVE': sc_glow_tunnel, 'PLOVER': sc_plover, 'DARKROOM': sc_tablet_scene,
    'ARCHED': sc_arch, 'SHELLROOM': sc_shells, 'SLOPING1': sc_ragged, 'CULDESAC': sc_cul_de_sac,
    'ANTEROOM': sc_construction, 'WITTSEND': sc_witts_end, 'MIRRORCANYON': sc_mirror,
    'TOPSTALACTITE': sc_stalactite, 'RESERVOIR': sc_reservoir, 'RESBOTTOM': sc_res_bottom,
    'RESNORTH': sc_shore, 'NE': sc_repository_ne, 'SW': sc_repository_sw,
    'SWCHASM': sc_troll_bridge, 'NECHASM': lambda p: sc_troll_bridge(p, False),
    'SECRET4': sc_dragon, 'CORRIDOR': sc_rumble, 'FORK': sc_fork,
    'WARMWALLS': lambda p: sc_rumble(p, True), 'BREATHTAKING': sc_volcano, 'BOULDERS2': sc_boulders,
    'BOULDERS1': sc_boulders, 'LIMESTONE': sc_limestone, 'BARRENFRONT': sc_bear_sign,
    'BARRENROOM': sc_bear, 'DEADEND13': sc_vending, 'LARGE': sc_ogre, 'CLIFFBASE': sc_bones,
    'CLIFFACE': sc_cliff_face, 'CLIFFLEDGE': sc_ledge, 'LEDGE': sc_ledge, 'NARROW': sc_narrow,
    'INCLINE': sc_incline, 'STEEP': sc_steep, 'TREACHEROUS': sc_slope, 'ROUGHHEWN': sc_hewn,
    'TALL': sc_tall_canyon, 'WIDEPLACE': sc_wide_place, 'TIGHTPLACE': sc_dead_end,
    'DEADCRAWL': sc_dead_end, 'REACHDEAD': sc_dead_end, 'WINDING': sc_ragged,
}


def scene_for(key, region):
    """Scene sketch for a room key (without the LOC_ prefix)."""
    if key in SCENES:
        return SCENES[key]
    if key.startswith('FOREST'):
        return sc_forest
    if key.startswith('ALIKE'):
        return sc_maze if key in ('ALIKE1', 'ALIKE6', 'ALIKE11') else None
    if key.startswith('DIFFERENT'):
        return (lambda p: sc_maze(p, True)) if key in ('DIFFERENT1', 'DIFFERENT6') else None
    return None


def draw(fn, seed):
    p = Pen(seed)
    fn(p)
    return p


def bounds(p, pad=1.0):
    xs = [x for s in p.strokes for x, _ in s[0]]
    ys = [y for s in p.strokes for _, y in s[0]]
    for t in p.texts:
        w = len(t[0]) * t[3] * 0.5
        xs += [t[1] - w / 2, t[1] + w / 2]
        ys += [t[2] - t[3] / 2, t[2] + t[3] / 2]
    return (min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad)


# ======================================================================
# Small terrain marks scattered round explored places
# ======================================================================

def mk_crag(p):
    n = 3 + int((p.n() + .5) * 3)
    s = 30.0
    xs = -s * .45
    for k in range(n):
        w = s * (.9 / n) * (1 + .3 * p.n())
        hh = s * (.25 + .35 * (p.n() + .5))
        bx, by = xs + w / 2, s * .3
        p.line([(bx - w * .6, by), (bx - w * .2, by - hh), (bx + w * .15, by - hh * .85), (bx + w * .6, by)], 0.9, INK, 0.3)
        for j in range(3):
            p.seg(bx + w * (.05 + j * .15), by - hh * (.7 - j * .2), bx + w * (.1 + j * .15), by - hh * (.25 - j * .1), 0.55, SOFT, 0.05)
        xs += w * .85
    p.line([(-s * .55, s * .3), (s * .5, s * .3)], 0.6, SOFT, 0.3)


def mk_stalag(p):
    s = 22.0
    for k, (dx, hh) in enumerate(((-.25, .5), (0, .8), (.22, .55))):
        bx, by, w = dx * s, s * .4, s * .09
        p.line([(bx - w, by), (bx + p.n() * s * .05, by - hh * s), (bx + w, by)], 0.85, INK, 0.15)
    p.line([(-s * .45, s * .4), (s * .45, s * .4)], 0.6, SOFT, 0.3)


def mk_rocks(p):
    p.rock(-4, 2, 4.5)
    p.rock(4, 3, 3.4)
    if p.n() > -0.1:
        p.rock(0, -1.5, 2.6)


def mk_pebbles(p):
    for k in range(4):
        x, y, r = p.n() * 14, p.n() * 9, 0.8 + (p.n() + .5) * 1.0
        p.ell(x, y, r, r * 0.8, w=0.6, c=SOFT, n=6)


def mk_wave(p):
    p.wave(-2, -1.5, 12, 1.2)
    p.wave(2, 2.5, 12, 1.2)


def mk_tree(p):
    tree(p, 0, 0, 22)


def mk_pine(p):
    pine(p, 0, 0, 24)


def mk_tufts(p):
    p.tuft(-4, 2, 4)
    p.tuft(3, 3, 3.4)


def mk_mount(p):
    s = 36.0
    for k, (dx, hh, ww) in enumerate(((-.28, .55, .3), (.05, .8, .38), (.33, .5, .28))):
        bx, by = dx * s, s * .35
        px, py = bx + p.n() * s * .06, by - hh * s
        p.line([(bx - ww * s, by), (px, py), (bx + ww * s, by)], 0.95, INK, 0.35)
        for j in range(4):
            t = 0.25 + j * 0.17
            ax, ay = px + (bx + ww * s - px) * t, py + (by - py) * t
            p.seg(ax, ay, ax - s * .07, ay + s * .12, 0.55, SOFT, 0.05)


def mk_hill(p):
    s = 28.0
    p.line([(-s * .6 + i * s * .12, s * .15 - math.sin(i / 10 * math.pi) * s * .35) for i in range(11)], 0.8, SOFT, 0.3)
    for k in range(3):
        p.seg(s * (.05 + k * .1), -s * .05 + k * s * .05, s * (.12 + k * .1), s * .1 + k * s * .03, 0.55, SOFT, 0.1)


MARKS = {
    'cave': [mk_crag, mk_rocks, mk_pebbles, mk_stalag, mk_rocks, mk_pebbles],
    'water': [mk_wave, mk_wave, mk_rocks, mk_pebbles],
    'surface': [mk_tree, mk_pine, mk_tufts, mk_tree, mk_mount, mk_pine, mk_hill, mk_tufts],
    'maze': [mk_pebbles, mk_crag, mk_rocks],
}
