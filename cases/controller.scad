// Controller shell, parametric. Tested with OpenSCAD 2026.10 (snapshot).
//
//   head       top shell: joystick and the A button; print top-face down
//   head_base  plate that closes the head: battery rails and stops, zip-tie slots,
//              four screw bores; print flat side down, rails up
//   socket     collar the handle plugs into; print flange down, then glue the
//              flange to the underside of head_base, inside the scribed outline
//   handle     grip holding the DevKitC; FSR trigger on the front
//   handle_fit TEST, print this first and alone (~20 min): a 10 mm slice of the
//              handle and of the socket. Push the ESP32 (plugs
//              on) into the slice, then the slice into the ring. Both should go
//              in by hand without forcing. Then print the real parts.
//   assembly   everything in place (don't print)
//   section    assembly cut open through the joystick, with the battery, boards
//              and plug spaces drawn in (don't print)
//
// As built (issue #2, docs/wiring.md step 2h): one button (A) per controller;
// the thumbstick hold does recenter and system in the bridge. The battery pack
// and the IMU live in the head (LEFT: GY-521, RIGHT: Adafruit BNO055). The IMU
// must not wobble: foam-tape it flat inside the head's top, in the corner behind
// the A button (the ridge marks its front edge), header toward the wrist, and
// turn both hands' IMUs the same way (one --mount serves both). Joystick pin
// header toward the wrist (+y, the back; STICK_INVERT_Y 0 assumes it). Both
// headers hang over the strip behind the battery, which is kept clear for the
// jumper plugs all the way down to head_base. The DevKitC sits in the handle,
// USB end down, reachable through the slot in the handle's bottom.
// Battery: zip-tie it to the rails through the two slots. Head: four M3 x 10
// screws through the front and back walls into the rail ends.
// Glue the handle into the socket once the wiring works.
// The same shell works for both hands.
// Print in PLA, 0.2 mm layers, no supports. Print one file at a time, handle_fit first.

part = "assembly";

// ---- Measure the real parts and adjust ----------------------------------------------
devkit = [51.5, 28.23];       // ESP32 board outline, measured (length x width)
devkit_h = 35;                // board + headers + wires, front-to-back depth needed with the female jumper
                              // plugs on: confirmed by the user (a plug needs about 30 mm: pin + housing + bend)
battery = [61.68, 57.7, 15.0]; // 4xAA holder, measured
joy_board = [38.1, 38.1];     // Adafruit 512 breakout, measured (Nafis): 38.08 square
joy_board_t = 1.6;            // measured (Nafis)
joy_hole = 25.8;              // opening the stick moves in: 28 less 8% after the fit test print. At least
                              // housing + 1 (the stick stays within the housing); the knob covers it
joy_housing = 19.96;          // measured: width of the stick's housing on the board
joy_knob_d = 26;              // measured: knob's outer diameter; it sits just above the top face
joy_post = [30.5, 30.5];      // mounting-hole spacing, center to center, measured (Nafis): 27.4 inner gap
                              // + 3.16 hole diameter (M3 holes)
joy_post_bore = 2.8;          // M3 screws thread into the printed posts
joy_depth = 15.9;             // head's outer top face down to the board's top surface: 13.5 mm posts + top_t,
                              // from two fit test prints. Measured from the board: housing top 12.26 (1.1 under
                              // the top's inside), knob rim 17.42 (1.5 above the top face, knob on, centered).
joy_plugs = 30;               // straight down from the board's underside: header pins soldered into the board
                              // + female jumper plugs + the bend (user). Nothing else may be in this space
joy_hdr = [13, 6];            // that space's footprint: the 5-pin header along the board's back edge, and how
                              // far in from the edge it reaches (Adafruit 512 layout, not measured)
joy_clear = 4.8;              // board underside to the battery: solder joints and screw tips
imu = [27, 20.5];             // IMU spot, header edge x depth: the larger board (Adafruit BNO055, datasheet
                              // 27 x 20; the GY-521 is 21 x 16.5). Not measured
imu_plugs = 30;               // same plug space under the IMU's header edge, for the boards with header pins
// Panel-mount push buttons (red cap, threaded body, nut inside): measured.
button_thread = 14.84;        // threaded body diameter
button_d = button_thread + 0.5; // hole for the threads (PLA holes print a little small)
button_body = 19.19;          // widest part: the ring under the cap, which sits on the outside
button_depth = 14.46;         // bottom of the ring to the solder tab tips
button_wires = 3;             // room for the wires soldered to the tabs (soldered, not plugged: user)
fsr_d = 18.5;                 // FSR pad diameter, measured
fsr_tail_w = 7.3;             // FSR ribbon tail width, measured (wires soldered: user)
usb_slot = [12, 8];           // not measured; the user is fine with it as is

// ---- Shell ------------------------------------------------------------------------------
wall = 2.2;
top_t = 2.4;
socket_depth = 12;
flange = 6;                   // socket's glue flange: width around the collar
flange_t = 2;
wire_gap = 3;                 // battery to the head's front wall, and at least this at its sides: wire room
edge_gap = 2;                 // joystick board and IMU to the head's walls
stop_h = 3;                   // battery end stops, height above the rails
rail_w = 7;
tie = [5, 2.5];               // zip-tie slot through each rail (ties up to 4.8 mm wide)
screw_bore = 2.8;             // M3 x 10 screws thread into the rail ends
screw_clear = 3.4;
screw_depth = 10;
lip_t = 1.6;
fit = 0.3;
r = 6;
$fn = 64;

handle_inner = [devkit[1] + 2, devkit_h + 2, devkit[0] + 14];
handle_outer = [handle_inner[0] + 2 * wall, handle_inner[1] + 2 * wall, handle_inner[2] + wall];
socket_outer = [handle_outer[0] + 2 * wall + 2 * fit, handle_outer[1] + 2 * wall + 2 * fit];

// Head, modeled top face at z = 0 (print orientation), open toward +z; +y is
// the back (wrist). The joystick board and the IMU sit against the back wall
// with their headers over a strip the battery stays out of; the battery sits
// forward of that strip. The A button is in front of the IMU.
joy_under = joy_depth + joy_board_t;          // top face down to the board's underside
back_strip = edge_gap + joy_hdr[1];           // battery to the back wall
head_inner = [max(battery[0] + 2 * wire_gap, 2 * edge_gap + joy_board[0] + 1 + imu[0]),
              wire_gap + battery[1] + back_strip,
              joy_under + joy_plugs - top_t];
head_outer = [head_inner[0] + 2 * wall, head_inner[1] + 2 * wall, head_inner[2] + top_t];
// Rails lift the battery so wires run underneath to the handle; their height
// is what's left under the battery once the plug space sets the head's depth.
rail_h = head_outer[2] - joy_under - joy_clear - battery[2];
rail_x = [for (s = [-1, 1]) head_outer[0] / 2 + s * (battery[0] / 2 - 5)];
bat_y = wall + wire_gap;                      // battery's front face
bat_z = head_outer[2] - rail_h - battery[2];  // battery's top, below the head's top face

module rbox(size, rad) {
  hull() for (x = [rad, size[0] - rad], y = [rad, size[1] - rad])
    translate([x, y, 0]) cylinder(r = rad, h = size[2]);
}

joy_back = head_outer[1] - wall - edge_gap;   // back edge of the joystick board and of the IMU
joy_c = [wall + edge_gap + joy_board[0] / 2, joy_back - joy_board[1] / 2];
imu_o = [joy_c[0] + joy_board[0] / 2 + 1, joy_back - imu[1]];   // IMU spot's front left corner
btn_x = joy_c[0] + joy_board[0] / 2 + 1 + button_body / 2;
btn_a = [btn_x, head_outer[1] / 2];

// Layout checks: the button clear of the joystick board, and everything inside
// the head's walls. (The ring is the widest part; the nut inside is no wider.)
assert(btn_x + button_body / 2 <= head_outer[0] - wall,
       "the A button doesn't fit beside the joystick board: widen the head or use a smaller button");
assert(btn_a[1] + button_body / 2 <= imu_o[1] - 1 && btn_a[1] - button_body / 2 >= wall,
       "the A button's nut overlaps the IMU spot or the front wall");
assert(button_depth + button_wires <= bat_z, "buttons reach the battery: make the head deeper");
assert(joy_c[1] - joy_board[1] / 2 >= wall, "joystick board taller than the head");
assert(imu_o[0] + imu[0] <= head_outer[0] - wall - edge_gap, "the IMU doesn't fit beside the joystick board");
assert(joy_post[0] < joy_board[0] && joy_post[1] < joy_board[1], "joystick posts outside its board");
assert(joy_hole >= joy_housing + 1, "joystick hole narrower than the stick's travel (housing width + 1)");
assert(joy_depth - top_t >= 12.26 + 0.5, "joystick housing (12.26 tall) hits the inside of the top: raise joy_depth");
// Plug spaces: under the joystick header, joy_plugs straight down; under the
// IMU's header edge, imu_plugs. Battery, rails, stops, lip and base stay out.
assert(bat_y + battery[1] <= joy_back - joy_hdr[1], "the battery is under the joystick's or the IMU's plugs");
assert(joy_under + joy_plugs <= head_outer[2], "head_base is in the joystick plugs' space: make the head deeper");
assert(rail_x[0] + rail_w / 2 <= joy_c[0] - joy_hdr[0] / 2, "a battery rail is under the joystick's plugs");
assert(edge_gap >= fit + lip_t, "head_base's lip is under the plugs");
assert(top_t + imu_plugs <= head_outer[2] - rail_h - stop_h, "a battery stop is in the IMU plugs' space");
assert(rail_h >= tie[1] + 3 && rail_h >= screw_bore + 4, "rails too low for the zip-tie slot and the screws");

module head() {
  difference() {
    rbox(head_outer, r);
    translate([wall, wall, top_t]) rbox([head_inner[0], head_inner[1], head_inner[2] + 1], r - wall);
    translate([joy_c[0], joy_c[1], -1]) cylinder(d = joy_hole, h = top_t + 2);
    translate([btn_a[0], btn_a[1], -1]) cylinder(d = button_d, h = top_t + 2);
    // Screws into head_base's rail ends, front and back.
    for (x = rail_x, y = [-1, head_outer[1] - wall - 1])
      translate([x, y, head_outer[2] - rail_h / 2]) rotate([-90, 0, 0]) cylinder(d = screw_clear, h = wall + 2);
  }
  // Joystick posts hang from the top face; M3 screws thread into them.
  for (dx = [-1, 1], dy = [-1, 1])
    translate([joy_c[0] + dx * joy_post[0] / 2, joy_c[1] + dy * joy_post[1] / 2, top_t - 0.01])
      difference() {
        cylinder(d = 5, h = joy_depth - top_t);
        cylinder(d = joy_post_bore, h = joy_depth);
      }
  // Ridge along the front edge of the IMU spot.
  translate([imu_o[0], imu_o[1] - 0.8, top_t - 0.01]) cube([imu[0], 0.8, 1]);
}

// Base plate closes the head. Flat underside (the bed face); everything else
// stands on top. Each rail ends in stops that keep the battery from sliding
// front to back, and each rail end takes one of the head's screws.
module head_base() {
  y0 = wall + fit;
  y1 = head_outer[1] - wall - fit;
  bat_back = bat_y + battery[1] + fit;
  difference() {
    union() {
      rbox([head_outer[0], head_outer[1], wall], r);
      // Lip that fits inside the head walls.
      translate([wall + fit, wall + fit, wall - 0.01])
        difference() {
          rbox([head_inner[0] - 2 * fit, head_inner[1] - 2 * fit, 3], r - wall);
          translate([lip_t, lip_t, -1])
            rbox([head_inner[0] - 2 * fit - 2 * lip_t, head_inner[1] - 2 * fit - 2 * lip_t, 5], 1);
        }
      for (x = rail_x) translate([x - rail_w / 2, 0, wall - 0.01]) {
        translate([0, y0, 0]) cube([rail_w, y1 - y0, rail_h]);
        translate([0, y0, 0]) cube([rail_w, bat_y - fit - y0, rail_h + stop_h]);
        translate([0, bat_back, 0]) cube([rail_w, y1 - bat_back, rail_h + stop_h]);
      }
    }
    // Wiring opening over the handle.
    translate([(head_outer[0] - handle_inner[0]) / 2, (head_outer[1] - handle_inner[1]) / 2, -1])
      cube([handle_inner[0], handle_inner[1], wall + 2]);
    for (x = rail_x) {
      // Zip-tie slot under each rail, at the battery's middle.
      translate([x - rail_w / 2 - 1, bat_y + (battery[1] - tie[0]) / 2, wall]) cube([rail_w + 2, tie[0], tie[1]]);
      // Screw bores in the rail ends.
      translate([x, y0 - 1, wall + rail_h / 2]) rotate([-90, 0, 0]) cylinder(d = screw_bore, h = screw_depth + 1);
      translate([x, y1 + 1, wall + rail_h / 2]) rotate([90, 0, 0]) cylinder(d = screw_bore, h = screw_depth + 1);
    }
    // Outline of the socket's flange scribed into the underside: glue it there.
    f = [socket_outer[0] + 2 * flange, socket_outer[1] + 2 * flange];
    translate([head_outer[0] / 2, head_outer[1] / 2, -0.01]) difference() {
      translate([-f[0] / 2 - 0.5, -f[1] / 2 - 0.5, 0]) rbox([f[0] + 1, f[1] + 1, 0.4], 3 + flange + 0.5);
      translate([-f[0] / 2 + 0.5, -f[1] / 2 + 0.5, -1]) rbox([f[0] - 1, f[1] - 1, 2], 3 + flange - 0.5);
    }
  }
}

// Collar around the handle's top, origin at the collar's outer corner.
module socket_ring(h, grow = 0) {
  translate([-grow, -grow, 0]) difference() {
    rbox([socket_outer[0] + 2 * grow, socket_outer[1] + 2 * grow, h], 3 + grow);
    translate([grow + wall, grow + wall, -1]) rbox([handle_outer[0] + 2 * fit, handle_outer[1] + 2 * fit, h + 2], 2);
  }
}

// Socket, flange at z = 0 (print orientation). The handle's top goes through
// it and stops against head_base's underside.
module socket() {
  socket_ring(socket_depth);
  socket_ring(flange_t, flange);
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
    translate([(handle_outer[0] - fsr_tail_w - 0.6) / 2, -1, tz - fsr_d / 2 - 14])
      cube([fsr_tail_w + 0.6, wall + 2, 14]);
  }
}

// Fit test: same cross-sections as handle() and socket(), 10 mm tall.
module handle_fit() {
  h = 10;
  difference() {
    rbox([handle_outer[0], handle_outer[1], h], 2);
    translate([wall, wall, -1]) cube([handle_inner[0], handle_inner[1], h + 2]);
  }
  translate([handle_outer[0] + 8, -wall - fit, 0]) socket_ring(h);
}

// The head's frame in the assembly: it sits upside down on head_base.
module in_head() {
  translate([-(head_outer[0] - handle_outer[0]) / 2, -(head_outer[1] - handle_outer[1]) / 2,
             handle_outer[2] + wall + head_outer[2]]) mirror([0, 0, 1]) children();
}

module assembly() {
  color("lightblue") handle();
  color("gray") translate([-wall - fit, -wall - fit, handle_outer[2]]) mirror([0, 0, 1]) socket();
  color("orange") in_head() translate([0, 0, head_outer[2] + wall]) mirror([0, 0, 1]) head_base();
  color("tan") in_head() head();
}

// What goes inside the head, in head() coordinates: battery, joystick, IMU,
// button, and the two plug spaces (red).
module contents() {
  color("dimgray") translate([(head_outer[0] - battery[0]) / 2, bat_y, bat_z]) cube(battery);
  color("green") {
    translate([joy_c[0] - joy_board[0] / 2, joy_c[1] - joy_board[1] / 2, joy_depth])
      cube([joy_board[0], joy_board[1], joy_board_t]);
    translate([imu_o[0], imu_o[1], top_t + 1]) cube([imu[0], imu[1], 1.6]);
  }
  color("silver") {
    translate([joy_c[0] - joy_housing / 2, joy_c[1] - joy_housing / 2, joy_depth - 12.26])
      cube([joy_housing, joy_housing, 12.26]);
    translate([joy_c[0], joy_c[1], -1.5 - 6]) cylinder(d = joy_knob_d, h = 6);
    translate([btn_a[0], btn_a[1], 0]) cylinder(d = button_thread, h = button_depth);
    translate([btn_a[0], btn_a[1], -3]) cylinder(d = button_body, h = 3);
  }
  color("red") {
    translate([joy_c[0] - joy_hdr[0] / 2, joy_back - joy_hdr[1], joy_under]) cube([joy_hdr[0], joy_hdr[1], joy_plugs]);
    translate([imu_o[0], joy_back - joy_hdr[1], top_t + 2.6]) cube([imu[0], joy_hdr[1], imu_plugs - 2.6]);
  }
}

section_x = joy_c[0];         // where to cut, in head() x: default through the joystick's middle
module section() {
  difference() {
    assembly();
    translate([section_x - (head_outer[0] - handle_outer[0]) / 2 - 200, -100, -1]) cube([200, 200, 200]);
  }
  in_head() contents();
}

echo(str("handle ", handle_outer[0], " x ", handle_outer[1], " mm grip, ", handle_outer[2], " mm long"));
echo(str("head ", head_outer[0], " x ", head_outer[1], " x ", head_outer[2] + wall, " mm; rails ", rail_h, " mm"));
echo(str("socket ", socket_outer[0] + 2 * flange, " x ", socket_outer[1] + 2 * flange, " x ", socket_depth, " mm"));
echo(str("joystick board right edge ", joy_c[0] + joy_board[0] / 2, " mm; A button at x = ", btn_x,
         " (", btn_x - button_body / 2 - (joy_c[0] + joy_board[0] / 2), " mm gap to the board)"));

if (part == "assembly") assembly();
else if (part == "section") section();
else if (part == "head") head();
else if (part == "head_base") head_base();
else if (part == "socket") socket();
else if (part == "handle") handle();
else if (part == "handle_fit") handle_fit();
else assert(false, str("unknown part: ", part));
