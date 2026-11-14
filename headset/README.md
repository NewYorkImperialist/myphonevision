# Headset

A printed shell around harvested lenses, with the Pixel's rear camera bar left uncovered for ARCore. Everything is in [headset.scad](headset.scad), driven by the parameters at the top.

## 1. Get lenses (hour 1)

In order of preference:

1. **A cheap phone VR viewer** from Walmart, Target or Five Below (Hadley or the Holyoke Mall). One purchase gets lenses, a strap and face foam. Check in-store stock first; many listings are online-only. Buy two if under $20.
2. **Two identical "5x" magnifiers** from CVS, Walgreens, Staples or a dollar store. "5x" usually means about 62 mm focal length. Many are a 2x lens with a small 5x inset; check the whole lens. A single 2x or 3x lens is too weak, but two 3x lenses stacked per eye (four identical magnifiers) act like about 5–6x.
3. Ask in the HackUMass Discord and the organizers for an old Cardboard; try Goodwill.
4. UMass physics teaching labs (a long shot on a weekend).

## 2. Measure

**Stacked lenses** (for example two 3x magnifiers per eye): measure the stack as one lens. Hold the lenses together for the focal-length test, and measure the whole stack's thickness. The lens plate thickens automatically to fit, and the `lens_ring` part locks the stack in.

- **Focal length:** focus a bright window across the room onto paper. The lens-to-paper distance is `lens_f`.
- **Diameter and rim thickness:** calipers, giving `lens_d` and `lens_thk`.

Expect about 66° vertical FOV at 50 mm and 56° at 62 mm.

## 3. Print the focus jig first (20 min)

```sh
openscad -D 'part="jig"' -D lens_d=25 -D lens_thk=6 -D lens_f=45 -o jig.stl headset.scad
openscad -D 'part="jig_ring"' -D lens_d=25 -o jig_ring.stl headset.scad
```

Stand the jig on the phone showing a grid, look through the lens, and add 1 mm rings until the grid is sharp. If it took two or more rings, raise `focus_back_off` by that much. If it's sharp with none, lower it. A 3 mm error pushes focus past infinity, which is why the shell takes shims.

## 4. Print the shell (overnight)

PLA, 0.2–0.28 mm layers. Set the measured values on the command line, or edit the top of the file:

```sh
tools/export-stl.sh -D lens_d=25 -D lens_thk=6 -D lens_f=45    # from the repo root
```

OpenSCAD: `brew install --cask openscad@snapshot` on macOS (the plain `openscad` cask is disabled), or a snapshot from openscad.org.

| Part | Print | Notes |
| --- | --- | --- |
| `front` | lens plate down | Lens plate, spacer body, septum, nose cutout, strap ears |
| `tray` | back down | Holds the phone; the camera bar pokes through the back slot |
| `door` | flat | Drops in across the USB end; USB-C passes through it |
| `shim` | flat, print 4 | `shim_count` (2) sit between body and tray at nominal focus; add or remove to refocus |
| `spacer` | flat | Two rails and a crossbar that slide in behind the phone once it is in, filling the room left for the camera bar |
| `lens_ring` | flat, print 2 | Press-fits behind each lens (or stack) to hold it in; a dab of glue if loose |

Assembly: drop the lenses into the seats from the tray side and press a `lens_ring` in behind each. Bolt (M3) or zip-tie the four corner flanges: body, then shims, then tray. Slide the phone in from the USB end, screen toward the lenses, camera end first: the pocket is deep enough for the camera bar (`cam_bar_h`, measure it). Then slide the `spacer` in behind the phone so it can't rattle. Drop the door in and push a 1.75 mm filament offcut through the ear and the door tab as the latch pin. Thread a headband through the two side ears. A second band from the top ear over your head takes weight off your face. If your band is wider than 32 mm, fold it or set `strap_slot`.

`openscad headset.scad` with `part = "assembly"` shows everything in place. The console echoes the lens-to-screen distance and spacer length; phone fork change 3 needs those numbers.

## Unchecked

- Every part renders and exports cleanly (OpenSCAD 2026.10), including with 50 mm stacked lenses, where the nose notch shrinks automatically to keep the lens seats intact. Nothing has been printed yet.
- Pixel 7 camera bar position (`cam_from_top`, `cam_bar_len`) and body size are from the spec sheet. Check them with calipers.
- IPD is fixed at 63 mm (lens centers at ±31.5 mm). An adjustable slider is a stretch goal.

## Thermals

Vent slots run across the back. Cap brightness, stream at 60–72 Hz, and keep sessions to about 5 minutes.
