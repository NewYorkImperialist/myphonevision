// Concept A, "paddle": everything in one flat body, held like a TV remote.
// Thumb face and battery in the wide front, ESP32 lying flat in the grip behind it.
//
//   top      tub with the thumb face; print face down, no supports
//   bottom   plate with the trigger pocket and grip button; print flat
//   assembly, print (both parts as they sit on the bed)

include <common.scad>
part = "assembly";

head = [max(battery[1] + 4, face_buttons * btn_pitch) + 2 * wall,   // across
        max(battery[0] + 4, joy_board[1] / 2 + btn_first + button_body / 2 + 3) + 2 * wall];  // along
grip_w = devkit[1] + 2 + 2 * wall;
neck = 18;                                   // taper from the head to the grip
inner_h = max(joy_stack - top_t + battery[2] + 1, devkit_h + 2);
H = inner_h + top_t + wall;                  // overall thickness
tub_h = H - wall;

// Stations along y, from the nose.
y_joy = head[1] - wall - 2 - joy_board[1] / 2;
y_fsr = head[1] + 11;                        // under the index finger, in the neck
y_grip = y_fsr + fsr_d / 2 + 3 + button_body / 2;
y_esp = grip_button ? y_grip + button_body / 2 + 2 : y_fsr + fsr_d / 2 + 3;
L = y_esp + devkit[0] + 2 + wall;
boss = [20, head[1] + 4];

assert(button_reach + 1 <= H - wall - battery[2], "thumb buttons reach the battery");
assert(joy_stack + 1 <= H - wall - battery[2], "joystick reaches the battery");
assert(!grip_button || button_reach + wall + imu_h <= H - top_t, "no room for the IMU above the grip button");

module outline() {
  offset(r = 6) offset(delta = -6) offset(r = -12) offset(delta = 12) {
    translate([-head[0] / 2, 0]) square(head);
    hull() {
      translate([-head[0] / 2, head[1] - 1]) square([head[0], 1]);
      translate([-grip_w / 2, head[1] + neck]) square([grip_w, 1]);
    }
    translate([-grip_w / 2, head[1]]) square([grip_w, L - head[1]]);
  }
}

// Top face at z = 0 (print orientation), open toward +z.
module top() {
  difference() {
    chamfer_extrude(tub_h) outline();
    translate([0, 0, top_t]) linear_extrude(tub_h) offset(delta = -wall) outline();
    translate([0, y_joy, 0]) thumb_cuts(face_buttons);
    // USB window in the end wall, against the top face where the board lies.
    translate([-usb_slot[0] / 2, L - wall - 1, top_t]) cube([usb_slot[0], wall + 2, usb_slot[1]]);
  }
  translate([0, y_joy, 0]) joy_posts();
  // Two screw bosses in the neck; they also stop the battery sliding back.
  for (sx = [-1, 1]) translate([sx * boss[0], boss[1], top_t - 0.01]) difference() {
    cylinder(d = 7, h = tub_h - top_t);
    translate([0, 0, tub_h - top_t - 12]) cylinder(d = joy_post_bore, h = 13);
  }
}

// Outer face at z = 0, lip up.
module bottom() {
  difference() {
    union() {
      chamfer_extrude(wall, c = 1) outline();
      translate([0, 0, wall - 0.01]) linear_extrude(3) difference() {
        offset(delta = -wall - fit) outline();
        offset(delta = -wall - fit - 1.6) outline();
      }
    }
    translate([0, y_fsr, -0.01]) cylinder(d = fsr_d + 0.6, h = 0.8);                       // pad pocket
    translate([-fsr_tail_w / 2 - 0.3, y_fsr + fsr_d / 2 - 1.5, -1]) cube([fsr_tail_w + 0.6, 1.6, wall + 2]);  // tail slit
    if (grip_button) translate([0, y_grip, -1]) cylinder(d = button_d, h = wall + 2);
    for (sx = [-1, 1]) translate([sx * boss[0], boss[1], -1]) {
      cylinder(d = 3.4, h = wall + 2);
      cylinder(d1 = 8, d2 = 3.4, h = 2.3);
    }
  }
}

module parts() {
  translate([0, y_joy, H]) mirror([0, 0, 1]) p_thumb(face_buttons);
  translate([battery[1] / 2, wall + 2, wall]) rotate([0, 0, 90]) p_battery();
  translate([0, y_esp, H - top_t - 3]) mirror([0, 0, 1]) p_devkit();
  translate([0, y_fsr, 0.8]) rotate([180, 0, 180]) p_fsr();
  if (grip_button) translate([0, y_grip, 0]) p_button();
  translate([0, (y_joy + joy_board[1] / 2 + y_esp) / 2, H - top_t]) rotate([180, 0, 90]) p_imu();
}

module assembly() {
  shell("tan") translate([0, 0, H]) mirror([0, 0, 1]) top();
  shell("orange") bottom();
  parts();
}

echo(str("A paddle: ", head[0], " wide x ", L, " long x ", H, " thick; grip ", grip_w, " x ", H));

if (part == "assembly") assembly();
else if (part == "top") top();
else if (part == "bottom") bottom();
else if (part == "print") { color("tan") top(); color("orange") translate([head[0] + 8, 0, 0]) bottom(); }
else assert(false, str("unknown part: ", part));
