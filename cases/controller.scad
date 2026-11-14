// Controller shell, parametric. Tested with OpenSCAD 2026.10 (snapshot).
//
//   head       top shell: joystick and the A button; print top-face down
//   head_base  plate under the head with the socket the handle plugs into
//   handle     grip holding the DevKitC; FSR trigger on the front
//   handle_fit TEST, print this first and alone (~20 min): a 10 mm slice of the
//              handle and a ring of the head_base socket. Push the ESP32 (plugs
//              on) into the slice, then the slice into the ring. Both should go
//              in by hand without forcing. Then print the real parts.
//   assembly   everything in place (don't print)
//
// As built (issue #2, docs/wiring.md step 2h): one button (A) per controller;
// the thumbstick hold does recenter and system in the bridge. The battery pack
// and the IMU live in the head (LEFT: GY-521, RIGHT: Adafruit BNO055). The IMU
// must not wobble: foam-tape it flat, chip up, and turn both hands' IMUs the
// same way (one --mount serves both). Joystick pin header toward the wrist (+y,
// the back; STICK_INVERT_Y 0 assumes it). The DevKitC sits in the handle,
// USB end down, reachable through the slot in the handle's bottom.
// Glue or zip-tie the handle into the socket once the wiring works.
// The same shell works for both hands.
// Print in PLA, 0.2 mm layers, no supports. Print one file at a time, handle_fit first.

part = "assembly";

// ---- Measure the real parts and adjust ----------------------------------------------
devkit = [51.5, 28.23];       // ESP32 board outline, measured (length x width)
devkit_h = 35;                // board + headers + wires, front-to-back depth needed: ~35 with the female
                              // jumper plugs on (estimate, issue #2); ~15-22 if they're cut off and soldered
battery = [61.68, 57.7, 15.0]; // 4xAA holder, measured
joy_board = [38.1, 38.1];     // Adafruit 512 breakout, measured 38.08 square, 1.6 thick
joy_hole = 25.8;              // opening the stick moves in: 28 less 8% after the fit test print. At least
                              // housing + 1 (the stick stays within the housing); the knob covers it
joy_housing = 19.96;          // measured: width of the stick's housing on the board
joy_knob_d = 26;              // measured: knob's outer diameter; it sits just above the top face
joy_post = [30.5, 30.5];      // mounting-hole spacing, center to center: measured 27.4 inner gap + 3.16 hole
joy_post_bore = 2.8;          // M3 screws thread into the printed posts
joy_depth = 15.9;             // head's outer top face down to the board's top surface: 13.5 mm posts + top_t,
                              // from two fit test prints. Measured from the board: housing top 12.26 (1.1 under
                              // the top's inside), knob rim 17.42 (1.5 above the top face, knob on, centered).
// Panel-mount push buttons (red cap, threaded body, nut inside): measured.
button_thread = 14.84;        // threaded body diameter
button_d = button_thread + 0.5; // hole for the threads (PLA holes print a little small)
button_body = 19.19;          // widest part: the ring under the cap, which sits on the outside
button_depth = 14.46;         // bottom of the ring to the solder tab tips
button_wires = 3;             // room for the wires soldered to the tabs
fsr_d = 18.5;                 // FSR pad diameter, measured
fsr_tail_w = 7.3;             // FSR ribbon tail width, measured
usb_slot = [12, 8];

// ---- Shell ------------------------------------------------------------------------------
wall = 2.2;
top_t = 2.4;
socket_depth = 12;
rail_h = 6;                   // battery sits on rails; wires run underneath to the handle
fit = 0.3;
r = 6;
$fn = 64;

handle_inner = [devkit[1] + 2, devkit_h + 2, devkit[0] + 14];
handle_outer = [handle_inner[0] + 2 * wall, handle_inner[1] + 2 * wall, handle_inner[2] + wall];
head_inner = [battery[0] + 4, battery[1] + 4, rail_h + battery[2] + joy_depth + 4];
head_outer = [head_inner[0] + 2 * wall, head_inner[1] + 2 * wall, head_inner[2] + top_t];

module rbox(size, rad) {
  hull() for (x = [rad, size[0] - rad], y = [rad, size[1] - rad])
    translate([x, y, 0]) cylinder(r = rad, h = size[2]);
}

// Head, modeled top face at z = 0 (print orientation), open toward +z.
// Thumb layout on the top face: the joystick board fills the left side, the A
// button sits to its right, level with the stick.
joy_c = [wall + 2 + joy_board[0] / 2, head_outer[1] / 2];
btn_x = joy_c[0] + joy_board[0] / 2 + 1 + button_body / 2;
btn_a = [btn_x, head_outer[1] / 2];

// Layout checks: the button clear of the joystick board, and everything inside
// the head's walls. (The ring is the widest part; the nut inside is no wider.)
assert(btn_x + button_body / 2 <= head_outer[0] - wall,
       "the A button doesn't fit beside the joystick board: widen the head or use a smaller button");
assert(button_depth + button_wires <= head_outer[2] - rail_h - battery[2],
       "buttons reach the battery: make the head deeper");
assert(joy_c[1] - joy_board[1] / 2 >= wall && joy_c[1] + joy_board[1] / 2 <= head_outer[1] - wall,
       "joystick board taller than the head");
assert(joy_post[0] < joy_board[0] && joy_post[1] < joy_board[1], "joystick posts outside its board");
assert(joy_hole >= joy_housing + 1, "joystick hole narrower than the stick's travel (housing width + 1)");
assert(joy_depth - top_t >= 12.26 + 0.5, "joystick housing (12.26 tall) hits the inside of the top: raise joy_depth");

module head() {
  difference() {
    rbox(head_outer, r);
    translate([wall, wall, top_t]) rbox([head_inner[0], head_inner[1], head_inner[2] + 1], r - wall);
    translate([joy_c[0], joy_c[1], -1]) cylinder(d = joy_hole, h = top_t + 2);
    translate([btn_a[0], btn_a[1], -1]) cylinder(d = button_d, h = top_t + 2);
  }
  // Joystick posts hang from the top face; M2.5 or self-tapping screws.
  for (dx = [-1, 1], dy = [-1, 1])
    translate([joy_c[0] + dx * joy_post[0] / 2, joy_c[1] + dy * joy_post[1] / 2, top_t - 0.01])
      difference() {
        cylinder(d = 5, h = joy_depth - top_t);
        cylinder(d = joy_post_bore, h = joy_depth);
      }
}

// Base plate closes the head; the handle socket sits under the head's middle.
module head_base() {
  difference() {
    union() {
      rbox([head_outer[0], head_outer[1], wall], r);
      // Lip that fits inside the head walls.
      translate([wall + fit, wall + fit, wall - 0.01])
        difference() {
          rbox([head_inner[0] - 2 * fit, head_inner[1] - 2 * fit, 3], r - wall);
          translate([1.6, 1.6, -1]) rbox([head_inner[0] - 2 * fit - 3.2, head_inner[1] - 2 * fit - 3.2, 5], 1);
        }
      // Rails the battery rests on, leaving a wiring channel down the middle.
      for (sx = [-1, 1])
        translate([head_outer[0] / 2 + sx * (battery[0] / 2 - 6) - 2, (head_outer[1] - battery[1]) / 2, wall - 0.01])
          cube([4, battery[1], rail_h]);
      // Socket collar on the outside (z < 0).
      translate([(head_outer[0] - handle_outer[0]) / 2 - wall, (head_outer[1] - handle_outer[1]) / 2 - wall, -socket_depth])
        rbox([handle_outer[0] + 2 * wall + 2 * fit, handle_outer[1] + 2 * wall + 2 * fit, socket_depth + 0.01], 3);
    }
    // Socket hole and the wiring opening above it.
    translate([(head_outer[0] - handle_outer[0]) / 2 - fit + 0, (head_outer[1] - handle_outer[1]) / 2 - fit, -socket_depth - 1])
      rbox([handle_outer[0] + 2 * fit, handle_outer[1] + 2 * fit, socket_depth + 1 - 1.5], 2);
    translate([(head_outer[0] - handle_inner[0]) / 2, (head_outer[1] - handle_inner[1]) / 2, -2])
      cube([handle_inner[0], handle_inner[1], wall + 4]);
  }
}

// Handle, bottom at z = 0, open top that plugs into the socket. Front = -y.
module handle() {
  difference() {
    rbox(handle_outer, 2);
    translate([wall, wall, wall]) cube([handle_inner[0], handle_inner[1], handle_inner[2] + 1]);
    // USB slot in the bottom for flashing.
    translate([(handle_outer[0] - usb_slot[0]) / 2, (handle_outer[1] - usb_slot[1]) / 2, -1])
      cube([usb_slot[0], usb_slot[1], wall + 2]);
    // FSR trigger: shallow round pocket on the front near the top, tail slot into the handle.
    tz = handle_outer[2] - socket_depth - fsr_d / 2 - 4;
    // Pocket cut from the outside, leaving a 0.8 mm floor so the pad sits flush
    // under the finger (the tail slot below also opens outward).
    translate([handle_outer[0] / 2, -1, tz]) rotate([-90, 0, 0]) cylinder(d = fsr_d + 0.6, h = 1 + wall - 0.8);
    translate([(handle_outer[0] - fsr_tail_w) / 2, -1, tz - fsr_d / 2 - 14]) cube([fsr_tail_w, wall + 2, 14]);
  }
}

// Fit test: same cross-sections as handle() and head_base()'s socket, 10 mm tall.
module handle_fit() {
  h = 10;
  difference() {
    rbox([handle_outer[0], handle_outer[1], h], 2);
    translate([wall, wall, -1]) cube([handle_inner[0], handle_inner[1], h + 2]);
  }
  translate([handle_outer[0] + 8, -wall - fit, 0]) difference() {
    rbox([handle_outer[0] + 2 * wall + 2 * fit, handle_outer[1] + 2 * wall + 2 * fit, h], 3);
    translate([wall, wall, -1]) rbox([handle_outer[0] + 2 * fit, handle_outer[1] + 2 * fit, h + 2], 2);
  }
}

module assembly() {
  hz = handle_outer[2];
  color("lightblue") handle();
  base_z = hz - socket_depth + 1.5;
  bx = -(head_outer[0] - handle_outer[0]) / 2;
  by = -(head_outer[1] - handle_outer[1]) / 2;
  color("orange") translate([bx, by, base_z + socket_depth]) head_base();
  color("tan") translate([bx, by, base_z + socket_depth + wall + head_outer[2]]) mirror([0, 0, 1]) head();
}

echo(str("handle ", handle_outer[0], " x ", handle_outer[1], " mm grip, ", handle_outer[2], " mm long"));
echo(str("head ", head_outer[0], " x ", head_outer[1], " x ", head_outer[2] + wall, " mm"));
echo(str("joystick board right edge ", joy_c[0] + joy_board[0] / 2, " mm; A button at x = ", btn_x,
         " (", btn_x - button_body / 2 - (joy_c[0] + joy_board[0] / 2), " mm gap to the board)"));

if (part == "assembly") assembly();
else if (part == "head") head();
else if (part == "head_base") head_base();
else if (part == "handle") handle();
else if (part == "handle_fit") handle_fit();
else assert(false, str("unknown part: ", part));
