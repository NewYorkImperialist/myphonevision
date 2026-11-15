"""Laser files from gen.py: cut and score lines only (no labels, no guides).

    python3 laser.py [--v2]      # writes laser/ (or v2/laser/): one .svg, .dxf and .pdf per page
                                 # --v2 also writes headset-v2-recut-sheet.svg/.pdf: every part v2 changes, on one sheet

Every line is a 0.01 mm hairline (the makerspace's "cut" convention); the color says what to do with it:
red = cut through, blue = score (fold lines; run at low power). Score lines are dashed (6 mm on, 1.5 mm off), so
even if they get cut at full power the part stays attached and folds along a perforation.
"""
import math, os, subprocess, sys, runpy
from shapely import affinity

here = os.path.dirname(os.path.abspath(__file__))
v2 = "--v2" in sys.argv[1:]
out = os.path.join(here, "v2" if v2 else "", "laser")
sys.argv = ["gen.py"] + (["--v2"] if v2 else [])
g = runpy.run_path(os.path.join(here, "gen.py"))
HAIR, RED, BLUE = 0.01, "#ff0000", "#0000ff"
DASH, GAP = 6.0, 1.5


def dashes(pts):
    """Split a polyline into DASH-long pieces with GAP between them."""
    segs, cur, left, on = [], [pts[0]], DASH, True
    for a, b in zip(pts, pts[1:]):
        L = math.dist(a, b)
        t = 0.0
        while L - t > left:
            t += left
            p = (a[0] + (b[0] - a[0]) * t / L, a[1] + (b[1] - a[1]) * t / L)
            if on:
                segs.append(cur + [p])
            cur, on = [p], not on
            left = GAP if not on else DASH
        left -= L - t
        cur.append(b)
    if on and len(cur) > 1:
        segs.append(cur)
    return segs


def write(name, w, h, cuts, scores):
    """cuts: closed rings; scores: open polylines; points in mm, y down."""
    svg = ['<?xml version="1.0" encoding="UTF-8"?>',
           f'<svg xmlns="http://www.w3.org/2000/svg" version="1.1" width="{w}mm" height="{h}mm" viewBox="0 0 {w} {h}">']
    dxf = ["0", "SECTION", "2", "HEADER", "9", "$INSUNITS", "70", "4", "0", "ENDSEC",
           "0", "SECTION", "2", "TABLES", "0", "TABLE", "2", "LAYER", "70", "2"]
    for layer, col in (("CUT", 1), ("SCORE", 5)):
        dxf += ["0", "LAYER", "2", layer, "70", "0", "62", str(col), "6", "CONTINUOUS"]
    dxf += ["0", "ENDTAB", "0", "ENDSEC", "0", "SECTION", "2", "ENTITIES"]
    for pts, closed, color, layer in [(c, True, RED, "CUT") for c in cuts] + [(s, False, BLUE, "SCORE") for s in scores]:
        d = "M" + " L".join(f"{x:.3f},{y:.3f}" for x, y in pts) + (" Z" if closed else "")
        svg.append(f'<path fill="none" stroke="{color}" stroke-width="{HAIR}" d="{d}"/>')
        if closed and pts[0] == pts[-1]:
            pts = pts[:-1]
        dxf += ["0", "POLYLINE", "8", layer, "66", "1", "70", "1" if closed else "0"]
        for x, y in pts:   # DXF is y up
            dxf += ["0", "VERTEX", "8", layer, "10", f"{x:.3f}", "20", f"{h - y:.3f}", "30", "0"]
        dxf += ["0", "SEQEND", "8", layer]
    svg.append("</svg>")
    dxf += ["0", "ENDSEC", "0", "EOF"]
    f = os.path.join(out, name)
    open(f + ".svg", "w").write("\n".join(svg))
    open(f + ".dxf", "w").write("\n".join(dxf) + "\n")
    subprocess.run(["rsvg-convert", "-f", "pdf", "-o", f + ".pdf", f + ".svg"], check=True)
    return len(cuts), len(scores)


os.makedirs(out, exist_ok=True)
PW, PH = g["PW"], g["PH"]
flip = lambda pts: [(x, PH - y) for x, y in pts]
for n, pg in enumerate(g["pages"], 1):
    cuts = [flip(geom.coords) for kind, geom, _ in pg["paths"] if kind == "cut"]
    scores = [s for kind, geom, _ in pg["paths"] if kind in ("mountain", "valley") for s in dashes(flip(geom.coords))]
    print(f"page {n}: {write(f'headset-page{n}', PW, PH, cuts, scores)} (cuts, score dashes)")

if v2:
    # Everything v2 changes, on one sheet: R1, R2 / A, B + FH, SC + SU. No spacers (P, PL, K), nothing unchanged.
    parts = {"R1": g["face_ring"](0), "R2": g["face_ring"](1), "A": g["top_wall"](), "B": g["bottom_wall"](),
             "FH": g["hook_doublers"](), "SC": g["side_wall"](False), "SU": g["side_wall"](True)}
    size = {k: (p.shape.bounds[2] - p.shape.bounds[0], p.shape.bounds[3] - p.shape.bounds[1]) for k, p in parts.items()}
    M = 5.0
    row2 = M + max(size["R1"][1], size["R2"][1]) + M
    xb, xs = M + size["A"][0] + M, 2 * M + size["A"][0] + size["B"][0] + M
    pos = {"R1": (M, M), "R2": (2 * M + size["R1"][0], M), "A": (M, row2), "B": (xb, row2),
           "FH": (xb, row2 + size["B"][1] + M), "SC": (xs, row2), "SU": (xs, row2 + size["SC"][1] + M)}
    placed = {}
    for k, p in parts.items():   # y down on the sheet, as on the pages (printed side up)
        x0, _, _, y1 = p.shape.bounds
        f = lambda geom, x0=x0, y1=y1, k=k: affinity.translate(affinity.scale(geom, 1, -1, origin=(0, 0)), pos[k][0] - x0, pos[k][1] + y1)
        placed[k] = (f(p.shape), [f(l) for kind, l in p.lines if kind in ("mountain", "valley")])
    shapes = [s for s, _ in placed.values()]
    assert all(a.distance(b) >= M - 0.01 for i, a in enumerate(shapes) for b in shapes[i + 1:]), "parts too close on the sheet"
    w = math.ceil(max(s.bounds[2] for s in shapes) + M)
    h = math.ceil(max(s.bounds[3] for s in shapes) + M)
    cuts = [list(r.coords) for s in shapes for poly in getattr(s, "geoms", [s]) for r in [poly.exterior, *poly.interiors]]
    scores = [d for _, ls in placed.values() for l in ls for d in dashes(list(l.coords))]
    print(f"sheet {w} x {h} mm: {write('headset-v2-recut-sheet', w, h, cuts, scores)} (cuts, score dashes)")
