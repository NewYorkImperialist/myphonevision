// Controller shell, parametric. Tested with OpenSCAD 2026.10 (snapshot).
//
//   head       top shell: joystick, A, B, system buttons; print top-face down
//   head_base  plate under the head with the socket the handle plugs into
//   handle     grip holding the DevKitC; FSR trigger and grip button on the front
//   assembly   everything in place (don't print)
//
// The battery pack and the GY-521 live in the head (the IMU must not wobble:
// foam-tape it flat to the head's underside). The DevKitC sits in the handle,
// USB end down, reachable through the slot in the handle's bottom.
// Glue or zip-tie the handle into the socket once the wiring works.
// The same shell works for both hands.
// Print in PLA, 0.2 mm layers, no supports.

part = "assembly";

// ---- Measure the real parts and adjust ----------------------------------------------
devkit = [55.0, 28.5];        // DevKitC board outline
devkit_h = 22;                // board + headers + wires, front-to-back depth needed
battery = [62.0, 58.0, 16.0]; // 4xAA holder
joy_board = [38.1, 38.1];     // Adafruit 512 thumb joystick breakout (1.5 in square)
joy_hole = 28;                // opening the stick moves in; measure the knob's travel
joy_post = [30.0, 30.0];      // mounting-hole spacing (x, y): ~30 mm per a retailer; measure
joy_post_bore = 2.8;          // M3 screws thread into the printed posts
joy_depth = 12;               // board underside to head top (sets post height)
button_d = 7.0;               // hole for each push button (cap or plunger)
button_body = 12.0;           // button body footprint under the top (12 mm tactile; 6 for small ones)
fsr_d = 19.0;                 // FSR pad diameter (FSR 402 is ~18 mm)
fsr_tail_w = 8;               // FSR ribbon tail width
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
// Thumb layout on the top face: the joystick board fills the left side, the
// buttons stand in a column to its right (B top, A middle, system bottom).
joy_c = [wall + 2 + joy_board[0] / 2, head_outer[1] / 2];
btn_x = joy_c[0] + joy_board[0] / 2 + 3 + button_body / 2;
btn_b = [btn_x, head_outer[1] * 0.75];
btn_a = [btn_x, head_outer[1] * 0.50];
btn_sys = [btn_x, head_outer[1] * 0.25];

// Layout checks: buttons clear of the joystick board and of each other, and
// everything inside the head's walls.
assert(btn_x + button_body / 2 <= head_outer[0] - wall,
       "buttons don't fit beside the joystick board: widen the head or use smaller buttons");
assert(head_outer[1] * 0.25 >= button_body + 1, "button bodies overlap: use smaller buttons");
assert(joy_c[1] - joy_board[1] / 2 >= wall && joy_c[1] + joy_board[1] / 2 <= head_outer[1] - wall,
       "joystick board taller than the head");
assert(joy_post[0] < joy_board[0] && joy_post[1] < joy_board[1], "joystick posts outside its board");

module head() {
  difference() {
    rbox(head_outer, r);
    translate([wall, wall, top_t]) rbox([head_inner[0], head_inner[1], head_inner[2] + 1], r - wall);
    translate([joy_c[0], joy_c[1], -1]) cylinder(d = joy_hole, h = top_t + 2);
    for (b = [btn_a, btn_b, btn_sys]) translate([b[0], b[1], -1]) cylinder(d = button_d, h = top_t + 2);
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
    // Grip button under the middle finger.
    translate([handle_outer[0] / 2, -1, tz - fsr_d / 2 - 22]) rotate([-90, 0, 0]) cylinder(d = button_d, h = wall + 2);
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
echo(str("joystick board right edge ", joy_c[0] + joy_board[0] / 2, " mm; button column at x = ", btn_x,
         " (", btn_x - button_body / 2 - (joy_c[0] + joy_board[0] / 2), " mm gap to the board)"));

if (part == "assembly") assembly();
else if (part == "head") head();
else if (part == "head_base") head_base();
else if (part == "handle") handle();
else assert(false, str("unknown part: ", part));
