// Concept C, "pistol": a slim body of one constant width, split down the middle into a left
// and a right half. Stick and buttons in a line along the top, grip leaning back, and the
// battery in a guard in front of the fingers (leave the guard off to power it over USB).
//
//   half_l, half_r  the two shells; print outer side down, open side up, no supports
//   guard           battery holder; print open end down
//   assembly, print (all parts as they sit on the bed)
// Modeled as a side profile in x (forward) and y (up, top face at y = 0), extruded along z.
// Every hole on the split line is a half circle open to the top of the print.

include <common.scad>
part = "assembly";
battery_guard = true;
lean = 15;                    // grip angle, degrees back from upright
guard_gap = 34;               // finger room between the grip and the guard

W = joy_board[0] + 2 + 2 * wall;          // overall width
h = W / 2;                                // one half; the split plane is z = h
head_h = joy_stack + 1 + wall;
grip_d = devkit_h + 2 + 2 * wall;         // grip, front to back
u_joy = wall + 1 + joy_board[1] / 2;
btn_end = face_buttons > 0 ? btn_first + (face_buttons - 1) * btn_pitch + button_body / 2 : joy_board[1] / 2;
guard_t = battery[2] + 1 + 2 * wall;
guard_w = battery[1] + 1 + 2 * wall;
guard_h = battery[0] + 1 + wall;
guard_x = grip_d * cos(lean) + guard_gap;
head_len = max(u_joy + btn_end + 10, battery_guard ? guard_x + guard_t + 12 : 0);

// Stations down the grip's front face, measured from the top face along the grip.
s0 = (head_h - grip_d * sin(lean)) / cos(lean);     // where the head's underside meets the grip
s_fsr = s0 + 8 + fsr_d / 2;                 // clear of the fillet under the head
s_grip = s_fsr + fsr_d / 2 + 3 + button_body / 2;
s_esp = (grip_button ? s_grip + button_body / 2 : s_fsr + fsr_d / 2) + 2;
grip_len = s_esp + devkit[0] + 11 + wall;

// Grip frame: x from the back (0) to the front (grip_d), y = -s.
module in_grip() rotate([0, 0, -lean]) children();
function g(x, s) = [x * cos(lean) - s * sin(lean), -x * sin(lean) - s * cos(lean)];
pillars = [[head_len - wall - 4.5, -head_h / 2], g(grip_d - wall - 5, s0 + 6), g(grip_d - wall - 5, grip_len - wall - 5.5)];
guard_screws = [guard_x - 5, guard_x + guard_t + 5];

assert(button_reach + 4 <= head_h - wall, "no room under the buttons for the guard's screw blocks");
echo(str("C pistol: ", W, " wide, head ", head_len, " x ", head_h, ", grip ", W, " x ", grip_d, ", ", grip_len - s0,
         " long below the head", battery_guard ? str("; guard ", guard_t, " x ", guard_w, " x ", guard_h) : ""));

module profile() {
  offset(r = 5) offset(delta = -5) offset(r = -6) offset(delta = 6) {
    translate([0, -head_h]) square([head_len, head_h]);
    in_grip() translate([0, -grip_len]) square([grip_d, grip_len]);
  }
}

// Thumb layout frame placed on the top face, centered on the split plane.
module thumb_frame() multmatrix([[0, -1, 0, u_joy], [0, 0, -1, 0], [1, 0, 0, h]]) children();

// One half, outer side on the bed (z = 0), split plane up (z = h).
// The left half takes the screw heads, the right half the threads.
module half(right = false) {
  difference() {
    union() {
      difference() {
        chamfer_extrude(h) profile();
        translate([0, 0, wall]) linear_extrude(h) offset(delta = -wall) profile();
      }
      // Ribs the joystick board screws to (in place of posts, which would overhang here).
      for (du = [-1, 1]) translate([u_joy + du * joy_post[1] / 2 - 2.5, -joy_depth, 0]) cube([5, joy_depth - 1, h - joy_post[0] / 2 + 3.5]);
      for (p = pillars) translate([p[0], p[1], 0]) cylinder(d = right ? 7 : 10, h = h);
      // Blocks under the buttons for the guard's screws.
      if (battery_guard) for (x = guard_screws) translate([x - 3, -head_h + wall - 0.01, 0]) cube([6, 3.5, h - 4]);
    }
    thumb_frame() thumb_cuts(face_buttons, inline = true);
    for (du = [-1, 1]) translate([u_joy + du * joy_post[1] / 2, -joy_depth - 1, h - joy_post[0] / 2]) rotate([-90, 0, 0]) cylinder(d = joy_post_bore, h = 10);
    for (p = pillars) translate([p[0], p[1], 0]) {
      if (right) translate([0, 0, h - 12]) cylinder(d = joy_post_bore, h = 13);
      else { translate([0, 0, -1]) cylinder(d = 3.4, h = h + 2); translate([0, 0, -1]) cylinder(d = 6.5, h = h - 5); }
    }
    in_grip() {
      // FSR pocket (0.8 mm floor), the slit for its tail, the grip button, the USB slot.
      translate([grip_d + 1, -s_fsr, h]) rotate([0, -90, 0]) cylinder(d = fsr_d + 0.6, h = 1 + wall - 0.8);
      translate([grip_d - wall - 1, -s_fsr - fsr_d / 2 - 1.2, h - fsr_tail_w / 2 - 0.3]) cube([wall + 2, 1.6, fsr_tail_w + 0.6]);
      if (grip_button) translate([grip_d + 1, -s_grip, h]) rotate([0, -90, 0]) cylinder(d = button_d, h = wall + 2);
      translate([wall + 1, -grip_len - 1, h - usb_slot[0] / 2]) cube([usb_slot[1], wall + 4, usb_slot[0]]);
    }
    if (battery_guard) {
      for (x = guard_screws) translate([x, -head_h - 1, h - 8]) rotate([-90, 0, 0]) cylinder(d = joy_post_bore, h = wall + 4);
      translate([guard_x + guard_t / 2, -head_h - 1, h]) rotate([-90, 0, 0]) cylinder(d = 6, h = wall + 2);   // battery leads
    }
  }
}

// Open end at z = 0 (against the head's underside), x 0..guard_t, centered on y.
module guard() {
  difference() {
    union() {
      translate([0, -guard_w / 2, 0]) rbox([guard_t, guard_w, guard_h], 2);
      translate([-10, -13, 0]) rbox([guard_t + 20, 26, 3], 3);
    }
    translate([wall, -guard_w / 2 + wall, -1]) cube([guard_t - 2 * wall, guard_w - 2 * wall, guard_h - wall + 1]);
    for (x = [-5, guard_t + 5], y = [-8, 8]) translate([x, y, -1]) cylinder(d = 3.4, h = 5);
  }
}

module parts() {
  thumb_frame() p_thumb(face_buttons, inline = true);
  in_grip() {
    multmatrix([[0, 0, 1, wall + 4], [0, -1, 0, -s_esp], [1, 0, 0, h]]) p_devkit();
    multmatrix([[0, 0, 1, grip_d - 1.4], [0, 1, 0, -s_fsr], [-1, 0, 0, h]]) p_fsr();
    if (grip_button) multmatrix([[0, 0, -1, grip_d], [0, 1, 0, -s_grip], [1, 0, 0, h]]) p_button();
    translate([wall + 1 + imu[1] / 2, -(s0 + 10 + imu[0] / 2), wall]) rotate([0, 0, 90]) p_imu();
  }
  if (battery_guard)
    multmatrix([[0, 0, 1, guard_x + wall + 0.5], [-1, 0, 0, -head_h - 0.5], [0, -1, 0, h + battery[1] / 2]]) p_battery();
}

module assembly() rotate([90, 0, 0]) translate([0, 0, -h]) {
  color("tan") half();
  if (!cut) color("burlywood") translate([0, 0, 2 * h]) mirror([0, 0, 1]) half(right = true);
  if (battery_guard) color("slategray") difference() {
    multmatrix([[1, 0, 0, guard_x], [0, 0, -1, -head_h], [0, 1, 0, h]]) guard();
    if (cut) translate([-500, -500, h]) cube(1000);
  }
  parts();
}

if (part == "assembly") assembly();
else if (part == "half_l") half();
else if (part == "half_r") mirror([0, 1, 0]) half(right = true);
else if (part == "guard") guard();
else if (part == "print") {
  color("tan") half();
  color("burlywood") translate([0, 24, 0]) mirror([0, 1, 0]) half(right = true);
  if (battery_guard) color("slategray") translate([head_len + 20, 0, 0]) guard();
}
else assert(false, str("unknown part: ", part));
