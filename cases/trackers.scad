// SlimeVR tracker cases, parametric. Tested with OpenSCAD 2026.10 (snapshot).
//
//   leg_case / leg_lid     DevKitC + primary MPU-6050 + 4xAA holder (thigh boards)
//   waist_case / waist_lid DevKitC + primary MPU-6050, powered by a USB bank
//   pod_case / pod_lid     extension MPU-6050 on its cable (chest, ankles)
//   layout                 every part laid out, for a quick look
//
// Each case has strap ears on both ends: thread the ACE bandage (or a strap up
// to strap_w wide) through them, or wrap the bandage over the closed case.
// Lids press-fit; add a strip of tape or a zip tie if one loosens.
// Print everything flat, open side up, PLA, no supports.

part = "layout";

// ---- Measure the real parts and adjust ----------------------------------------
devkit = [55.0, 28.5];      // ESP32-DevKitC board outline
devkit_h = 24;              // board + headers + plugged jumper wires, total height
imu = [21.0, 16.5];         // GY-521 board outline
imu_h = 9;                  // GY-521 with wires soldered on
battery = [62.0, 58.0, 16.0];  // 4xAA holder (2x2 flat); measure the lab's
usb_slot = [12, 8];         // micro-USB plug clearance
cable_d = 5.0;              // 4-wire extension cable pass-through
strap_w = 52;               // widest strap that threads through the ears
strap_gap = 4;              // strap thickness clearance

// ---- Shell ------------------------------------------------------------------------
wall = 2.0;
floor_t = 2.0;
lid_t = 2.0;
lip_h = 3.0;                // lid's press-fit lip depth
fit = 0.25;                 // lid lip clearance per side
r = 3;                      // outer corner radius
$fn = 48;

module rbox(size, rad) {
  // Rounded-corner box, corners rounded in XY only.
  hull() for (x = [rad, size[0] - rad], y = [rad, size[1] - rad])
    translate([x, y, 0]) cylinder(r = rad, h = size[2]);
}

// Strap ears on the two short (X) ends, flush with the floor.
module ears(outer) {
  bar = 4;                       // ear bar width and thickness: strap tension pulls on it
  ear_len = strap_gap + 2 * bar;
  slot_h = min(strap_w, outer[1] + 10);
  for (side = [0, 1])
    translate([side == 0 ? -ear_len + 1 : outer[0] - 1, (outer[1] - slot_h - 2 * bar) / 2, 0])
      difference() {
        rbox([ear_len, slot_h + 2 * bar, bar], 2);
        translate([bar, bar, -1]) cube([strap_gap, slot_h, bar + 2]);
      }
}

// Open-top case with a given inner cavity. Holes are added by the caller.
module case_shell(inner) {
  outer = [inner[0] + 2 * wall, inner[1] + 2 * wall, inner[2] + floor_t];
  difference() {
    union() {
      rbox(outer, r);
      ears(outer);
    }
    translate([wall, wall, floor_t]) rbox([inner[0], inner[1], inner[2] + 1], max(0.5, r - wall));
  }
}

module lid(inner, recess = [0, 0]) {
  outer = [inner[0] + 2 * wall, inner[1] + 2 * wall];
  difference() {
    union() {
      rbox([outer[0], outer[1], lid_t], r);
      translate([wall + fit, wall + fit, lid_t - 0.01])
        difference() {
          rbox([inner[0] - 2 * fit, inner[1] - 2 * fit, lip_h], max(0.5, r - wall));
          translate([1.2, 1.2, -1]) rbox([inner[0] - 2 * fit - 2.4, inner[1] - 2 * fit - 2.4, lip_h + 2], 0.5);
        }
    }
  }
}

// ---- Leg tracker: battery on the floor, DevKitC and IMU on top of it ---------------
leg_inner = [max(battery[0], devkit[0]) + 2, max(battery[1], devkit[1] + imu[1] + 4) + 2,
             battery[2] + max(devkit_h, imu_h) + 1];

module leg_case() {
  outer = [leg_inner[0] + 2 * wall, leg_inner[1] + 2 * wall];
  difference() {
    case_shell(leg_inner);
    // Micro-USB access at the DevKitC end (flashing), high up above the battery.
    translate([-1, wall + 4, floor_t + battery[2] + 2]) cube([wall + 2, usb_slot[0], usb_slot[1]]);
    // Extension cable out the far end.
    translate([outer[0] - wall - 1, outer[1] / 2, floor_t + leg_inner[2] - cable_d / 2 - 1])
      rotate([0, 90, 0]) cylinder(d = cable_d, h = wall + 2);
  }
}

module leg_lid() { lid(leg_inner); }

// ---- Waist tracker: no battery bay; a USB bank powers it -----------------------
waist_inner = [devkit[0] + 2, devkit[1] + imu[1] + 6, max(devkit_h, imu_h) + 1];

module waist_case() {
  outer = [waist_inner[0] + 2 * wall, waist_inner[1] + 2 * wall];
  difference() {
    case_shell(waist_inner);
    translate([-1, wall + 4, floor_t + 2]) cube([wall + 2, usb_slot[0], usb_slot[1]]);  // power + flashing
    translate([outer[0] - wall - 1, outer[1] / 2, floor_t + waist_inner[2] - cable_d / 2 - 1])
      rotate([0, 90, 0]) cylinder(d = cable_d, h = wall + 2);
  }
}

module waist_lid() { lid(waist_inner); }

// ---- Extension IMU pod -------------------------------------------------------------
pod_inner = [imu[0] + 1, imu[1] + 1, imu_h];

module pod_case() {
  outer = [pod_inner[0] + 2 * wall, pod_inner[1] + 2 * wall];
  difference() {
    case_shell(pod_inner);
    translate([-1, outer[1] / 2, floor_t + pod_inner[2] - cable_d / 2])
      rotate([0, 90, 0]) cylinder(d = cable_d, h = wall + 2);
  }
}

module pod_lid() { lid(pod_inner); }

module layout() {
  leg_case();
  translate([0, 90, 0]) leg_lid();
  translate([110, 0, 0]) waist_case();
  translate([110, 70, 0]) waist_lid();
  translate([200, 0, 0]) pod_case();
  translate([200, 40, 0]) pod_lid();
}

echo(str("leg case outer ", leg_inner[0] + 2 * wall, " x ", leg_inner[1] + 2 * wall, " x ",
         leg_inner[2] + floor_t + lid_t, " mm closed"));
echo(str("waist case outer ", waist_inner[0] + 2 * wall, " x ", waist_inner[1] + 2 * wall, " x ",
         waist_inner[2] + floor_t + lid_t, " mm closed"));
echo(str("pod outer ", pod_inner[0] + 2 * wall, " x ", pod_inner[1] + 2 * wall, " x ",
         pod_inner[2] + floor_t + lid_t, " mm closed"));

if (part == "layout") layout();
else if (part == "leg_case") leg_case();
else if (part == "leg_lid") leg_lid();
else if (part == "waist_case") waist_case();
else if (part == "waist_lid") waist_lid();
else if (part == "pod_case") pod_case();
else if (part == "pod_lid") pod_lid();
else assert(false, str("unknown part: ", part));
