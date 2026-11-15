"""3D model of the assembled cardboard headset, built from gen.py's real part outlines.

World frame (gen.py's): x along the phone (CAM end 0, USB end W), y up from the floor's inner
face, z from the body's front edge (face side) toward the phone. Every card part is gen.py's
shapely polygon, extruded T and placed by a frame (origin, u axis, v axis, outward normal), so
the printed/engraved face is the outside one. OpenSCAD gets (x, -z, y) so its Z is up.
"""
import math, os, subprocess, sys
from pathlib import Path
import numpy as np
from PIL import Image
from shapely import affinity
from shapely.geometry import MultiPolygon, Point, Polygon, box
from shapely.ops import unary_union

HERE = Path(__file__).resolve().parent
CARD = HERE.parent
WORK = HERE / "work"
WORK.mkdir(exist_ok=True)
OPENSCAD = os.environ.get("OPENSCAD", str(Path.home() / ".local/bin/openscad"))

# gen.py's part functions with the laser-cut defaults (T 3, d 24-32), without writing any file.
_argv, sys.argv = sys.argv, ["gen.py"]
G = {"__name__": "gen"}
exec((CARD / "gen.py").read_text().split("# ---- Pages")[0], G)
sys.argv = _argv
for _k in ("T W H XC YC ZS DEPTH ZN SLOT_W AP SEAT WP HP YL HOOKS XCUT GAP M LAYERS N_BLOCKS PHONE_W PHONE_H "
           "PHONE_T SCREEN_W SCREEN_H CAM_END IPD FRAME_OD STACK GLASS CASE_W BTN_FREE USB_W USB_H USB_LEN LIP "
           "EAR STRAP NOSE_W NOSE_TOP THUMB D_MIN D_MAX FIT PAD").split():
    globals()[_k] = G[_k]
assert (T, D_MIN, D_MAX) == (3.0, 24.0, 32.0)

# ---- Placement -----------------------------------------------------------------
X0 = 0.5 + T                       # carrier plates start here (0.5 clearance + end flap)
ZC = ZS - 30 - T - 0.5 - STACK     # carrier front at the measured d = 30 (scale reads 30)
ZL = ZC + T + 0.5                  # front face of the lens stack
LENS_Y = T + YL - (SEAT - FRAME_OD) / 2   # rim resting in the seat
LENS_XS = [XC + lx for lx in G["LENS_X"]]
D_NOW = ZS - (ZL + STACK)

CARD_NEW, CARD_OLD = "#d39a55", "#e2ddd3"
INK_NEW, INK_OLD = "#4a2c10", "#a59d8f"


def frame(o, eu, ev, ew):
    m = np.eye(4)
    m[:3, 0], m[:3, 1], m[:3, 2], m[:3, 3] = eu, ev, ew, o
    return m


def rot_x(deg, about):              # rotation about the x axis through point `about`
    a = math.radians(deg)
    r = np.eye(4)
    r[1:3, 1:3] = [[math.cos(a), -math.sin(a)], [math.sin(a), math.cos(a)]]
    t1, t2 = np.eye(4), np.eye(4)
    t1[:3, 3], t2[:3, 3] = np.negative(about), about
    return t2 @ r @ t1


def polys(g):
    g = g.buffer(0)
    return [p for p in getattr(g, "geoms", [g]) if isinstance(p, Polygon) and p.area > 0.5]


def texts(part, rot):
    """Engraved labels in the part frame: (x, y, s, size, angle). Page-upright on the laser
    sheet, so a part placed at rot 90 carries them at -90; drop is page-down."""
    out = []
    for x, y, s, size, drop in part.texts:
        a = math.radians(-rot)
        dx, dy = drop * math.sin(a), -drop * math.cos(a)
        out.append((x + dx, y + dy, s, size, -rot))
    return out


class Piece:
    def __init__(self, shape, txt, m):
        self.shape, self.m, self.ticks = shape, m, []
        self.txt = [t for t in txt if shape.buffer(0.01).contains(Point(t[0], t[1]))]

    def world(self, u, v, w=0.0):
        return (self.m @ [u, v, w, 1])[:3]


def card_parts(flap=90.0, fold=(90.0, 90.0)):
    """name -> list of Pieces. flap: back flap angle, 0 = flat (open), 90 = closed."""
    P = {}
    a = G["top_wall"]()
    ma = frame((0, H, 0), (1, 0, 0), (0, 0, -1), (0, 1, 0))
    ta = texts(a, 0)
    main, fl = a.shape & box(-9, -DEPTH, W + 9, 9), a.shape & box(-9, -DEPTH - 200, W + 9, -DEPTH)
    P["A"] = [Piece(main, ta, ma), Piece(fl, ta, rot_x(flap, (0, H, DEPTH)) @ ma)]
    P["A"][0].ticks = [l for k, l in a.lines if k == "guide" and len(l.coords) == 2]
    b = G["bottom_wall"]()
    P["B"] = [Piece(b.shape, texts(b, 0), frame((0, 0, 0), (1, 0, 0), (0, 0, 1), (0, -1, 0)))]
    sc, su = G["side_wall"](False), G["side_wall"](True)
    P["SC"] = [Piece(sc.shape, texts(sc, 0), frame((0, 0, 0), (0, 0, 1), (0, 1, 0), (-1, 0, 0)))]
    P["SU"] = [Piece(su.shape, texts(su, 0), frame((W, 0, 0), (0, 0, -1), (0, 1, 0), (1, 0, 0)))]
    r = G["face_ring"]()
    P["R"] = [Piece(r.shape, texts(r, 90), frame((XC, 0, 0), (-1, 0, 0), (0, 1, 0), (0, 0, -1)))]
    f = G["screen_frame"]()
    P["F"] = [Piece(f.shape, texts(f, 90), frame((0, 0, ZS - T), (1, 0, 0), (0, 1, 0), (0, 0, 1)))]
    P["C"] = carrier_pieces(*fold)
    s = G["seat"]()
    P["S1"] = [Piece(s.shape, texts(s, 0), frame((X0, T, ZC + T), (1, 0, 0), (0, 1, 0), (0, 0, 1)))]
    P["S2"] = [Piece(s.shape, texts(s, 0), frame((X0 + WP, T, ZC + T + GAP), (-1, 0, 0), (0, 1, 0), (0, 0, -1)))]
    return P


def rot_y(deg, about):
    a = math.radians(deg)
    r = np.eye(4)
    r[0, 0], r[0, 2], r[2, 0], r[2, 2] = math.cos(a), math.sin(a), -math.sin(a), math.cos(a)
    t1, t2 = np.eye(4), np.eye(4)
    t1[:3, 3], t2[:3, 3] = np.negative(about), about
    return t2 @ r @ t1


def carrier_pieces(plate=90.0, flaps=90.0):
    """C folded: plates up by `plate` degrees from flat, end flaps back by `flaps` (90, 90 = done)."""
    c = G["carrier"]()
    tc = texts(c, 90)
    floor = frame((X0 + WP, T, ZC + T), (-1, 0, 0), (0, 0, -1), (0, -1, 0))
    front = rot_x(plate, (0, T, ZC + T)) @ floor
    rear = rot_x(-plate, (0, T, ZC + T + GAP)) @ floor
    f90 = rot_x(90, (0, T, ZC + T)) @ floor
    back = rot_x(plate - 90, (0, T, ZC + T))
    return [Piece(c.shape & box(0, -GAP, WP, 0), tc, floor), Piece(c.shape & box(0, 0, WP, HP), tc, front),
            Piece(c.shape & box(0, -GAP - HP, WP, -GAP), tc, rear),
            Piece(c.shape & box(-GAP - 1, 0, 0, HP), tc, back @ rot_y(-flaps, (X0 + WP, 0, ZC + T)) @ f90),
            Piece(c.shape & box(WP, 0, WP + GAP + 1, HP), tc, back @ rot_y(flaps, (X0, 0, ZC + T)) @ f90)]


# ---- OpenSCAD emission -----------------------------------------------------------
def poly_scad(g):
    out = []
    for p in polys(g):
        pts, paths = [], []
        for ring in [p.exterior, *p.interiors]:
            c = list(ring.coords)[:-1]
            paths.append(list(range(len(pts), len(pts) + len(c))))
            pts += c
        out.append("polygon(points=[%s], paths=%s);" % (",".join(f"[{x:.3f},{y:.3f}]" for x, y in pts), paths))
    return "\n".join(out)


def mm(m):
    return "[" + ",".join("[" + ",".join(f"{v:.5f}" for v in row) + "]" for row in m) + "]"


def piece_scad(pc, color, ink, off=(0, 0, 0), extra=None):
    m = pc.m if extra is None else extra @ pc.m
    m = m.copy()
    m[:3, 3] += off
    s = f'color("{color}") multmatrix({mm(m)}) linear_extrude({T}) {{ {poly_scad(pc.shape)} }}\n'
    for x, y, txt, size, ang in pc.txt:
        s += (f'color("{ink}") multmatrix({mm(m)}) translate([{x:.2f},{y:.2f},{T - 0.05}]) rotate({ang}) '
              f'linear_extrude(0.25) text("{txt}", size={size * 0.74:.2f}, halign="center", font="DejaVu Sans:style=Bold");\n')
    for ln in pc.ticks:
        (x0, y0), (x1, y1) = ln.coords
        s += f'color("{ink}") multmatrix({mm(m)}) translate([{min(x0, x1):.2f},{y0 - 0.2:.2f},{T - 0.05}]) cube([{abs(x1 - x0):.2f},0.4,0.25]);\n'
    return s


def cube(x0, y0, z0, x1, y1, z1, color):
    lo = [min(x0, x1), min(y0, y1), min(z0, z1)]
    return f'color("{color}") translate([{lo[0]:.2f},{lo[1]:.2f},{lo[2]:.2f}]) cube([{abs(x1 - x0):.2f},{abs(y1 - y0):.2f},{abs(z1 - z0):.2f}]);\n'


def tube(pts, r, color, fn=10):
    """Chain of hulled spheres through world points."""
    s = f'color("{color}") union() {{\n'
    for a, b in zip(pts, pts[1:]):
        s += f"hull() {{ translate([{a[0]:.2f},{a[1]:.2f},{a[2]:.2f}]) sphere({r},$fn={fn}); translate([{b[0]:.2f},{b[1]:.2f},{b[2]:.2f}]) sphere({r},$fn={fn}); }}\n"
    return s + "}\n"


def strip(pts, width, thick, normal_axis, color):
    """Flat band through world points; width across normal_axis ('x' ...)."""
    i = "xyz".index(normal_axis)
    s = f'color("{color}") union() {{\n'
    for a, b in zip(pts, pts[1:]):
        cs = []
        for p in (a, b):
            sz = [thick, thick, thick]
            sz[i] = width
            c = [p[k] - sz[k] / 2 for k in range(3)]
            cs.append(f"translate([{c[0]:.2f},{c[1]:.2f},{c[2]:.2f}]) cube([{sz[0]},{sz[1]},{sz[2]}]);")
        s += "hull() { " + " ".join(cs) + " }\n"
    return s + "}\n"


# ---- Stand-ins and small parts (world frame) -------------------------------------
FOAM, TAPE, BAND, PHONE, SCREEN, LIT, CASE, RING, GLASSC = ("#f2cf4a", "#7fb8e6", "#c8442c", "#3b3d42",
                                                         "#15171a", "#a9dcff", "#2e3033", "#55585e", "#cdeef8")


def phone(lit=False, off=(0, 0, 0)):
    x0, y0, z0 = M + off[0], M + off[1], ZS + off[2]
    s = (f'color("{PHONE}") translate([{x0},{y0},{z0}]) linear_extrude({PHONE_T}) offset(r=9) offset(delta=-9) '
         f'square([{PHONE_W},{PHONE_H}]);\n')
    sx, sy = x0 + (PHONE_W - SCREEN_W) / 2, y0 + (PHONE_H - SCREEN_H) / 2
    s += (f'color("{LIT if lit else SCREEN}") translate([{sx},{sy},{z0 - 0.15}]) linear_extrude(0.2) offset(r=7) offset(delta=-7) '
          f'square([{SCREEN_W},{SCREEN_H}]);\n')
    if lit:   # side-by-side test pattern, one per eye
        for lx in LENS_XS:
            s += f'color("#2b6cb0") translate([{lx + off[0]},{YC + off[1]},{z0 - 0.3}]) linear_extrude(0.2) difference() {{ circle(18,$fn=48); circle(16,$fn=48); }}\n'
            s += f'color("#2b6cb0") translate([{lx + off[0] - 10},{YC + off[1] - 1},{z0 - 0.3}]) cube([20,2,0.2]);\n'
    zb = z0 + PHONE_T   # camera island: phone top at the CAM end, island toward the floor
    s += (f'color("#2a2c30") translate([{x0 + 3},{y0 + 3},{zb - 0.1}]) linear_extrude(3.75) offset(r=8) offset(delta=-8) '
          f'square([{CAM_END - 3},{39}]);\n')
    for cx, cy in ((x0 + 13, y0 + 13), (x0 + 13, y0 + 32), (x0 + 31, y0 + 22)):
        s += f'color("#111") translate([{cx},{cy},{zb + 3.6}]) cylinder(h=1.2, r=7.2, $fn=32);\n'
    # side buttons (approximate, unmeasured): Action + volume on the top edge, side + Camera Control below
    for a, b, top in ((30, 37, 1), (44, 55, 1), (58, 69, 1), (44, 61, 0), (95, 113, 0)):
        y = y0 + PHONE_H if top else y0 - 0.8
        s += cube(x0 + a, y, z0 + 2.5, x0 + b, y + 0.8, z0 + 6.5, "#b9bec7")
    return s


def magnifier(lx, z0=None, lift=0.0, logo=True):
    """TV-36 at 5.5x: top and bottom lens rings swung out (front and rear thirds of the stack),
    middle lens in the case, case pointing up."""
    z0 = ZL if z0 is None else z0
    y0, t3 = LENS_Y + lift, STACK / 3
    s = ""
    for zz in (z0, z0 + 2 * t3):
        s += (f'color("{RING}") translate([{lx},{y0},{zz}]) linear_extrude({t3 - 0.3}) difference() {{ union() {{ '
              f'hull() {{ circle({FRAME_OD / 2},$fn=64); translate([0,33]) circle(8,$fn=32); }} '
              f'translate([-4,{-FRAME_OD / 2 - 4.3}]) square([8,6]); }} circle({GLASS / 2},$fn=64); }}\n')
        s += f'color("{GLASSC}") translate([{lx},{y0},{zz + t3 / 2 - 1}]) cylinder(h=2, r={GLASS / 2}, $fn=64);\n'
    zf, zb = z0 - 3.4, z0 + STACK + 3.4
    s += (f'color("{CASE}") translate([{lx},{y0},{zf}]) linear_extrude({zb - zf}) hull() {{ translate([0,35]) circle(11,$fn=40); '
          f'translate([0,74.45]) circle({CASE_W / 2},$fn=64); }}\n')
    s += f'color("#888") translate([{lx},{y0 + 35},{zf - 0.3}]) cylinder(h={zb - zf + 0.6}, r=2.5, $fn=20);\n'
    if logo:   # CARSON logo on the face side (-z), readable from the front
        s += (f'color("#c9c9c9") translate([{lx},{y0 + 74},{zf - 0.2}]) mirror([1,0,0]) linear_extrude(0.25) '
              f'text("CARSON", size=4.2, halign="center", valign="center", font="DejaVu Sans:style=Bold");\n')
    return s


def case_box(lx, z0=None):
    """World bounding box of a magnifier case (for K pieces and annotations)."""
    z0 = ZL if z0 is None else z0
    return (lx - CASE_W / 2, LENS_Y + 24, z0 - 3.4, lx + CASE_W / 2, LENS_Y + 94.75, z0 + STACK + 3.4)


def shade(color, f):
    c = [int(color[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{max(0, min(255, int(v * f))):02x}" for v in c)


def block_stack(x0, y0, z0, x1, y1, z1, axis, n, color):
    """n card layers stacked along axis ('x' or 'y'), one cube each, alternate shades so the layers show."""
    s = ""
    base = color
    for k in range(n):
        color = base if k % 2 == 0 else shade(base, 0.86)
        if axis == "y":
            t = (y1 - y0) / n
            s += cube(x0, y0 + k * t, z0, x1, y0 + (k + 1) * t, z1, color)
        else:
            t = (x1 - x0) / n
            s += cube(x0 + k * t, y0, z0, x0 + (k + 1) * t, y1, z1, color)
    return s


BLOCK_Z = (ZS, ZS + 10)
BLOCKS = {   # name: (box, stacking axis, layers)
    "bot1": ((M, 0, M + BTN_FREE, M), "y", 3), "bot2": ((M + PHONE_W - BTN_FREE, 0, M + PHONE_W, M), "y", 3),
    "top1": ((M, H - 2 * T, M + BTN_FREE, H), "y", 2), "top2": ((M + PHONE_W - BTN_FREE, H - 2 * T, M + PHONE_W, H), "y", 2),
    "usb1": ((W - M, YC + 7, W, YC + 7 + BTN_FREE), "x", 3), "usb2": ((W - M, YC - 7 - BTN_FREE, W, YC - 7), "x", 3),
    "pl": ((0, YC - 15, 2 * T, YC + 15), "x", 2)}
BLOCK_FOAM = {"top1": (M, H - M, M + BTN_FREE, H - 2 * T), "top2": (M + PHONE_W - BTN_FREE, H - M, M + PHONE_W, H - 2 * T),
              "pl": (2 * T, YC - 15, M, YC + 15)}


def blocks(color, names=BLOCKS, foam=True, off=(0, 0, 0)):
    s = ""
    for n in names:
        (x0, y0, x1, y1), ax, k = BLOCKS[n]
        s += block_stack(x0 + off[0], y0 + off[1], BLOCK_Z[0] + off[2], x1 + off[0], y1 + off[1], BLOCK_Z[1] + off[2], ax, k, color)
        if foam and n in BLOCK_FOAM:
            x0, y0, x1, y1 = BLOCK_FOAM[n]
            s += cube(x0 + off[0], y0 + off[1], BLOCK_Z[0] + off[2], x1 + off[0], y1 + off[1], BLOCK_Z[1] + off[2], FOAM)
    return s


def face_foam_2d():
    """12 mm band round R's opening and nose gap, in R's frame."""
    r = G["face_ring"]().shape
    o = T + 6
    hole = unary_union([box(-XC + 12, 12, XC - 12, H - 12).buffer(6), affinity.translate(G["nose"](NOSE_TOP + o), 0, -o)])
    return Polygon(r.exterior) & box(-XC - o, -o - 2, XC + o, H + o) & hole.buffer(12) - hole


def face_foam():
    pc = Piece(face_foam_2d(), [], frame((XC, 0, 0), (-1, 0, 0), (0, 1, 0), (0, 0, -1)))
    m = pc.m.copy()
    m[:3, 3] += (0, 0, -T)
    return f'color("{FOAM}") multmatrix({mm(m)}) linear_extrude(10) {{ {poly_scad(pc.shape)} }}\n'


def flap_pads(flap=90.0, color=FOAM):
    """Foam pads on the inside of the back flap at the four dotted squares."""
    s = ""
    ma = rot_x(flap, (0, H, DEPTH)) @ frame((0, H, 0), (1, 0, 0), (0, 0, -1), (0, 1, 0))
    for px in (-12, 52):
        for py in (-20, 20):
            u, v = XC + px, -DEPTH - (H - YC - py)
            m = ma.copy()
            s += f'color("{color}") multmatrix({mm(m)}) translate([{u - 10},{v - 10},{-PAD}]) cube([20,20,{PAD}]);\n'
    return s


def cable(tied=True):
    zc, yc = ZS + PHONE_T / 2, YC
    x1 = M + PHONE_W
    s = cube(x1, yc - 6, zc - 3.5, x1 + USB_LEN, yc + 6, zc + 3.5, "#d9d9d9")
    pts = [(x1 + USB_LEN, yc, zc), (x1 + USB_LEN + 4, yc, ZS + 2.6), (W + T + 22, yc, ZS + 2.6), (W + T + 48, yc, ZS + 2.2),
           (W + T + 62, yc - 6, ZS + 3), (W + T + 68, yc - 30, ZS + 3)]
    s += tube(pts, 2.0, "#f4f4f4")
    if tied:
        for x in (W + T + 28, W + T + 38):
            s += (f'color("#1f1f1f") translate([{x - 0.75},0,0]) rotate([90,0,90]) linear_extrude(1.5) difference() {{ '
                  f'translate([{yc - 8.6},{ZS - T - 0.9}]) square([17.2,{T + 6.6}]); translate([{yc - 7.6},{ZS - T}]) square([15.2,{T + 4.7}]); }}\n')
            s += cube(x - 0.75, yc - 8.6, ZS + 4.6, x + 0.75, yc - 4, ZS + 9, "#1f1f1f")
    return s


def rubber_bands():
    s = ""
    for hx in HOOKS:
        for dx in (-3.6, 3.6):
            x = hx + dx
            pts = [(x, H + T + 3.2, ZS - 1.5), (x, H + T + 1.6, DEPTH + T + 0.6), (x, -T - LIP - 0.6, DEPTH + T + 0.6),
                   (x, -T - 3.2, ZS - 1.5)]
            s += tube(pts, 0.8, BAND, 8)
    return s


def strap():
    o = T + 6
    s = ""
    for sx in (-1, 1):
        x = XC + sx * (XC + o + EAR / 2)
        s += strip([(x, YC, 6), (x, YC, -T - 14), (x + sx * 8, YC, -T - 40), (x + sx * 14, YC, -T - 90)], 26, 1.6, "y", "#262626")
        s += strip([(x + sx * 9, YC, -1), (x + sx * 9, YC, -T - 14), (x + sx * 13, YC, -T - 40)], 26, 1.6, "y", "#262626")
    yt = H + o + EAR / 2
    s += strip([(XC, yt, 6), (XC, yt, -T - 14), (XC, yt + 14, -T - 40), (XC, yt + 30, -T - 85)], 26, 1.6, "x", "#262626")
    return s


def ear_tape():
    o = T + 6
    s = ""
    for sx in (-1, 1):
        xo = XC + sx * (XC + o + EAR)
        xi = XC + sx * (XC + o + EAR / 2 + STRAP[0] / 2)
        s += cube(xi, YC - 18, -T - 0.4, xo + sx * 0.4, YC + 18, 0.4, TAPE)
    yt = H + o + EAR
    s += cube(XC - 18, yt - EAR / 2 + STRAP[0] / 2, -T - 0.4, XC + 18, yt + 0.4, 0.4, TAPE)
    return s


def corner_tape():
    """Tape along the four long corners (walls to top and bottom) and round R's back."""
    s, t = "", 0.4
    for x0, x1 in ((-T - t, 14), (W - 14, W + T + t)):
        for y0, y1 in ((H + T, H + T + t), (-T - t, -T)):
            s += cube(x0, y0, 0, x1, y1, DEPTH, TAPE)
        xs = (-T - t, -T) if x0 < 0 else (W + T, W + T + t)
        for y0, y1 in ((H - 14, H + T), (-T, 14)):
            s += cube(xs[0], y0, 0, xs[1], y1, DEPTH, TAPE)
    return s


def r_tape():
    """Tape from R's back face onto the walls, all the way round."""
    s, t = "", 0.4
    for x0, x1 in ((-T, 30.8 - 1), (73.8 + 1, 94.8 - 1), (137.8 + 1, W + T)):   # top: off the magnifier notches
        s += cube(x0, H + T, 0, x1, H + T + t, 12, TAPE)
    s += cube(-T, -T - t, 0, W + T, -T, 12, TAPE)
    for x in (-T - t, W + T):
        s += cube(x, -T, 0, x + t, H + T, 12, TAPE)
    return s


def k_pieces(color, lxs=LENS_XS, lift=0.0):
    s = ""
    for lx in lxs:
        _, _, zf, _, _, zb = case_box(lx)
        x0, x1 = lx - SLOT_W / 2 - 6, lx + SLOT_W / 2 + 6
        s += cube(x0, H + T + lift, 0, x1, H + 2 * T + lift, zf - 0.4, color)
        s += cube(x0, H + T + lift, zb + 0.4, x1, H + 2 * T + lift, ZN + 8, color)
    return s


def case_tape():
    xs = [case_box(lx) for lx in LENS_XS]
    y = LENS_Y + 60
    return cube(xs[0][0] - 0.4, y, xs[0][2] - 0.4, xs[1][3] + 0.4, y + 18, xs[0][5] + 0.4, TAPE)


# ---- Scenes and rendering ---------------------------------------------------------
TO_SCAD = "multmatrix([[1,0,0,0],[0,0,-1,0],[0,1,0,0],[0,0,0,1]])"


def scene_scad(body):
    return f"{TO_SCAD} {{\n{body}}}\n"


def to_scad_pt(p):
    return (p[0], -p[2], p[1])


class Camera:
    """Orthographic camera looking at `center` from direction `d` (world frame), framing `half`
    mm vertically (approximately; the exact map comes from calibration)."""

    def __init__(self, d, center, half, size=(1600, 1100)):
        d = np.asarray(d, float)
        self.d, self.center, self.half, self.size = d / np.linalg.norm(d), np.asarray(center, float), half, size
        self.A = None

    def args(self):
        dist = self.half / math.tan(math.radians(22.5 / 2))
        eye = self.center + self.d * dist
        e, c = to_scad_pt(eye), to_scad_pt(self.center)
        return [f"--camera={e[0]:.3f},{e[1]:.3f},{e[2]:.3f},{c[0]:.3f},{c[1]:.3f},{c[2]:.3f}", "--projection=o",
                f"--imgsize={self.size[0]},{self.size[1]}"]

    def key(self):
        return "cam_" + "_".join(f"{v:.2f}" for v in (*self.d, *self.center, self.half, *self.size)).replace("-", "m")

    def calibrate(self):
        """Fit the 3D->pixel affine map from marker cubes rendered with this camera."""
        cols = {"red": (1, 0, 0), "lime": (0, 1, 0), "blue": (0, 0, 1), "black": (0, 0, 0)}
        k = self.half * 0.35
        pts = {"red": self.center + (k, 0, 0), "lime": self.center + (0, k, 0), "blue": self.center + (0, 0, k),
               "black": self.center + (-k * 0.6, -k * 0.5, -k * 0.7)}
        r = self.half * 0.012
        body = "".join(cube(p[0] - r, p[1] - r, p[2] - r, p[0] + r, p[1] + r, p[2] + r, n) for n, p in pts.items())
        png = render(scene_scad(body), self, raw=True)
        a = np.asarray(Image.open(png).convert("RGB")).astype(int)
        R, Gc, B = a[..., 0], a[..., 1], a[..., 2]
        masks = {"red": (R > 60) & (Gc < R * 0.35) & (B < R * 0.35), "lime": (Gc > 60) & (R < Gc * 0.35) & (B < Gc * 0.35),
                 "blue": (B > 60) & (R < B * 0.35) & (Gc < B * 0.35), "black": (R < 45) & (Gc < 45) & (B < 45)}
        X, Y = [], []
        for n, msk in masks.items():
            ys, xs = np.nonzero(msk)
            assert len(xs) > 4, f"calibration marker {n} not found ({self.key()})"
            X.append([*pts[n], 1])
            Y.append([xs.mean() + 0.5, ys.mean() + 0.5])
        self.A = np.linalg.solve(np.array(X), np.array(Y))   # 4x2
        return self

    def px(self, p):
        if self.A is None:
            self.calibrate()
        return np.array([*p, 1]) @ self.A


def render(scad, cam, raw=False, name=None):
    name = name or f"r{abs(hash((scad, cam.key()))) % 10 ** 12}"
    f = WORK / f"{name}.scad"
    png = WORK / f"{name}{'_raw' if raw else ''}.png"
    f.write_text(scad)
    if not png.exists() or png.stat().st_mtime < f.stat().st_mtime:
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen")
        subprocess.run([OPENSCAD, "-q", "--backend=manifold", "--render", "--colorscheme=Tomorrow", *cam.args(), "-o", str(png), str(f)],
                       check=True, env=env)
    if raw:
        return png
    return outline(png)


def outline(png):
    """Transparent background plus dark outlines wherever the colour changes: line-art look."""
    out = png.with_name(png.stem + "_line.png")
    if out.exists() and out.stat().st_mtime >= png.stat().st_mtime:
        return out
    a = np.asarray(Image.open(png).convert("RGB")).astype(int)
    bg = (np.abs(a - a[0, 0]).max(-1) < 3)
    e = np.zeros(bg.shape, bool)
    for dy, dx in ((0, 1), (1, 0), (1, 1), (1, -1)):
        b = np.roll(a, (dy, dx), (0, 1))
        bb = np.roll(bg, (dy, dx), (0, 1))
        diff = np.abs(a - b).max(-1)
        e |= ((diff > 14) & ~(bg & bb)) | (bg != bb)
    e[0, :] = e[-1, :] = e[:, 0] = e[:, -1] = False
    rgba = np.dstack([a, np.where(bg, 0, 255)]).astype(np.uint8)
    rgba[e] = (40, 40, 40, 255)
    Image.fromarray(rgba, "RGBA").save(out)
    return out


def check_orientation():
    """Engraved labels must land where their words say."""
    P = card_parts()
    where = {}
    for n, pcs in P.items():
        for pc in pcs:
            for x, y, s, *_ in pc.txt:
                where.setdefault((n, s), []).append(pc.world(x, y, T))
    ok = lambda c, msg: None if c else sys.exit("orientation check failed: " + msg)
    for n in ("A", "B", "F"):
        ok(where[(n, "CAM")][0][0] < 10 and where[(n, "USB")][0][0] > W - 10, f"{n} CAM/USB ends")
    for n in ("A", "B", "SC", "SU"):
        ok(where[(n, "FRONT")][0][2] < 20, f"{n} FRONT not at the front: {where[(n, 'FRONT')]}")
    for n in ("SC", "SU", "F"):
        ok(where[(n, "TOP")][0][1] > H * 0.6, f"{n} TOP not up")
    ok(where[("R", "TOP")][0][1] > H, "R TOP not up")
    ok(where[("C", "FRONT")][0][2] < ZC + T and where[("C", "REAR")][0][2] > ZC + GAP, "C FRONT/REAR")
    # printed (outer, w = T) face normal points away from the body centre
    ctr = np.array([XC, YC, DEPTH / 2])
    for n in ("A", "B", "SC", "SU", "R"):
        pc = P[n][0]
        c = pc.shape.representative_point()
        p_in, p_out = pc.world(c.x, c.y, 0), pc.world(c.x, c.y, T)
        ok(np.linalg.norm(p_out - ctr) > np.linalg.norm(p_in - ctr), f"{n} printed side faces in")
    return where


if __name__ == "__main__":
    w = check_orientation()
    print("orientation ok;", {k: np.round(v[0], 1).tolist() for k, v in w.items() if k[1] in ("CAM", "USB", "FRONT", "TOP")})
    print(f"carrier front z {ZC:.2f}, lens stack {ZL:.2f}-{ZL + STACK:.2f}, d {D_NOW:.2f}")
