// Fit tests: quick prints that check uncertain sizes before the long prints.
// Tested with OpenSCAD 2026.10 (snapshot). Print flat, PLA, no supports.
//
//   buttons      plate of labeled holes: find the hole your push buttons fit
//                -> controller.scad button_d
//   lens_seats   rings with seats at lens_d + 0.1 / 0.3 / 0.5 / 0.7 mm: find the
//                snug one -> adjust lens_d in headset.scad by that clearance
//   lens_rings   retaining rings at 3 press-fit tightnesses, for the snug seat
//   phone        10 mm slice of the phone tray: slide the Pixel through it,
//                camera end first, to check width, thickness, the camera bar
//                and the screen lip -> headset.scad clear, cam_bar_h
//   frames       low outline frames for the 4xAA holder, the DevKitC and the
//                GY-521: drop each part in -> trackers/controller sizes
//   joystick     the controller's joystick hole and posts: screw the joystick
//                board on and check the stick moves freely -> joy_post, joy_hole
//   straps       strap ears with 25 / 32 / 40 / 52 mm slots: thread your
//                headband and bandage -> strap_slot / strap_w
//   all          everything laid out
//
// Each test prints in about 5-25 minutes. Pass your measured values with -D,
// the same way as for the real parts.

part = "all";

// ---- Same parameters as the real designs ----------------------------------------
lens_d = 25.0;
lens_thk = 6.0;
phone_h = 73.2;               // Pixel 7 short edge
phone_t = 8.7;                // Pixel 7 thickness (body, without the camera bar)
cam_bar_h = 2.7;              // camera bar protrusion past the back
clear = 0.6;                  // headset.scad phone clearance per side
lip = 2.0;
battery = [62.0, 58.0, 16.0];
devkit = [55.0, 28.5];
imu = [21.0, 16.5];
joy_hole = 25;
joy_post = [26.0, 19.0];
button_sizes = [5, 6, 7, 8, 10, 12, 16];
seat_clearances = [0.1, 0.3, 0.5, 0.7];
strap_sizes = [25, 32, 40, 52];

$fn = 64;
t = 2.4;                      // plate thickness (matches the controller top)

module label(txt, size = 4) {
  linear_extrude(0.6) text(txt, size = size, halign = "center", valign = "center",
                           font = "Liberation Sans:style=Bold");
}

// Holes of each size in a row, size engraved under each.
module buttons() {
  pitch = max(button_sizes) + 6;
  w = pitch * len(button_sizes) + 4;
  difference() {
    cube([w, 32, t]);
    for (i = [0 : len(button_sizes) - 1]) {
      x = 4 + pitch * (i + 0.5);
      translate([x, 20, -1]) cylinder(d = button_sizes[i], h = t + 2);
      translate([x, 6, t - 0.6]) label(str(button_sizes[i]));
    }
  }
}

// Lens seats: a ledge to rest on and a pocket at each clearance.
module lens_seats() {
  pitch = lens_d + 10;
  for (i = [0 : len(seat_clearances) - 1])
    translate([pitch * i, 0, 0]) difference() {
      union() {
        cylinder(d = lens_d + 7, h = lens_thk + 1.2);
        // Label tab, attached to the ring.
        translate([-7, -(lens_d + 7) / 2 - 7, 0]) cube([14, 9, 2]);
      }
      translate([0, 0, -1]) cylinder(d = lens_d - 2.4, h = lens_thk + 4);
      translate([0, 0, 1.2]) cylinder(d = lens_d + seat_clearances[i], h = lens_thk + 1);
      translate([0, -(lens_d + 7) / 2 - 3, 1.4]) label(str(seat_clearances[i]), 3.5);
    }
}

// Retaining rings: OD = lens_d + 0.3 (the headset's seat) minus three
// interferences. Ring 1 (one notch on the inner edge) is loosest, ring 3 (three
// notches) tightest. Matching value for headset.scad's lens_ring: 0.15 = ring 2.
module lens_rings() {
  pitch = lens_d + 8;
  for (i = [0 : 2]) {
    od = lens_d + 0.3 - [0.05, 0.15, 0.25][i];
    translate([pitch * i, 0, 0]) difference() {
      cylinder(d = od, h = 1.6);
      translate([0, 0, -1]) cylinder(d = lens_d - 3, h = 4);
      for (n = [0 : i])
        rotate([0, 0, 90 + n * 20]) translate([(lens_d - 3) / 2, 0, -1]) cylinder(d = 1.0, h = 4, $fn = 16);
    }
  }
}

// Tray cross-section: same pocket and lip as headset.scad's tray, 10 mm long.
// The pocket includes room for the camera bar: slide the phone through this
// slice camera end first, the way it goes into the headset.
module phone() {
  in_h = phone_h + 2 * clear;
  wall = 2.4;
  pocket = phone_t + cam_bar_h + clear;
  depth = lip + pocket + wall;
  difference() {
    translate([0, -in_h / 2 - wall, 0]) cube([10, in_h + 2 * wall, depth]);
    translate([-1, -in_h / 2, lip]) cube([12, in_h, pocket]);   // phone pocket
    translate([-1, -68 / 2, -1]) cube([12, 68, lip + 2]);                // screen window
  }
}

// Outline frames 5 mm tall: the part should drop in with a little play.
module frame(inner, txt) {
  difference() {
    translate([-2, -2, 0]) cube([inner[0] + 4, inner[1] + 4, 5]);
    translate([0, 0, 1]) cube([inner[0], inner[1], 5]);
    translate([inner[0] / 2, inner[1] / 2, 0.4]) label(txt, 5);
  }
}

module frames() {
  frame([battery[0] + 2, battery[1] + 2], "AA x4");      // trackers.scad leg case inner
  translate([battery[0] + 10, 0, 0]) frame([devkit[0] + 2, devkit[1] + 2], "DevKitC");
  translate([battery[0] + 10, devkit[1] + 10, 0]) frame([imu[0] + 1, imu[1] + 1], "IMU");
}

// Controller joystick mount: the head's hole and posts on a small plate.
module joystick() {
  s = max(joy_hole, joy_post[0]) + 16;
  translate([-s / 2, -s / 2, 0]) difference() {
    cube([s, s, t]);
    translate([s / 2, s / 2, -1]) cylinder(d = joy_hole, h = t + 2);
  }
  for (dx = [-1, 1], dy = [-1, 1])
    translate([dx * joy_post[0] / 2, dy * joy_post[1] / 2, t - 0.01])
      difference() { cylinder(d = 5, h = 8); cylinder(d = 2.2, h = 9); }
}

// Strap ears with several slot widths.
module straps() {
  for (i = [0 : len(strap_sizes) - 1])
    translate([i * 14, 0, 0]) difference() {
      cube([12, max(strap_sizes) + 16, 4]);
      translate([4, 4, -1]) cube([4, strap_sizes[i], 6]);
      translate([6, max(strap_sizes) + 10, 3.4]) rotate([0, 0, 90]) label(str(strap_sizes[i]), 3.5);
    }
}

module all() {
  buttons();
  translate([lens_d / 2 + 4, 62, 0]) lens_seats();
  translate([lens_d / 2 + 4, 105, 0]) lens_rings();
  translate([0, 130, 0]) frames();
  translate([200, 40, 0]) phone();
  translate([245, 20, 0]) joystick();
  translate([225, 65, 0]) straps();
}

if (part == "all") all();
else if (part == "buttons") buttons();
else if (part == "lens_seats") lens_seats();
else if (part == "lens_rings") lens_rings();
else if (part == "phone") phone();
else if (part == "frames") frames();
else if (part == "joystick") joystick();
else if (part == "straps") straps();
else assert(false, str("unknown part: ", part));
