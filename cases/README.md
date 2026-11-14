# Cases

Parametric OpenSCAD cases for the body trackers and the controllers. Every size is a setting at the top of each file. **Measure the real parts before printing** and pass the numbers with `-D`, or edit the file.

Install OpenSCAD with `brew install --cask openscad@snapshot` (the plain `openscad` cask is disabled on macOS), or download a snapshot from openscad.org. Export everything at once with `tools/export-stl.sh`; the files land in `build/stl/`.

## Fit tests first: [fit_tests.scad](fit_tests.scad)

Small prints (about 5–25 minutes each) that check each uncertain size before a long print. Each piece has its sizes printed on it.

| Test | Check | Then set |
| --- | --- | --- |
| `buttons` | Which labeled hole (14.9–15.7 mm) your push buttons fit through | `button_d` in controller.scad |
| `lens_seats` | Which seat (lens_d + 0.1 / 0.3 / 0.5 / 0.7 mm) holds the lens snugly without forcing | Add that clearance minus 0.3 to `lens_d` in headset.scad (the headset seat already adds 0.3) |
| `lens_rings` | Which retaining ring (1–3 notches, loose to tight) press-fits into that seat | Default matches ring 2; tell me if 1 or 3 fits better |
| `phone` | The Pixel slides through this 10 mm slice of the tray, camera end first, with a little play, screen against the lip | `clear` and `cam_bar_h` in headset.scad |
| `frames` | The 4×AA holder, DevKitC and GY-521 each drop into their outline | `battery`, `devkit`, `imu` in trackers.scad and controller.scad |
| `joystick` | The Adafruit 512 board screws onto the posts (M3, 30.5 mm spacing, measured) and the stick moves freely in the hole | `joy_post`, `joy_hole` in controller.scad |
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
| `handle_fit` | Test, print first and alone (about 20 min): a 10 mm slice of the handle and of the socket. The ESP32 with its plugs on should push into the slice, and the slice into the ring, by hand | flat |
| `head` | Top shell: joystick, A button and IMU under the top face; covers the battery | top face down |
| `head_base` | Closes the head. Two rails lift the battery so wires pass under it; stops at the rail ends keep it from sliding; a zip-tie slot under each rail; a screw bore in each rail end | flat side down, rails up |
| `socket` | Collar the handle plugs into, with a flange that is glued to the underside of `head_base` | flange down |
| `handle` | Grip (35 × 41 mm, 68 mm long) holding the DevKitC with its jumper plugs on; FSR trigger pocket on the front; USB slot in the bottom | bottom down |

Print two sets. The same shell works for both hands. The head is 74.5 × 73.1 × 49.7 mm with its base on. No part needs supports.

You also need, per controller: 8 M3 × 10 screws (4 for the joystick board, 4 for the head), one zip tie up to 4.8 mm wide, glue for the socket, and foam tape for the IMU.

- **Layout:** the joystick board (Adafruit 512, 38 mm square) sits against the back (wrist side) of the head, on the left. The IMU sits beside it in the back right corner, and the A button is in front of the IMU. The battery sits forward of a strip along the back wall. That strip stays empty from the boards down to `head_base`: the joystick's and the IMU's header pins point into it, and the jumper plugs need about 30 mm (`joy_plugs`, `imu_plugs`). The file stops with an error if the battery, a rail or the base ends up in that space, or if the button or the IMU won't fit.
- **Assembly:**
  1. Glue the `socket`'s flange to the underside of `head_base`, inside the outline scribed there.
  2. Screw the joystick board to the four posts under the head top, pin header toward the back. Push the A button through its hole from the outside and tighten its nut inside. Foam-tape the IMU flat to the inside of the top, in the back right corner behind the ridge, header edge toward the back.
  3. Put the FSR pad in the pocket on the handle front and feed its tail in through the slot.
  4. Set the battery on the rails between the stops. Run a zip tie through the slot under each rail and over the battery, and pull it tight.
  5. Run the wires down the back strip and under the battery, through the opening, into the handle.
  6. Close the head over `head_base` and drive the four screws through the front and back walls into the rail ends.
  7. Push the handle into the socket. Glue it once the wiring works.
- **Measured:** `battery`, `devkit`, `joy_board`, `joy_post` (30.5 mm, M3 holes), the button and the FSR. `devkit_h` (35 mm with plugs on) and the 30 mm plug length are confirmed. **Not measured:** `imu` (sized for the Adafruit BNO055, 27 × 20 mm; the GY-521 is smaller), `joy_hdr` (where the joystick's header sits on its board) and `usb_slot`.
- After printing, set the bridge's `--mount` to match how the IMU sits in the head (see `firmware/controller/README.md`).
- `-D part='"section"'` shows the assembly cut open with the battery, the boards and the plug spaces drawn in.

## Checked so far

All parts render and export as clean solids with OpenSCAD 2026.10. The `buttons` and `joystick` fit tests have been printed and their results are in controller.scad. The controller's `head`, `head_base` and `socket` have not been printed since the layout changed for the jumper plugs. Sizes not listed as measured above are from datasheets.
