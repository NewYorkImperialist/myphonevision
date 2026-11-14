// Shared by the controller enclosure mockups: part sizes, thumb layout, stand-in parts.
// Mockups only; cases/controller.scad stays the real model.

use <../../controller.scad>   // rbox()

// ---- Part sizes: copied from cases/controller.scad on cad-work @ 490224a -------------------------
devkit = [51.5, 28.23];       // ESP32 board outline, measured (length x width)
joy_board = [38.1, 38.1];     // Adafruit 512 breakout, measured 38.08 square, 1.6 thick (cad-work 20030d8)
joy_hole = 25.8;              // opening the stick moves in, from the fit test print
joy_housing = 19.96;          // measured: width of the stick's housing on the board
joy_knob_d = 26;              // measured: knob's outer diameter
joy_post = [30.5, 30.5];      // mounting-hole spacing, center to center, measured: 27.4 inner gap + 3.16 hole (cad-work 20030d8)
joy_post_hole = 3.16;         // M3 holes in the board, measured
joy_post_bore = 2.8;          // M3 screws thread into the printed posts
joy_depth = 15.9;             // outer top face down to the board's top surface (13.5 mm posts + top_t)
button_thread = 14.84;        // panel-mount push button: threaded body diameter
button_d = button_thread + 0.5;
button_body = 19.19;          // ring under the cap, sits on the outside
button_depth = 14.46;         // bottom of the ring to the solder tab tips
button_wires = 3;
usb_slot = [12, 8];           // not measured
wall = 2.2;
top_t = 2.4;
socket_depth = 12;
fit = 0.3;
$fn = 64;

// ---- As built (issue #2, docs/wiring.md step 2h); cad-work still has the datasheet values ---------
devkit_h = 35;                // ESP32 with the jumper plugs on: confirmed by TSVRN9
battery = [61.68, 57.7, 15];  // 4xAA holder, measured
fsr_d = 18.5;                 // FSR pad, measured
fsr_tail_w = 7.3;             // FSR tail, measured
imu = [25.35, 20.3];          // Adafruit BNO055 (RIGHT), measured; the GY-521 (LEFT) is smaller

// ---- Wiring, from TSVRN9 --------------------------------------------------------------------------
// Joystick and ESP32: header pins with female jumper plugs. IMU: plugs on some boards, soldered on
// others, so its spot is sized for plugs. A button and FSR: soldered.
plug_len = 30;                // a jumper plug on a header pin: pin + housing + bend
plug_t = 5;                   // room across a row of plugs (2.5 mm housings and the wires leaving them)

// ---- Not measured: guesses -----------------------------------------------------------------------
joy_solder = 3;               // solder joints under the joystick board, away from its header
imu_h = 4;                    // IMU board with foam tape

// ---- Options ---------------------------------------------------------------------------------------
face_buttons = 1;             // on the thumb face: A only, as wired today (3 adds B and system)
grip_button = false;          // not wired today

joy_stack = joy_depth + 1.6 + plug_len;        // outer top face to the end of the joystick's plugs
button_reach = button_depth + button_wires;    // outer face to the end of a button's wires
btn_pitch = button_body + 2;
btn_first = joy_board[1] / 2 + 1 + button_body / 2;   // stick center to the nearest button center

// Thumb layout frame: origin at the stick center on the outer face, +z into the shell (the face is
// printed on the bed), +y toward the wrist (the joystick's pin header side), buttons at -y.
// row: buttons side by side across x.  inline: buttons one behind the other along -y.
function btn_pos(n, inline = false) = n < 1 ? [] :
  [for (i = [0 : n - 1]) inline ? [0, -btn_first - i * btn_pitch] : [(i - (n - 1) / 2) * btn_pitch, -btn_first]];

module thumb_cuts(n, inline = false) {
  translate([0, 0, -1]) cylinder(d = joy_hole, h = top_t + 2);
  for (b = btn_pos(n, inline)) translate([b[0], b[1], -1]) cylinder(d = button_d, h = top_t + 2);
}

// Joystick posts hanging from the face (as in controller.scad's head).
module joy_posts() {
  for (dx = [-1, 1], dy = [-1, 1]) translate([dx * joy_post[0] / 2, dy * joy_post[1] / 2, top_t - 0.01])
    difference() {
      cylinder(d = 5, h = joy_depth - top_t);
      cylinder(d = joy_post_bore, h = joy_depth);
    }
}

// Extrude a 2D outline with a chamfer on the bed side, built in 0.2 mm layer steps.
module chamfer_extrude(h, c = 1.6, step = 0.2) {
  for (i = [0 : round(c / step) - 1]) translate([0, 0, i * step])
    linear_extrude(step + 0.01) offset(delta = -(c - i * step)) children();
  translate([0, 0, c]) linear_extrude(h - c) children();
}

// ---- Stand-in parts for the assembly views (never printed) ---------------------------------------
module p_joystick() {   // thumb layout frame
  color("royalblue") translate([-joy_board[0] / 2, -joy_board[1] / 2, joy_depth]) cube([joy_board[0], joy_board[1], 1.6]);
  color("dimgray") translate([-joy_housing / 2, -joy_housing / 2, joy_depth - 12.26]) cube([joy_housing, joy_housing, 12.26]);
  color("#3a3a3a") translate([0, 0, joy_depth - 17.42]) { cylinder(d = joy_knob_d, h = 3); cylinder(d = 8, h = 6); }
  color("darkorange") translate([-7, joy_board[1] / 2 - plug_t, joy_depth + 1.6]) cube([14, plug_t, plug_len]);   // plugs on its header
}
module p_button() {     // origin on the panel's outer face, +z into the shell
  color("silver") translate([0, 0, -2]) cylinder(d = button_body, h = 2);
  color("crimson") translate([0, 0, -6]) cylinder(d = 11, h = 4);
  color("silver") cylinder(d = button_thread, h = button_depth);
  color("gold") translate([0, 0, button_depth]) cylinder(d = 5, h = button_wires);
}
module p_thumb(n, inline = false) {
  p_joystick();
  for (b = btn_pos(n, inline)) translate([b[0], b[1], 0]) p_button();
}
module p_devkit() {     // board in z 0..1.6, USB end at +y; components below, pins and plugs above
  color("seagreen") translate([-devkit[1] / 2, 0, 0]) cube([devkit[1], devkit[0], 1.6]);
  color("silver") translate([-8, 3, -3]) cube([16, 18, 3]);
  color("silver") translate([-4, devkit[0] - 6, -3]) cube([8, 6.5, 3]);
  color("dimgray") for (sx = [-1, 1]) translate([sx * (devkit[1] / 2 - 1.5) - 1.3, 2, 1.6]) cube([2.6, devkit[0] - 4, devkit_h - 4.6]);
}
module p_battery() {    // corner at the origin
  color("dimgray") cube([battery[0], battery[1], 3]);
  color("goldenrod") for (i = [0 : 3]) translate([5.5, battery[1] / 8 * (2 * i + 1), battery[2] / 2])
    rotate([0, 90, 0]) cylinder(d = 14.2, h = 50.5);
}
module p_fsr() {        // pad centered, on z = 0, tail toward -y
  color("darkslategray") cylinder(d = fsr_d, h = 0.5);
  color("darkslategray") translate([-fsr_tail_w / 2, -fsr_d / 2 - 6, 0]) cube([fsr_tail_w, 8, 0.5]);
}
module p_imu(plugs = false) {   // centered, lying on z = 0; header and its plugs along the +y edge
  if (plugs) color("darkorange") translate([-imu[0] / 2, imu[1] / 2 - 2.6, 1.6]) cube([imu[0], 2.6, plug_len]);
  color("mediumpurple") translate([-imu[0] / 2, -imu[1] / 2, 0]) cube([imu[0], imu[1], 1.6]);
  color("black") translate([-2.5, -2, 1.6]) cube([5, 4, 1]);
}

// Printed shell part in the assembly: colored, and cut open at x > 0 when cut is set.
cut = false;
module shell(c) {
  color(c) difference() {
    children();
    if (cut) translate([0, -500, -500]) cube(1000);
  }
}
