# Controller enclosure mockups

Concept **D** (`d_ergo.scad`) is the one TSVRN9 picked. A, B and C are earlier concepts, kept for reference. All of them use Nafis's measured values from `cases/controller.scad` and the as-built parts (A button only, FSR grip, 4×AA holder, jumper plugs ~30 mm).

Needs OpenSCAD 2026 (Manifold backend). Fedora's 2021.01 can't render these. `./render.sh d` re-renders the images in `img/`.

## D: ergonomic pistol grip
Two halves split down the middle, a battery cradle that closes the finger loop, a slide-on cell cover, and an IMU clamp. Every internal part is held: the ESP32 slides under a wedge and clicks into two hooks, the IMU sits in a clamp with one M3, the joystick screws to ribs, the holder snaps under two lips, and a divider wall keeps the boards' soldered backs apart. The header comment in `d_ergo.scad` has the details and the part list.

**Print the fit test first:** `part="fit_test"` (about 45 min, 10.7 cm³). It covers the ESP32 seat, a cradle section, the cover end and the IMU clamp, all cut from the real geometry. Uploaded 2026-11-14 as pickup code **9AF7**. Use the same slicer settings as the real parts.

| Order | Part | Volume | Rough time |
| --- | --- | --- | --- |
| 1 | `fit_test` | 10.7 cm³ | ~45 min |
| 2 | `half_l` + `imu_clamp` | 57 cm³ | 2.8–5.7 h |
| 3 | `half_r` | 52.8 cm³ | 2.6–5.3 h |
| 4 | `cradle` | 30.1 cm³ | 1.5–3 h |
| 5 | `cover` | 8.5 cm³ | 25–50 min |

All parts print without supports in the orientation `part="print"` shows. Times are volume estimates, not slicer figures.

**Still guessed:** the ESP32 header-row pitch (25.4) and how far its solder joints sit in from the long edges (the ledges are 0.6 mm), the GY-521 outline, the FSR tail length, and the joystick header position. The fit test checks the riskiest of these.
