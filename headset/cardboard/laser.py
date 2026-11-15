"""Laser files from gen.py: cut and score lines only (no labels, no guides).

    python3 laser.py [--v2]      # writes laser/ (or v2/laser/): one .svg, .dxf and .pdf per page
                                 # --v2 also writes headset-v2-recut-sheet.svg/.pdf: every part v2 changes, on one sheet

Makerspace convention: 0.01 mm strokes are cut, anything wider is engraved. Red 0.01 mm = cut through;
blue 0.5 mm = fold lines, engraved at low power so they score the top liner.
"""
import math, os, subprocess, sys, runpy
from shapely import affinity

here = os.path.dirname(os.path.abspath(__file__))
v2 = "--v2" in sys.argv[1:]
out = os.path.join(here, "v2" if v2 else "", "laser")
sys.argv = ["gen.py"] + (["--v2"] if v2 else [])
g = runpy.run_path(os.path.join(here, "gen.py"))
HAIR, SCORE_W, RED, BLUE = 0.01, 0.5, "#ff0000", "#0000ff"


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
        svg.append(f'<path fill="none" stroke="{color}" stroke-width="{HAIR if closed else SCORE_W}" d="{d}"/>')
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
    scores = [flip(geom.coords) for kind, geom, _ in pg["paths"] if kind in ("mountain", "valley")]
    print(f"page {n}: {write(f'headset-page{n}', PW, PH, cuts, scores)} (cuts, scores)")

if v2:
    # Only the parts v2 changes (no spacers P, PL, K; nothing unchanged): one big sheet, and the same parts on
    # US Letter pages for drivers that clip anything past a default page size.
    parts = {"R1": g["face_ring"](0), "R2": g["face_ring"](1), "A": g["top_wall"](), "B": g["bottom_wall"](),
             "FH": g["hook_doublers"](), "SC": g["side_wall"](False), "SU": g["side_wall"](True)}

    def sheet(name, items, w=None, h=None, M=5.0):
        """items: (part, rotation, left, top) with y down; printed side stays up."""
        placed = []
        for k, rot, left, top in items:
            prt = parts[k]
            r = lambda geom: affinity.rotate(affinity.scale(geom, 1, -1, origin=(0, 0)), rot, origin=(0, 0))
            x0, y0, _, _ = r(prt.shape).bounds
            f = lambda geom: affinity.translate(r(geom), left - x0, top - y0)
            placed.append((f(prt.shape), [f(l) for kind, l in prt.lines if kind in ("mountain", "valley")]))
        shapes = [s for s, _ in placed]
        assert all(a.distance(b) >= 5 - 0.01 for i, a in enumerate(shapes) for b in shapes[i + 1:]), f"{name}: parts too close"
        w = w or math.ceil(max(s.bounds[2] for s in shapes) + M)
        h = h or math.ceil(max(s.bounds[3] for s in shapes) + M)
        assert all(s.bounds[0] >= M - 0.01 and s.bounds[1] >= M - 0.01 and s.bounds[2] <= w - M + 0.01 and s.bounds[3] <= h - M + 0.01
                   for s in shapes), f"{name}: part off the page"
        cuts = [list(r.coords) for s in shapes for poly in getattr(s, "geoms", [s]) for r in [poly.exterior, *poly.interiors]]
        scores = [list(l.coords) for _, ls in placed for l in ls]
        print(f"{name} {w} x {h} mm: {write(name, w, h, cuts, scores)} (cuts, scores)")

    size = {k: (p.shape.bounds[2] - p.shape.bounds[0], p.shape.bounds[3] - p.shape.bounds[1]) for k, p in parts.items()}
    M = 5.0
    row2 = M + max(size["R1"][1], size["R2"][1]) + M
    xb, xs = M + size["A"][0] + M, 2 * M + size["A"][0] + size["B"][0] + M
    sheet("headset-v2-recut-sheet", [("R1", 0, M, M), ("R2", 0, 2 * M + size["R1"][0], M), ("A", 0, M, row2), ("B", 0, xb, row2),
                                     ("FH", 0, xb, row2 + size["B"][1] + M), ("SC", 0, xs, row2), ("SU", 0, xs, row2 + size["SC"][1] + M)])
    L = 10.0   # Letter margin: some print paths can't reach the paper's edge
    sheet("headset-v2-recut-letter1-R1", [("R1", 90, L, L)], PW, PH, L)
    sheet("headset-v2-recut-letter2-R2", [("R2", 90, L, L)], PW, PH, L)
    sheet("headset-v2-recut-letter3-A-FH", [("A", 0, L, L), ("FH", 0, L, L + size["A"][1] + 5)], PW, PH, L)
    sheet("headset-v2-recut-letter4-B-SC-SU", [("B", 0, L, L), ("SC", 0, L, L + size["B"][1] + 5),
                                               ("SU", 0, L + size["SC"][0] + 5, L + size["B"][1] + 5)], PW, PH, L)
