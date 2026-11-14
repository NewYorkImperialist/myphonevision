#!/usr/bin/env python3
"""Make a Cardboard viewer QR code for our headset.

PhoneVR's "switch viewer" button scans Cardboard viewer QR codes. A code of the
form https://google.com/cardboard/cfg?p=<params> is decoded on the phone with no
network access, so scanning one of these replaces hard-coding the headset's
optics in the app (fork change 3).

    python3 tools/cardboard_qr.py --lens-f 62 --back-off 2.5
    python3 tools/cardboard_qr.py --lens-f 62 --k1-sweep 0.1 0.2 0.3 0.4   # tuning sheet
    python3 tools/cardboard_qr.py --decode 'https://google.com/cardboard/cfg?p=...'

Distances match headset/headset.scad: screen-to-lens = lens_f - focus_back_off.
Writes SVG files to build/qr/ (needs `pip install segno` for the images; the
URL alone needs nothing).
"""

from __future__ import annotations

import argparse
import base64
import math
import struct
from pathlib import Path

# DeviceParams field numbers (googlevr/cardboard proto/cardboard_device.proto).
F_VENDOR, F_MODEL, F_SCREEN_TO_LENS, F_INTER_LENS = 1, 2, 3, 4
F_FOV, F_TRAY_TO_LENS, F_DISTORTION = 5, 6, 7
F_VERTICAL_ALIGNMENT, F_PRIMARY_BUTTON = 11, 12
ALIGN = {"bottom": 0, "center": 1, "top": 2}
BUTTON = {"none": 0, "magnet": 1, "touch": 2, "indirect_touch": 3}


def _varint(n: int) -> bytes:
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        out.append(b | (0x80 if n else 0))
        if not n:
            return bytes(out)


def _key(field: int, wire: int) -> bytes:
    return _varint(field << 3 | wire)


def encode(params: dict) -> bytes:
    out = bytearray()
    for field, name in ((F_VENDOR, "vendor"), (F_MODEL, "model")):
        data = params[name].encode()
        out += _key(field, 2) + _varint(len(data)) + data
    for field, name in ((F_SCREEN_TO_LENS, "screen_to_lens"), (F_INTER_LENS, "inter_lens")):
        out += _key(field, 5) + struct.pack("<f", params[name])
    fov = struct.pack("<4f", *params["fov"])
    out += _key(F_FOV, 2) + _varint(len(fov)) + fov
    out += _key(F_TRAY_TO_LENS, 5) + struct.pack("<f", params["tray_to_lens"])
    dist = struct.pack(f"<{len(params['distortion'])}f", *params["distortion"])
    out += _key(F_DISTORTION, 2) + _varint(len(dist)) + dist
    out += _key(F_VERTICAL_ALIGNMENT, 0) + _varint(params["vertical_alignment"])
    out += _key(F_PRIMARY_BUTTON, 0) + _varint(params["primary_button"])
    return bytes(out)


def decode(blob: bytes) -> dict:
    """Minimal protobuf reader for DeviceParams, for checking codes."""
    names = {F_VENDOR: "vendor", F_MODEL: "model", F_SCREEN_TO_LENS: "screen_to_lens",
             F_INTER_LENS: "inter_lens", F_FOV: "fov", F_TRAY_TO_LENS: "tray_to_lens",
             F_DISTORTION: "distortion", F_VERTICAL_ALIGNMENT: "vertical_alignment",
             F_PRIMARY_BUTTON: "primary_button"}
    out: dict = {}
    i = 0

    def varint() -> int:
        nonlocal i
        shift = n = 0
        while True:
            b = blob[i]
            i += 1
            n |= (b & 0x7F) << shift
            shift += 7
            if not b & 0x80:
                return n

    while i < len(blob):
        key = varint()
        field, wire = key >> 3, key & 7
        name = names.get(field, f"field{field}")
        if wire == 0:
            out[name] = varint()
        elif wire == 5:
            out[name] = struct.unpack_from("<f", blob, i)[0]
            i += 4
        elif wire == 2:
            n = varint()
            chunk = blob[i:i + n]
            i += n
            out[name] = (chunk.decode() if field in (F_VENDOR, F_MODEL)
                         else list(struct.unpack(f"<{n // 4}f", chunk)))
        else:
            raise ValueError(f"unsupported wire type {wire} for field {field}")
    return out


def to_url(blob: bytes) -> str:
    p = base64.urlsafe_b64encode(blob).decode().rstrip("=")
    return f"https://google.com/cardboard/cfg?p={p}"


def from_url(url: str) -> bytes:
    p = url.split("p=", 1)[1].split("&", 1)[0]
    return base64.urlsafe_b64decode(p + "=" * (-len(p) % 4))


def build_params(args: argparse.Namespace, k1: float) -> dict:
    screen_to_lens_mm = args.lens_f - args.back_off
    # View half-angle per side: limited by the lens aperture seen from the eye.
    half = math.degrees(math.atan((args.lens_d / 2 - 1.2) / args.eye_relief))
    half = min(half, args.max_fov)
    return {
        "vendor": "myphonevision",
        "model": f"f{args.lens_f:g} d{args.lens_d:g} k1={k1:g}",
        "screen_to_lens": screen_to_lens_mm / 1000,
        "inter_lens": args.ipd / 1000,
        "fov": [half, half, half, half],
        # The printed tray centers the screen on the lenses vertically.
        "tray_to_lens": args.tray_to_lens / 1000,
        "vertical_alignment": ALIGN["center"],
        "distortion": [k1, args.k2],
        "primary_button": BUTTON["touch"],
    }


def write_svg(url: str, path: Path, label: str) -> bool:
    try:
        import segno
    except ImportError:
        return False
    qr = segno.make(url, error="m")
    path.parent.mkdir(parents=True, exist_ok=True)
    qr.save(str(path), scale=8, border=4, title=label)
    return True


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lens-f", type=float, default=45.0, help="lens (stack) focal length, mm")
    ap.add_argument("--lens-d", type=float, default=25.0, help="lens diameter, mm")
    ap.add_argument("--back-off", type=float, default=2.5, help="headset.scad focus_back_off, mm")
    ap.add_argument("--ipd", type=float, default=63.0, help="lens center spacing, mm")
    ap.add_argument("--eye-relief", type=float, default=15.0, help="eye to lens, mm (for FOV)")
    ap.add_argument("--max-fov", type=float, default=60.0, help="cap on each half-angle, degrees")
    ap.add_argument("--tray-to-lens", type=float, default=35.0, help="only used for bottom alignment")
    ap.add_argument("--k1", type=float, default=0.24, help="radial distortion k1 (Cardboard v2: 0.24)")
    ap.add_argument("--k2", type=float, default=0.30, help="radial distortion k2 (Cardboard v2: 0.30)")
    ap.add_argument("--k1-sweep", type=float, nargs="+", help="make one code per k1 value, for tuning")
    ap.add_argument("--out", default="build/qr", help="output folder for SVGs")
    ap.add_argument("--decode", metavar="URL", help="print the parameters inside a Cardboard URL")
    args = ap.parse_args()

    if args.decode:
        for k, v in decode(from_url(args.decode)).items():
            print(f"{k:20s} {v}")
        return

    images = True
    for k1 in args.k1_sweep or [args.k1]:
        params = build_params(args, k1)
        url = to_url(encode(params))
        assert decode(from_url(url))["model"] == params["model"]
        print(f"k1={k1:<5g} {url}")
        name = f"cardboard-k1-{k1:g}.svg"
        images = write_svg(url, Path(args.out) / name, params["model"]) and images
    print(f"\nscreen-to-lens {args.lens_f - args.back_off:g} mm, lens spacing {args.ipd:g} mm, "
          f"FOV half-angle {build_params(args, 0)['fov'][0]:.1f} deg")
    if images:
        print(f"QR images in {args.out}/. In PhoneVR, tap 'switch viewer' and scan one.")
    else:
        print("Install segno (pip install segno) for QR images, or paste a URL into any QR generator.")


if __name__ == "__main__":
    main()
