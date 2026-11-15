"""Laser files from gen.py's pages: red = cut through, blue = score (folds), black = mark (labels, guides).

    python3 laser.py [--v2]      # writes laser/ (or v2/laser/): one .svg, .dxf and .pdf per page
"""
import os, subprocess, sys, runpy
here = os.path.dirname(os.path.abspath(__file__))
v2 = "--v2" in sys.argv[1:]
out = os.path.join(here, "v2" if v2 else "", "laser")
sys.argv = ["gen.py"] + (["--v2"] if v2 else [])
g = runpy.run_path(os.path.join(here, "gen.py"))
pages, PW, PH = g["pages"], g["PW"], g["PH"]
COLOR = {"cut": "#ff0000", "mountain": "#0000ff", "valley": "#0000ff", "guide": "#000000"}
LAYER = {"cut": ("CUT", 1), "mountain": ("SCORE", 5), "valley": ("SCORE", 5), "guide": ("MARK", 7)}
os.makedirs(out, exist_ok=True)
counts = {}
for n, pg in enumerate(pages, 1):
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{PW}mm" height="{PH}mm" viewBox="0 0 {PW} {PH}">']
    dxf = ["0", "SECTION", "2", "HEADER", "9", "$INSUNITS", "70", "4", "0", "ENDSEC",
           "0", "SECTION", "2", "TABLES", "0", "TABLE", "2", "LAYER", "70", "3"]
    for name, col in (("CUT", 1), ("SCORE", 5), ("MARK", 7)):
        dxf += ["0", "LAYER", "2", name, "70", "0", "62", str(col), "6", "CONTINUOUS"]
    dxf += ["0", "ENDTAB", "0", "ENDSEC", "0", "SECTION", "2", "ENTITIES"]
    for kind, geom, _ in pg["paths"]:
        if kind not in COLOR: continue
        pts = list(geom.coords)
        closed = geom.is_ring
        d = "M" + " L".join(f"{x:.3f},{PH - y:.3f}" for x, y in pts) + (" Z" if closed else "")
        svg.append(f'<path fill="none" stroke="{COLOR[kind]}" stroke-width="0.1" d="{d}"/>')
        layer, _ = LAYER[kind]
        if closed and pts[0] == pts[-1]: pts = pts[:-1]
        dxf += ["0", "POLYLINE", "8", layer, "66", "1", "70", "1" if closed else "0"]
        for x, y in pts: dxf += ["0", "VERTEX", "8", layer, "10", f"{x:.3f}", "20", f"{y:.3f}", "30", "0"]
        dxf += ["0", "SEQEND", "8", layer]
        counts[kind] = counts.get(kind, 0) + 1
    for x, y, s, z in pg["texts"]:
        svg.append(f'<text x="{x:.2f}" y="{PH - y:.2f}" font-size="{z}" text-anchor="middle" fill="#000000" font-family="Arial, DejaVu Sans, sans-serif">{s}</text>')
        dxf += ["0", "TEXT", "8", "MARK", "10", f"{x:.3f}", "20", f"{y:.3f}", "30", "0", "40", f"{z * 0.7:.2f}",
                "1", s, "72", "1", "11", f"{x:.3f}", "21", f"{y:.3f}", "31", "0"]
    svg.append("</svg>")
    dxf += ["0", "ENDSEC", "0", "EOF"]
    open(f"{out}/headset-page{n}.svg", "w").write("\n".join(svg))
    open(f"{out}/headset-page{n}.dxf", "w").write("\n".join(dxf) + "\n")
print("paths written:", counts, "pages:", len(pages))
for n in range(1, len(pages) + 1):
    f = os.path.join(out, f"headset-page{n}")
    subprocess.run(["rsvg-convert", "-f", "pdf", "-o", f + ".pdf", f + ".svg"], check=True)
