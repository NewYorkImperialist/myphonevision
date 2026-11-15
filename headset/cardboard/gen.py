#!/usr/bin/env python3
"""Cardboard headset for the iPhone 16 Pro + two Carson TriView TV-36 magnifiers.

Writes template.svg (all pages side by side, 1 unit = 1 mm), pages/page-N.svg,
template.pdf, preview/page-N.png and overview.svg/png, then measures the key
sizes back out of template.svg and fails if any is off.

    python3 gen.py              # 3 mm corrugated card
    python3 gen.py --t 4        # thicker card
    python3 gen.py --d-max 24   # shorter body once the focus distance is known

Needs shapely and rsvg-convert. Optics, IPD and phone numbers are the ones in
headset/slot_headset.scad.

Frame: x along the phone (camera end 0, USB end W), y up from the floor's inner
face, z from the body's front edge toward the phone. Every fold is a "mountain":
cut through the top liner only on the printed side and fold away from it, so the
distance between two fold lines is the inside size and needs no allowance. Card
thickness T sets tab lengths, slot widths, the pocket blocks (LAYERS x T, about
9 mm) and the sizes of the parts that nest inside the body. Works for corrugated
card from 2 to 4 mm; thinner card is too soft and the carrier no longer fits a page.
"""
import argparse, math, re, subprocess
from pathlib import Path
from shapely import affinity
from shapely.geometry import LineString, MultiLineString, Point, box
from shapely.ops import unary_union

ap = argparse.ArgumentParser()
ap.add_argument("--t", type=float, default=3.0, help="card thickness, mm")
ap.add_argument("--d-max", type=float, default=32.0, help="longest rear-lens-face-to-screen distance, mm")
ap.add_argument("--d-min", type=float, default=24.0)
ap.add_argument("--v2", action="store_true", help="double face ring (R1 + R2) with wrap tabs, long body tabs, hook doublers; writes v2/")
args = ap.parse_args()
T, D_MAX, D_MIN, V2 = args.t, args.d_max, args.d_min, args.v2

# ---- Measured / spec (same as slot_headset.scad) ----------------------------
PHONE_W, PHONE_H, PHONE_T = 149.6, 71.5, 8.95
SCREEN_W, SCREEN_H = 144.8, 66.7
CAM_END = 43.5            # camera bump ends this far from the phone's top
IPD = 63.0
FRAME_OD, STACK = 38.75, 21.09   # Nafis's calipers
GLASS = 30.0
# ---- Unmeasured: oversized on purpose, trimmed or shimmed at the table -------
CASE_W = 40.6             # manual; the slots leave 2.4 mm over it
BTN_FREE = 18.0           # button-free length at each end of the phone's long edges
USB_W, USB_H, USB_LEN = 13.0, 8.0, 25.0
THUMB = (10.0, 5.0)       # room under each lens frame for the thumb tabs
PAD = 2.0                 # foam behind the phone, squeezed

FIT = 0.3                 # slot = tab + FIT
GAP = STACK + 1.0         # between the carrier plates
LAYERS = max(2, round(9 / T))   # card layers in a pocket block
M = LAYERS * T            # pocket margin around the phone (9 mm with 3 mm card)
N_BLOCKS = 6 * LAYERS - 2 # bottom 2 stacks + USB end 2 stacks (LAYERS each), top 2 stacks (one layer less, plus foam)
W, H = PHONE_W + 2 * M, PHONE_H + 2 * M          # body, inside
XC, YC = W / 2, H / 2                            # phone centre = lens height
ZS = T + GAP + D_MAX                             # screen plane
DEPTH = ZS + PHONE_T + PAD
TRAVEL = D_MAX - D_MIN
ZN = TRAVEL + T + GAP + 1                        # magnifier notch depth in the top wall
SLOT_W = CASE_W + 2.4
AP = GLASS + 3
SEAT = FRAME_OD + 0.75
WP, HP = W - 1 - 2 * T, H - 1 - T                # carrier plates
YL = YC - T - 0.5                                # lens centre above the carrier's fold
NOSE_W, NOSE_TOP = 38.0, 34.0                    # nose arch: width, top above the floor
HOOKS = (XC - 12, XC + 48)                       # band hooks, clear of the camera
XCUT = M + CAM_END + 1.5                         # back flap starts here
LIP = 8.0
EAR = 22.0 if V2 else 16.0                       # strap ear depth; v2 leaves 9 mm of card outside the slot
EAR_L = 25.0 if V2 else 21.0                     # half the side ears' length
TAB = 2 * T + 8 if V2 else T                     # body tabs: through R (two layers in v2) plus 8 mm to fold and tape
A_TAB = (2.0, 14.0) if V2 else (6.0, 22.0)       # A's end tabs; v2 moves them out to make room for R's top wrap tabs
WRAP = 25.0                                      # v2: R's wrap tabs, folded back along the body
STRAP = (4.0, 32.0)                              # issue #9
LENS_X = (-IPD / 2, IPD / 2)

assert D_MIN >= 2 * T + 1, "carrier would hit the screen frame"
assert ZS - T - ZN > 6, "top wall too thin between the notches and the hook slots"
assert IPD - SLOT_W > 15, "no card left between the magnifier slots"
assert (H - SCREEN_H - 1) / 2 > 8 and (W - SCREEN_W - 1) / 2 > 8, "screen frame bars too thin"
assert XCUT + 10 < HOOKS[0] - 7, "hook under the camera"


def nose(h):
    r = 0.33 * NOSE_W
    return unary_union([box(-NOSE_W / 2, -1, NOSE_W / 2, 0), Point(0, h - r).buffer(r, 32)]).convex_hull


def at(g, x=0, y=0):
    return affinity.translate(g, x, y)


class Part:
    def __init__(self, shape, label, lx, ly, sub=""):
        self.shape, self.lines, self.texts, self.tags, self.probes = shape, [], [], [], []
        self.text(lx, ly, label, 6)
        if sub:
            self.text(lx, ly, sub, 2.6, 4.5)

    def text(self, x, y, s, size=2.6, drop=0):   # drop: mm below (x, y) on the page, whatever the rotation
        self.texts.append((x, y, s, size, drop))

    def line(self, kind, *pts):
        self.lines.append((kind, LineString(pts)))

    def probe(self, name, p, q, want):
        self.probes.append((name, p, q, want))


# ---- Parts -------------------------------------------------------------------
def top_wall():          # seen from above: right = +x, up = front
    flap_h = H + T + LIP
    s = unary_union([box(-T, -DEPTH, W + T, 0), box(XC - 6, 0, XC + 6, TAB),
                     box(A_TAB[0], 0, A_TAB[1], TAB), box(W - A_TAB[1], 0, W - A_TAB[0], TAB),
                     box(XCUT, -DEPTH - flap_h, W + T, -DEPTH)])
    for lx in LENS_X:
        s -= box(XC + lx - SLOT_W / 2, -ZN, XC + lx + SLOT_W / 2, T + 1)
    for hx in HOOKS:
        s -= box(hx - 7 - FIT / 2, -ZS - FIT / 2, hx + 7 + FIT / 2, -ZS + T + FIT / 2)
    p = Part(s, "A", W - 22, -ZS - 30, "step 5")
    p.line("mountain", (XCUT, -DEPTH), (W + T, -DEPTH))
    for px in (-12, 52):                         # foam pads behind the phone (inside face)
        for py in (-20, 20):
            x, y = XC + px, -DEPTH - (H - YC - py)
            p.line("guide", (x - 10, y - 10), (x + 10, y - 10), (x + 10, y + 10), (x - 10, y + 10), (x - 10, y - 10))
    for d in range(int(D_MIN), int(D_MAX) + 1, 2):   # focus scale: rear lens face to screen
        p.line("guide", (XC - 10, -ZS + d), (XC - (5 if d % 4 == 0 else 7.5), -ZS + d))
        if d % 4 == 0:
            p.text(XC - 2, -ZS + d - 0.8, str(d), 2.2)
    p.text(XC, -6, "FRONT"); p.text(4, -DEPTH + 3, "CAM"); p.text(W - 4, -DEPTH + 3, "USB")
    p.probe("A magnifier notch width", (XC + LENS_X[0] - 30, -10), (XC + LENS_X[0] + 30, -10), SLOT_W)
    p.probe("A card behind the magnifier notch (depth - notch)", (XC + LENS_X[0], -ZN + 5), (XC + LENS_X[0], -DEPTH - 5), DEPTH - ZN)
    return p


def bottom_wall():       # seen from below: right = +x, up = back
    s = unary_union([box(-T, 0, W + T, DEPTH), box(6, -TAB, 22, 0), box(W - 22, -TAB, W - 6, 0)])
    s -= at(nose(30), XC, 0)
    for hx in HOOKS:
        s -= box(hx - 7 - FIT / 2, ZS - T - FIT / 2, hx + 7 + FIT / 2, ZS + FIT / 2)
    p = Part(s, "B", W - 22, 30, "step 5")
    p.text(XC + 40, 4, "FRONT"); p.text(4, DEPTH - 5, "CAM"); p.text(W - 4, DEPTH - 5, "USB")
    return p


def side_wall(usb):      # seen from outside; cam: right = back, usb: right = front
    s = unary_union([box(0, 0, DEPTH, H), box(-TAB, YC - 10, 0, YC + 10)])
    s -= box(ZS - T - FIT / 2, YC - 10 - FIT / 2, ZS + FIT / 2, YC + 10 + FIT / 2)
    if usb:
        s -= box(ZS + 0.5 - 1, YC - USB_W / 2, DEPTH + 1, YC + USB_W / 2)
    p = Part(s, "SU" if usb else "SC", 28, 22, "step 5")
    p.text(8, YC + 16, "FRONT"); p.text(28, H - 6, "TOP")
    if usb:
        p.probe("SU plug notch width", (ZS + 6, YC - 12), (ZS + 6, YC + 12), USB_W)
        p.shape = affinity.scale(p.shape, -1, 1, origin=(0, 0))
        p.texts = [(-x, y, *rest) for x, y, *rest in p.texts]
        p.probes = [(n, (-a[0], a[1]), (-b[0], b[1]), w) for n, a, b, w in p.probes]
    return p


def face_ring(layer=0):  # x centred; symmetric, so it has no left or right. v2: layer 0 = R1 (back), 1 = R2 (face)
    o = T + 6
    s = unary_union([box(-XC - o + 6, -o + 6, XC + o - 6, H + o - 6).buffer(6),
                     box(-XC - o - EAR, YC - EAR_L, XC + o + EAR, YC + EAR_L),
                     box(-EAR_L, H + o - 1, EAR_L, H + o + EAR)])
    s -= box(-XC + 12, 12, XC - 12, H - 12).buffer(6)
    s -= at(nose(NOSE_TOP + o), 0, -o)
    folds = []
    if V2:
        # Wrap tabs fold back over the body's outside. R2's fold sits one card further out, so it wraps around R1's tab.
        hinge = T * (1 + layer)
        a_slot = XC - A_TAB[1] - FIT / 2                         # inner edge of the slot for A's end tab
        spans = []
        for sx in (-1, 1):
            spans.append(("y", H + hinge, 1, sorted((sx * (IPD / 2 + SLOT_W / 2 + 1.5), sx * (a_slot - 4)))))   # top, clear of the magnifier notches
            spans.append(("y", -hinge, -1, sorted((sx * (NOSE_W / 2 + 3), sx * (XC - 22 - FIT / 2 - 4)))))   # bottom, clear of the nose
            for y0, y1 in ((4, YC - EAR_L - 1.5), (YC + EAR_L + 1.5, H - 4)):                                 # sides, clear of the ears
                spans.append(("x", sx * (XC + hinge), sx, (y0, y1)))
        for axis, c, d, (u0, u1) in spans:     # 4 mm from a slot leaves ~3 mm of card beside the slit's end
            assert u1 - u0 >= 10, "wrap tab under 10 mm wide"
            flap = box(u0, c, u1, c + d * WRAP) if axis == "y" else box(c, u0, c + d * WRAP, u1)
            s = s.union(flap)
            reach = sorted((c, c + d * (o - hinge + 2)))          # slits beside the tab, from the fold out past the rim
            for u in (u0 - 0.6, u1):
                s -= box(u, *reach[:1], u + 0.6, reach[1]) if axis == "y" else box(reach[0], u, reach[1], u + 0.6)
                s -= Point((u + 0.3, c) if axis == "y" else (c, u + 0.3)).buffer(0.8, 12)   # round end so the fold can't tear on
            folds.append(((u0, c), (u1, c)) if axis == "y" else ((c, u0), (c, u1)))
    for sx in (-1, 1):
        x = sx * (XC + o + EAR / 2)
        s -= box(x - STRAP[0] / 2, YC - STRAP[1] / 2, x + STRAP[0] / 2, YC + STRAP[1] / 2)
        ax = sorted((sx * (XC - A_TAB[0]), sx * (XC - A_TAB[1])))
        s -= box(ax[0] - FIT / 2, H - FIT / 2, ax[1] + FIT / 2, H + T + FIT / 2)
        s -= box(sx * (XC - 14) - 8 - FIT / 2, -T - FIT / 2, sx * (XC - 14) + 8 + FIT / 2, FIT / 2)
        xs = sorted((sx * (XC - FIT / 2), sx * (XC + T + FIT / 2)))
        s -= box(xs[0], YC - 10 - FIT / 2, xs[1], YC + 10 + FIT / 2)
    s -= box(-6 - FIT / 2, H - FIT / 2, 6 + FIT / 2, H + T + FIT / 2)
    s -= box(-STRAP[1] / 2, H + o + EAR / 2 - STRAP[0] / 2, STRAP[1] / 2, H + o + EAR / 2 + STRAP[0] / 2)
    name = ("R1" if layer == 0 else "R2") if V2 else "R"
    sub = ("back" if layer == 0 else "face") if V2 else "step 5"
    p = Part(s, name, 35, H + 1.5, sub)
    p.text(-35, H + 1.5, "TOP")
    for a, b in folds:
        p.line("mountain", a, b)
    p.probe(f"{name} strap slot length", (XC + o + EAR / 2, YC - 20), (XC + o + EAR / 2, YC + 20), STRAP[1])
    p.probe(f"{name} tab slot width (card T + fit)", (0, H - 2), (0, H + T + 2), T + FIT)
    return p


def hook_doublers():     # v2: glued on the part of each F hook that sticks out past A or B, so the band pulls on two layers
    pieces = []
    for i in range(4):
        x = i * 18
        piece = box(x, 0, x + 14, 9.5)
        for xs in ((x - 1, x + 2.5), (x + 11.5, x + 15)):
            piece -= box(xs[0], 1.0, xs[1], 4.5)
        pieces.append(piece)
    p = Part(unary_union(pieces), "FH", -9, 4.75, "x4")
    return p


def screen_frame():      # seen from behind (the phone side): right = +x
    s = box(0.3, 0.3, W - 0.3, H - 0.3)
    for hx in HOOKS:
        for sy, y0 in ((1, H), (-1, 0)):
            hook = box(hx - 7, y0 - 1, hx + 7, y0 + T + 10) if sy > 0 else box(hx - 7, y0 - T - 10, hx + 7, y0 + 1)
            for sx in (-1, 1):
                xs = sorted((hx + sx * 4.5, hx + sx * 7.1))
                ys = sorted((y0 + sy * (T + 1.5), y0 + sy * (T + 5)))
                hook -= box(xs[0], ys[0], xs[1], ys[1])
            s = s.union(hook)
    tab = box(W - 1, YC - 10, W + T + 45, YC + 10)           # cable tie-down
    for x in (W + T + 28, W + T + 38):
        tab -= box(x - 1.5, YC - 11, x + 1.5, YC - 7.5)
        tab -= box(x - 1.5, YC + 7.5, x + 1.5, YC + 11)
    s = unary_union([s, tab, box(-T, YC - 10, 1, YC + 10)])
    s -= box(XC - SCREEN_W / 2 - 0.5, YC - SCREEN_H / 2 - 0.5, XC + SCREEN_W / 2 + 0.5, YC + SCREEN_H / 2 + 0.5)
    p = Part(s, "F", 30, H - 5.5, "step 5")
    p.text(5.5, YC + 20, "CAM"); p.text(W - 5.5, YC + 20, "USB"); p.text(XC + 20, H - 5.5, "TOP")
    p.probe("F window width (screen + 1)", (XC - 80, YC), (XC + 80, YC), SCREEN_W + 1)
    p.probe("F window height (screen + 1)", (XC, YC - 40), (XC, YC + 40), SCREEN_H + 1)
    return p


def plate_cuts(seat):
    """Holes in one carrier plate (seat=False) or seat layer (True); fold at y = 0."""
    cuts = [at(nose(NOSE_TOP - T - 0.5), WP / 2, 0)]
    for lx in LENS_X:
        x = WP / 2 + lx
        cuts.append(box(x - SLOT_W / 2, YL + 21, x + SLOT_W / 2, HP + 1))
        if seat:
            cuts += [Point(x, YL).buffer(SEAT / 2, 32), box(x - SEAT / 2, YL, x + SEAT / 2, YL + 21.5),
                     box(x - THUMB[0] / 2, YL - SEAT / 2 - THUMB[1], x + THUMB[0] / 2, YL)]
        else:
            cuts.append(Point(x, YL).buffer(AP / 2, 32))
    return unary_union(cuts)


def carrier():           # net, outside face up: front plate, floor, rear plate, end flaps
    s = unary_union([box(0, -GAP - HP, WP, HP), box(-GAP, 0, 0, HP), box(WP, 0, WP + GAP, HP)])
    cuts = plate_cuts(False)
    s -= cuts
    s -= at(affinity.scale(cuts, 1, -1, origin=(0, 0)), 0, -GAP)
    s -= box(WP / 2 - NOSE_W / 2, -GAP, WP / 2 + NOSE_W / 2, 0)
    p = Part(s, "C", 22, 12, "step 3")
    for y in (0, -GAP):
        p.line("mountain", (0, y), (WP / 2 - NOSE_W / 2, y))
        p.line("mountain", (WP / 2 + NOSE_W / 2, y), (WP, y))
    p.line("mountain", (0, 0), (0, HP)); p.line("mountain", (WP, 0), (WP, HP))
    p.text(WP / 2, 36, "FRONT"); p.text(WP / 2, -GAP - 36, "REAR")
    for name, y in (("front", YL), ("rear", -GAP - YL)):
        for side, lx in zip("LR", LENS_X):
            p.tags.append((f"ap-{name}-{side}", (WP / 2 + lx, y)))
    p.probe("C aperture diameter", (WP / 2 + LENS_X[0] - 20, YL), (WP / 2 + LENS_X[0] + 20, YL), AP)
    p.probe("C plate spacing (stack + 1)", (20, 5), (20, -GAP - 5), GAP)
    return p


def seat():
    s = box(0.5, 0, WP - 0.5, HP) - plate_cuts(True)
    p = Part(s, "S", 22, 12, "x2  step 3")
    for side, lx in zip("LR", LENS_X):
        x = WP / 2 + lx
        p.probe(f"S seat width {side} (frame 38.75 + 0.75)", (x - 25, YL), (x + 25, YL), SEAT)
    p.probe("S card between the seats (IPD 63 - seat)", (WP / 2 + LENS_X[0], YL), (WP / 2 + LENS_X[1], YL), IPD - SEAT)
    return p


def grid(w, h, nx, ny, label, sub):
    p = Part(unary_union([box(i * w, j * h, (i + 1) * w, (j + 1) * h) for i in range(nx) for j in range(ny)]), label, -9, h * ny / 2, sub)
    for i in range(1, nx):
        p.line("cut", (i * w, 0), (i * w, h * ny))
    for j in range(1, ny):
        p.line("cut", (0, j * h), (w * nx, j * h))
    return p


# ---- Pages -------------------------------------------------------------------
PW, PH, MARGIN = 215.9, 279.4, 10.0
STYLE = {"cut": 'stroke="#000" stroke-width="0.35"',
         "valley": 'stroke="#000" stroke-width="0.3" stroke-dasharray="3 1.5"',
         "mountain": 'stroke="#000" stroke-width="0.3" stroke-dasharray="6 1.5 0.8 1.5"',
         "guide": 'stroke="#777" stroke-width="0.2" stroke-dasharray="0.6 1"'}
FONT = 'font-family="DejaVu Sans, Liberation Sans, Arial, sans-serif"'
pages, probes, tags = [], [], {}


def put(page, part, left, top, rot=0):
    """Place a part with its bounding box's top-left corner at (left, top), y up."""
    r = lambda g: affinity.rotate(g, rot, origin=(0, 0))
    x0, _, _, y1 = r(part.shape).bounds
    f = lambda g: at(r(g), left - x0, top - y1)
    pt = lambda p: f(Point(p)).coords[0]
    shape = f(part.shape)
    assert shape.bounds[0] >= MARGIN - 0.01 and shape.bounds[2] <= PW - MARGIN + 0.01 and shape.bounds[1] >= 22, \
        f"{part.texts[0][2]} is off the page: {shape.bounds}"
    for other in page["shapes"]:
        assert not shape.intersects(other), f"{part.texts[0][2]} overlaps another part"
    page["shapes"].append(shape)
    for poly in getattr(shape, "geoms", [shape]):
        for ring in [poly.exterior, *poly.interiors]:
            tag = next((n for n, p in part.tags if Point(pt(p)).within(box(*ring.bounds))), "")
            page["paths"].append(("cut", ring, tag))
    page["paths"] += [(k, f(l), "") for k, l in part.lines]
    page["texts"] += [(pt((x, y))[0], pt((x, y))[1] - drop, s, z) for x, y, s, z, drop in part.texts]
    probes.extend((len(pages), n, pt(a), pt(b), w) for n, a, b, w in part.probes)


def svg_page(page, n, total):
    out = []
    for kind, g, tag in page["paths"]:
        d = "M" + " L".join(f"{x:.3f},{PH - y:.3f}" for x, y in g.coords) + (" Z" if g.is_ring else "")
        out.append(f'<path class="{kind}" {f"id=\"p{n}-{tag}\" " if tag else ""}fill="none" {STYLE[kind]} d="{d}"/>')
    for x, y, s, z in page["texts"]:
        out.append(f'<text x="{x:.2f}" y="{PH - y:.2f}" font-size="{z}" text-anchor="middle" {FONT}>{s}</text>')
    # Key strip: 50 mm check bar, line key, page number.
    y = PH - 13
    out.append(f'<path id="p{n}-scale" class="scale" fill="none" stroke="#000" stroke-width="0.35" d="M{MARGIN},{y} L{MARGIN + 50},{y}"/>')
    out += [f'<path fill="none" stroke="#000" stroke-width="0.35" d="M{x},{y - 2} L{x},{y + 2}"/>' for x in (MARGIN, MARGIN + 50)]
    out.append(f'<text x="{MARGIN + 25}" y="{y + 4}" font-size="2.6" text-anchor="middle" {FONT}>50 mm</text>')
    x = MARGIN + 60
    for kind, name in (("cut", "cut"), ("valley", "valley fold"), ("mountain", "mountain fold"), ("guide", "guide")):
        out.append(f'<path fill="none" {STYLE[kind]} d="M{x},{y} L{x + 14},{y}"/>')
        out.append(f'<text x="{x + 7}" y="{y + 4}" font-size="2.6" text-anchor="middle" {FONT}>{name}</text>')
        x += 26
    out.append(f'<text x="{PW - MARGIN}" y="{y + 1}" font-size="2.6" text-anchor="end" {FONT}>T {T:g} mm   {n}/{total}</text>')
    return "\n".join(out)


def new_page():
    pages.append({"shapes": [], "paths": [], "texts": []})
    return pages[-1]


TOP, LEFT = PH - MARGIN, MARGIN
pg = new_page()
put(pg, top_wall(), LEFT + 11, TOP)
rows = math.ceil(N_BLOCKS / 8)
put(pg, grid(BTN_FREE, 10, 8, rows, "P", f"x{N_BLOCKS}  step 6"), LEFT + 24, 90 - (TAB - T))
put(pg, grid(30, 10, LAYERS - 1, 1, "PL", f"x{LAYERS - 1}"), LEFT + 24, 82 - rows * 10 - (TAB - T))
pg = new_page()
put(pg, bottom_wall(), LEFT + 11, TOP)
put(pg, side_wall(False), LEFT + 14, TOP - DEPTH - TAB - 6)
put(pg, side_wall(True), LEFT + 104, TOP - DEPTH - TAB - 6)
put(pg, grid(55, 24, 2, 2, "K", "x4  step 7"), LEFT + 30, TOP - DEPTH - TAB - H - 12)
if V2:
    put(pg, hook_doublers(), LEFT + 30, 34)
    put(new_page(), face_ring(0), LEFT + 2, TOP, 90)
    put(new_page(), face_ring(1), LEFT + 2, TOP, 90)
else:
    put(new_page(), face_ring(), LEFT + 30, TOP, 90)
put(new_page(), screen_frame(), LEFT + 30, TOP, 90)
put(new_page(), carrier(), LEFT + (PW - 2 * MARGIN - 2 * HP - GAP) / 2, TOP, 90)
pg = new_page()
put(pg, seat(), LEFT + 18, TOP)
put(pg, seat(), LEFT + 18, TOP - HP - 8)

here = Path(__file__).parent / ("v2" if V2 else "")
here.mkdir(exist_ok=True)
(here / "pages").mkdir(exist_ok=True)
(here / "preview").mkdir(exist_ok=True)
N = len(pages)
bodies = [svg_page(p, i + 1, N) for i, p in enumerate(pages)]
head = lambda w: (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}mm" height="{PH}mm" viewBox="0 0 {w} {PH}">\n'
                  f'<rect width="{w}" height="{PH}" fill="#fff"/>\n')
page_files = []
for i, b in enumerate(bodies):
    f = here / "pages" / f"page-{i + 1}.svg"
    f.write_text(head(PW) + b + "\n</svg>\n")
    page_files.append(str(f))
    subprocess.run(["rsvg-convert", "-d", "110", "-p", "110", "-o", str(here / "preview" / f"page-{i + 1}.png"), str(f)], check=True)
(here / "template.svg").write_text(
    head(PW * N) + "\n".join(f'<g transform="translate({PW * i:.1f},0)">\n{b}\n<rect width="{PW}" height="{PH}" fill="none" stroke="#bbb" stroke-width="0.2"/>\n</g>'
                             for i, b in enumerate(bodies)) + "\n</svg>\n")
subprocess.run(["rsvg-convert", "-f", "pdf", "-o", str(here / "template.pdf"), *page_files], check=True)


# ---- Overview: two sections and the stacking order ----------------------------
def overview():
    out = []
    card, foam, lens = "#d9b98a", "#f2d35b", "#bbb"
    zc = D_MAX - 30                                         # carrier drawn where d = 30 (measured at 5.5x)
    z_r = zc + T + 0.5 + STACK                              # rear lens face

    def rect(a0, b0, a1, b1, fill, extra=""):               # y up
        out.append(f'<rect x="{min(a0, a1):.1f}" y="{-max(b0, b1):.1f}" width="{abs(a1 - a0):.1f}" height="{abs(b1 - b0):.1f}" '
                   f'fill="{fill}" stroke="#000" stroke-width="0.3" {extra}/>')

    def txt(a, b, t, size=4.5):
        out.append(f'<text x="{a:.1f}" y="{-b:.1f}" font-size="{size * 1.5}" text-anchor="middle" {FONT}>{t}</text>')

    def shape(g, fill="#fff"):
        for poly in getattr(g, "geoms", [g]):
            d = " ".join("M" + " L".join(f"{x:.1f},{-y:.1f}" for x, y in r.coords) + " Z" for r in [poly.exterior, *poly.interiors])
            out.append(f'<path d="{d}" fill="{fill}" fill-rule="evenodd" stroke="#000" stroke-width="0.5"/>')

    def stack(put_frame):
        for k in range(3):
            put_frame(zc + T + 0.5 + k * STACK / 3, zc + T + 0.5 + (k + 1) * STACK / 3)

    def focus_dim(b):
        out.append(f'<path d="M{z_r:.1f},{-b:.1f} L{ZS:.1f},{-b:.1f}" stroke="#000" stroke-width="0.3" marker-start="url(#a)" marker-end="url(#a)"/>')
        txt((z_r + ZS) / 2 + 1, b + 2.5, f"{D_MIN:g}-{D_MAX:g}", 3.5)

    # 1. Side section through one lens, eye on the left.
    out.append('<g transform="translate(62,262) scale(1.4)">')
    rect(-T - 6, H - 6, -T, H + T + 6, foam); rect(-T - 6, -T - 6, -T, 6, foam)
    rect(-T, H - 6, 0, H + T + 6 + EAR, card); rect(-T, -T - 6, 0, 6, card); txt(-T - 12, H + T + 12, "R")
    rect(ZN, H, DEPTH, H + T, card); rect(0, -T, DEPTH, 0, card); txt(DEPTH - 6, H + T + 13, "A"); txt(20, -T - 6, "B")
    rect(0, H + T, zc + T - 4, H + 2 * T, card); rect(zc + T + STACK + 5, H + T, ZN + 8, H + 2 * T, card); txt(6, H + 2 * T + 2, "K", 3.5)
    for z0 in (zc, zc + T + GAP):
        rect(z0, T + 0.5, z0 + T, YC - AP / 2, card); rect(z0, YC + AP / 2, z0 + T, YC + 21, card)
    rect(zc, 0.5, zc + 2 * T + GAP, T + 0.5, card); txt(zc + T + GAP / 2, T + 6, "C")
    stack(lambda a, b: (rect(a, YC - FRAME_OD / 2, b, YC + FRAME_OD / 2, lens), rect(a + 1.5, YC - GLASS / 2, b - 1.5, YC + GLASS / 2, "#e6f6fb")))
    rect(zc + T - 3.4, YC + 24, zc + T + STACK + 4.4, H + 50, "none", 'stroke-dasharray="2 1.5"'); txt(zc + T + 11, H + 28, "TV-36", 3.5)
    rect(ZS - T, 0.3, ZS, YC - SCREEN_H / 2 - 0.5, card); rect(ZS - T, YC + SCREEN_H / 2 + 0.5, ZS, H - 0.3, card)
    rect(ZS - T, H, ZS, H + T + 10, card); rect(ZS - T, -T - 10, ZS, 0, card); txt(ZS - T - 5, H - 9, "F")
    rect(ZS, M, ZS + PHONE_T, M + PHONE_H, "#555"); rect(ZS, 0, DEPTH, M, "#c9a772"); rect(ZS, H - M, DEPTH, H, "#c9a772"); txt(ZS + 5, M / 2 - 1.5, "P", 3.5)
    rect(DEPTH, -T - LIP, DEPTH + T, H, card); txt(DEPTH + T + 6, YC, "A")
    focus_dim(YC)
    out.append(f'<circle cx="{-T - 6 - 12:.1f}" cy="{-YC:.1f}" r="6" fill="#fff" stroke="#000" stroke-width="0.3"/>')
    out.append("</g>")

    # 2. Plan section at lens height, seen from above: a = x, b = -z (front at the top).
    out.append('<g transform="translate(285,62) scale(1.4)">')
    o = T + 6
    rect(-o - EAR, T, W + o + EAR, 0, card); rect(-o, T + 6, 12, T, foam); rect(W - 12, T + 6, W + o, T, foam); txt(-o - EAR - 5, -1, "R")
    rect(-T, 0, 0, -DEPTH, card); rect(W, 0, W + T, -ZS + T, card); txt(-T - 6, -30, "SC"); txt(W + T + 7, -30, "SU")
    cx0 = 0.5
    rect(cx0, -zc, cx0 + T, -zc - 2 * T - GAP, card); rect(W - cx0 - T, -zc, W - cx0, -zc - 2 * T - GAP, card)
    for z0 in (zc, zc + T + GAP):
        for a0, a1 in ((cx0 + T, XC - IPD / 2 - AP / 2), (XC - IPD / 2 + AP / 2, XC + IPD / 2 - AP / 2), (XC + IPD / 2 + AP / 2, W - cx0 - T)):
            rect(a0, -z0, a1, -z0 - T, card)
    txt(XC, -zc - T - GAP / 2 - 1.5, "C")
    for lx in LENS_X:
        stack(lambda a, b: (rect(XC + lx - FRAME_OD / 2, -a, XC + lx + FRAME_OD / 2, -b, lens), rect(XC + lx - GLASS / 2, -a - 1.5, XC + lx + GLASS / 2, -b + 1.5, "#e6f6fb")))
    out.append(f'<path d="M{XC - IPD / 2:.1f},{12} L{XC + IPD / 2:.1f},{12}" stroke="#000" stroke-width="0.3" marker-start="url(#a)" marker-end="url(#a)" transform="translate(0,{-zc + 6 - 12:.1f})"/>')
    txt(XC, -zc + 7.5, f"{IPD:g}", 3.5)
    rect(0.3, -ZS + T, XC - SCREEN_W / 2 - 0.5, -ZS, card); rect(XC + SCREEN_W / 2 + 0.5, -ZS + T, W + T + 45, -ZS, card); txt(W + T + 30, -ZS + T + 2, "F")
    rect(M, -ZS, M + PHONE_W, -ZS - PHONE_T, "#555"); rect(M + 3, -ZS - PHONE_T, M + CAM_END, -ZS - PHONE_T - 3.65, "#555")
    rect(M - 2 * T, -ZS - 0.5, M, -DEPTH + 0.5, "#c9a772"); txt(M - T, -ZS - 7.5, "PL", 3)
    rect(M + PHONE_W, -ZS - PHONE_T / 2 + 3, M + PHONE_W + USB_LEN, -ZS - PHONE_T / 2 - 3, "#eee")
    rect(M + PHONE_W + USB_LEN, -ZS - PHONE_T / 2 + 2, W + T + 60, -ZS - PHONE_T / 2 - 2, "#eee")
    rect(XCUT, -DEPTH, W + T, -DEPTH - T, card); txt(XC + 20, -DEPTH - T - 5, "A")
    out.append("</g>")

    # 3. Stacking order, face side first, half size.
    x = 190
    for label, g, w in (("R", at(face_ring().shape, XC + T + 6 + EAR), 2 * (XC + T + 6 + EAR)),
                        ("C + S", at((box(0, 0, WP, HP) - plate_cuts(False)), T), W),
                        ("F + P", at(screen_frame().shape, T), W + 2 * T + 45),
                        ("phone", box(0, M, PHONE_W, M + PHONE_H).buffer(-8).buffer(8), PHONE_W),
                        ("A", box(0, -LIP, W + T - XCUT, H), W + T - XCUT)):
        out.append(f'<g transform="translate({x:.1f},335) scale(0.5)">')
        shape(g, "#666" if label == "phone" else card)
        if label == "C + S":
            shape(at(box(0.5, 0, WP - 0.5, HP) - plate_cuts(True), T, 0).intersection(at(plate_cuts(False), T).buffer(8)), "#c9a772")
        if label == "F + P":
            for u, v in ((M, 0), (M + PHONE_W - BTN_FREE, 0), (M, H - M), (M + PHONE_W - BTN_FREE, H - M)):
                shape(box(u + T, v, u + T + BTN_FREE, v + M), "#c9a772")
        if label == "phone":
            shape(box(3, M + 30, CAM_END, M + PHONE_H - 3).buffer(-6).buffer(6), "#333")
        txt(w / 2, -T - 6 - 22, label, 11)
        out.append("</g>")
        x += w / 2 + 12
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="680" height="305" viewBox="15 52 680 305">'
           '<defs><marker id="a" markerWidth="6" markerHeight="6" refX="3" refY="3" orient="auto-start-reverse">'
           '<path d="M0,0 L6,3 L0,6 Z"/></marker></defs><rect x="15" y="52" width="680" height="305" fill="#fff"/>' + "\n".join(out) + "</svg>")
    (here / "overview.svg").write_text(svg)
    subprocess.run(["rsvg-convert", "-z", "2.5", "-o", str(here / "overview.png"), str(here / "overview.svg")], check=True)


if not V2:   # the overview still draws v1
    overview()

# ---- Self-check: measure the written template.svg ----------------------------
svg = (here / "template.svg").read_text()
groups = svg.split("<g transform=")[1:]
assert len(groups) == N
ok = True


def report(name, got, want):
    global ok
    good = abs(got - want) < 0.02
    ok &= good
    print(f"  {'ok ' if good else 'BAD'} {name}: {got:.2f} (want {want:.2f})")


def coords(d):
    return [(float(a), PH - float(b)) for a, b in re.findall(r"(-?[\d.]+),(-?[\d.]+)", d)]


print(f"T {T:g}: {LAYERS} layers per block ({N_BLOCKS} P, {LAYERS - 1} PL); body inside {W:.1f} x {H:.1f} x {DEPTH:.1f}, outside {W + 2 * T:.1f} x {H + 2 * T:.1f}; "
      f"screen plane z {ZS:.1f}; carrier {WP + 2 * T:.1f} x {HP + T:.1f} x {GAP + 2 * T:.1f}; lens axis {YC:.2f} above the floor")
for i, g in enumerate(groups):
    cuts = MultiLineString([coords(d) for d in re.findall(r'<path class="(?:cut|mountain)"[^>]* d="([^"]+)"', g)])
    bar = coords(re.search(r'class="scale"[^>]* d="([^"]+)"', g).group(1))
    report(f"page {i + 1} scale bar", math.dist(*bar), 50)
    for page, name, a, b, want in probes:
        if page != i + 1:
            continue
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        hits = LineString([a, b]).intersection(cuts)
        pts = [p.coords[0] for p in getattr(hits, "geoms", [hits]) if p.geom_type == "Point"]
        side = lambda end: min((math.dist(p, mid) for p in pts if math.dist(p, end) < math.dist(mid, end) and math.dist(p, mid) > 1e-6), default=float("nan"))
        report(name, side(a) + side(b), want)
    centres = {}
    for tag, d in re.findall(r'id="p\d+-(ap-[^"]+)"[^>]* d="([^"]+)"', g):
        c = coords(d)
        centres[tag] = ((min(x for x, _ in c) + max(x for x, _ in c)) / 2, (min(y for _, y in c) + max(y for _, y in c)) / 2)
    for plate_name in ("front", "rear"):
        if f"ap-{plate_name}-L" in centres:
            report(f"C {plate_name} plate aperture centres (IPD)", math.dist(centres[f"ap-{plate_name}-L"], centres[f"ap-{plate_name}-R"]), IPD)
assert ok, "template.svg does not match the parameters"
