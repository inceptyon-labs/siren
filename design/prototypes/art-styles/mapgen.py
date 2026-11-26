#!/usr/bin/env python3
"""Seeded fog-of-war maps (copy of fogmap/gen.py for the art-styles sample).

Changes from the original: square 400x400 sheet (the player art area is square), fog drawn in the
player's raised color, and render(reserve=...) keeps boxes (the cover cartouche) clear of hills,
trees, waves, labels and the compass rose.

A book ID hashes (SHA-256) to a seed. The seed drives the terrain noise, coastline,
hills, forests, river, the road and the chapter regions, so every book gets its own map.
Standard library only.  Usage:  python3 -I gen.py OUT.html
"""
import bisect, hashlib, math, random, sys

W, H = 400.0, 400.0          # map sheet in world units
C = 3.5                      # grid cell
PAD = 6                      # grid cells beyond the sheet
NX = int(round(W / C)) + 2 * PAD + 1
NY = int(round(H / C)) + 2 * PAD + 1
X0 = Y0 = -PAD * C
INK, PAPER, SEA, FLAG = '#2B2620', '#E9E1CF', '#3E6B8C', '#C8402B'
FOG = '#1C1F24'


def seed_of(book_id):
    return int.from_bytes(hashlib.sha256(book_id.encode()).digest()[:8], 'big')


def f(v):
    s = f"{v:.1f}"
    if s.endswith('.0'):
        s = s[:-2]
    return '0' if s == '-0' else s


def poly_d(pts, closed=False):
    d = 'M' + ' '.join(f(x) + ' ' + f(y) for x, y in (pts[:-1] if closed and pts[0] == pts[-1] else pts))
    return d + ('Z' if closed else '')


class Noise:
    """Seeded 2D gradient (Perlin) noise."""
    def __init__(self, rng):
        p = list(range(256)); rng.shuffle(p); self.p = p * 2
        self.g = [(math.cos(a), math.sin(a)) for a in (rng.random() * math.tau for _ in range(256))]

    def n(self, x, y):
        xi, yi = math.floor(x), math.floor(y)
        xf, yf = x - xi, y - yi
        xi &= 255; yi &= 255
        p, g = self.p, self.g
        u = xf * xf * xf * (xf * (xf * 6 - 15) + 10)
        v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)
        a = g[p[p[xi] + yi]]; b = g[p[p[xi + 1] + yi]]
        c = g[p[p[xi] + yi + 1]]; d = g[p[p[xi + 1] + yi + 1]]
        n00 = a[0] * xf + a[1] * yf
        n10 = b[0] * (xf - 1) + b[1] * yf
        n01 = c[0] * xf + c[1] * (yf - 1)
        n11 = d[0] * (xf - 1) + d[1] * (yf - 1)
        x1 = n00 + u * (n10 - n00); x2 = n01 + u * (n11 - n01)
        return x1 + v * (x2 - x1)

    def fbm(self, x, y, octaves=5):
        s, a, fr, norm = 0.0, 1.0, 1.0, 0.0
        for _ in range(octaves):
            s += a * self.n(x * fr, y * fr); norm += a; a *= 0.5; fr *= 2.0
        return s / norm


# ---------- geometry helpers ----------
def chain(segs):
    adj = {}
    for k, (u, v) in enumerate(segs):
        adj.setdefault(u, []).append(k); adj.setdefault(v, []).append(k)
    used = [False] * len(segs); out = []

    def walk(node, k):
        line = [node]
        while True:
            used[k] = True
            u, v = segs[k]; node = v if u == node else u
            line.append(node)
            if len(adj[node]) != 2:
                break
            nxt = [s for s in adj[node] if not used[s]]
            if not nxt:
                break
            k = nxt[0]
        return line
    for node, ks in adj.items():
        if len(ks) != 2:
            for k in ks:
                if not used[k]:
                    out.append(walk(node, k))
    for k in range(len(segs)):
        if not used[k]:
            out.append(walk(segs[k][0], k))
    return out


def march(F, level):
    """Marching squares; returns [(points, closed)] in world coords."""
    pts = {}

    def P(key):
        if key not in pts:
            t, i, j = key
            if t == 'h':
                a, b = F[j][i], F[j][i + 1]; q = (level - a) / (b - a)
                pts[key] = (X0 + (i + q) * C, Y0 + j * C)
            else:
                a, b = F[j][i], F[j + 1][i]; q = (level - a) / (b - a)
                pts[key] = (X0 + i * C, Y0 + (j + q) * C)
        return pts[key]
    segs = []
    for j in range(len(F) - 1):
        r0, r1 = F[j], F[j + 1]
        for i in range(len(r0) - 1):
            a, b, c, d = r0[i] > level, r0[i + 1] > level, r1[i + 1] > level, r1[i] > level
            if a == b == c == d:
                continue
            top, right, bot, left = ('h', i, j), ('v', i + 1, j), ('h', i, j + 1), ('v', i, j)
            act = [e for e, on in ((top, a != b), (right, b != c), (bot, d != c), (left, a != d)) if on]
            if len(act) == 2:
                segs.append((act[0], act[1]))
            else:
                hi = (r0[i] + r0[i + 1] + r1[i] + r1[i + 1]) / 4 > level
                if a and c:
                    segs += [(top, right), (bot, left)] if hi else [(top, left), (right, bot)]
                else:
                    segs += [(top, left), (right, bot)] if hi else [(top, right), (bot, left)]
    out = []
    for line in chain(segs):
        p = [P(k) for k in line]
        out.append((p, line[0] == line[-1]))
    return out


def chaikin(p, closed, it=2):
    for _ in range(it):
        if closed:
            q = p[:-1] if p[0] == p[-1] else p
            n = len(q); r = []
            for k in range(n):
                a, b = q[k], q[(k + 1) % n]
                r += [(a[0] * .75 + b[0] * .25, a[1] * .75 + b[1] * .25), (a[0] * .25 + b[0] * .75, a[1] * .25 + b[1] * .75)]
            p = r + [r[0]]
        else:
            r = [p[0]]
            for a, b in zip(p, p[1:]):
                r += [(a[0] * .75 + b[0] * .25, a[1] * .75 + b[1] * .25), (a[0] * .25 + b[0] * .75, a[1] * .25 + b[1] * .75)]
            p = r + [p[-1]]
    return p


def rdp(p, eps):
    if len(p) < 3:
        return p
    (x1, y1), (x2, y2) = p[0], p[-1]
    dx, dy = x2 - x1, y2 - y1; L = math.hypot(dx, dy) or 1e-9
    best, bi = -1, 0
    for k in range(1, len(p) - 1):
        dd = abs(dy * (p[k][0] - x1) - dx * (p[k][1] - y1)) / L
        if dd > best:
            best, bi = dd, k
    if best > eps:
        return rdp(p[:bi + 1], eps)[:-1] + rdp(p[bi:], eps)
    return [p[0], p[-1]]


def simplify(p, closed, eps=.3):
    if closed:
        q = p[:-1]
        m = len(q) // 2
        a = rdp(q[:m + 1], eps); b = rdp(q[m:] + [q[0]], eps)
        return a[:-1] + b
    return rdp(p, eps)


def length(p):
    return sum(math.dist(a, b) for a, b in zip(p, p[1:]))


def chamfer(mask):
    INF = 1e9; r2 = 1.4142
    d = [[0.0 if mask[j][i] else INF for i in range(NX)] for j in range(NY)]
    for j in range(NY):
        for i in range(NX):
            v = d[j][i]
            if v == 0:
                continue
            if i > 0: v = min(v, d[j][i - 1] + 1)
            if j > 0:
                v = min(v, d[j - 1][i] + 1)
                if i > 0: v = min(v, d[j - 1][i - 1] + r2)
                if i < NX - 1: v = min(v, d[j - 1][i + 1] + r2)
            d[j][i] = v
    for j in range(NY - 1, -1, -1):
        for i in range(NX - 1, -1, -1):
            v = d[j][i]
            if v == 0:
                continue
            if i < NX - 1: v = min(v, d[j][i + 1] + 1)
            if j < NY - 1:
                v = min(v, d[j + 1][i] + 1)
                if i < NX - 1: v = min(v, d[j + 1][i + 1] + r2)
                if i > 0: v = min(v, d[j + 1][i - 1] + r2)
            d[j][i] = v
    return d


def blur(F, passes=2):
    for _ in range(passes):
        G = [row[:] for row in F]
        for j in range(1, NY - 1):
            for i in range(1, NX - 1):
                G[j][i] = (F[j][i] * 4 + F[j][i - 1] + F[j][i + 1] + F[j - 1][i] + F[j + 1][i]) / 8
        F = G
    return F


def catmull(pts, per=14):
    out = []
    P = [pts[0]] + pts + [pts[-1]]
    for k in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[k - 1], P[k], P[k + 1], P[k + 2]
        for s in range(per):
            t = s / per; t2 = t * t; t3 = t2 * t
            out.append(tuple(.5 * (2 * p1[c] + (-p0[c] + p2[c]) * t + (2 * p0[c] - 5 * p1[c] + 4 * p2[c] - p3[c]) * t2
                                   + (-p0[c] + 3 * p1[c] - 3 * p2[c] + p3[c]) * t3) for c in (0, 1)))
    out.append(pts[-1])
    return out


def resample(p, step):
    out = [p[0]]; acc = 0.0
    for a, b in zip(p, p[1:]):
        seg = math.dist(a, b)
        while acc + seg >= step:
            t = (step - acc) / seg
            a = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            out.append(a); seg = math.dist(a, b); acc = 0.0
        acc += seg
    out.append(p[-1])
    return out


def chapter_bounds(rng, n, anchor=None):
    w = [rng.uniform(.7, 1.3) for _ in range(n)]
    if anchor:                                   # (chapter, progress at its midpoint)
        cur, p = anchor
        e = w[:cur]; scale = p / (sum(e[:-1]) + e[-1] / 2); e = [x * scale for x in e]
        rest = 1 - sum(e); late = w[cur:]; L = sum(late)
        w = e + [x * rest / L for x in late]
    else:
        s = sum(w); w = [x / s for x in w]
    b = [0.0]
    for x in w:
        b.append(b[-1] + x)
    b[-1] = 1.0
    return b


ROMAN = [(10, 'X'), (9, 'IX'), (5, 'V'), (4, 'IV'), (1, 'I')]


def roman(n):
    out = ''
    for v, s in ROMAN:
        while n >= v:
            out += s; n -= v
    return out


# ---------- the map ----------
class Map:
    def __init__(self, book_id, chapters, anchor=None):
        self.id = book_id
        self.seed = seed_of(book_id)
        self.R = lambda name: random.Random(f"{self.seed}:{name}")
        self.n = chapters
        self.bounds = chapter_bounds(self.R('chapters'), chapters, anchor)
        self.terrain()
        self.make_road()
        self.regions()

    # terrain: shaped value field + fbm noise with domain warp, threshold at a seeded land fraction
    def terrain(self):
        rng = self.R('shape'); nz = Noise(self.R('noise')); wz = Noise(self.R('warp'))
        self.mode = mode = ['island', 'coast', 'twin', 'bay'][self.seed % 4]
        cx = W * (.5 + rng.uniform(-.07, .07)); cy = H * (.5 + rng.uniform(-.07, .07))
        rot = rng.uniform(0, math.pi); rx = W * rng.uniform(.38, .46); ry = H * rng.uniform(.36, .44)

        def ell(x, y, cx, cy, rx, ry, rot):
            dx, dy = x - cx, y - cy; c, s = math.cos(rot), math.sin(rot)
            u = (dx * c + dy * s) / rx; v = (-dx * s + dy * c) / ry
            return 1 - (u * u + v * v)
        if mode == 'island':
            base = lambda x, y: ell(x, y, cx, cy, rx, ry, rot)
        elif mode == 'coast':
            a = rng.uniform(0, math.tau); ux, uy = math.cos(a), math.sin(a)
            base = lambda x, y: 1.25 * ((x - W / 2) * ux + (y - H / 2) * uy) / (W * .5)
        elif mode == 'twin':
            a = rng.uniform(0, math.tau); off = rng.uniform(.2, .26)
            c1 = (W / 2 + math.cos(a) * W * off, H / 2 + math.sin(a) * H * off)
            c2 = (W / 2 - math.cos(a) * W * off, H / 2 - math.sin(a) * H * off)
            r1, r2 = rng.uniform(.3, .36), rng.uniform(.26, .32)
            base = lambda x, y: max(ell(x, y, c1[0], c1[1], W * r1, H * r1 * 1.15, rot),
                                    ell(x, y, c2[0], c2[1], W * r2, H * r2 * 1.15, rot + 1))
        else:
            a = rng.uniform(0, math.tau)
            bx, by = cx + math.cos(a) * rx * .8, cy + math.sin(a) * ry * .8
            rb = min(rx, ry) * rng.uniform(.5, .62)

            def base(x, y):
                d = math.hypot(x - bx, y - by) / rb
                return ell(x, y, cx, cy, rx * 1.08, ry * 1.08, rot) - 1.4 * max(0.0, 1 - d * d)
        ox, oy = rng.uniform(0, 300), rng.uniform(0, 300)
        h = []
        for j in range(NY):
            y = Y0 + j * C; row = []
            for i in range(NX):
                x = X0 + i * C
                wx = wz.fbm(x / 150 + 7.1, y / 150, 3) * 46
                wy = wz.fbm(x / 150, y / 150 + 3.3, 3) * 46
                row.append(base(x, y) + .95 * nz.fbm((x + wx) / 105 + ox, (y + wy) / 105 + oy, 5))
            h.append(row)
        frac = {'island': .46, 'coast': .54, 'twin': .44, 'bay': .44}[mode] + rng.uniform(-.03, .03)
        vis = sorted(h[j][i] for j in range(PAD, NY - PAD) for i in range(PAD, NX - PAD))
        self.t = vis[int(len(vis) * (1 - frac))]
        for i in range(NX):
            h[0][i] = h[NY - 1][i] = -9
        for j in range(NY):
            h[j][0] = h[j][NX - 1] = -9
        self.h = h
        self.land = [[v > self.t for v in row] for row in h]
        self.seaD = chamfer(self.land)
        self.landD = chamfer([[not v for v in row] for row in self.land])
        lv = sorted(h[j][i] for j in range(PAD, NY - PAD) for i in range(PAD, NX - PAD) if self.land[j][i])
        self.q = lambda frac: lv[min(len(lv) - 1, int(len(lv) * frac))]
        self.landcells = len(lv)

    def cell(self, x, y):
        i = int(round((x - X0) / C)); j = int(round((y - Y0) / C))
        return (min(max(i, 0), NX - 1), min(max(j, 0), NY - 1))

    def is_land(self, x, y):
        i, j = self.cell(x, y); return self.land[j][i]

    # road: Poisson waypoints on land, ordered as an open tour (greedy + 2-opt, water penalised)
    def make_road(self):
        rng = self.R('road'); mz = Noise(self.R('meander'))
        cand = [(X0 + i * C, Y0 + j * C) for j in range(NY) for i in range(NX)
                if self.landD[j][i] >= 2.5 and 22 <= X0 + i * C <= W - 22 and 22 <= Y0 + j * C <= H - 22]
        rmin = math.sqrt(self.landcells * C * C / 17) * .82
        rng.shuffle(cand); way = []
        for p in cand:
            if all((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 >= rmin * rmin for q in way):
                way.append(p)
        a = rng.uniform(0, math.tau); ux, uy = math.cos(a), math.sin(a)
        start = min(way, key=lambda p: p[0] * ux + p[1] * uy)

        def cost(p, q):
            wet = sum(0 if self.is_land(p[0] + (q[0] - p[0]) * k / 10, p[1] + (q[1] - p[1]) * k / 10) else 1 for k in range(1, 10))
            return math.dist(p, q) * (1 + .9 * wet)
        path = [start]; rest = [p for p in way if p != start]
        while rest:
            nxt = min(rest, key=lambda q: cost(path[-1], q)); path.append(nxt); rest.remove(nxt)
        improved = True
        while improved:
            improved = False; n = len(path)
            for i in range(n - 2):
                for k in range(i + 2, n):
                    A, B, Cc = path[i], path[i + 1], path[k]
                    if k + 1 < n:
                        delta = cost(A, Cc) + cost(B, path[k + 1]) - cost(A, B) - cost(Cc, path[k + 1])
                    else:
                        delta = cost(A, Cc) - cost(A, B)
                    if delta < -1e-6:
                        path[i + 1:k + 1] = path[i + 1:k + 1][::-1]; improved = True
        curve = resample(catmull(path), 2.0)
        out = []
        for k, p in enumerate(curve):
            a0 = curve[max(k - 1, 0)]; a1 = curve[min(k + 1, len(curve) - 1)]
            dx, dy = a1[0] - a0[0], a1[1] - a0[1]; L = math.hypot(dx, dy) or 1
            off = 6 * mz.fbm(k * 2.0 / 34, 3.7, 3)
            out.append((p[0] - dy / L * off, p[1] + dx / L * off))
        self.road = resample(out, 2.0)
        L = len(self.road) - 1
        self.road_s = [k / L for k in range(len(self.road))]

    def chapter_at(self, s):
        return min(self.n - 1, bisect.bisect_right(self.bounds, s) - 1)

    def point_at(self, s):
        k = int(round(s * (len(self.road) - 1)))
        return self.road[k], k

    # chapter regions: every grid point belongs to the chapter of its nearest road point
    def regions(self):
        sub = [(p[0], p[1], self.chapter_at(s), s) for p, s in zip(self.road[::2], self.road_s[::2])]
        self.lab, self.ns = [], []   # chapter of the nearest road point, and that point's place in the book
        for j in range(NY):
            y = Y0 + j * C; row, srow = [], []
            for i in range(NX):
                x = X0 + i * C
                best = min(sub, key=lambda r: (r[0] - x) ** 2 + (r[1] - y) ** 2)
                row.append(best[2]); srow.append(best[3])
            self.lab.append(row); self.ns.append(srow)

    def rivers(self):
        rng = self.R('river'); hi = self.q(.86); out = []
        src = [(i, j) for j in range(PAD + 4, NY - PAD - 4) for i in range(PAD + 4, NX - PAD - 4)
               if self.land[j][i] and self.h[j][i] > hi]
        rng.shuffle(src)
        for (i, j) in src[:60]:
            if len(out) >= 2:
                break
            if any(math.dist((X0 + i * C, Y0 + j * C), r[0]) < 70 for r in out):
                continue
            path = [(i, j)]; seen = {(i, j)}
            cost = lambda q: self.h[q[1]][q[0]] + .014 * self.landD[q[1]][q[0]]
            while self.land[path[-1][1]][path[-1][0]] and len(path) < 300:
                ci, cj = path[-1]
                nb = [(ci + a, cj + b) for a in (-1, 0, 1) for b in (-1, 0, 1)
                      if (a or b) and (ci + a, cj + b) not in seen and 0 < ci + a < NX - 1 and 0 < cj + b < NY - 1]
                if not nb:
                    break
                nxt = min(nb, key=lambda q: cost(q) + rng.uniform(0, .006))
                seen.add(nxt); path.append(nxt)
            if self.land[path[-1][1]][path[-1][0]] or len(path) < 14:
                continue
            pts = [(X0 + a * C, Y0 + b * C) for a, b in path]
            out.append(simplify(chaikin(pts, False, 3), False, .25))
        return out

    def borders(self):
        lab, segs = self.lab, []
        mid = lambda key: {'h': lambda i, j: (X0 + (i + .5) * C, Y0 + j * C),
                           'v': lambda i, j: (X0 + i * C, Y0 + (j + .5) * C),
                           'c': lambda i, j: (X0 + (i + .5) * C, Y0 + (j + .5) * C)}[key[0]](key[1], key[2])
        for j in range(NY - 1):
            for i in range(NX - 1):
                l00, l10, l11, l01 = lab[j][i], lab[j][i + 1], lab[j + 1][i + 1], lab[j + 1][i]
                if l00 == l10 == l11 == l01:
                    continue
                act = [e for e, on in ((('h', i, j), l00 != l10), (('v', i + 1, j), l10 != l11),
                                       (('h', i, j + 1), l01 != l11), (('v', i, j), l00 != l01)) if on]
                if len(act) == 2:
                    segs.append((act[0], act[1]))
                else:
                    segs += [(e, ('c', i, j)) for e in act]
        keep = []
        for u, v in segs:
            a, b = mid(u), mid(v)
            if self.landD[self.cell(*a)[1]][self.cell(*a)[0]] >= 1 and self.landD[self.cell(*b)[1]][self.cell(*b)[0]] >= 1:
                keep.append((u, v))
        out = []
        for line in chain(keep):
            p = [mid(k) for k in line]
            if length(p) > 6:
                out.append(simplify(chaikin(p, line[0] == line[-1], 2), line[0] == line[-1], .3))
        return out

    def field_poly(self, test):
        F = [[1.0 if (0 < i < NX - 1 and 0 < j < NY - 1 and test(i, j)) else 0.0 for i in range(NX)] for j in range(NY)]
        return ' '.join(poly_d(simplify(chaikin(p, True, 2), True, .3), True) for p, c in march(F, .5) if c and len(p) > 4)

    # ---------- render ----------
    def render(self, key, kind, progress, flags=(), labels=(), numerals=False, view=None, reserve=()):
        k = 1.0 if kind == 'player' else 2.1
        rng = self.R('decor-' + kind)
        busy = set()

        def mark(x, y, r):
            ci, cj = self.cell(x, y); rr = int(r / C) + 1
            for a in range(ci - rr, ci + rr + 1):
                for b in range(cj - rr, cj + rr + 1):
                    if (X0 + a * C - x) ** 2 + (Y0 + b * C - y) ** 2 <= r * r:
                        busy.add((a, b))
        free = lambda x, y: self.cell(x, y) not in busy
        for rx0, ry0, rx1, ry1 in reserve:
            for b in range(int((ry0 - 6 - Y0) / C), int((ry1 + 6 - Y0) / C) + 1):
                for a in range(int((rx0 - 6 - X0) / C), int((rx1 + 6 - X0) / C) + 1):
                    busy.add((a, b))
        vx, vy, vw, vh = view or (0, 0, W, H)
        area = f'x="{f(vx)}" y="{f(vy)}" width="{f(vw)}" height="{f(vh)}"'
        defs = [f'<clipPath id="{key}s"><rect width="{f(W)}" height="{f(H)}"/></clipPath>']
        body = []
        cur = self.chapter_at(progress) if progress < 1 else self.n
        p_pt, p_k = self.point_at(min(progress, 1))
        if progress > 0:
            coast = [simplify(chaikin(p, True, 2), True, .3) for p, c in march(self.h, self.t) if c and len(p) > 5]
            coast_d = ' '.join(poly_d(p, True) for p in coast)
            if kind == 'player':
                body.append(f'<rect width="{f(W)}" height="{f(H)}" fill="{PAPER}" filter="url(#shadow)"/>')
            body.append(f'<g clip-path="url(#{key}s)"><rect width="{f(W)}" height="{f(H)}" fill="{PAPER}"/>'
                        f'<rect width="{f(W)}" height="{f(H)}" fill="{SEA}" opacity=".26"/>'
                        f'<path d="{coast_d}" fill="none" stroke="{SEA}" stroke-width="{f(9 * k)}" opacity=".32" filter="url(#wash)"/>')
            sd = blur(self.seaD, 2)
            for lvl, op in ((1.5, .5), (2.9, .32), (4.6, .18)):
                wl = [simplify(chaikin(p, c, 2), c, .3) for p, c in march(sd, lvl) if len(p) > 4]
                body.append(f'<path d="{" ".join(poly_d(p, False) for p in wl)}" fill="none" stroke="{INK}" stroke-width="{f(.7 * k)}" opacity="{op}"/>')
            body.append(f'<path d="{coast_d}" fill="{PAPER}" fill-rule="evenodd"/>')
            hl = [simplify(chaikin(p, True, 2), True, .4) for p, c in march(self.h, self.q(.8)) if c and len(p) > 5]
            body.append(f'<path d="{" ".join(poly_d(p, True) for p in hl)}" fill="url(#{"hatch" if k == 1 else "hatchT"})" opacity=".42"/>')
            body.append(f'<rect width="{f(W)}" height="{f(H)}" filter="url(#grain)"/>')
            body.append(f'<path d="{coast_d}" fill="none" stroke="{INK}" stroke-width="{f(1.25 * k)}" stroke-linejoin="round"/>')
            # river: tapering ink line from source to mouth
            for rv in self.rivers():
                n = len(rv); parts = [rv[:n // 3 + 1], rv[n // 3:2 * n // 3 + 1], rv[2 * n // 3:]]
                for part, wdt in zip(parts, (.7, 1.05, 1.45)):
                    body.append(f'<path d="{poly_d(part)}" fill="none" stroke="{INK}" stroke-width="{f(wdt * k)}" stroke-linecap="round"/>')
                for x, y in rv[::2]:
                    mark(x, y, 5 * k)
            # chapter borders and the road
            body.append(f'<path d="{" ".join(poly_d(p) for p in self.borders())}" fill="none" stroke="{INK}" stroke-width="{f(.75 * k)}" stroke-dasharray="{f(3 * k)} {f(2.6 * k)}" opacity=".62"/>')
            body.append(f'<path d="{poly_d(self.road)}" fill="none" stroke="{INK}" stroke-width="{f(1.9 * k)}" stroke-linecap="round" stroke-dasharray="0 {f(4.4 * k)}"/>')
            for x, y in self.road[::2]:
                mark(x, y, 6 * k)
            # labels (player only): numeral + name, placed in the revealed part of the region
            # ground is uncovered where its nearest road point has been heard (plus a clearing round the marker)
            heard = lambda i, j: self.ns[j][i] < progress or math.dist((X0 + i * C, Y0 + j * C), p_pt) < 24

            def revealed(x, y):
                i, j = self.cell(x, y)
                return self.ns[j][i] < progress - .012 or math.dist((x, y), p_pt) < 14
            near = set()   # cells within reach of any revealed ground (incl. the fog's ragged edge)
            for j in range(NY):
                for i in range(NX):
                    if heard(i, j):
                        for a in range(i - 5, i + 6):
                            for b in range(j - 5, j + 6):
                                if (a - i) ** 2 + (b - j) ** 2 <= 25:
                                    near.add((a, b))
            fogged = lambda x, y: self.cell(x, y) not in near
            boxes = [(a - 6, b - 6, c + 6, d + 6) for a, b, c, d in reserve]
            occupied = lambda bx: sum(1 for o in boxes if bx[0] < o[2] and o[0] < bx[2] and bx[1] < o[3] and o[1] < bx[3])
            for ch in flags:
                s = self.bounds[ch - 1] + .55 * (self.bounds[ch] - self.bounds[ch - 1])
                (x, y), _ = self.point_at(s)
                boxes.append((x - 3 * k, y - 17 * k, x + 11 * k, y + 2 * k)); mark(x + 3 * k, y - 8 * k, 10 * k)
            if 0 < progress < 1:
                boxes.append((p_pt[0] - 15 * k, p_pt[1] - 15 * k, p_pt[0] + 15 * k, p_pt[1] + 15 * k)); mark(*p_pt, 10 * k)
            texts, fogtexts = [], []
            for ch, name in labels:
                lc = ch - 1
                fs = 12.5; wdt = max(len(name) * fs * .46, 30); hgt = fs * 2.1
                if lc == cur:   # the chapter being heard: lettered on the fog, just past the marker
                    pts = [(X0 + i * C, Y0 + j * C) for j in range(NY) for i in range(NX)
                           if math.dist((X0 + i * C, Y0 + j * C), p_pt) < 120]
                else:
                    pts = [(X0 + i * C, Y0 + j * C) for j in range(NY) for i in range(NX)
                           if self.lab[j][i] == lc and self.landD[j][i] >= 1]
                if not pts:
                    continue
                cx, cy = (p_pt if lc == cur else (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)))
                best = None
                for x, y in pts:
                    bx = (x - wdt / 2, y - hgt * .62, x + wdt / 2, y + hgt * .38)
                    if bx[0] < 14 or bx[2] > W - 14 or bx[1] < 14 or bx[3] > H - 14:
                        continue
                    samp = [(bx[0], bx[1]), (bx[2], bx[1]), (bx[0], bx[3]), (bx[2], bx[3]), (x, bx[1]), (x, bx[3])]
                    e = 9; ring = [(bx[0] - e, bx[1] - e), (bx[2] + e, bx[1] - e), (bx[0] - e, bx[3] + e), (bx[2] + e, bx[3] + e), (x, bx[1] - e), (x, bx[3] + e), (bx[0] - e, y), (bx[2] + e, y)]
                    if lc == cur:
                        dark = sum(1 for q in samp + ring if not fogged(*q)) + (0 if self.lab[self.cell(x, y)[1]][self.cell(x, y)[0]] == lc else .4)
                    else:
                        dark = sum(1 for q in ring if not revealed(*q))
                    wet = sum(1 for q in samp if not self.is_land(*q))
                    road = sum(1 for a, b in self.road[::3] if bx[0] < a < bx[2] and bx[1] < b < bx[3])
                    sc = math.dist((x, y), (cx, cy)) * .35 + 400 * occupied(bx) + 160 * dark + (0 if lc == cur else 14 * wet + 9 * road)
                    if best is None or sc < best[0]:
                        best = (sc, x, y, bx)
                if best:
                    _, x, y, bx = best; boxes.append(bx)
                    for a in range(int(bx[0]), int(bx[2]), 4):
                        for b in range(int(bx[1]), int(bx[3]), 4):
                            mark(a, b, 3)
                    (fogtexts if lc == cur else texts).append(f'<text class="{"lbf" if lc == cur else "lb"}" x="{f(x)}" y="{f(y - fs * .55)}"><tspan class="rn">{roman(ch)}</tspan>'
                                 f'<tspan x="{f(x)}" dy="{f(fs * 1.15)}">{name}</tspan></text>')
            if numerals:
                named = {ch for ch, _ in labels}
                for lc in range(cur):
                    if lc + 1 in named:
                        continue
                    pts = [(X0 + i * C, Y0 + j * C) for j in range(NY) for i in range(NX)
                           if self.lab[j][i] == lc and self.landD[j][i] >= 1.5]
                    if len(pts) < 8:
                        continue
                    cx = sum(p[0] for p in pts) / len(pts); cy = sum(p[1] for p in pts) / len(pts)
                    txt = roman(lc + 1); wdt = len(txt) * 6 + 4
                    cands = []
                    for x, y in pts:
                        bx = (x - wdt / 2, y - 8, x + wdt / 2, y + 2)
                        if bx[0] < 16 or bx[2] > W - 16 or bx[1] < 16 or bx[3] > H - 16:
                            continue
                        road = sum(1 for a, b in self.road[::3] if bx[0] - 2 < a < bx[2] + 2 and bx[1] - 2 < b < bx[3] + 2)
                        cands.append((math.dist((x, y), (cx, cy)) * .3 + 400 * occupied(bx) + 20 * road, x, y, bx))
                    if cands:
                        _, x, y, bx = min(cands); boxes.append(bx); mark(x, y - 3, 9)
                        texts.append(f'<text class="rnum" x="{f(x)}" y="{f(y)}">{txt}</text>')
            # hills and mountains
            hrng = self.R('hills-' + kind); hi = self.q(.66); mt = self.q(.9)
            cand = [(X0 + i * C + hrng.uniform(-1.5, 1.5), Y0 + j * C + hrng.uniform(-1.5, 1.5)) for j in range(NY) for i in range(NX)
                    if self.land[j][i] and self.h[j][i] > hi and self.landD[j][i] >= 2 and 12 < X0 + i * C < W - 12 and 18 < Y0 + j * C < H - 10]
            hills = self.poisson(cand, 15 * k, hrng, 40 if k == 1 else 14, free)
            hills.sort(key=lambda p: p[1])
            hatch = 'hatch' if k == 1 else 'hatchT'
            for x, y in hills:
                v = self.h[self.cell(x, y)[1]][self.cell(x, y)[0]]
                if v > mt:
                    w = (13 + 7 * hrng.random()) * k; hh = w * .95
                    o = f'M{f(x - w / 2)} {f(y)}L{f(x - w * .06)} {f(y - hh)}L{f(x + w * .1)} {f(y - hh * .86)}L{f(x + w / 2)} {f(y)}'
                    sh = f'M{f(x - w * .06)} {f(y - hh)}L{f(x + w * .1)} {f(y - hh * .86)}L{f(x + w / 2)} {f(y)}L{f(x + w * .1)} {f(y)}Z'
                else:
                    w = (10 + 6 * hrng.random()) * k; hh = w * .48
                    o = (f'M{f(x - w / 2)} {f(y)}C{f(x - w * .38)} {f(y - hh * .75)} {f(x - w * .2)} {f(y - hh)} {f(x)} {f(y - hh)}'
                         f'C{f(x + w * .22)} {f(y - hh)} {f(x + w * .4)} {f(y - hh * .6)} {f(x + w / 2)} {f(y)}')
                    sh = (f'M{f(x)} {f(y - hh)}C{f(x + w * .22)} {f(y - hh)} {f(x + w * .4)} {f(y - hh * .6)} {f(x + w / 2)} {f(y)}'
                          f'L{f(x + w * .14)} {f(y)}C{f(x + w * .16)} {f(y - hh * .5)} {f(x + w * .08)} {f(y - hh * .85)} {f(x)} {f(y - hh)}Z')
                body.append(f'<path d="{o}Z" fill="{PAPER}"/><path d="{sh}" fill="url(#{hatch})"/><path d="{o}" fill="none" stroke="{INK}" stroke-width="{f(.95 * k)}" stroke-linejoin="round"/>')
                mark(x, y - hh / 2, w * .7)
            # forests
            fz = Noise(self.R('forest'))
            trng = self.R('trees-' + kind)
            cand = []
            for j in range(NY):
                for i in range(NX):
                    x, y = X0 + i * C + trng.uniform(-1.7, 1.7), Y0 + j * C + trng.uniform(-1.7, 1.7)
                    if self.land[j][i] and self.landD[j][i] >= 1.5 and self.h[j][i] < hi and 10 < x < W - 10 and 14 < y < H - 10 \
                            and fz.fbm(x / 62, y / 62, 3) > .12:
                        cand.append((x, y))
            trees = sorted(self.poisson(cand, 5.2 * k, trng, 500, free), key=lambda p: p[1])
            s = 2.4 * k; td = []
            for x, y in trees:
                if fz.n(x / 9, y / 9) > .05:
                    td.append(f'M{f(x)} {f(y - 2.6 * s)}L{f(x + s)} {f(y - .2 * s)}L{f(x - s)} {f(y - .2 * s)}ZM{f(x)} {f(y - .2 * s)}V{f(y + .5 * s)}')
                else:
                    td.append(f'M{f(x - s)} {f(y - s)}a{f(s)} {f(s)} 0 1 1 {f(2 * s)} 0a{f(s)} {f(s)} 0 1 1 {f(-2 * s)} 0M{f(x)} {f(y)}V{f(y + .7 * s)}')
            body.append(f'<path d="{"".join(td)}" fill="{PAPER}" stroke="{INK}" stroke-width="{f(.7 * k)}" stroke-linejoin="round"/>')
            # waves
            wrng = self.R('waves-' + kind)
            cand = [(X0 + i * C, Y0 + j * C) for j in range(NY) for i in range(NX)
                    if self.seaD[j][i] > 6 and 24 < X0 + i * C < W - 24 and 24 < Y0 + j * C < H - 20]
            wd = []
            for x, y in self.poisson(cand, 42 * k ** .5, wrng, 9 if k == 1 else 4, free):
                u = 2.6 * k
                wd.append(f'M{f(x - 1.5 * u)} {f(y)}q{f(u * .5)} {f(-u * .7)} {f(u)} 0t{f(u)} 0t{f(u)} 0')
                mark(x, y, 6 * k)
            body.append(f'<path d="{"".join(wd)}" fill="none" stroke="{INK}" stroke-width="{f(.75 * k)}" stroke-linecap="round" opacity=".6"/>')
            # compass rose in the corner with the most open sea
            r = 15 * (k ** .55)
            corners = [(36 * k ** .3 + r, 36 * k ** .3 + r), (W - 36 * k ** .3 - r, 36 * k ** .3 + r),
                       (36 * k ** .3 + r, H - 30 * k ** .3 - r), (W - 36 * k ** .3 - r, H - 30 * k ** .3 - r)]
            corners = [c for c in corners if not any(a - r - 8 < c[0] < cc + r + 8 and b - r - 8 < c[1] < d + r + 8 for a, b, cc, d in reserve)]
            cx, cy = max(corners, key=lambda c: sum(1 for a in range(-3, 4) for b in range(-3, 4) if not self.is_land(c[0] + a * r / 3, c[1] + b * r / 3)))
            cd, cf = [], []
            for a in range(8):
                ang = a * math.pi / 4 - math.pi / 2; L = r if a % 2 == 0 else r * .55; wv = r * .14
                tip = (cx + math.cos(ang) * L, cy + math.sin(ang) * L)
                l1 = (cx + math.cos(ang - math.pi / 2) * wv, cy + math.sin(ang - math.pi / 2) * wv)
                l2 = (cx + math.cos(ang + math.pi / 2) * wv, cy + math.sin(ang + math.pi / 2) * wv)
                cd.append(f'M{f(l1[0])} {f(l1[1])}L{f(tip[0])} {f(tip[1])}L{f(l2[0])} {f(l2[1])}')
                cf.append(f'M{f(cx)} {f(cy)}L{f(tip[0])} {f(tip[1])}L{f(l2[0])} {f(l2[1])}Z')
            body.append(f'<circle cx="{f(cx)}" cy="{f(cy)}" r="{f(r * .6)}" fill="{PAPER}" stroke="{INK}" stroke-width="{f(.6 * k)}"/>'
                        f'<path d="{"".join(cd)}Z" fill="{PAPER}" stroke="{INK}" stroke-width="{f(.7 * k)}" stroke-linejoin="round"/>'
                        f'<path d="{"".join(cf)}" fill="{INK}"/>')
            if k == 1:
                body.append(f'<text class="cn" x="{f(cx)}" y="{f(cy - r - 3)}">N</text>')
            # neatline with alternating scale bars
            nb = [f'M5 5H{f(W - 5)}V{f(H - 5)}H5Z', f'M9 9H{f(W - 9)}V{f(H - 9)}H9Z']
            bars = []
            for x in range(9, int(W) - 9, 24):
                if (x // 24) % 2 == 0:
                    x2 = min(x + 24, W - 9)
                    bars.append(f'M{x} 5H{f(x2)}V9H{x}ZM{x} {f(H - 9)}H{f(x2)}V{f(H - 5)}H{x}Z')
            for y in range(9, int(H) - 9, 24):
                if (y // 24) % 2 == 1:
                    y2 = min(y + 24, H - 9)
                    bars.append(f'M5 {y}H9V{f(y2)}H5ZM{f(W - 9)} {y}H{f(W - 5)}V{f(y2)}H{f(W - 9)}Z')
            body.append(f'<path d="{"".join(bars)}" fill="{INK}"/><path d="{"".join(nb)}" fill="none" stroke="{INK}" stroke-width="{f(.8 * k ** .5)}"/>')
            body += texts
            # flags
            fl = []
            for ch in flags:
                sx = self.bounds[ch - 1] + .55 * (self.bounds[ch] - self.bounds[ch - 1])
                (x, y), _ = self.point_at(sx); u = k ** .8
                fl.append(f'<path d="M{f(x)} {f(y + 1 * u)}V{f(y - 16 * u)}" stroke="{INK}" stroke-width="{f(1.3 * u)}" stroke-linecap="round"/>'
                          f'<path d="M{f(x + .5 * u)} {f(y - 16 * u)}L{f(x + 11 * u)} {f(y - 12.6 * u)}L{f(x + .5 * u)} {f(y - 9.2 * u)}Z" fill="{FLAG}" stroke="{INK}" stroke-width="{f(.7 * u)}" stroke-linejoin="round"/>'
                          f'<ellipse cx="{f(x)}" cy="{f(y + 1 * u)}" rx="{f(2.6 * u)}" ry="{f(1 * u)}" fill="{INK}"/>')
            body += fl
            if 0 < progress < 1:
                x, y = p_pt; u = k ** .8
                body.append(f'<circle class="pulse" cx="{f(x)}" cy="{f(y)}" r="{f(6.5 * u)}" fill="none" stroke="{FLAG}" stroke-width="{f(1.4 * u)}"/>'
                            f'<circle cx="{f(x)}" cy="{f(y)}" r="{f(6.5 * u)}" fill="{PAPER}" stroke="{INK}" stroke-width="{f(1.5 * u)}"/>'
                            f'<circle cx="{f(x)}" cy="{f(y)}" r="{f(2.7 * u)}" fill="{FLAG}"/>')
            body.append('</g>')
        # fog
        if progress < 1:
            s1, s2 = self.seed % 991, (self.seed >> 12) % 997
            defs.append(f'<filter id="{key}c" color-interpolation-filters="sRGB" filterUnits="userSpaceOnUse" {area}><feTurbulence type="fractalNoise" baseFrequency=".012 .019" numOctaves="4" seed="{s2}"/>'
                        f'<feColorMatrix values="0 0 0 0 .165 0 0 0 0 .176 0 0 0 0 .208 2.7 0 0 0 -1"/></filter>')
            fade = kind == 'player' and vy + vh > H + 1   # fade the cloud texture only where the view runs past the sheet
            cloud = f'<rect {area} filter="url(#{key}c)"' + (f' mask="url(#{key}f)"/>' if fade else '/>')
            if fade:
                defs.append(f'<linearGradient id="{key}g" gradientUnits="userSpaceOnUse" x1="0" y1="{f(H - 10)}" x2="0" y2="{f(vy + vh)}"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#000"/></linearGradient>'
                            f'<mask id="{key}f" maskUnits="userSpaceOnUse" {area}><rect {area} fill="url(#{key}g)"/></mask>')
            if progress > 0:
                defs.append(f'<g id="{key}h"><path d="{self.field_poly(heard)}" fill-rule="evenodd"/></g>')
                for fid, sc, sd_ in (('r', 22, 4), ('q', 22, 13)):
                    defs.append(f'<filter id="{key}{fid}" filterUnits="userSpaceOnUse" {area}><feTurbulence type="fractalNoise" baseFrequency=".03" numOctaves="3" seed="{s1}" result="n"/>'
                                f'<feDisplacementMap in="SourceGraphic" in2="n" scale="{sc}" xChannelSelector="R" yChannelSelector="G"/><feGaussianBlur stdDeviation="{sd_}"/></filter>'
                                f'<mask id="{key}m{fid}" maskUnits="userSpaceOnUse" {area}><rect {area} fill="#fff"/><use href="#{key}h" filter="url(#{key}{fid})"/></mask>')
                body.append(f'<rect {area} fill="#2A2D35" opacity=".7" mask="url(#{key}mq)"/>'
                            f'<g mask="url(#{key}mr)"><rect {area} fill="{FOG}"/>{cloud}</g>')
            else:
                body.append(f'<rect {area} fill="{FOG}"/>{cloud}')
        if progress > 0:
            body += fogtexts
        return f'<defs>{"".join(defs)}</defs>' + ''.join(body)

    def poisson(self, cand, rmin, rng, maxn, ok):
        cand = cand[:]; rng.shuffle(cand); acc = []; grid = {}
        for x, y in cand:
            if not ok(x, y):
                continue
            gi, gj = int(x // rmin), int(y // rmin)
            if any((px - x) ** 2 + (py - y) ** 2 < rmin * rmin for a in (gi - 1, gi, gi + 1) for b in (gj - 1, gj, gj + 1) for px, py in grid.get((a, b), ())):
                continue
            acc.append((x, y)); grid.setdefault((gi, gj), []).append((x, y))
            if len(acc) >= maxn:
                break
        return acc




TEMPLATE = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=820">
<title>Siren, Fog-of-War Map</title>
<!-- Every map is generated from its book ID (SHA-256 seed: noise terrain, coast, hills, forests, river, road, chapter regions). Nothing is hand-placed. -->
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IM+Fell+English:ital@0;1&display=block">
<style>
:root{--ground:#15171C;--fog:#2A2D35;--paper:#E9E1CF;--ink:#2B2620;--flag:#C8402B;--flagt:#EF8C76;--l2:#ABA597;--sep:rgba(233,225,207,.14);--sys:-apple-system,"SF Pro Text",system-ui,sans-serif;--fell:"IM Fell English",Georgia,serif}
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:820px;height:874px;overflow:hidden;background:#0B0C0F}
body{display:flex;gap:16px;color:var(--paper);font-family:var(--sys);-webkit-font-smoothing:antialiased;font-variant-numeric:tabular-nums}
::selection{background:rgba(200,64,43,.45);color:#fff}
svg{display:block}
.defs{position:absolute;width:0;height:0}
.ph{position:relative;width:402px;height:874px;flex:none;border-radius:48px;overflow:hidden;background:var(--ground)}
/* map lettering */
.lb{font:italic 12.5px var(--fell);fill:var(--ink);text-anchor:middle;paint-order:stroke;stroke:var(--paper);stroke-width:3.4px;stroke-linejoin:round}
.lb .rn{font-style:normal;font-size:9.5px;letter-spacing:.18em}
.lbf{font:italic 13.5px var(--fell);fill:var(--paper);text-anchor:middle}
.lbf .rn{font-style:normal;font-size:10px;letter-spacing:.18em}
.rnum{font:10px var(--fell);fill:var(--ink);text-anchor:middle;letter-spacing:.12em;paint-order:stroke;stroke:var(--paper);stroke-width:2.6px;stroke-linejoin:round}
.cn{font:10px var(--fell);fill:var(--ink);text-anchor:middle}
.pulse{transform-box:fill-box;transform-origin:center;animation:pulse 2.6s cubic-bezier(.16,1,.3,1) infinite}
@keyframes pulse{from{transform:scale(1);opacity:.9}to{transform:scale(2.6);opacity:0}}
@media (prefers-reduced-motion:reduce){.pulse{animation:none;opacity:0}}
/* native shell */
.sb{position:relative;height:54px;display:flex;align-items:center;justify-content:space-between;padding:6px 28px 0 50px;font-size:17px;font-weight:600;letter-spacing:-.4px}
.top{position:relative;height:48px;display:flex;align-items:center;justify-content:space-between;padding:0 16px 0 20px}
h1{font-size:34px;line-height:41px;font-weight:700;letter-spacing:.37px}
.av{width:44px;height:44px;display:grid;place-items:center}
.av span{width:36px;height:36px;border-radius:50%;background:#3A3F4B;display:grid;place-items:center;font-size:16px;font-weight:600}
.seg{position:relative;margin:6px 16px 0;height:32px;border-radius:16px;background:rgba(118,118,128,.24);display:flex;padding:2px}
.seg span{flex:1;display:grid;place-items:center;border-radius:14px;font-size:13px;font-weight:500;color:#C9C6BE}
.seg .on{background:#5B5E68;color:#fff;font-weight:600;box-shadow:0 3px 8px rgba(0,0,0,.3)}
.glass{position:absolute;background:rgba(40,43,51,.62);-webkit-backdrop-filter:blur(18px) saturate(1.6);backdrop-filter:blur(18px) saturate(1.6);border:.5px solid rgba(233,225,207,.16);box-shadow:0 8px 24px rgba(0,0,0,.45)}
.mini{left:16px;right:16px;top:726px;height:48px;border-radius:24px;display:flex;align-items:center;gap:10px;padding:0 4px 0 8px}
.mini .cv{width:34px;height:34px;flex:none;border-radius:6px;overflow:hidden;outline:.5px solid rgba(233,225,207,.25)}
.tx{flex:1;min-width:0}
.tx b{display:block;font-size:15px;line-height:18px;font-weight:600;letter-spacing:-.2px}
.fn{font-size:13px;line-height:16px;color:var(--l2)}
.ic{width:44px;height:44px;display:grid;place-items:center;flex:none;color:var(--paper)}
.tabs{left:16px;top:782px;width:300px;height:60px;border-radius:30px;display:flex;padding:4px}
.tab{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:2px;border-radius:26px;font-size:10px;line-height:12px;font-weight:600;color:var(--paper)}
.tab.on{background:rgba(233,225,207,.12);color:var(--flagt)}
.srch{right:16px;top:782px;width:60px;height:60px;border-radius:30px;display:grid;place-items:center}
.hi{position:absolute;left:134px;bottom:8px;width:134px;height:5px;border-radius:3px;background:var(--paper)}
/* player sheet */
.map{position:absolute;left:0;top:0}
.grab{position:absolute;left:183px;top:57px;width:36px;height:5px;border-radius:3px;background:rgba(233,225,207,.42)}
.hd{position:absolute;left:24px;right:24px;top:414px}
h3{font:400 32px/36px var(--fell);letter-spacing:-.005em}
.sub{font-size:15px;line-height:20px;color:var(--l2)}
.chap{position:absolute;left:24px;right:24px;top:504px;display:flex;justify-content:space-between;font-size:17px;line-height:22px;font-weight:600;letter-spacing:-.4px}
.chap span{color:var(--l2);font-weight:400}
.trk{position:absolute;left:24px;right:24px;top:538px;height:6px;border-radius:3px;background:rgba(233,225,207,.16);overflow:hidden}
.trk i{display:block;width:49%;height:100%;background:var(--paper)}
.tl{position:absolute;left:24px;right:24px;top:552px;display:flex;justify-content:space-between;font-size:13px;line-height:16px;font-weight:500;color:var(--l2)}
.tl .m{color:var(--paper)}
.tp{position:absolute;left:16px;right:16px;top:584px;height:80px;display:flex;align-items:center;justify-content:space-between}
.pp{width:76px;height:76px;border-radius:50%;background:var(--paper);display:grid;place-items:center;color:var(--ground);box-shadow:0 6px 20px rgba(0,0,0,.45)}
.sec{position:absolute;left:12px;right:12px;top:690px;height:44px;display:flex;justify-content:space-between;align-items:center}
.sec .ic{width:auto;min-width:48px;padding:0 6px;gap:5px;display:flex;justify-content:center;align-items:center;font-size:15px;font-weight:600}
.sec small{font-size:13px;font-weight:500;color:var(--l2)}
.act{position:absolute;left:20px;right:20px;top:764px;height:50px;display:flex;align-items:center;gap:14px}
.flag{height:50px;padding:0 22px 0 18px;border-radius:25px;display:flex;align-items:center;gap:8px;background:rgba(200,64,43,.2);border:.5px solid rgba(239,140,118,.35);color:var(--flagt);font-size:17px;font-weight:600;letter-spacing:-.3px}
.act p{font-size:13px;line-height:17px;color:var(--l2)}
.act p b{display:block;color:var(--paper);font-weight:600}
/* library: map room */
.grid{position:absolute;left:16px;right:16px;top:154px;display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:10px 18px}
.fm{padding:5px;border-radius:2px;background:linear-gradient(155deg,#43372C,#1D1813 55%,#2E251D);box-shadow:0 10px 18px rgba(0,0,0,.55),inset 0 1px 0 rgba(255,236,205,.14),inset 0 -1px 0 rgba(0,0,0,.6)}
.fm svg{width:100%;height:auto;aspect-ratio:400/350;outline:1px solid #8A6E42}
.plate{display:table;margin:6px auto 0;padding:3px 7px 2px;border-radius:2px;font:400 11px/14px var(--fell);color:#2A1F0E;background:linear-gradient(#E4CB92,#B9965D 55%,#CFB074);box-shadow:0 1px 3px rgba(0,0,0,.55),inset 0 0 0 .5px rgba(70,48,14,.7),inset 0 1px 0 rgba(255,248,225,.5);white-space:nowrap}
</style>
</head>
<body>
<svg class="defs" aria-hidden="true"><defs>
<pattern id="hatch" patternUnits="userSpaceOnUse" width="2.3" height="2.3" patternTransform="rotate(45)"><path d="M0 0V2.3" stroke="#2B2620" stroke-width=".75"/></pattern>
<pattern id="hatchT" patternUnits="userSpaceOnUse" width="4.4" height="4.4" patternTransform="rotate(45)"><path d="M0 0V4.4" stroke="#2B2620" stroke-width="1.5"/></pattern>
<filter id="grain" color-interpolation-filters="sRGB" x="0" y="0" width="1" height="1"><feTurbulence type="fractalNoise" baseFrequency=".8" numOctaves="2" seed="7" result="g"/><feColorMatrix in="g" values="0 0 0 0 .17 0 0 0 0 .15 0 0 0 0 .12 .9 0 0 0 -.4" result="g2"/><feTurbulence type="fractalNoise" baseFrequency=".013" numOctaves="3" seed="11" result="s"/><feColorMatrix in="s" values="0 0 0 0 .5 0 0 0 0 .36 0 0 0 0 .2 .9 0 0 0 -.38" result="s2"/><feMerge><feMergeNode in="s2"/><feMergeNode in="g2"/></feMerge></filter>
<filter id="wash" color-interpolation-filters="sRGB" x="-5%" y="-5%" width="110%" height="110%"><feGaussianBlur stdDeviation="2.6"/></filter>
<filter id="shadow" x="-10%" y="-10%" width="120%" height="125%"><feDropShadow dx="0" dy="5" stdDeviation="7" flood-color="#000" flood-opacity=".6"/></filter>
<symbol id="sbr" viewBox="0 0 77 13"><g fill="#E9E1CF"><rect y="8" width="3" height="4" rx="1"/><rect x="5" y="5.5" width="3" height="6.5" rx="1"/><rect x="10" y="3" width="3" height="9" rx="1"/><rect x="15" width="3" height="12" rx="1"/></g><path d="M25.5 4.4a9.4 9.4 0 0 1 13 0M28.2 7.2a5.6 5.6 0 0 1 7.6 0" fill="none" stroke="#E9E1CF" stroke-width="1.8" stroke-linecap="round"/><circle cx="32" cy="10.2" r="1.3" fill="#E9E1CF"/><rect x="49.5" y=".5" width="23" height="12" rx="3.8" fill="none" stroke="#E9E1CF" stroke-opacity=".4"/><rect x="51" y="2" width="20" height="9" rx="2.4" fill="#E9E1CF"/><path d="M74 4.5v4c.8-.3 1.4-1.1 1.4-2s-.6-1.7-1.4-2z" fill="#E9E1CF" fill-opacity=".4"/></symbol>
<symbol id="pause" viewBox="0 0 24 24"><rect x="6" y="4.5" width="4.2" height="15" rx="1.3" fill="currentColor"/><rect x="13.8" y="4.5" width="4.2" height="15" rx="1.3" fill="currentColor"/></symbol>
<symbol id="f30" viewBox="0 0 28 28"><path d="M14 5.5A9.5 9.5 0 1 1 5.8 10.2" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/><path d="M13.6 2.3l4 3.2-4 3.2z" fill="currentColor"/><text x="14" y="18.6" text-anchor="middle" font-size="8.6" font-weight="700" fill="currentColor" font-family="-apple-system,system-ui">30</text></symbol>
<symbol id="b30" viewBox="0 0 28 28"><path d="M14 5.5A9.5 9.5 0 1 0 22.2 10.2" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/><path d="M14.4 2.3l-4 3.2 4 3.2z" fill="currentColor"/><text x="14" y="18.6" text-anchor="middle" font-size="8.6" font-weight="700" fill="currentColor" font-family="-apple-system,system-ui">30</text></symbol>
<symbol id="pflag" viewBox="0 0 24 24"><path d="M6 21.5V3" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/><path d="M6.6 3.6 19 8.1 6.6 12.6z" fill="currentColor"/></symbol>
</defs></svg>

<!-- LEFT: player sheet, the book's map -->
<div class="ph">
%%PLAYER%%
<div class="sb"><span>9:41</span><svg width="77" height="13"><use href="#sbr"/></svg></div>
<i class="grab"></i>
<div class="hd"><h3>The Salt Road</h3><p class="sub">Mara Kessling · Tidewater Saga, Book 2</p><p class="fn">Read by Daniel Okafor</p></div>
<p class="chap">Chapter 14 · The Lantern Keeper</p>
<div class="trk"><i></i></div>
<div class="tl"><span>18:20</span><span class="m">6h 12m left in book</span><span>−18:42</span></div>
<div class="tp">
  <div class="ic" aria-label="Previous chapter"><svg width="26" height="26" viewBox="0 0 24 24"><path d="M5.5 5v14" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/><path d="M19 5.6v12.8a.8.8 0 0 1-1.2.7L8.6 12.7a.8.8 0 0 1 0-1.4l9.2-6.4a.8.8 0 0 1 1.2.7z" fill="currentColor"/></svg></div>
  <div class="ic" aria-label="Back 30 seconds"><svg width="34" height="34"><use href="#b30"/></svg></div>
  <div class="pp" aria-label="Pause"><svg width="34" height="34"><use href="#pause"/></svg></div>
  <div class="ic" aria-label="Forward 30 seconds"><svg width="34" height="34"><use href="#f30"/></svg></div>
  <div class="ic" aria-label="Next chapter"><svg width="26" height="26" viewBox="0 0 24 24"><path d="M18.5 5v14" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/><path d="M5 5.6v12.8a.8.8 0 0 0 1.2.7l9.2-6.4a.8.8 0 0 0 0-1.4L6.2 4.9a.8.8 0 0 0-1.2.7z" fill="currentColor"/></svg></div>
</div>
<div class="sec">
  <div class="ic" aria-label="Speed">1.3×</div>
  <div class="ic" aria-label="Sleep timer"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round"><path d="M20 14.6A8.4 8.4 0 1 1 9.4 4a6.8 6.8 0 0 0 10.6 10.6z"/></svg><small>30 min</small></div>
  <div class="ic" aria-label="AirPlay"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M7 17H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-2"/><path d="m12 14.5 4.8 5.9H7.2z"/></svg></div>
  <div class="ic" aria-label="Chapters"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"><path d="M9 6h12M9 12h12M9 18h12"/><path d="M4 6h.01M4 12h.01M4 18h.01" stroke-width="2.8"/></svg></div>
</div>
<div class="act">
  <div class="flag" role="button"><svg width="20" height="20"><use href="#pflag"/></svg>Plant flag</div>
  <p><b>3 flags planted</b>Chapters 3, 9 and 13</p>
</div>
<div class="hi"></div>
</div>

<!-- RIGHT: Library as a map room -->
<div class="ph">
<div class="sb"><span>9:41</span><svg width="77" height="13"><use href="#sbr"/></svg></div>
<div class="top"><h1>Library</h1><div class="av"><span>J</span></div></div>
<div class="seg" role="tablist"><span class="on" role="tab" aria-selected="true">Maps</span><span role="tab">List</span></div>
<div class="grid">
%%THUMBS%%
</div>
<div class="glass mini">
  <div class="cv">%%COVER%%</div>
  <div class="tx"><b>The Salt Road</b><p class="fn">Ch 14 · 18:42 left</p></div>
  <div class="ic" aria-label="Pause"><svg width="22" height="22"><use href="#pause"/></svg></div>
  <div class="ic" aria-label="Forward 30 seconds"><svg width="26" height="26"><use href="#f30"/></svg></div>
</div>
<nav class="glass tabs">
  <div class="tab"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M3.5 10.6 12 3.4l8.5 7.2V20a.9.9 0 0 1-.9.9h-4.8v-6.2H9.2v6.2H4.4a.9.9 0 0 1-.9-.9z"/></svg>Home</div>
  <div class="tab on"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><rect x="3" y="4" width="4.6" height="16" rx="1"/><rect x="9.6" y="4" width="4.6" height="16" rx="1"/><rect x="17" y="4.6" width="4.4" height="15.4" rx="1" transform="rotate(14 19.2 12.3)"/></svg>Library</div>
  <div class="tab"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="9" cy="8" r="3.3"/><path d="M2.8 20c0-3.6 2.8-6 6.2-6s6.2 2.4 6.2 6"/><circle cx="16.8" cy="8.6" r="2.7"/><path d="M17.4 13.8c2.4.3 4.1 2.4 4.1 5.4"/></svg>Household</div>
</nav>
<div class="glass srch"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#E9E1CF" stroke-width="1.8" stroke-linecap="round"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m15.5 15.5 5 5"/></svg></div>
<div class="hi"></div>
</div>
</body>
</html>
'''

BOOKS = [  # id, title, chapters, progress, flags, plate suffix
    ('li_harbor_of_bells_1', 'Harbor of Bells', 32, 1.0, (5, 21), 'finished'),
    ('li_map_small_hours', 'A Map of Small Hours', 21, 1.0, (8,), 'finished'),
    ('li_salt_road_2', 'The Salt Road', 38, .57, (3, 9, 13), '57%'),
    ('li_cartographers_widow', 'The Cartographer’s Widow', 26, .12, (), '12%'),
    ('li_glass_orchard', 'The Glass Orchard', 30, 0.0, (), 'not started'),
    ('li_iron_and_orchid', 'Iron and Orchid', 24, 0.0, (), 'not started'),
]


def main(out):
    maps = {}
    for bid, title, n, p, fl, note in BOOKS:
        maps[bid] = Map(bid, n, anchor=(14, .57) if bid == 'li_salt_road_2' else None)
    sr = maps['li_salt_road_2']
    s = 378 / W
    view = (-12 / s, -66 / s, 402 / s, 440 / s)
    vb = ' '.join(f(v) for v in view)
    player = sr.render('P', 'player', .57, flags=(3, 9, 13), numerals=True, view=view,
                       labels=[(12, 'Low Water'), (13, 'The Ferryman'), (14, 'The Lantern Keeper')])
    player_svg = (f'<svg class="map" width="402" height="440" viewBox="{vb}" role="img" aria-label="Map of The Salt Road: '
                  f'chapters 1 to 13 charted, chapter 14 half revealed, 15 to 38 under fog; flags in chapters 3, 9 and 13">{player}</svg>')
    thumbs = []
    for idx, (bid, title, n, p, fl, note) in enumerate(BOOKS):
        key = 'T%d' % idx
        inner = maps[bid].render(key, 'thumb', p, flags=fl)
        label = title + ('' if p in (0, 1) else ' · ' + note)
        thumbs.append(f'<figure><div class="fm"><svg viewBox="0 0 400 350" role="img" aria-label="{title}: {note}">'
                      f'<g id="{key}g">{inner}</g></svg></div><figcaption class="plate">{label}</figcaption></figure>')
    (cx, cy), _ = sr.point_at(.57)
    cover = f'<svg width="34" height="34" viewBox="{f(cx - 70)} {f(cy - 62)} 140 140" aria-hidden="true"><use href="#T2g"/></svg>'
    html = TEMPLATE.replace('%%PLAYER%%', player_svg).replace('%%THUMBS%%', '\n'.join(thumbs)).replace('%%COVER%%', cover)
    open(out, 'w').write(html)
    print(out, len(html), 'bytes', html.count('\n') + 1, 'lines', {k: m.mode for k, m in maps.items()})


def standalone(book_id, chapters=30, progress=1.0):
    defs = TEMPLATE[TEMPLATE.index('<svg class="defs"'):TEMPLATE.index('</defs></svg>')].split('<defs>', 1)[1]
    style = TEMPLATE[TEMPLATE.index('/* map lettering */'):TEMPLATE.index('/* native shell */')]
    inner = Map(book_id, chapters).render('S', 'thumb', progress)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 350" width="800" height="700"><style>{style}</style>'
            f'<defs>{defs}</defs>{inner}</svg>')


if __name__ == '__main__':
    if len(sys.argv) > 2 and sys.argv[1] == '--svg':   # gen.py --svg BOOK_ID [CHAPTERS] [PROGRESS] > map.svg
        a = sys.argv[2:] + [None, None]
        print(standalone(a[0], int(a[1] or 30), float(a[2] or 1)))
    else:
        main(sys.argv[1] if len(sys.argv) > 1 else 'fog-map.html')
