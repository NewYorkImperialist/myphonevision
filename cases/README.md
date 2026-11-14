# Cases

Parametric OpenSCAD cases for the body trackers and the controllers. Every size is a setting at the top of each file. **Measure the real parts before printing** and pass the numbers with `-D`, or edit the file.

Install OpenSCAD with `brew install --cask openscad@snapshot` (the plain `openscad` cask is disabled on macOS), or download a snapshot from openscad.org. Export everything at once with `tools/export-stl.sh`; the files land in `build/stl/`.

## Fit tests first: [fit_tests.scad](fit_tests.scad)

Small prints (about 5–25 minutes each) that check each uncertain size before a long print. Each piece has its sizes printed on it.

| Test | Check | Then set |
| --- | --- | --- |
| `buttons` | Which labeled hole (5–16 mm) your push buttons fit through | `button_d` in controller.scad |
| `lens_seats` | Which seat (lens_d + 0.1 / 0.3 / 0.5 / 0.7 mm) holds the lens snugly without forcing | Add that clearance minus 0.3 to `lens_d` in headset.scad (the headset seat already adds 0.3) |
| `lens_rings` | Which retaining ring (1–3 notches, loose to tight) press-fits into that seat | Default matches ring 2; tell me if 1 or 3 fits better |
| `phone` | The Pixel slides through this 10 mm slice of the tray, camera end first, with a little play, screen against the lip | `clear` and `cam_bar_h` in headset.scad |
| `frames` | The 4×AA holder, DevKitC and GY-521 each drop into their outline | `battery`, `devkit`, `imu` in trackers.scad and controller.scad |
| `joystick` | The Adafruit 512 board screws onto the posts (M3, 30 mm placeholder spacing) and the stick moves freely in the hole | `joy_post`, `joy_hole` in controller.scad |
| `straps` | Which slot (25 / 32 / 40 / 52 mm) your headband and bandage thread through | `strap_slot` (headset) and `strap_w` (trackers) |

Print `lens_seats` with your measured `-D lens_d=... -D lens_thk=...`, same as the headset.

## Body trackers: [trackers.scad](trackers.scad)

| Part | Holds | Closed size | Print |
| --- | --- | --- | --- |
| `leg_case` + `leg_lid` | DevKitC, primary MPU-6050, 4×AA holder (thighs, ×2) | 68 × 64 × 45 mm | open side up |
| `waist_case` + `waist_lid` | DevKitC, primary MPU-6050; USB bank powers it (×1) | 61 × 55 × 29 mm | open side up |
| `pod_case` + `pod_lid` | Extension MPU-6050 on its cable (chest, ankles; ×3) | 26 × 22 × 13 mm | open side up |

- **Straps:** each case has ears on both ends. Thread a strap up to 52 mm wide through them (a 4" ACE bandage folded in half), or wrap the bandage over the closed case. The pods are too small for wide straps; wrap the bandage over them.
- **The IMU must not move inside the case.** Foam-tape the GY-521 flat to the floor or lid. A loose sensor makes the in-game limb wobble.
- **Lids press-fit.** Add tape or a zip tie if one works loose.
- **Measure first:** `battery` (the lab's 4×AA holder), `devkit_h` (board height with wires plugged in) and `imu_h`.

## Controllers: [controller.scad](controller.scad)

| Part | Does | Print |
| --- | --- | --- |
| `head` | Top shell: joystick, A, B, system buttons; holds the battery and IMU | top face down |
| `head_base` | Closes the head; rails lift the battery so wires pass under it; socket for the handle | flat |
| `handle` | Grip (35 × 28 mm, 71 mm long) holding the DevKitC; FSR trigger pocket and grip button on the front; USB slot in the bottom | bottom down |

Print two sets. The same shell works for both hands. The head is 70 × 66 × 43 mm.

- **Layout:** the joystick board (Adafruit 512, 38 mm square) fills the left of the head; B, A and system stand in a column to its right. The file stops with an error if the buttons (`button_body`) won't fit.
- **Assembly:** joystick board screws to the four posts under the head top. Buttons go through the top holes from inside. The FSR pad sits in the pocket on the handle front, its tail fed in through the slot. The IMU is foam-taped flat to the head's underside, and the battery rests on the rails. Glue or zip-tie the handle into the socket once the wiring works.
- **Measure first:** `battery`, `joy_board` and `joy_post` (joystick mounting-hole spacing), `button_d` (the lab's buttons), `fsr_d`, and `devkit_h`.
- After printing, set the bridge's `--mount` to match how the GY-521 sits in the head (see `firmware/controller/README.md`).

## Checked so far

All parts render and export as clean solids with OpenSCAD 2026.10. None has been printed, and the default part sizes are from datasheets, not from the lab's actual parts.
