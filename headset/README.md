# Headset

A printed shell around harvested lenses, with the Pixel's rear camera bar left uncovered for ARCore. Everything is in [headset.scad](headset.scad), driven by the parameters at the top.

## 1. Get lenses (hour 1)

In order of preference:

1. **A cheap phone VR viewer** from Walmart, Target or Five Below (Hadley or the Holyoke Mall). One purchase gets lenses, a strap and face foam. Check in-store stock first; many listings are online-only. Buy two if under $20.
2. **Two identical "5x" magnifiers** from CVS, Walgreens, Staples or a dollar store. "5x" usually means about 62 mm focal length. Many are a 2x lens with a small 5x inset; check the whole lens. 2x and 3x are too weak.
3. Ask in the HackUMass Discord and the organizers for an old Cardboard; try Goodwill.
4. UMass physics teaching labs (a long shot on a weekend).

## 2. Measure

- **Focal length:** focus a bright window across the room onto paper. The lens-to-paper distance is `lens_f`.
- **Diameter and rim thickness:** calipers, giving `lens_d` and `lens_thk`.

Expect about 66° vertical FOV at 50 mm and 56° at 62 mm.

## 3. Print the focus jig first (20 min)

```sh
openscad -D 'part="jig"' -D lens_d=25 -D lens_f=45 -o jig.stl headset.scad
openscad -D 'part="jig_ring"' -D lens_d=25 -o jig_ring.stl headset.scad
```

Stand the jig on the phone showing a grid, look through the lens, and add 1 mm rings until the grid is sharp. If it took two or more rings, raise `focus_back_off` by that much. If it's sharp with none, lower it. A 3 mm error pushes focus past infinity, which is why the shell takes shims.

## 4. Print the shell (overnight)

PLA, 0.2–0.28 mm layers. Set the measured values on the command line, or edit the top of the file:

```sh
for p in front tray door shim; do
  openscad -D "part=\"$p\"" -D lens_d=25 -D lens_thk=6 -D lens_f=45 -o "$p.stl" headset.scad
done
```

| Part | Print | Notes |
| --- | --- | --- |
| `front` | lens plate down | Lens plate, spacer body, septum, nose cutout, strap ears |
| `tray` | back down | Holds the phone; the camera bar pokes through the back slot |
| `door` | flat | Drops in across the USB end; USB-C passes through it |
| `shim` | flat, print 4 | `shim_count` (2) sit between body and tray at nominal focus; add or remove to refocus |

Assembly: drop the lenses into the seats from the tray side. Bolt (M3) or zip-tie the four corner flanges: body, then shims, then tray. Slide the phone in from the USB end, screen toward the lenses, camera end first. Drop the door in and push a 1.75 mm filament offcut through the ear and the door tab as the latch pin. Reuse the donor viewer's strap and foam, or use elastic and velcro through the strap ears.

`openscad headset.scad` with `part = "assembly"` shows everything in place. The console echoes the lens-to-screen distance and spacer length; phone fork change 3 needs those numbers.

## Unchecked

- The CAD hasn't been rendered or printed yet. Render the assembly before the first long print.
- Pixel 7 camera bar position (`cam_from_top`, `cam_bar_len`) and body size are from the spec sheet. Check them with calipers.
- IPD is fixed at 63 mm (lens centers at ±31.5 mm). An adjustable slider is a stretch goal.

## Thermals

Vent slots run across the back. Cap brightness, stream at 60–72 Hz, and keep sessions to about 5 minutes.
