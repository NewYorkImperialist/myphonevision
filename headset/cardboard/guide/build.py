#!/usr/bin/env python3
"""Picture build guide (IKEA style) for the cardboard headset.

    python3 build.py      # writes step-NN.png here and ../build-guide.pdf

Needs shapely, numpy, PIL, rsvg-convert and an OpenSCAD 2026 snapshot (OPENSCAD=..., default
~/.local/bin/openscad). The parts come from ../gen.py (laser-cut defaults: T 3, d 24-32);
model.py places them in 3D. Renders are cached in work/.
"""
import base64, math, subprocess
from model import *

PW, PH = 215.9, 279.4
FONT = "DejaVu Sans, Liberation Sans, sans-serif"
INK = "#1d1d1d"
OKC, NOC = "#2e9d4b", "#d23a2a"


# ---- SVG helpers (page millimetres) -------------------------------------------------
def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def text(x, y, s, size=4.0, bold=True, anchor="middle", color=INK, rot=0):
    w = "bold" if bold else "normal"
    r = f' transform="rotate({rot} {x:.2f} {y:.2f})"' if rot else ""
    return (f'<text x="{x:.2f}" y="{y:.2f}" font-family="{FONT}" font-size="{size:.2f}" font-weight="{w}" '
            f'text-anchor="{anchor}" fill="{color}"{r}>{esc(s)}</text>')


def arrow(p, q, w=0.9, color=INK, head=3.2, both=False):
    p, q = np.asarray(p, float), np.asarray(q, float)
    d = q - p
    L = np.linalg.norm(d)
    if L < 1e-6:
        return ""
    u = d / L
    n = np.array([-u[1], u[0]])
    out = []
    ends = [(q, u)] + ([(p, -u)] if both else [])
    a = p + (u * head * 0.8 if both else 0)
    b = q - u * head * 0.8
    out.append(f'<path d="M{a[0]:.2f},{a[1]:.2f} L{b[0]:.2f},{b[1]:.2f}" stroke="{color}" stroke-width="{w}" fill="none" stroke-linecap="round"/>')
    for tip, uu in ends:
        nn = np.array([-uu[1], uu[0]])
        b1, b2 = tip - uu * head + nn * head * 0.5, tip - uu * head - nn * head * 0.5
        out.append(f'<path d="M{tip[0]:.2f},{tip[1]:.2f} L{b1[0]:.2f},{b1[1]:.2f} L{b2[0]:.2f},{b2[1]:.2f} Z" fill="{color}"/>')
    return "\n".join(out)


def curved(p, c, q, w=0.9, color=INK, head=3.2):
    p, c, q = (np.asarray(v, float) for v in (p, c, q))
    u = (q - c) / np.linalg.norm(q - c)
    n = np.array([-u[1], u[0]])
    e = q - u * head * 0.8
    b1, b2 = q - u * head + n * head * 0.5, q - u * head - n * head * 0.5
    return (f'<path d="M{p[0]:.2f},{p[1]:.2f} Q{c[0]:.2f},{c[1]:.2f} {e[0]:.2f},{e[1]:.2f}" stroke="{color}" stroke-width="{w}" fill="none" stroke-linecap="round"/>'
            f'<path d="M{q[0]:.2f},{q[1]:.2f} L{b1[0]:.2f},{b1[1]:.2f} L{b2[0]:.2f},{b2[1]:.2f} Z" fill="{color}"/>')


def path_arrow(pts, w=0.9, color=INK, head=3.2):
    """Arrow along a polyline of page points (e.g. a projected 3D arc)."""
    pts = [np.asarray(p, float) for p in pts]
    q, u = pts[-1], pts[-1] - pts[-2]
    u = u / np.linalg.norm(u)
    n = np.array([-u[1], u[0]])
    e = q - u * head * 0.8
    d = "M" + " L".join(f"{p[0]:.2f},{p[1]:.2f}" for p in pts[:-1] + [e])
    b1, b2 = q - u * head + n * head * 0.5, q - u * head - n * head * 0.5
    return (f'<path d="{d}" stroke="{color}" stroke-width="{w}" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'
            f'<path d="M{q[0]:.2f},{q[1]:.2f} L{b1[0]:.2f},{b1[1]:.2f} L{b2[0]:.2f},{b2[1]:.2f} Z" fill="{color}"/>')


def label(x, y, s, size=4.2, to=None, fill="#fff", color=INK):
    """Boxed callout, optional leader line to a point."""
    w = 0.62 * size * len(s) + 2.6
    h = size + 2.4
    out = []
    if to is not None:
        out.append(f'<path d="M{x:.2f},{y:.2f} L{to[0]:.2f},{to[1]:.2f}" stroke="{color}" stroke-width="0.35"/>'
                   f'<circle cx="{to[0]:.2f}" cy="{to[1]:.2f}" r="0.8" fill="{color}"/>')
    out.append(f'<rect x="{x - w / 2:.2f}" y="{y - h / 2:.2f}" width="{w:.2f}" height="{h:.2f}" rx="1.2" fill="{fill}" stroke="{color}" stroke-width="0.4"/>')
    out.append(text(x, y + size * 0.36, s, size, color=color))
    return "\n".join(out)


def badge(x, y, ok, r=4.5):
    c, g = (OKC, "✓") if ok else (NOC, "✗")
    return f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{r}" fill="{c}"/>' + text(x, y + r * 0.55, g, r * 1.55, color="#fff")


def dim(p, q, s, off=(0, 0), size=3.6, color=INK):
    p, q = np.asarray(p, float), np.asarray(q, float)
    m = (p + q) / 2 + off
    return arrow(p, q, 0.35, color, 2.0, both=True) + text(m[0], m[1], s, size, color=color)


def frame_box(x, y, w, h, tag=None):
    s = f'<rect x="{x:.2f}" y="{y:.2f}" width="{w:.2f}" height="{h:.2f}" rx="2" fill="none" stroke="#b9b9b9" stroke-width="0.35"/>'
    if tag:
        s += f'<circle cx="{x + 5:.2f}" cy="{y + 5:.2f}" r="3.6" fill="{INK}"/>' + text(x + 5, y + 6.35, tag, 3.6, color="#fff")
    return s


def b64(png):
    return "data:image/png;base64," + base64.b64encode(Path(png).read_bytes()).decode()


class Panel:
    """A rendered view placed on the page: x, y, width in mm; P() maps world points to the page."""

    def __init__(self, body, cam, x, y, w, name):
        self.cam, self.x, self.y, self.w = cam, x, y, w
        self.png = render(scene_scad(body), cam, name=name)
        self.s = w / cam.size[0]
        self.h = cam.size[1] * self.s

    def P(self, p):
        u, v = self.cam.px(p)
        return np.array([self.x + u * self.s, self.y + v * self.s])

    def boxed(self, tag=None):
        """Image with its frame and step tag drawn on top."""
        return self.svg() + frame_box(self.x, self.y, self.w, self.h, tag)

    def svg(self, clip=None):
        img = f'<image x="{self.x:.2f}" y="{self.y:.2f}" width="{self.w:.2f}" height="{self.h:.2f}" href="{b64(self.png)}"/>'
        if clip:
            cx, cy, r = clip
            cid = f"c{abs(hash(self.png)) % 10 ** 9}"
            return (f'<clipPath id="{cid}"><circle cx="{cx:.2f}" cy="{cy:.2f}" r="{r:.2f}"/></clipPath>'
                    f'<circle cx="{cx:.2f}" cy="{cy:.2f}" r="{r:.2f}" fill="#fff"/>'
                    f'<g clip-path="url(#{cid})">{img}</g>'
                    f'<circle cx="{cx:.2f}" cy="{cy:.2f}" r="{r:.2f}" fill="none" stroke="{INK}" stroke-width="0.6"/>')
        return img


def zoom(body, center, d, half, at, r, name, src=None, src_r=6.0):
    """Circular zoom of `center` drawn at page point `at` with radius r; src = main Panel to circle."""
    px = 700
    cam = Camera(d, center, half, (px, px))
    w = 2 * r * 1.0
    pn = Panel(body, cam, at[0] - r, at[1] - r, w, name)
    out = ""
    if src is not None:
        c = src.P(center)
        v = np.asarray(at) - c
        L = np.linalg.norm(v)
        a, b = c + v / L * src_r, np.asarray(at) - v / L * r
        out += (f'<circle cx="{c[0]:.2f}" cy="{c[1]:.2f}" r="{src_r}" fill="none" stroke="{INK}" stroke-width="0.6"/>'
                f'<path d="M{a[0]:.2f},{a[1]:.2f} L{b[0]:.2f},{b[1]:.2f}" stroke="{INK}" stroke-width="0.4"/>')
    return pn, out + pn.svg(clip=(at[0], at[1], r))


def page(n, body, title=None, subtitle=None):
    head = ""
    if n is not None:
        head += text(12, 30, str(n), 26, anchor="start")
    if title:
        head += text(PW - 12, 22, title, 6, anchor="end")
    if subtitle:
        head += text(PW - 12, 29, subtitle, 4, bold=False, anchor="end", color="#555")
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{PW}mm" height="{PH}mm" viewBox="0 0 {PW} {PH}">'
            f'<rect width="{PW}" height="{PH}" fill="#fff"/>{head}{body}</svg>')


# ---- Scene helpers ----------------------------------------------------------------
def card(have, new=(), off=None, flap=90.0, fold=(90.0, 90.0), skip=()):
    """Card parts in world position: `new` ones in colour, the rest beige; off: name -> (dx, dy, dz)."""
    off = off or {}
    P = card_parts(flap, fold)
    s = ""
    for n in have:
        for i, pc in enumerate(P[n]):
            if (n, i) in skip:
                continue
            c, k = (CARD_NEW, INK_NEW) if n in new else (CARD_OLD, INK_OLD)
            s += piece_scad(pc, c, k, off.get(n, (0, 0, 0)))
    return s


BODY = ["B", "F", "SC", "SU", "C", "S1", "S2", "A", "R"]
CTR = np.array([XC, YC + 5, DEPTH / 2])
V_FRONT = (0.55, 0.45, -0.7)     # front, USB side, above
V_BACK = (0.6, 0.5, 0.65)        # back, USB side, above
V_BACKC = (-0.55, 0.5, 0.67)     # back, CAM side, above
pages = []


# ---- Page 1: parts and what else you need ---------------------------------------------
def knife(x, y, rot=0, s=1.0):
    return (f'<g transform="translate({x:.2f},{y:.2f}) rotate({rot}) scale({s})"><path d="M-1,1.6 L12,1.6 L18,-1.2 L12,-1.2 L-1,-1.2 Z" fill="#c4c4c4" stroke="#555" stroke-width="0.3"/>'
            f'<rect x="-12" y="-1.6" width="11" height="3.6" rx="0.8" fill="#e0b000" stroke="#555" stroke-width="0.3"/></g>')


def page1():
    k = 0.28
    out = [text(12, 30, "Parts", 9, anchor="start")]

    def part2d(shape, txts, x, y, letter, count):
        x0, y0, x1, y1 = shape.bounds
        tf = lambda px, py: (x + (px - x0) * k, y + (y1 - py) * k)
        for p in polys(shape):
            d = " ".join("M" + " L".join(f"{tf(*c)[0]:.2f},{tf(*c)[1]:.2f}" for c in r.coords) + " Z" for r in [p.exterior, *p.interiors])
            out.append(f'<path d="{d}" fill="#e6c08f" fill-rule="evenodd" stroke="{INK}" stroke-width="0.3"/>')
        for tx, ty, s, size, ang in txts:
            if shape.buffer(0.01).contains(Point(tx, ty)):
                px, py = tf(tx, ty)
                out.append(text(px, py, s, max(size * k, 0.9), color="#6b4a22", rot=-ang))
        w, h = (x1 - x0) * k, (y1 - y0) * k
        out.append(label(x + w / 2, y + h + 5, f"{count}× {letter}" if count > 1 else letter, 4.4))

    part2d(G["top_wall"]().shape, texts(G["top_wall"](), 0), 14, 38, "A", 1)
    part2d(G["face_ring"]().shape, texts(G["face_ring"](), 90), 72, 38, "R", 1)
    part2d(G["seat"]().shape, texts(G["seat"](), 0), 150, 38, "S", 2)
    part2d(box(0, 0, 55, 24), [], 150, 78, "K", 4)
    part2d(box(0, 0, BTN_FREE, 10), [], 172, 80, "P", N_BLOCKS)
    part2d(box(0, 0, 30, 10), [], 190, 80, "PL", LAYERS - 1)
    part2d(G["bottom_wall"]().shape, texts(G["bottom_wall"](), 0), 14, 99, "B", 1)
    part2d(G["side_wall"](False).shape, texts(G["side_wall"](False), 0), 14, 131, "SC", 1)
    part2d(G["side_wall"](True).shape, texts(G["side_wall"](True), 0), 42, 131, "SU", 1)
    part2d(G["screen_frame"]().shape, texts(G["screen_frame"](), 90), 72, 88, "F", 1)
    part2d(G["carrier"]().shape, texts(G["carrier"](), 90), 142, 100, "C", 1)

    # Optional bench check (step 1, already done) and P/PL from scrap
    y, h = 168, 44
    out.append(frame_box(12, y, 94, h, "1"))
    g = 0.5
    grp = []
    t3 = STACK / 3
    grp.append(f'<rect x="0" y="60" width="64" height="5" rx="1.5" fill="#3b3d42"/><rect x="2" y="59.2" width="60" height="0.8" fill="#a9dcff"/>')
    for yy in (30 - t3, 30 - 3 * t3):
        grp.append(f'<rect x="13" y="{yy:.2f}" width="38" height="{t3 - 0.6:.2f}" rx="1" fill="#55585e"/><rect x="17" y="{yy + 2:.2f}" width="30" height="{t3 - 4.6:.2f}" fill="#cdeef8"/>')
    grp.append(f'<path d="M51,{30 - 2 * t3:.2f} L64,{30 - 2 * t3 - 6:.2f} L76,{30 - 2 * t3 - 3:.2f} L76,{30 - t3 + 1:.2f} L51,{30 - t3:.2f} Z" fill="#2e3033"/>')
    ey = 30 - 3 * t3 - 7
    grp.append(f'<ellipse cx="32" cy="{ey:.2f}" rx="6" ry="3" fill="#fff" stroke="{INK}" stroke-width="0.6"/><circle cx="32" cy="{ey:.2f}" r="1.8" fill="{INK}"/>')
    grp.append(arrow((-6, 30), (-6, 59.2), 0.6, both=True, head=3))
    out.append(f'<g transform="translate(30,{y + 9}) scale({g})">{"".join(grp)}</g>')
    out.append(text(68, y + 30, "d ≈ 30 mm", 4.6, anchor="start"))
    out.append(text(68, y + 18, "5.5x", 4.2, anchor="start"))
    out.append(text(102, y + 6, "done", 3.4, bold=False, anchor="end", color="#666"))
    x2 = 110
    out.append(frame_box(x2, y, 94, h))
    out.append(text(x2 + 4, y + 7, "P / PL ?", 4.2, anchor="start"))
    for i in range(3):
        out.append(f'<rect x="{x2 + 40}" y="{y + 26 - i * 7:.2f}" width="28" height="7" fill="#e6c08f" stroke="{INK}" stroke-width="0.3"/>')
    out.append(arrow((x2 + 72, y + 33), (x2 + 72, y + 12), 0.4, both=True, head=2))
    out.append(text(x2 + 75, y + 24, "≈ 9 mm", 4, anchor="start"))
    out.append(text(x2 + 54, y + 40, "scrap", 3.4, bold=False))
    out.append(knife(x2 + 16, y + 26, -30, 0.9))

    y0 = 224
    out.append(f'<line x1="12" y1="{y0 - 6}" x2="{PW - 12}" y2="{y0 - 6}" stroke="#bbb" stroke-width="0.35"/>')
    items = [
        ('<rect x="-9" y="-6" width="18" height="12" rx="2" fill="#3b3d42"/><rect x="-7.5" y="-4.5" width="15" height="9" rx="1.5" fill="#15171a"/>', "iPhone 16 Pro", ""),
        ('<circle cx="0" cy="3" r="5.5" fill="#55585e"/><circle cx="0" cy="3" r="4" fill="#cdeef8"/><path d="M-5,-1 Q0,-14 5,-1 Z" fill="#2e3033"/>', "TV-36", "2×"),
        ('<path d="M-10,4 Q-4,4 -2,0 L6,0" stroke="#999" stroke-width="1.6" fill="none"/><rect x="5" y="-2" width="6" height="4" fill="#ccc" stroke="#555" stroke-width="0.3"/>', "USB-C", ""),
        ('<circle cx="0" cy="0" r="7" fill="#7fb8e6"/><circle cx="0" cy="0" r="3.5" fill="#fff"/>', "tape", ""),
        ('<rect x="-2.5" y="-8" width="5" height="16" rx="1" fill="#e9e9e9" stroke="#555" stroke-width="0.4"/><rect x="-2.5" y="-8" width="5" height="5" fill="#7a5"/>', "glue", ""),
        ('<rect x="-9" y="-4" width="18" height="8" fill="#f2cf4a" stroke="#555" stroke-width="0.3"/>', "foam", "10 mm"),
        ('<rect x="-9" y="-1.2" width="18" height="2.4" fill="#f2cf4a" stroke="#555" stroke-width="0.3"/>', "foam", "2–3 mm"),
        ('<ellipse cx="0" cy="0" rx="9" ry="3.5" fill="none" stroke="#c8442c" stroke-width="1.2"/>', "rubber band", "2×"),
        ('<path d="M-10,-3 L10,-3 L10,3 L-10,3 Z" fill="#262626"/>', "strap", "≤ 32 mm"),
        ('<path d="M-9,2 L8,-2" stroke="#1f1f1f" stroke-width="1"/><rect x="6" y="-4" width="4" height="4" fill="#1f1f1f"/>', "cable tie", ""),
        (knife(-4, 0, 0, 0.8), "knife", ""),
        ('<rect x="-10" y="-2.5" width="20" height="5" fill="#ddd" stroke="#555" stroke-width="0.3"/>' + "".join(f'<line x1="{x}" y1="-2.5" x2="{x}" y2="-0.5" stroke="#555" stroke-width="0.25"/>' for x in range(-9, 10, 2)), "ruler", "")]
    for i, (svg, lab, cnt) in enumerate(items):
        cx, cy = 26 + (i % 6) * 32.5, y0 + 6 + (i // 6) * 26
        out.append(f'<g transform="translate({cx:.2f},{cy:.2f})">{svg}</g>')
        out.append(text(cx, cy + 12, lab, 3.2, bold=False))
        if cnt:
            out.append(text(cx, cy + 16, cnt, 3.2))
    return page(None, "\n".join(out))


# ---- Step 3: carrier ------------------------------------------------------------------
def step3():
    out = []
    # 3.1 plates up, then end flaps back (printed side out = down on the table)
    cam = Camera((0.5, 0.75, -0.43), (XC, 30, ZC + 12), 100, (1100, 800))
    pa = Panel(card(["C"], ["C"], fold=(45, 0)), cam, 10, 38, 96, "s3_fold_a")
    out.append(pa.boxed("1"))
    for idx, sgn, u in ((1, 1, WP / 2 + 45), (2, -1, WP / 2 + 45)):
        pts = [pa.P(carrier_pieces(a, 0)[idx].world(u, sgn * HP if sgn > 0 else -GAP - HP, T)) for a in range(50, 91, 8)]
        out.append(path_arrow(pts))
    out.append(label(pa.x + pa.w - 10, pa.y + 9, "C", 5))
    out.append(label(*(pa.P((X0 + 30, T, ZC + GAP + 10)) + (18, 10)), "printed side ↓", 3.2))
    pb = Panel(card(["C"], ["C"], fold=(90, 40)), cam, 110, 38, 96, "s3_fold_b")
    out.append(pb.boxed())
    for idx, u in ((3, -GAP), (4, WP + GAP)):
        pts = [pb.P(carrier_pieces(90, a)[idx].world(u, HP * 0.95, T)) for a in range(45, 91, 9)]
        out.append(path_arrow(pts))
    # 3.2 taped, 22 mm inside
    y2 = 38 + pa.h + 6
    t = 0.4
    tape = ""
    for xe, sgn in ((X0 + WP + T, 1), (X0 - T, -1)):
        tape += cube(xe, T + 2, ZC + T + GAP - 10, xe + sgn * t, T + HP - 2, ZC + 2 * T + GAP + t, TAPE)
        tape += cube(xe, T + 2, ZC + 2 * T + GAP, xe - sgn * 10, T + HP - 2, ZC + 2 * T + GAP + t, TAPE)
    cam2 = Camera((0.62, 0.55, 0.56), (XC, 45, ZC + 15), 100, (1100, 800))
    p2 = Panel(card(["C"], ["C"]) + tape, cam2, 10, y2, 96, "s3_taped")
    out.append(p2.boxed("2"))
    xe = X0 + WP + T
    out.append(label(*(p2.P((xe, T + 30, ZC + 2 * T + GAP)) + (14, 6)), "tape", 3.6, to=p2.P((xe - 4, T + 30, ZC + 2 * T + GAP))))
    out.append(label(*(p2.P((X0 - T, T + 30, ZC + 2 * T + GAP)) + (-12, 8)), "tape", 3.6, to=p2.P((X0 + 2, T + 30, ZC + 2 * T + GAP))))
    a, b = p2.P((X0 + WP - 25, T + HP + 3, ZC + T)), p2.P((X0 + WP - 25, T + HP + 3, ZC + T + GAP))
    out.append(dim(a, b, "22 mm", off=(9, -5), size=3.8))
    # 3.3 seats: one inside each plate, bottom edge on the floor
    P3 = card(["C", "S1", "S2"], ["S1", "S2"], off={"S1": (0, 100, 0), "S2": (0, 100, 0)})
    cam3 = Camera((0.5, 0.62, -0.6), (XC, 90, ZC + 15), 118, (1100, 1150))
    p3 = Panel(P3, cam3, 110, y2, 96, "s3_seats")
    out.append(p3.boxed("3"))
    for xx in (X0 + 25, X0 + WP - 25):
        for z in (ZC + T + 1.5, ZC + GAP + 1.5):
            out.append(arrow(p3.P((xx, 100 + 2, z)), p3.P((xx, 50, z)), 0.8))
    out.append(label(*(p3.P((X0 + WP, T + 100 + HP, ZC + 15)) + (-4, -8)), "2× S", 5))
    # zoom from the CAM end (end flaps hidden): both S against their plates, on the floor
    zb = card(["C", "S1", "S2"], ["S1", "S2"], skip={("C", 3), ("C", 4)})
    y3 = y2 + max(p2.h, p3.h) + 6
    at = (58, y2 + p2.h + 34)
    _, zs = zoom(zb, (X0, 30, ZC + T + GAP / 2), (-1, 0.18, 0.0001), 50, at, 26, "s3_end", src=p3, src_r=6)
    out.append(zs)
    out.append(badge(at[0] + 22, at[1] + 20, True))
    return page(3, "\n".join(out), "C + S")


# ---- Step 4: magnifiers into the carrier ---------------------------------------------------
def step4():
    out = []
    lx = LENS_XS[0]
    cam = Camera((0.5, 0.25, -0.83), (lx, LENS_Y + 33, ZL + 10), 68, (800, 900))
    p = Panel(magnifier(lx), cam, 10, 38, 58, "s4_mag")
    out.append(p.boxed("1"))
    out.append(label(39, 38 + p.h - 8, "5.5x", 5.5))
    out.append(label(60, 46, "2×", 4.6))
    # 4.2 into the carrier: rims into the S seats, case up
    body = card(["C", "S1", "S2"]) + "".join(magnifier(x, lift=60) for x in LENS_XS)
    cam2 = Camera((0.5, 0.62, -0.6), (XC, 80, ZC + 14), 100, (1300, 850))
    p2 = Panel(body, cam2, 72, 38, 134, "s4_in")
    out.append(p2.boxed("2"))
    for x in LENS_XS:
        out.append(arrow(p2.P((x - 28, LENS_Y + 55, ZL + 10)), p2.P((x - 28, LENS_Y + 10, ZL + 10))))
    # ✓ / ✗: stack all the way down (front plate hidden, seat in colour)
    y2 = 38 + max(p.h, p2.h) + 8
    for i, (lift, ok) in enumerate(((0, True), (7, False))):
        zb = card(["C", "S1"], ["S1"], skip={("C", 1), ("C", 3), ("C", 4)}) + magnifier(lx, lift=lift)
        cx = 34 + i * 52
        _, zs = zoom(zb, (lx, LENS_Y - 8, ZL), (0.0, 0.2, -1.0), 32, (cx, y2 + 22), 22, f"s4_seat{i}")
        out += [zs, badge(cx + 17, y2 + 39, ok)]
    out.append(knife(112, y2 + 38, -35, 1.0))
    # 4.3 front view: holes centred, 63 mm
    body3 = card(["C", "S1", "S2"]) + "".join(magnifier(x) for x in LENS_XS)
    cam3 = Camera((0, 0.0001, -1), (XC, 60, ZC), 98, (1300, 1200))
    y3 = y2 + 52
    p3 = Panel(body3, cam3, 10, y3, 86, "s4_front")
    out.append(p3.boxed("3"))
    a, b = p3.P((LENS_XS[0], LENS_Y, ZC - 1)), p3.P((LENS_XS[1], LENS_Y, ZC - 1))
    out.append(dim(a, b, "63 mm", off=(0, -3.5), size=4.4))
    out.append(label(*(p3.P((LENS_XS[1], LENS_Y - 36, ZC)) + (-6, 0)), "Ø 33", 3.6, to=p3.P((LENS_XS[1] + 11, LENS_Y - 12, ZC))))
    # 4.4 out again
    body4 = card(["C", "S1", "S2"]) + "".join(magnifier(x, lift=50) for x in LENS_XS)
    p4 = Panel(body4, Camera((0.5, 0.62, -0.6), (XC, 75, ZC + 14), 112, (1100, 1000)), 104, y3, 80, "s4_out")
    out.append(p4.boxed("4"))
    for x in LENS_XS:
        out.append(arrow(p4.P((x - 28, LENS_Y + 10, ZL + 10)), p4.P((x - 28, LENS_Y + 52, ZL + 10)), 0.8))
    return page(4, "\n".join(out), "TV-36 → C")


# ---- Step 5: body ----------------------------------------------------------------------
def step5a():
    out = []
    W2 = 96
    cam = Camera((0.0, 0.85, -0.53), (XC, 0, DEPTH / 2), 95, (1200, 900))
    p = Panel(card(["B"], ["B"]), cam, 10, 38, W2, "s5_B")
    out.append(p.boxed("1"))
    out.append(arrow(p.P((XC, 0, -30)), p.P((XC, 0, -8)), 0.8))
    out.append(text(*(p.P((XC, 0, -34)) + (0, 4)), "FRONT", 4.2))
    out.append(label(*(p.P((20, 0, DEPTH)) + (0, -9)), "B", 5))
    camb = Camera((0.0, -0.85, -0.53), (XC, 0, DEPTH / 2), 95, (700, 520))
    pb = Panel(card(["B"], ["B"]), camb, 10 + W2 - 36, 38 + p.h - 27, 34, "s5_Bunder")
    out += [pb.svg(), text(10 + W2 - 19, 38 + p.h - 27, "printed side ↓", 3.0, bold=False)]
    cam2 = Camera(V_BACK, CTR + (8, 10, 0), 120, (1200, 1000))
    p2 = Panel(card(["B", "F"], ["F"], off={"F": (0, 40, 0)}), cam2, 110, 38, W2, "s5_F")
    out.append(p2.boxed("2"))
    for hx in HOOKS:
        out.append(arrow(p2.P((hx, 40 - 14, ZS)), p2.P((hx, -T + 2, ZS)), 0.8))
    out.append(label(*(p2.P((XC - 60, H + 40, ZS)) + (-4, -6)), "F", 5))
    out.append(label(*(p2.P((W + 40, YC + 40, ZS)) + (2, -12)), "USB", 3.6, to=p2.P((W + 30, YC + 40, ZS))))
    y2 = 38 + max(p.h, p2.h) + 6
    cam3 = Camera(V_BACK, CTR + (8, 0, -5), 135, (1200, 1000))
    p3 = Panel(card(["B", "F", "SC", "SU"], ["SC", "SU"], off={"SC": (-55, 0, 0), "SU": (55, 0, 0)}), cam3, 10, y2, W2, "s5_S")
    out.append(p3.boxed("3"))
    out.append(arrow(p3.P((W + 50, H + 8, ZS - 30)), p3.P((W + 12, H + 8, ZS - 30)), 0.8))
    out.append(arrow(p3.P((-50, H + 8, ZS - 30)), p3.P((-12, H + 8, ZS - 30)), 0.8))
    out.append(label(*(p3.P((W + 55, -T, 40)) + (0, 8)), "SU", 4.6))
    out.append(label(*(p3.P((-55, -T, 40)) + (0, 8)), "SC", 4.6))
    out.append(label(*(p3.P((W + 55, YC, -T)) + (-12, 12)), "FRONT", 3.2, to=p3.P((W + 55, YC, -T / 2))))
    cam4 = Camera(V_FRONT, CTR + (0, 15, -6), 125, (1200, 1000))
    body = card(["B", "F", "SC", "SU", "C", "S1", "S2"], ["C", "S1", "S2"], off={"C": (0, 55, 0), "S1": (0, 55, 0), "S2": (0, 55, 0)})
    p4 = Panel(body, cam4, 110, y2, W2, "s5_C")
    out.append(p4.boxed("4"))
    out.append(arrow(p4.P((XC, 55 + T + 2, ZC - 20)), p4.P((XC, T + 30, ZC - 20)), 0.8))
    out.append(arrow(p4.P((XC + 10, -T - 2, ZC - 45)), p4.P((XC + 10, -T - 2, ZC + 30)), 0.8, both=True))
    out.append(label(*(p4.P((X0 + 10, 55 + HP, ZC)) + (-6, -8)), "C", 5))
    out.append(label(*(p4.P((XC + 40, 55 + 40, ZC)) + (-28, -10)), "FRONT", 3.2, to=p4.P((XC + 20, 55 + 40, ZC))))
    return page(5, "\n".join(out), "B · F · SC · SU · C", "1/2")


def hinge_section(x, y):
    """2D side section of the back flap hinge: tape inside the fold."""
    s = 1.6
    g = [f'<rect x="0" y="0" width="30" height="3" fill="{CARD_NEW}" stroke="{INK}" stroke-width="0.25"/>',
         f'<rect x="30" y="0" width="3" height="26" fill="{CARD_NEW}" stroke="{INK}" stroke-width="0.25"/>',
         f'<path d="M18,3.2 L30,3.2 L30,3.2 L29.8,15 L29.4,15 L29.4,3.6 L18,3.6 Z" fill="{TAPE}"/>',
         f'<rect x="18" y="3.0" width="11.8" height="0.9" fill="{TAPE}"/><rect x="29.1" y="3.0" width="0.9" height="12" fill="{TAPE}"/>']
    return (f'<g transform="translate({x:.2f},{y:.2f}) scale({s})">{"".join(g)}</g>'
            + text(x + 36 * s, y + 3 * s, "A", 3.6, anchor="start") + label(x + 10 * s, y + 13 * s, "tape", 3.4, to=(x + 26 * s, y + 6 * s)))


def step5b():
    out = []
    W2 = 96
    have = ["B", "F", "SC", "SU", "C", "S1", "S2"]
    cam = Camera(V_BACK, CTR + (0, 25, 12), 135, (1200, 1000))
    p = Panel(card(have + ["A"], ["A"], off={"A": (0, 45, 0)}, flap=0), cam, 10, 38, W2, "s5_A")
    out.append(p.boxed("1"))
    for x in (20, W - 20):
        out.append(arrow(p.P((x, H + 45, 30)), p.P((x, H + 8, 30)), 0.8))
    out.append(label(*(p.P((W - 22, H + 45 + T, DEPTH + 60)) + (8, 6)), "A", 5))
    cam2 = Camera(V_FRONT, CTR + (0, 10, -20), 135, (1200, 1000))
    p2 = Panel(card(have + ["A", "R"], ["R"], off={"R": (0, 0, -50)}, flap=0), cam2, 110, 38, W2, "s5_R")
    out.append(p2.boxed("2"))
    for x, y in ((14, H + 1.5), (W - 14, H + 1.5), (14, -1.5), (W - 14, -1.5)):
        out.append(arrow(p2.P((x, y, -50)), p2.P((x, y, -8)), 0.7))
    out.append(label(*(p2.P((XC, H + T + 6 + EAR, -50)) + (-14, -6)), "R", 5))
    out.append(label(*(p2.P((XC, H + T + 6 + EAR, -50)) + (2, -8)), "TOP ↑", 3.4, to=p2.P((XC, H + T + 6 + EAR - 2, -50))))
    y2 = 38 + max(p.h, p2.h) + 6
    cam3 = Camera(V_FRONT, CTR + (0, 6, -8), 125, (1200, 1000))
    p3 = Panel(card(have + ["A", "R"], flap=0) + corner_tape() + r_tape(), cam3, 10, y2, W2, "s5_tape")
    out.append(p3.boxed("3"))
    out.append(label(*(p3.P((W + T, H + T, DEPTH / 2)) + (12, -12)), "4×", 4.2, to=p3.P((W + T, H + T, DEPTH / 2))))
    zb = card(have + ["A", "R"], flap=0) + r_tape()
    zbx = zb + cube(LENS_XS[1] - 30, H + T, 6, LENS_XS[1] + 30, H + T + 0.4, 18, TAPE)
    zc = (LENS_XS[1], H + T, 14)
    yz = y2 + p3.h + 26
    _, zs1 = zoom(zb, zc, (0.2, 0.9, -0.4), 34, (32, yz), 21, "s5_notch_ok")
    _, zs2 = zoom(zbx, zc, (0.2, 0.9, -0.4), 34, (82, yz), 21, "s5_notch_no")
    out += [zs1, badge(48, yz + 16, True), zs2, badge(98, yz + 16, False)]
    cam4 = Camera(V_BACK, CTR + (0, 15, 20), 140, (1200, 1000))
    p4 = Panel(card(have + ["A", "R"], ["A"], flap=50), cam4, 110, y2, W2, "s5_flap")
    out.append(p4.boxed("4"))
    out.append(curved(p4.P((W - 30, H + 40, DEPTH + 75)), p4.P((W - 30, H + 10, DEPTH + 75)), p4.P((W - 30, H - 50, DEPTH + 12))))
    out.append(hinge_section(140, y2 + p4.h + 8))
    return page(5, "\n".join(out), "A · R · tape", "2/2")


# ---- Step 6: pocket blocks --------------------------------------------------------------
def step6():
    out = []
    s, xs, groups = "", 0, []
    for n, (L, k) in enumerate([(BTN_FREE, 3)] * 4 + [(BTN_FREE, 2)] * 2 + [(30, 2)]):
        s += block_stack(xs, 0, 0, xs + L, k * T, 10, "y", k, CARD_NEW)
        groups.append((xs, xs + L, k))
        xs += L + 9
    cam = Camera((0, 0.55, -0.83), (xs / 2, 4, 5), 26, (1500, 330))
    p = Panel(s, cam, 10, 38, 196, "s6_stacks")
    out.append(p.boxed("1"))
    for (a0, _, _), (_, b1, _), txt in ((groups[0], groups[3], "4 × (3× P)"), (groups[4], groups[5], "2 × (2× P)"), (groups[6], groups[6], "2× PL")):
        c = (p.P((a0, 9, 0)) + p.P((b1, 9, 0))) / 2
        out.append(label(c[0], p.y + p.h - 5, txt, 4.0))
    y2 = 38 + p.h + 6
    cam2 = Camera((0.18, 0.07, 0.98), (XC + 4, YC + 4, ZS), 72, (1500, 1050))
    p2 = Panel(card(BODY, flap=0) + blocks(CARD_NEW), cam2, 10, y2, 130, "s6_where")
    out.append(p2.boxed("2"))
    z = BLOCK_Z[1]
    for n, txt, d in (("bot1", "3× P", (0, 10)), ("bot2", "3× P", (0, 10)), ("top1", "2× P", (0, -10)), ("top2", "2× P", (0, -10)),
                      ("usb1", "3× P", (14, -4)), ("usb2", "3× P", (14, 4)), ("pl", "2× PL", (-12, 0))):
        (x0, y0, x1, y1), *_ = BLOCKS[n]
        c = p2.P(((x0 + x1) / 2, (y0 + y1) / 2, z))
        out.append(label(*(c + d), txt, 3.2, to=c))
    out.append(label(*(p2.P((M + 9, H - M - 1, z)) + (22, 12)), "foam", 3.2, to=p2.P((M + 9, H - M + 1, z)), fill="#f2cf4a"))
    out.append(dim(p2.P((M, YC - 18, z)), p2.P((M + BTN_FREE, YC - 18, z)), "18", off=(0, -2.5), size=3.2))
    cam3 = Camera((0.35, 0.3, 0.89), (XC + 6, YC + 10, ZS + 20), 100, (1000, 1050))
    p3 = Panel(card(BODY, flap=0) + blocks(CARD_OLD) + phone(off=(-4, 0, 45)), cam3, 144, y2, 62, "s6_phone")
    out.append(p3.boxed("3"))
    out.append(arrow(p3.P((XC, YC, ZS + 60)), p3.P((XC, YC, ZS + 18)), 0.8))
    out.append(arrow(p3.P((XC + 40, H + 25, ZS + 50)), p3.P((XC + 75, H + 25, ZS + 50)), 0.8))
    out.append(label(*(p3.P((W, H + 25, ZS + 50)) + (-3, -6)), "USB", 3.2))
    # 6.4 from the front through F's window: whole lit screen visible; buttons free
    y3 = y2 + p2.h + 8
    camf = Camera((0, 0.0001, -1), (XC, YC, ZS), 58, (900, 640))
    for i, (ok, offx) in enumerate(((True, 0), (False, -7))):
        pf = Panel(card(["F"]) + blocks(CARD_OLD) + phone(lit=True, off=(offx, 0, 0)), camf, 10 + i * 66, y3, 62, f"s6_screen{i}")
        out += [pf.boxed("4" if i == 0 else None), badge(10 + i * 66 + 56, y3 + pf.h - 6, ok)]
    camt = Camera((0.0, 0.95, 0.3), (M + 45, H - 5, ZS + 5), 24, (700, 620))
    for i, (ok, dx) in enumerate(((True, 0), (False, 33))):
        pt = Panel(blocks(CARD_NEW, ["top1"], off=(dx, 0, 0)) + phone(), camt, 142 + i * 33, y3, 31, f"s6_btn{i}")
        out += [pt.boxed(), badge(142 + i * 33 + 26, y3 + pt.h - 5, ok, 3.6)]
    return page(6, "\n".join(out), "P · PL")


# ---- Step 7: magnifiers in, focus, K --------------------------------------------------------
def step7():
    out = []
    W2 = 96
    body = card(BODY, flap=90) + blocks(CARD_OLD)
    cam = Camera(V_FRONT, CTR + (0, 40, -10), 140, (1200, 1100))
    p = Panel(body + "".join(magnifier(x, lift=60) for x in LENS_XS), cam, 10, 38, W2, "s7_in")
    out.append(p.boxed("1"))
    for x in LENS_XS:
        out.append(arrow(p.P((x + 26, LENS_Y + 150, ZL)), p.P((x + 26, LENS_Y + 100, ZL)), 0.8))
    out.append(label(*(p.P((LENS_XS[1], LENS_Y + 134, ZL - 4)) + (-4, -14)), "CARSON → face", 3.4, to=p.P((LENS_XS[1], LENS_Y + 134, ZL - 4))))
    out.append(label(*(p.P((LENS_XS[0], LENS_Y + 160, ZL)) + (10, -6)), "2× 5.5x", 4.2))
    cam2 = Camera((-0.62, 0.42, -0.66), CTR + (0, 30, -10), 135, (1200, 1100))
    p2 = Panel(body + "".join(magnifier(x) for x in LENS_XS) + phone(lit=True), cam2, 110, 38, W2, "s7_focus")
    out.append(p2.boxed("2"))
    for x in LENS_XS:
        out.append(arrow(p2.P((x, LENS_Y + 100, ZL - 14)), p2.P((x, LENS_Y + 100, ZL + STACK + 14)), 0.8, both=True))
    ex = p2.P((XC, YC, -60))
    out.append(f'<ellipse cx="{ex[0]:.2f}" cy="{ex[1]:.2f}" rx="5" ry="2.6" fill="#fff" stroke="{INK}" stroke-width="0.5"/><circle cx="{ex[0]:.2f}" cy="{ex[1]:.2f}" r="1.5" fill="{INK}"/>')
    # zoom: scale beside the CAM-side notch, from above; lens rings shown, case dashed
    rings = magnifier(LENS_XS[0]).split(f'color("{CASE}")')[0]
    zb = card(["A", "R"], flap=90) + rings
    zc = (XC - 14, H + T, ZS - 30)
    at = (186, 38 + p2.h - 21)
    zp, zs = zoom(zb, zc, (0, 1, 0.0001), 17, at, 19, "s7_scale", src=p2, src_r=5)
    out.append(zs)
    zr = ZL + STACK
    a, b = zp.P((XC - 27, H + T, zr)), zp.P((XC - 6, H + T, zr))
    out.append(f'<path d="M{a[0]:.2f},{a[1]:.2f} L{b[0]:.2f},{b[1]:.2f}" stroke="{NOC}" stroke-width="0.5" stroke-dasharray="1.2 0.8"/>')
    t30 = zp.P((XC - 7.5, H + T, ZS - 30))
    out.append(label(at[0] - 26, at[1] + 14, "d ≈ 30", 3.8, to=t30))
    y2 = 38 + max(p.h, p2.h) + 10
    body3 = body + "".join(magnifier(x) for x in LENS_XS)
    cam3 = Camera((0.45, 0.75, -0.48), (XC, H + 20, 25), 80, (1200, 900))
    p3 = Panel(body3 + k_pieces(CARD_NEW, lift=26), cam3, 10, y2, W2, "s7_K")
    out.append(p3.boxed("3"))
    for x in LENS_XS:
        for zz in (1, 38):
            out.append(arrow(p3.P((x + 24, H + 2 * T + 26, zz)), p3.P((x + 24, H + 2 * T + 3, zz)), 0.6))
    out.append(label(*(p3.P((LENS_XS[1] + 27, H + 2 * T + 26, 40)) + (10, -8)), "4× K", 4.4))
    p4 = Panel(body3 + k_pieces(CARD_OLD) + case_tape(), cam3, 110, y2, W2, "s7_casetape")
    out.append(p4.boxed("4"))
    out.append(label(*(p4.P((XC, LENS_Y + 78, ZL + STACK + 4)) + (0, -22)), "tape", 3.6, to=p4.P((XC, LENS_Y + 78, ZL + STACK + 4))))
    y3 = y2 + p3.h + 8
    out.append(frame_box(10, y3, 196, 30, "5"))
    out.append(f'<rect x="40" y="{y3 + 5}" width="40" height="20" rx="3.5" fill="#3b3d42"/><rect x="42" y="{y3 + 7}" width="36" height="16" rx="2" fill="#a9dcff"/>')
    out.append(text(90, y3 + 18, "screen ↔ lens  =  d + 10  ≈  40 mm", 5.2, anchor="start"))
    return page(7, "\n".join(out), "TV-36 · focus · K")


# ---- Step 8: phone, cable, flap, bands --------------------------------------------------------
def step8():
    out = []
    W2 = 96
    base = card(BODY, flap=0) + blocks(CARD_OLD) + "".join(magnifier(x) for x in LENS_XS) + k_pieces(CARD_OLD)
    cam = Camera((0.4, -0.5, 0.77), CTR + (10, 30, 70), 130, (1200, 1100))
    p = Panel(base + flap_pads(0), cam, 10, 38, W2, "s8_pads")
    out.append(p.boxed("1"))
    pad = (XC + 52, H - PAD, DEPTH + H - YC + 20)
    out.append(label(*(p.P(pad) + (12, 14)), "4× foam", 3.8, to=p.P(pad), fill="#f2cf4a"))
    out.append(label(*(p.P(pad) + (12, 24)), "2–3 mm", 3.4))
    cam2 = Camera((0.6, 0.35, 0.72), CTR + (20, 15, 45), 140, (1200, 1100))
    p2 = Panel(base + phone(off=(0, 0, 55)) + f"translate([0,0,55]) {{ {cable(tied=False)} }}", cam2, 110, 38, W2, "s8_phone")
    out.append(p2.boxed("2"))
    out.append(arrow(p2.P((XC, H + 10, ZS + 55)), p2.P((XC, H + 10, ZS + 12)), 0.8))
    out.append(label(*(p2.P((M + PHONE_W + 12, YC, ZS + 60)) + (6, -12)), "1", 4.0, to=p2.P((M + PHONE_W + 12, YC, ZS + 60))))
    out.append(label(*(p2.P((XC, H + 10, ZS + 60)) + (0, -8)), "2", 4.0))
    y2 = 38 + max(p.h, p2.h) + 8
    full = base + phone() + cable()
    cam3 = Camera((0.55, 0.45, 0.7), (W + 25, YC, ZS), 30, (1000, 900))
    p3 = Panel(full, cam3, 10, y2, 62, "s8_ties")
    out.append(p3.boxed("3"))
    out.append(label(*(p3.P((W + T + 33, YC + 12, ZS + 4)) + (0, -12)), "2× tie", 3.6))
    cam4 = Camera(V_BACK, CTR + (10, 10, 20), 128, (1200, 1100))
    closed = (card(BODY, ["A"], flap=90) + blocks(CARD_OLD) + "".join(magnifier(x) for x in LENS_XS) + k_pieces(CARD_OLD) + phone()
              + cable() + flap_pads(90))
    p4 = Panel(closed + rubber_bands(), cam4, 76, y2, 82, "s8_bands")
    out.append(p4.boxed("4"))
    out.append(curved(p4.P((XCUT + 20, H + 60, DEPTH + 70)), p4.P((XCUT + 20, H + 40, DEPTH + 30)), p4.P((XCUT + 20, H - 10, DEPTH + 8))))
    out.append(label(*(p4.P((HOOKS[1], H + T + 12, ZS)) + (14, -10)), "2× band", 3.6, to=p4.P((HOOKS[1], H + T + 8, ZS))))
    cz = (M + 22, M + 22, ZS + PHONE_T + 3)
    _, zs = zoom(closed + rubber_bands(), cz, (-0.25, 0.3, 0.92), 34, (184, y2 + 30), 21, "s8_cam")
    out += [zs, badge(198, y2 + 46, True)]
    return page(8, "\n".join(out), "phone · cable · bands")


# ---- Step 9: foam and straps --------------------------------------------------------------------
def step9():
    out = []
    W2 = 96
    full = (card(BODY, flap=90) + blocks(CARD_OLD) + "".join(magnifier(x) for x in LENS_XS) + k_pieces(CARD_OLD) + phone()
            + cable() + rubber_bands())
    cam = Camera((0.4, 0.35, -0.85), CTR + (0, 12, -10), 105, (1200, 1000))
    p = Panel(full + face_foam(), cam, 43, 38, 130, "s9_foam")
    out.append(p.boxed("1"))
    out.append(label(*(p.P((XC + 70, H - 6, -T - 10)) + (14, -20)), "12 × 10 mm", 3.6, to=p.P((XC + 70, H - 4, -T - 10)), fill="#f2cf4a"))
    p2 = Panel(full + face_foam() + ear_tape() + strap(), Camera((0.6, 0.45, -0.66), CTR + (0, 20, -40), 128, (1200, 1000)), 43, 38 + p.h + 6, 130, "s9_strap")
    out.append(p2.boxed("2"))
    o = T + 6
    out.append(label(*(p2.P((XC + XC + o + EAR, YC + 20, 0)) + (-4, -26)), "3× tape", 3.4, to=p2.P((XC + XC + o + EAR - 2, YC + 14, -T))))
    return page(9, "\n".join(out), "foam · strap")


# ---- Step 10: final check ------------------------------------------------------------------------
def step10():
    out = []
    closed = (card(BODY, flap=90) + blocks(CARD_OLD) + "".join(magnifier(x) for x in LENS_XS) + k_pieces(CARD_OLD) + phone(lit=True)
              + cable() + rubber_bands() + face_foam() + flap_pads(90))
    cells = [(Camera((-0.3, 0.3, 0.9), (M + 25, M + 22, ZS + 6), 40, (800, 560)), "camera clear"),
             (Camera((0, 0.0001, -1), (XC, YC, ZS), 56, (800, 560)), "screen clear"),
             (Camera((0.55, 0.45, 0.7), (W + 25, YC, ZS), 32, (800, 560)), "USB tied"),
             (Camera(V_BACK, CTR + (0, 20, 0), 125, (800, 560)), "shake"),
             (Camera(V_FRONT, CTR + (0, 20, -10), 125, (800, 560)), "dark room: no light"),
             (Camera((0, 0.0001, -1), (XC, YC + 4, 0), 100, (800, 560)), "63 mm · both sharp")]
    for i, (cam, lab) in enumerate(cells):
        x, y = 10 + (i % 2) * 100, 40 + (i // 2) * 72
        if i == 4:
            out.append(f'<rect x="{x}" y="{y}" width="96" height="68" rx="2" fill="#20242c"/>')
        pn = Panel(closed.replace(LIT, SCREEN).replace("#2b6cb0", SCREEN) if i == 4 else closed, cam, x + 8, y + 2, 80, f"s10_{i}")
        out += [pn.svg(), frame_box(x, y, 96, 68), badge(x + 89, y + 7, True, 4), text(x + 48, y + 65, lab, 4, color="#fff" if i == 4 else INK)]
        if i == 3:
            c = pn.P(CTR)
            out.append(arrow(c + (-36, 22), c + (-24, 22), 0.7, both=True) + arrow(c + (24, 22), c + (36, 22), 0.7, both=True))
        if i == 5:
            out.append(dim(pn.P((LENS_XS[0], LENS_Y, -20)), pn.P((LENS_XS[1], LENS_Y, -20)), "63", off=(0, -2.5), size=3.6))
    y = 40 + 3 * 72
    out.append(frame_box(10, y, 196, 18))
    cx, cy = 30, y + 9
    out.append(f'<circle cx="{cx}" cy="{cy}" r="6" fill="#fff" stroke="{INK}" stroke-width="0.6"/><path d="M{cx},{cy} L{cx},{cy - 4.2} M{cx},{cy} L{cx + 3},{cy + 1}" stroke="{INK}" stroke-width="0.6"/>')
    out.append(text(42, cy + 2.2, "≈ 5 min per session", 5.2, anchor="start"))
    return page(10, "\n".join(out), "check")


PAGES = [("parts", page1), ("step-03", step3), ("step-04", step4), ("step-05a", step5a), ("step-05b", step5b), ("step-06", step6),
         ("step-07", step7), ("step-08", step8), ("step-09", step9), ("step-10", step10)]


def main(only=None):
    check_orientation()
    files = []
    for name, f in PAGES:
        svg = WORK / f"{name}.svg"
        if only is None or name in only:
            svg.write_text(f())
            subprocess.run(["rsvg-convert", "-d", "110", "-p", "110", "-o", str(HERE / f"{name}.png"), str(svg)], check=True)
        files.append(str(svg))
    subprocess.run(["rsvg-convert", "-f", "pdf", "-o", str(CARD / "build-guide.pdf"), *files], check=True)
    print(f"{len(files)} pages -> {CARD / 'build-guide.pdf'}")


if __name__ == "__main__":
    main(set(sys.argv[1:]) or None)
