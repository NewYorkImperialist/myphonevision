# Controller enclosure mockups

Concept **D** (`d_ergo.scad`) is the one TSVRN9 picked. A, B and C are earlier concepts, kept for reference. All of them use Nafis's measured values from `cases/controller.scad` and the as-built parts (A button only, FSR grip, 4×AA holder, jumper plugs ~30 mm).

Needs OpenSCAD 2026 (Manifold backend). Fedora's 2021.01 can't render these. `./render.sh d` re-renders the images in `img/`.

## D: ergonomic pistol grip
Two halves split down the middle, a battery cradle that closes the finger loop, a slide-on cell cover, and an IMU clamp. Every internal part is held: the ESP32 slides under a wedge and clicks into two hooks, the IMU sits in a clamp with one M3, the joystick screws to ribs, the holder snaps under two lips, and a divider wall keeps the boards' soldered backs apart. The header comment in `d_ergo.scad` has the details and the part list.

**Print the fit test first:** `part="fit_test"` (about 45 min, 10.7 cm³). It covers the ESP32 seat, a cradle section, the cover end and the IMU clamp, all cut from the real geometry. Uploaded 2026-11-14 as pickup code **9AF7**. Use the same slicer settings as the real parts.

**Fit test printed 2026-11-14: everything fit** except the IMU mount, where a wire leaves the board's VCC corner. Both IMU corners now have a wire relief (`img/d_ergo-imu_relief.png`); nothing else changed.

Print plates for a Prusa Core One (250 × 220), each part in print orientation, no supports. Center them in the slicer.

| Plate | Parts | Bed footprint | Volume | Rough time |
| --- | --- | --- | --- | --- |
| `plate_a` | `half_l` + `imu_clamp` + `cover` | 205.9 × 133.2 | 65.3 cm³ | 3.3–6.5 h |
| `plate_b` | `half_r` + `cradle` | 208.5 × 133.2 | 82.9 cm³ | 4.1–8.3 h |

OrcaSlicer settings that passed the fit test: 0.28 mm layers, 2 walls, 4/3 top/bottom, 12% grid, supports off, elephant foot 0.15.

All parts print without supports in the orientation `part="print"` shows. Times are volume estimates, not slicer figures.

**Still guessed:** the ESP32 header-row pitch (25.4) and how far its solder joints sit in from the long edges (the ledges are 0.6 mm), the GY-521 outline, the FSR tail length, and the joystick header position. The fit test checks the riskiest of these.
