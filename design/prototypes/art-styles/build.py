#!/usr/bin/env python3
"""Siren opt-in progress art: Map (with cover cartouche) and Voice print, two player screens.

Usage: python3 -I build.py OUT.html
Standard library only. The map comes from mapgen.py (copy of fogmap/gen.py, square sheet).
The voice-print envelopes are SYNTHETIC: generated from the book ID seed, not from audio.
"""
import math, random, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mapgen as mg

BOOK, CHAPTERS, CUR, BOOK_P, CH_P = 'li_salt_road_2', 38, 14, .57, .40
G, RAISED, TXT, SEC, TINT = '#111316', '#1C1F24', '#F2F2F0', '#A3A8B2', '#3FB6BF'
ART = 354


def f(v):
    return mg.f(v)


# ---------- the jacket: The Salt Road (sea, low sun, a salt causeway; teal / sand / rust) ----------
COVER = ('<symbol id="cov" viewBox="0 0 100 100">'
         '<rect width="100" height="100" fill="#EAD3A0"/>'
         '<circle cx="66" cy="50" r="15" fill="#C0522B"/>'
         '<rect y="50" width="100" height="50" fill="#1E6971"/>'
         '<rect y="50" width="100" height="5" fill="#2C7C83"/>'
         '<path d="M52 53.4h9v1.6h-9zM68 53.4h11v1.6H68zM55 58.6h5v1.5h-5zM70 58.6h7v1.5h-7zM73 64h3v1.4h-3z" fill="#E39A66"/>'
         '<path d="M0 79c13-3 25-1 37 8l-3 13H0z" fill="#D6AE6E"/>'
         '<path d="M100 75c-14 0-28 4-40 12l3 13h37z" fill="#C2914F"/>'
         '<path d="M28 100 63.5 50.5h1L58 100z" fill="#F4EAD2"/>'
         '<path d="M43 100 64 50.5" stroke="#C0522B" stroke-width=".8" stroke-dasharray="2.4 2.4" fill="none"/>'
         '<text x="50" y="17" text-anchor="middle" font-family="ui-serif,&quot;New York&quot;,Georgia,serif" font-weight="600" '
         'font-size="9.8" letter-spacing=".5" fill="#163F45">THE SALT ROAD</text>'
         '<text x="50" y="27" text-anchor="middle" font-family="-apple-system,system-ui,sans-serif" font-weight="600" '
         'font-size="5.4" letter-spacing="1.6" fill="#7A3A20">MARA KESSLING</text>'
         '</symbol>')


# ---------- left: the seeded map with a cartouche in the revealed north-east corner ----------
CW, CH_, CX, CY = 114, 124, ART - 12 - 114, 12          # cartouche box in art-area px


def cartouche():
    k = 400 / ART
    frame = 'M7 0H107A7 7 0 0 0 114 7V117A7 7 0 0 0 107 124H7A7 7 0 0 0 0 117V7A7 7 0 0 0 7 0Z'
    a = math.sqrt(10.5 ** 2 - 3.5 ** 2)
    inner = (f'M{f(a)} 3.5H{f(114 - a)}A10.5 10.5 0 0 0 110.5 {f(a)}V{f(124 - a)}A10.5 10.5 0 0 0 {f(114 - a)} 120.5'
             f'H{f(a)}A10.5 10.5 0 0 0 3.5 {f(124 - a)}V{f(a)}A10.5 10.5 0 0 0 {f(a)} 3.5Z')
    rivets = ''.join(f'<circle cx="{x}" cy="{y}" r="1.7"/>' for x in (0, 114) for y in (0, 124))
    return (f'<g transform="translate({f(CX * k)} {f(CY * k)}) scale({k:.5f})" role="img" aria-label="The Salt Road by Mara Kessling">'
            f'<path d="{frame}" fill="#F2EBDA" stroke="#2B2620" stroke-width="1.1" filter="url(#cs)"/>'
            f'<path d="{inner}" fill="none" stroke="#2B2620" stroke-width=".6"/>'
            f'<g fill="#2B2620">{rivets}</g>'
            '<rect x="23.5" y="8.5" width="67" height="67" fill="none" stroke="#2B2620" stroke-width=".7"/>'
            '<use href="#cov" x="25" y="10" width="64" height="64"/>'
            '<text class="ct" x="57" y="93">The Salt Road</text>'
            '<path d="M34 99.5H52M62 99.5H80" stroke="#2B2620" stroke-width=".6"/><path d="M57 97 59.5 99.5 57 102 54.5 99.5Z" fill="#2B2620"/>'
            '<text class="ca" x="57" y="114">Mara Kessling</text></g>')


def map_svg():
    m = mg.Map(BOOK, CHAPTERS, anchor=(CUR, BOOK_P))
    k = 400 / ART
    box = (CX * k, CY * k, (CX + CW) * k, (CY + CH_) * k)
    inner = m.render('M', 'player', BOOK_P, flags=(3, 9, 13), numerals=True, labels=[(CUR, 'The Lantern Keeper')], reserve=[box])
    return (f'<svg width="{ART}" height="{ART}" viewBox="0 0 400 400" role="img" aria-label="Map of The Salt Road: chapters 1 to 13 charted, '
            f'chapter 14 half revealed, 15 to 38 under fog; flags in chapters 3, 9 and 13">{inner}{cartouche()}</svg>'), m.mode


# ---------- right: voice print, one synthetic loudness envelope per chapter ----------
def envelope(seed, ch, n):
    """Speech-shaped loudness across one chapter, one value per sample (1 = narration level), from the book seed.
    A short heading ("Chapter Fourteen. The Lantern Keeper."), a pause, a quiet opening that warms up,
    narration phrases split by short pauses and the odd paragraph break, louder clipped dialogue scenes,
    an optional scene break, a fade and a little trailing room tone."""
    r = random.Random(f'{seed}:voice:{ch}')
    a = [0.0] * n
    level = r.uniform(.85, 1.15)

    def bump(i, w, amp):
        for j in range(w):
            if 0 <= i + j < n:
                u = (j + .5) / w
                a[i + j] = max(a[i + j], amp * math.sin(math.pi * u) ** .55 * (1 - .22 * u) * (1 + .44 * (r.random() - .5)))
    i = int(n * r.uniform(.014, .026))
    bump(i, 3, .5 * level); bump(i + 4, 4, .58 * level)
    i += 8 + r.randint(5, 8)
    t_open = i; open_end = i + int(n * r.uniform(.1, .16)); end = n - int(n * r.uniform(.025, .045))
    scenes = []
    for _ in range(1 + int(r.random() * 3.4)):
        s0 = r.randint(open_end, end - 16); scenes.append((s0, s0 + r.randint(8, 22)))
    brk = r.randint(int(n * .35), int(n * .8)) if r.random() < .4 else None
    while i < end:
        if brk is not None and i >= brk:
            i += r.randint(6, 10); brk = None; continue
        dlg = any(s0 <= i < s1 for s0, s1 in scenes)
        if dlg:
            w = r.randint(2, 5); g = r.uniform(1.6, 2.7) * (1.3 if r.random() < .12 else 1)
        else:
            w = r.randint(4, 12); g = r.uniform(.75, 1.15)
        ramp = .42 + .58 * min(1, (i - t_open) / (open_end - t_open))
        fade = .5 + .5 * min(1, (end - i) / 10)
        bump(i, min(w, end - i), level * g * ramp * fade)
        i += w + (r.randint(1, 2) if dlg else r.randint(1, 3))
        if not dlg and r.random() < .08:
            i += r.randint(4, 7)                                   # paragraph pause
    out = [v if v > 0 else .05 + .07 * r.random() for v in a]       # room tone
    out[0] = out[-1] = 0.0
    return out


def smooth_d(x0, dx, ys, stop=None):
    """Quadratic curve through the midpoints of the samples (control points on the samples).
    With stop (an x inside the line) the curve is cut there exactly; returns (d, end point)."""
    n = len(ys); xs = [x0 + k * dx for k in range(n)]
    d = [f'M{f(xs[0])} {f(ys[0])}L{f(xs[0] + dx / 2)} {f((ys[0] + ys[1]) / 2)}q']
    cx, cy = xs[0] + dx / 2, (ys[0] + ys[1]) / 2
    for j in range(1, n - 1):
        mx, my = xs[j] + dx / 2, (ys[j] + ys[j + 1]) / 2
        if stop is not None and mx >= stop:
            t = (stop - cx) / dx
            qx, qy = cx + (xs[j] - cx) * t, cy + (ys[j] - cy) * t
            ey = (1 - t) ** 2 * cy + 2 * t * (1 - t) * ys[j] + t * t * my
            d.append(f'{f(qx - cx)} {f(qy - cy)} {f(stop - cx)} {f(ey - cy)}')
            return ' '.join(d), (stop, ey)
        d.append(f'{f(xs[j] - cx)} {f(ys[j] - cy)} {f(mx - cx)} {f(my - cy)}')
        cx, cy = mx, my
    return ' '.join(d) + f'L{f(xs[-1])} {f(ys[-1])}', (xs[-1], ys[-1])


def voice_svg():
    seed = mg.seed_of(BOOK)
    x0, x1, top, bot, N, AMP = 34.0, 340.0, 44.0, 340.0, 154, 6.2
    sp = (bot - top) / (CHAPTERS - 1); dx = (x1 - x0) / (N - 1)
    xp = x0 + CH_P * (x1 - x0)
    body = [f'<rect width="{ART}" height="{ART}" fill="{RAISED}"/>']
    faint = f'stroke="{SEC}" stroke-opacity=".46" stroke-width="1.15" stroke-linecap="round" stroke-dasharray="0 2.7"'
    full = f'stroke="{TXT}" stroke-width="1.15" stroke-linejoin="round"'
    marker = ''
    for i in range(CHAPTERS):
        ch = i + 1; base = top + i * sp
        ys = [base - min(v * AMP, 26) for v in envelope(seed, ch, N)]
        d, _ = smooth_d(x0, dx, ys)
        body.append(f'<path d="{d}" fill="{RAISED}" {full if ch < CUR else faint}/>')
        if ch == CUR:
            hd, (px, py) = smooth_d(x0, dx, ys, stop=xp)
            body.append(f'<path d="{hd}" fill="none" {full}/>')
            marker = f'<circle cx="{f(px)}" cy="{f(py)}" r="4.2" fill="{TINT}" stroke="{RAISED}" stroke-width="2"/>'
        if ch % 5 == 0:
            body.append(f'<text class="vn" x="26" y="{f(base + 3.2)}">{ch}</text>')
    body.append(marker)
    body.append(f'<rect x="10" y="8" width="64" height="64" rx="9" fill="{RAISED}"/>'
                '<clipPath id="vcl"><rect x="14" y="12" width="56" height="56" rx="6"/></clipPath>'
                '<g clip-path="url(#vcl)"><use href="#cov" x="14" y="12" width="56" height="56"/></g>')
    return (f'<svg width="{ART}" height="{ART}" viewBox="0 0 {ART} {ART}" role="img" aria-label="Voice print of The Salt Road: '
            f'38 chapter loudness lines, 1 to 13 heard, chapter 14 heard to 40 percent">{"".join(body)}</svg>')


# ---------- page ----------
def player(art, dot):
    dots = ''.join(f'<i{" class=on" if k == dot else ""}></i>' for k in range(3))
    return f'''<div class="ph">
<div class="sb"><span>9:41</span><svg width="77" height="13"><use href="#sbr"/></svg></div>
<i class="grab"></i>
<div class="art">{art}</div>
<div class="dots" aria-label="Page {dot + 1} of 3: Cover, Map, Voice">{dots}</div>
<h2>The Salt Road</h2>
<p class="by">Mara Kessling · read by Daniel Okafor</p>
<p class="chp">Ch 14 · The Lantern Keeper</p>
<div class="trk"><i></i><b></b></div>
<div class="tm"><span>12:28</span><span>6h 12m left in book</span><span>−18:42</span></div>
<div class="tp">
<button aria-label="Previous chapter"><svg width="26" height="26"><use href="#prv"/></svg></button>
<button aria-label="Back 30 seconds"><svg width="34" height="34"><use href="#b30"/></svg></button>
<button class="pp" aria-label="Pause"><svg width="32" height="32"><use href="#pau"/></svg></button>
<button aria-label="Forward 30 seconds"><svg width="34" height="34"><use href="#f30"/></svg></button>
<button aria-label="Next chapter"><svg width="26" height="26"><use href="#nxt"/></svg></button>
</div>
<div class="ut">
<button aria-label="Speed 1.3 times">1.3×</button>
<button aria-label="Sleep timer, 30 minutes"><svg width="20" height="20"><use href="#moon"/></svg>30 min</button>
<button aria-label="AirPlay"><svg width="24" height="24"><use href="#air"/></svg></button>
<button aria-label="Add bookmark"><svg width="22" height="22"><use href="#bmk"/></svg></button>
<button aria-label="Chapters"><svg width="24" height="24"><use href="#lst"/></svg></button>
</div>
<i class="hi"></i>
</div>'''


def main(out):
    T = mg.TEMPLATE
    mapdefs = T[T.index('<pattern id="hatch"'):T.index('<symbol id="sbr"')]
    mapcss = T[T.index('/* map lettering */'):T.index('/* native shell */')].replace('/* map lettering */\n', '')
    msvg, mode = map_svg()
    vsvg = voice_svg()
    html = TEMPLATE.replace('%%MAPDEFS%%', mapdefs).replace('%%MAPCSS%%', mapcss).replace('%%COVER%%', COVER) \
        .replace('%%LEFT%%', player(msvg, 1)).replace('%%RIGHT%%', player(vsvg, 2))
    open(out, 'w').write(html)
    print(out, len(html), 'bytes', html.count('\n') + 1, 'lines, map mode', mode)


TEMPLATE = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=820">
<title>Siren, Progress Art Styles</title>
<!-- Opt-in progress art in the player's art area. Left: seeded fog map (book ID SHA-256 seed) with a cover cartouche.
     Right: voice print, 38 chapter loudness lines. The envelopes are SYNTHETIC, generated from the book ID seed, not from audio.
     Generated by build.py; nothing is hand-placed. -->
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IM+Fell+English:ital@0;1&display=block">
<style>
:root{--g:#111316;--rz:#1C1F24;--t:#F2F2F0;--s:#A3A8B2;--tint:#3FB6BF;--wash:#16343A;--paper:#E9E1CF;--ink:#2B2620;--sys:-apple-system,"SF Pro Text",system-ui,sans-serif;--ny:ui-serif,"New York",Georgia,serif;--fell:"IM Fell English",Georgia,serif}
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:820px;height:874px;overflow:hidden;background:#2A2B2F}
body{display:flex;gap:16px;color:var(--t);font-family:var(--sys);-webkit-font-smoothing:antialiased;font-variant-numeric:tabular-nums}
::selection{background:var(--wash);color:var(--t)}
svg{display:block}
.defs{position:absolute;width:0;height:0}
%%MAPCSS%%.ct{font:15px var(--fell);fill:var(--ink);text-anchor:middle}
.ca{font:italic 11.5px var(--fell);fill:var(--ink);text-anchor:middle}
.vn{font:600 9px var(--sys);fill:var(--s);fill-opacity:.8;text-anchor:end;font-variant-numeric:tabular-nums}
.ph{position:relative;width:402px;height:874px;flex:none;border-radius:48px;overflow:hidden;background:var(--g)}
.sb{height:54px;display:flex;align-items:center;justify-content:space-between;padding:6px 28px 0 50px;font-size:17px;font-weight:600;letter-spacing:-.4px}
.grab{position:absolute;left:183px;top:66px;width:36px;height:5px;border-radius:3px;background:rgba(242,242,240,.34)}
.art{position:absolute;left:24px;top:96px;width:354px;height:354px;border-radius:6px;overflow:hidden;background:var(--rz);box-shadow:0 2px 8px rgba(0,0,0,.18)}
.dots{position:absolute;left:0;right:0;top:464px;display:flex;justify-content:center;gap:9px}
.dots i{width:7px;height:7px;border-radius:50%;background:rgba(242,242,240,.3)}
.dots i.on{background:var(--tint)}
h2{position:absolute;left:24px;right:24px;top:488px;font:600 26px/32px var(--ny);letter-spacing:-.01em}
.by{position:absolute;left:24px;right:24px;top:522px;font-size:15px;line-height:20px;color:var(--s)}
.chp{position:absolute;left:24px;right:24px;top:550px;font-size:15px;line-height:20px;font-weight:600;letter-spacing:-.2px}
.trk{position:absolute;left:24px;right:24px;top:590px;height:4px;border-radius:2px;background:rgba(242,242,240,.16)}
.trk i{position:absolute;left:0;top:0;bottom:0;width:40%;border-radius:2px;background:var(--tint)}
.trk b{position:absolute;left:calc(40% - 7px);top:-5px;width:14px;height:14px;border-radius:50%;background:var(--t);box-shadow:0 1px 4px rgba(0,0,0,.4)}
.tm{position:absolute;left:24px;right:24px;top:604px;display:flex;justify-content:space-between;font-size:13px;line-height:16px;font-weight:500;color:var(--s)}
.tm span:nth-child(2){color:var(--t)}
button{font:inherit;color:inherit;background:none;border:0;display:flex;align-items:center;justify-content:center}
.tp{position:absolute;left:24px;right:24px;top:652px;height:72px;display:flex;align-items:center;justify-content:space-between;color:var(--t)}
.tp button{width:44px;height:44px}
.tp .pp{width:72px;height:72px;border-radius:50%;background:var(--tint);color:var(--g)}
.ut{position:absolute;left:14px;right:14px;top:772px;height:44px;display:flex;align-items:center;justify-content:space-between;color:var(--s)}
.ut button{min-width:44px;height:44px;padding:0 8px;gap:6px;font-size:15px;font-weight:600}
.hi{position:absolute;left:134px;bottom:8px;width:134px;height:5px;border-radius:3px;background:var(--t)}
</style>
</head>
<body>
<svg class="defs" aria-hidden="true"><defs>
%%MAPDEFS%%<filter id="cs" x="-20%" y="-20%" width="140%" height="150%"><feDropShadow dx="0" dy="3" stdDeviation="4" flood-color="#000" flood-opacity=".5"/></filter>
%%COVER%%
<symbol id="sbr" viewBox="0 0 77 13"><g fill="#F2F2F0"><rect y="8" width="3" height="4" rx="1"/><rect x="5" y="5.5" width="3" height="6.5" rx="1"/><rect x="10" y="3" width="3" height="9" rx="1"/><rect x="15" width="3" height="12" rx="1"/></g><path d="M25.5 4.4a9.4 9.4 0 0 1 13 0M28.2 7.2a5.6 5.6 0 0 1 7.6 0" fill="none" stroke="#F2F2F0" stroke-width="1.8" stroke-linecap="round"/><circle cx="32" cy="10.2" r="1.3" fill="#F2F2F0"/><rect x="49.5" y=".5" width="23" height="12" rx="3.8" fill="none" stroke="#F2F2F0" stroke-opacity=".4"/><rect x="51" y="2" width="20" height="9" rx="2.4" fill="#F2F2F0"/><path d="M74 4.5v4c.8-.3 1.4-1.1 1.4-2s-.6-1.7-1.4-2z" fill="#F2F2F0" fill-opacity=".4"/></symbol>
<symbol id="pau" viewBox="0 0 24 24"><rect x="6" y="4.5" width="4.2" height="15" rx="1.3" fill="currentColor"/><rect x="13.8" y="4.5" width="4.2" height="15" rx="1.3" fill="currentColor"/></symbol>
<symbol id="f30" viewBox="0 0 28 28"><path d="M14 5.5A9.5 9.5 0 1 1 5.8 10.2" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/><path d="M13.6 2.3l4 3.2-4 3.2z" fill="currentColor"/><text x="14" y="18.4" text-anchor="middle" font-size="8.4" font-weight="700" fill="currentColor" font-family="-apple-system,system-ui">30</text></symbol>
<symbol id="b30" viewBox="0 0 28 28"><path d="M14 5.5A9.5 9.5 0 1 0 22.2 10.2" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/><path d="M14.4 2.3l-4 3.2 4 3.2z" fill="currentColor"/><text x="14" y="18.4" text-anchor="middle" font-size="8.4" font-weight="700" fill="currentColor" font-family="-apple-system,system-ui">30</text></symbol>
<symbol id="prv" viewBox="0 0 24 24"><rect x="4.6" y="5" width="2.2" height="14" rx="1.1" fill="currentColor"/><path d="M19 6.2v11.6a.9.9 0 0 1-1.4.7L9.4 12.7a.9.9 0 0 1 0-1.4l8.2-5.8a.9.9 0 0 1 1.4.7z" fill="currentColor"/></symbol>
<symbol id="nxt" viewBox="0 0 24 24"><rect x="17.2" y="5" width="2.2" height="14" rx="1.1" fill="currentColor"/><path d="M5 6.2v11.6a.9.9 0 0 0 1.4.7l8.2-5.8a.9.9 0 0 0 0-1.4L6.4 5.5A.9.9 0 0 0 5 6.2z" fill="currentColor"/></symbol>
<symbol id="moon" viewBox="0 0 24 24"><path d="M20 14.6A8.4 8.4 0 1 1 9.4 4a6.8 6.8 0 0 0 10.6 10.6z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/></symbol>
<symbol id="air" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M7 17H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-2"/><path d="m12 14.5 4.8 5.9H7.2z"/></g></symbol>
<symbol id="bmk" viewBox="0 0 24 24"><path d="M6.5 4.2a1 1 0 0 1 1-1h9a1 1 0 0 1 1 1v16.3l-5.5-4-5.5 4z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/></symbol>
<symbol id="lst" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M9 6h11.5M9 12h11.5M9 18h11.5"/><path d="M4.2 6h.01M4.2 12h.01M4.2 18h.01" stroke-width="2.8"/></g></symbol>
</defs></svg>

<!-- LEFT: player, Map view (page 2 of 3) -->
%%LEFT%%

<!-- RIGHT: player, Voice print view (page 3 of 3) -->
%%RIGHT%%
</body>
</html>
'''

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'art-styles.html')
