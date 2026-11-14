# Cases

Parametric OpenSCAD cases for the body trackers and the controllers. Every size is a setting at the top of each file. **Measure the real parts before printing** and pass the numbers with `-D`, or edit the file.

Install OpenSCAD with `brew install --cask openscad@snapshot` (the plain `openscad` cask is disabled on macOS), or download a snapshot from openscad.org. Export everything at once with `tools/export-stl.sh`; the files land in `build/stl/`.

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

- **Assembly:** joystick board screws to the four posts under the head top. Buttons go through the top holes from inside. The FSR pad sits in the pocket on the handle front, its tail fed in through the slot. The IMU is foam-taped flat to the head's underside, and the battery rests on the rails. Glue or zip-tie the handle into the socket once the wiring works.
- **Measure first:** `battery`, `joy_board` and `joy_post` (joystick mounting-hole spacing), `button_d` (the lab's buttons), `fsr_d`, and `devkit_h`.
- After printing, set the bridge's `--mount` to match how the GY-521 sits in the head (see `firmware/controller/README.md`).

## Checked so far

All parts render and export as clean solids with OpenSCAD 2026.10. None has been printed, and the default part sizes are from datasheets, not from the lab's actual parts.
