// Concept D, "ergo": the chosen controller shell. Left/right split, grip leaning back, a
// hand-shaped body: the side profile is drawn from curves (palm swell, finger grooves, heel,
// tapering head) and its edges are rounded off toward both sides, so the grip's section is
// an oval with flat cheeks. A bow runs from the grip's base up to the head and closes a loop
// around the fingers; the battery cradle is clamped into that loop by rails.
//
// Every part has a fitted place:
//   battery   the 4xAA holder snaps into the cradle under two lips (no holes needed) and a
//             cover slides across the cells from the side, so cells swap without opening
//             anything. Its leads run in channels behind it to exits at the top and bottom.
//   ESP32     lies flat over the left cheek, plugs pointing across the body. It rests on
//             ledges under its two long edges between two rails, with a wedge stop at the
//             top end and two snap hooks at the USB end.
//   IMU       on a pad on the left cheek, pushed into a corner made by two fences and held by
//             a slotted clamp and one M3 screw. Fits the BNO055 and the smaller GY-521.
//   joystick  screws to ribs; its plugs hang straight down into the top of the grip.
//   wires     zip-tie anchors in the head, the arm and the grip.
//   shorts    a divider wall crosses the grip between the ESP32 and the joystick's and IMU's
//             plugs, with a window on the split plane for the wires. The battery's terminals
//             are behind the cradle's solid top and bottom walls; its leads leave through
//             slots behind the holder.
//
//   half_l, half_r  the two shells; print cheek down, open side up, no supports
//   cradle          battery cradle; print back down, open side up
//   cover           slides over the cells; print flat, wide face down
//   imu_clamp       print flat
//   assembly, print (all parts as they sit on the bed)
//   fit_test        print this first: the ESP32 seat and IMU mount, a section of the cradle, the
//                   end of the cover and the IMU clamp, all cut from the real parts
//                   (fit_esp, fit_cradle, fit_cover print them one at a time)
// Side profile in x (forward) and y (up, thumb face at y = 0), extruded along z.

include <common.scad>
part = "assembly";
lean = 15;                    // grip angle, degrees back from upright
finger_room = 33;             // between the grip and the cradle, at the top
edge_r = 14;                  // rounding from the cheeks into the rest of the body
groove = 1.5;                 // depth of the finger grooves
grip_x0 = 8;                  // grip set forward of the head's back end (the web of the thumb sits under it)

// Guesses about parts nobody has measured yet.
row_pitch = 25.4;             // ESP32: distance between its two header rows
esp_ledge = 0.6;              // ESP32: how far the ledges reach under the board's long edges
gy521 = [21, 16];             // GY-521 outline; the IMU spot takes anything up to the BNO055's size

// Inset of the outline at height z above the cheek: an arc that leaves the bed at 45 degrees.
function pillow(z, r) = z >= r * sin(45) ? 0 : r * (1 - cos(asin((r * sin(45) - z) / r)));

W = joy_board[0] + 2 + 2 * wall;          // overall width
h = W / 2;                                // one half; the split plane is z = h
head_h = max(joy_depth + 1.6 + joy_solder, button_reach) + 3 + wall;   // 3 mm of wire room over the floor
arm_t = 18;                               // head in front of the button, over the cradle
strut_t = 14;                             // bow under the cradle
esp_z = wall + 5;                         // ESP32 board above the left cheek's outside (room for the USB plug)
esp_top = esp_z + 1.6;                    // the board's plug side
grip_d = devkit[1] + 2 + 2 * (wall + pillow(esp_z - wall, edge_r)) + groove;   // grip, front to back
grip_c = (grip_d - groove) / 2;           // middle of the grip's inside
u_joy = joy_board[1] / 2 + 9.5;           // board corners clear the rounded back of the head
btn_end = face_buttons > 0 ? btn_first + (face_buttons - 1) * btn_pitch + button_body / 2 : joy_board[1] / 2;
x_step = u_joy + btn_end + 3;             // where the head steps down to the arm

// ---- Battery cradle (its own frame: x across, y up, z from its back toward the front) ---------
cb = 3.4; cs = 2.6; ct = 3.6;             // back, side, top and bottom walls
hold = [battery[1] + 0.6, battery[0] + 0.6];   // pocket for the holder: across, up
w_h = cb + battery[2] + 0.4;              // the holder's front face
w_p = w_h + 2.2;                          // the cover's inner face, above the snap lips
cov_in = 1.2;                             // how far the cover reaches into its grooves
cradle = [hold[0] + 2 * cs, hold[1] + 2 * ct, w_p + 2.4 + 1.2];
gx = max(x_step + 8, grip_x0 + grip_d * cos(lean) + finger_room);   // cradle's back face
ys = -arm_t - cradle[1] - 0.2;            // cradle's seat on the bow
head_len = gx + cradle[2] + 10;
bow_end = gx + cradle[2] + 9;
rail = [28, 8, 10, 4];                    // cradle rails: length across, root, tip, height
lead_ch = 1.8;                            // lead channels and exits: depth into the cradle's back wall, behind the holder

// ---- Stations down the grip, measured from the thumb face along the grip ----------------------
s0 = (head_h - grip_d * sin(lean)) / cos(lean);     // where the head's underside meets the grip
s_fsr = s0 + 8 + fsr_d / 2;
s_imu = s0 + 16;                          // IMU's top end; clear of the joystick's rear screw
s_esp = s_imu + imu[0] + 4.3;             // ESP32's top end; its stop is also the IMU's end fence
s_end = s_esp + devkit[0];                // ESP32's USB end
grip_len = s_end + 14 + wall;

// IMU spot on the left cheek: non-header long edge to the back, header edge (and plugs) to the front.
imu_x0 = grip_c - imu[1] / 2;
imu_z = wall + 2;                         // on a 2 mm pad, so solder joints under the header edge hang free
pad_w = 10;                               // pad and fences stay under the half away from the header
imu_boss = [imu_x0 + 5, s_imu - 4.5];

// Divider across the grip, in both halves, between the IMU and joystick plugs above and the ESP32 below.
div_t = 1.4;
div_s = s_esp - 2.6;                      // its upper face
div_gap = [14, 8];                        // wire window: along the divider, and across the split plane

module in_grip() translate([grip_x0, 0]) rotate([0, 0, -lean]) children();
function g(x, s) = [grip_x0 + x * cos(lean) - s * sin(lean), -x * sin(lean) - s * cos(lean)];
function to_grip(p) = [(p[0] - grip_x0) * cos(lean) - p[1] * sin(lean), -((p[0] - grip_x0) * sin(lean) + p[1] * cos(lean))];   // [x, s]
toe = g(grip_d - 9, grip_len - 9);
seat = [gx + 2, ys - strut_t / 2];
pillars = [[head_len - 6, -arm_t + 6], g(grip_d - wall - 5.5, s0 + 6), g(grip_d - wall - 6, grip_len - wall - 5.5), [bow_end - 7, ys - strut_t / 2]];

echo(str("D ergo: ", W, " wide, ", head_len, " long; grip ", W, " x ", grip_d, ", ", grip_len - s0, " below the head; cradle ", cradle));

// ---- Checks: nothing sits in a plug's space, on a header row, in the USB plug's way or on a wire path
front_in = grip_d - groove - wall - pillow(0, edge_r);    // grip's inside front wall at the cheek
hook_x = [7, 10.8];                                        // snap hooks, distance from the board's center line
stop_x = 7;                                                // wedge stop's half width
row_clear = row_pitch / 2 - 1.27 - 0.3;                    // free strip between the two header rows, half width
// The joystick's plugs: a box under its header (the board's wrist-side edge), plug_len deep, 14 wide
// across the split plane.
jp_x = [u_joy - joy_board[1] / 2, u_joy - joy_board[1] / 2 + plug_t];
jp_y = [-(joy_depth + 1.6), -(joy_depth + 1.6 + plug_len)];
assert(to_grip([jp_x[0], jp_y[0]])[0] >= wall + 0.5, "joystick plugs hit the grip's back wall");
assert(to_grip([jp_x[0], jp_y[1]])[1] + 2 <= s_esp - 4, "joystick plugs reach the ESP32's stop");
assert(to_grip([jp_x[1], jp_y[1]])[0] + 2 <= imu_x0 + gy521[1] - 2.6, "joystick plugs reach the IMU's plugs");
assert(imu_z + 1.6 + 2.5 + 3 <= h - 7, "joystick plugs reach the IMU's clamp and screw");
assert(jp_x[1] < gx, "joystick plugs reach the cradle");
// ESP32: guides touch only the board's edges, between the header rows at the ends.
assert(esp_top + devkit_h - 4.6 <= W - wall, "ESP32 with its plugs is taller than the body is wide");
assert(esp_ledge <= (devkit[1] - row_pitch) / 2 - 0.8, "ESP32 ledges reach the header pins' solder joints");
assert(stop_x <= row_clear && hook_x[1] <= row_clear, "ESP32 stop or hooks sit on a header row");
assert(hook_x[0] >= usb_slot[0] / 2 + 1, "ESP32 hooks are in the USB plug's way");
// IMU: pad, fences and clamp stay off the header edge of either board; plugs fit across the body.
assert(pad_w + 1 <= gy521[1] - 2.6, "IMU pad or clamp reaches the GY-521's header");
assert(imu_z + 1.6 + plug_len <= W - wall - 4 - 1, "IMU plugs reach the wire anchor on the right cheek");
assert(imu_x0 + imu[1] + 1 <= front_in, "IMU does not fit between the grip's walls");
assert(front_in - (imu_x0 + imu[1]) >= 1 && grip_d - groove - wall - (imu_x0 + imu[1]) >= 5, "no path for the FSR tail past the IMU's plugs");
// Divider: clear of every plug and board on both sides, with a window big enough for the wires.
assert(div_t >= 1.2 && div_t <= 1.6, "divider should be 1.2 to 1.6 mm");
assert(to_grip([jp_x[0], jp_y[1]])[1] + 1 <= div_s, "divider is in the joystick plugs' space");
assert(s_imu + imu[0] + 0.5 <= div_s, "divider is in the IMU's or its plugs' space");
assert(div_s + div_t + 0.5 <= s_esp, "divider touches the ESP32");
assert(div_gap[0] >= 10 && div_gap[1] >= 6, "divider's wire window is too small");
// Battery: lead exits stay behind the holder, so the walls in front of its terminals are solid.
assert(cb - lead_ch >= 1.2, "cradle's back is too thin under the lead channels");
// Wire anchors in the grip keep clear of the USB plug.
assert(10.5 + 1 <= grip_c - usb_slot[0] / 2, "heel wire anchor is in the USB plug's way");

// ---- Side profile -------------------------------------------------------------------------------
module grip2d() in_grip() difference() {
  hull() {
    translate([0, -40]) square([grip_d, 40]);
    translate([5, -(s0 + 50)]) scale([1, 3]) circle(r = 11);            // palm swell
    translate([10, -(grip_len - 9)]) circle(r = 12);                    // heel
    translate([grip_d - 9, -(grip_len - 9)]) circle(r = 9);
  }
  for (i = [1 : 3]) translate([grip_d + 30 - groove, -(s_fsr + 22 * i)]) circle(r = 30, $fn = 160);   // fingers
}
module head2d() {
  hull() {
    translate([7, -10]) circle(r = 10);
    translate([10, -head_h]) square([x_step - 10, head_h]);
  }
  hull() {                                                              // arm, sloping down to the nose
    translate([x_step - 1, -arm_t]) square([1, arm_t]);
    translate([head_len - 6, -arm_t + 6]) circle(r = 6);
  }
}
module bow2d() {
  mid = (toe + seat) / 2 - [0, 4];
  hull() { translate(toe) circle(d = strut_t); translate(mid) circle(d = strut_t); }
  hull() { translate(mid) circle(d = strut_t); translate(seat) circle(d = strut_t); }
  translate([gx - 5, ys - strut_t]) square([bow_end - strut_t / 2 - gx + 5, strut_t]);
  translate([bow_end - strut_t / 2, ys - strut_t / 2]) circle(d = strut_t);
}
module profile() offset(r = 5) offset(delta = -5) offset(r = -7) offset(delta = 7) { head2d(); grip2d(); bow2d(); }

module pillow_extrude(ht, r, extra = 0, step = 0.2) {
  n = ceil(ht / step);
  for (i = [0 : n - 1]) translate([0, 0, i * ht / n])
    linear_extrude(ht / n + (i < n - 1 ? 0.01 : 0)) offset(r = -(extra + pillow((i + 0.5) * ht / n, r))) children();
}
module outer() pillow_extrude(h, edge_r) profile();

// Thumb layout frame on the top face, centered on the split plane.
module thumb_frame() multmatrix([[0, -1, 0, u_joy], [0, 0, -1, 0], [1, 0, 0, h]]) children();
// Notch a cradle rail slides into: at the arm (dir = 1) or at the bow (dir = -1).
module rail_slot(y, dir) translate([0, 0, h - rail[0] / 2 - 0.5]) linear_extrude(rail[0])
  polygon([[gx - fit, y - dir * 0.01], [gx + rail[1] + fit, y - dir * 0.01],
           [gx + rail[2] + fit, y + dir * (rail[3] + fit)], [gx - fit, y + dir * (rail[3] + fit)]]);
// A shape drawn in (s, z), s down the grip and z up from the cheek, made wd wide from x on.
module grip_section(x, wd, pts) translate([x, 0, 0]) rotate([90, 0, 90]) linear_extrude(wd) polygon([for (p = pts) [-p[0], p[1]]]);
// Zip-tie anchor on the cheek: a small bridge a tie threads under. Long side along x unless turned.
module tie(p, turn = 0) translate([p[0], p[1], 0]) rotate([0, 0, turn]) difference() {
  translate([-3, -1.5, 0]) cube([6, 3, wall + 4]);
  translate([-1.6, -2, wall + 0.8]) cube([3.2, 4, 1.6]);
}

// Left half only: the ESP32's seat and the IMU's.
module left_fittings() in_grip() {
  // ESP32: a ledge under each long edge, a rail beside it, from just below the top to just above the USB end.
  for (sx = [-1, 1]) translate([grip_c + sx * (devkit[1] / 2 + 0.3), -s_end + 3, 0]) {
    translate([sx < 0 ? -4 : 0, 0, 0]) cube([4, devkit[0] - 6, esp_top + 2.5]);
    translate([sx < 0 ? 0 : -0.3 - esp_ledge, 0, 0]) cube([0.3 + esp_ledge, devkit[0] - 6, esp_z]);
  }
  // Wedge stop over the top end, between the header rows; its upper face is the IMU's end fence.
  grip_section(grip_c - stop_x, 2 * stop_x, [[s_esp - 4, 0], [s_esp - 0.3, 0], [s_esp - 0.3, esp_top + 0.2],
                                               [s_esp + 2.2, esp_top + 2.7], [s_esp - 4, esp_top + 2.7]]);
  // Two snap hooks over the USB end, either side of the USB plug.
  for (sx = [-1, 1]) grip_section(grip_c + (sx < 0 ? -hook_x[1] : hook_x[0]), hook_x[1] - hook_x[0],
    [[s_end + 0.3, 0], [s_end + 1.9, 0], [s_end + 1.9, esp_top + 2.2], [s_end + 0.3, esp_top + 2.2], [s_end - 0.6, esp_top + 1.1], [s_end + 0.3, esp_top + 0.2]]);
  // IMU: pad, back fence, and the boss for the clamp screw.
  translate([imu_x0, -(s_imu + imu[0]), 0]) cube([pad_w, imu[0], imu_z]);
  translate([imu_x0 - 4, -(s_imu + imu[0]), 0]) cube([3.8, imu[0], imu_z + 2.6]);
  translate([imu_boss[0], -imu_boss[1], 0]) cylinder(d = 8, h = imu_z + 1.6);
}

// One half, cheek on the bed (z = 0), split plane up (z = h).
// The left half takes the screw heads, the ESP32 and the IMU; the right half the threads.
module half(right = false) {
  difference() {
    union() {
      difference() {
        outer();
        translate([0, 0, wall]) pillow_extrude(h, edge_r, extra = wall) profile();
      }
      intersection() {
        outer();
        union() {
          // Ribs the joystick board screws to.
          for (du = [-1, 1]) translate([u_joy + du * joy_post[1] / 2 - 2.5, -joy_depth, 0]) cube([5, joy_depth - 1, h - joy_post[0] / 2 + 3.5]);
          for (p = pillars) translate([p[0], p[1], 0]) cylinder(d = right ? 7 : 10, h = h);
          // Solid around the rail slots.
          translate([gx - 3, -arm_t, 0]) cube([17, 7.5, h]);
          translate([gx - 3, ys - 7.5, 0]) cube([17, 7.5, h]);
          // Wire anchors: head and arm in both halves, the grip's ends where each half is free.
          tie([u_joy + joy_board[1] / 2 + 4.5, -15]);
          tie([gx - 8, -arm_t / 2 - 0.5]);
          if (right) in_grip() { tie([grip_c, -(s_end + 8)]); tie([13, -(s_imu + 8)], 90); }
          else in_grip() tie([9, -(s_end + 8)], 90);
          if (!right) left_fittings();
          // Divider, with half of the wire window.
          in_grip() difference() {
            translate([0, -(div_s + div_t), 0]) cube([grip_d, div_t, h]);
            translate([grip_c - div_gap[0] / 2, -(div_s + div_t) - 1, h - div_gap[1] / 2]) cube([div_gap[0], div_t + 2, div_gap[1]]);
          }
        }
      }
    }
    thumb_frame() thumb_cuts(face_buttons, inline = true);
    for (du = [-1, 1]) translate([u_joy + du * joy_post[1] / 2, -joy_depth - 1, h - joy_post[0] / 2]) rotate([-90, 0, 0]) cylinder(d = joy_post_bore, h = 10);
    for (p = pillars) translate([p[0], p[1], 0]) {
      if (right) translate([0, 0, h - 12]) cylinder(d = joy_post_bore, h = 13);
      else { translate([0, 0, -1]) cylinder(d = 3.4, h = h + 2); translate([0, 0, -1]) cylinder(d = 6.5, h = h - 5); }
    }
    in_grip() {
      // FSR pocket (0.8 mm floor) and the slit for its tail.
      translate([grip_d + 1, -s_fsr, h]) rotate([0, -90, 0]) cylinder(d = fsr_d + 0.6, h = 1 + wall - 0.8);
      translate([grip_d - wall - 1, -s_fsr - fsr_d / 2 - 1.2, h - fsr_tail_w / 2 - 0.3]) cube([wall + 2, 1.6, fsr_tail_w + 0.6]);
      if (!right) {
        // USB slot through the base, beside the left cheek where the board lies.
        translate([grip_c - usb_slot[0] / 2, -grip_len - 25, esp_z - 1.5 - usb_slot[1] / 2]) cube([usb_slot[0], 25 + grip_len - s_end - 2.5, usb_slot[1]]);
        translate([imu_boss[0], -imu_boss[1], 1]) cylinder(d = joy_post_bore, h = imu_z + 2);
      }
    }
    rail_slot(-arm_t, 1);
    rail_slot(ys, -1);
    // Battery leads: up into the arm and down into the bow.
    translate([gx + cb - lead_ch - 0.2, -arm_t - 1, h - 3.2]) cube([lead_ch + 0.4, 10, 4]);
    translate([gx + cb - lead_ch - 0.2, ys - 9, h - 3.2]) cube([lead_ch + 0.4, 10, 4]);
  }
}

// Battery cradle: back on the bed (z = 0), open toward +z (the controller's front).
// The +x side wall is low: the cover slides in over it and stops against the -x wall.
module cradle() {
  difference() {
    union() {
      pillow_extrude(cradle[2], 6) translate([-cradle[0] / 2, 0]) offset(r = 5) offset(delta = -5) square([cradle[0], cradle[1]]);
      // Rails on the top and bottom ends, flush with the back.
      for (e = [[cradle[1] - 0.01, 1], [0.01, -1]]) hull() {
        translate([-rail[0] / 2 + 0.5, e[0], 0]) cube([rail[0] - 1, 0.01, rail[1]]);
        translate([-rail[0] / 2 + 0.5, e[0] + e[1] * rail[3], 0]) cube([rail[0] - 1, 0.01, rail[2]]);
      }
    }
    translate([-hold[0] / 2, ct, cb]) cube([hold[0], hold[1], cradle[2]]);
    translate([hold[0] / 2 - 0.01, ct - cov_in, w_h + 2]) cube([cs + 1, hold[1] + 2 * cov_in, cradle[2]]);
    // Grooves for the cover in the top and bottom walls; the overhanging side is a 45 degree slope.
    for (e = [[ct, -1], [ct + hold[1], 1]]) translate([-hold[0] / 2, 0, 0]) rotate([90, 0, 90]) linear_extrude(cradle[0])
      polygon([[e[0] - e[1] * 0.01, w_p - 0.1], [e[0] + e[1] * cov_in, w_p - 0.1], [e[0] + e[1] * cov_in, w_p + 1.2], [e[0] - e[1] * 0.01, w_p + 2.4]]);
    // Channels behind the holder, so leads leaving any edge reach the exits in the top and bottom.
    translate([-3, -rail[3] - 1, cb - lead_ch]) cube([6, cradle[1] + 2 * rail[3] + 2, lead_ch + 0.01]);
    translate([-hold[0] / 2, cradle[1] / 2 - 3, cb - lead_ch]) cube([hold[0], 6, lead_ch + 0.01]);
  }
  // Snap lips on both side walls: the holder clicks in under them.
  for (sx = [-1, 1]) translate([0, cradle[1] / 2 + 10, 0]) rotate([90, 0, 0]) linear_extrude(20)
    polygon([[sx * (hold[0] / 2 + 0.1), w_h + 0.2], [sx * (hold[0] / 2 - 0.6), w_h + 0.9], [sx * (hold[0] / 2 + 0.1), w_h + 2]]);
  // Detent the cover clicks over.
  translate([hold[0] / 2 + 0.8, cradle[1] / 2 - 5, w_h + 1.99]) cube([1, 10, 0.5]);
}
// Cover: wide face down (toward the cells), long edges sloped to match the grooves.
module cover() {
  y0 = ct - cov_in + 0.2;
  wd = hold[1] + 2 * cov_in - 0.4;
  len = hold[0] / 2 - 0.2 + cradle[0] / 2;
  difference() {
    hull() {
      translate([-hold[0] / 2 + 0.2, y0, 0]) cube([len, wd, 1]);
      translate([-hold[0] / 2 + 0.2, y0 + 1.2, 2.19]) cube([len, wd - 2.4, 0.01]);
    }
    translate([hold[0] / 2 + 0.6, cradle[1] / 2 - 5.5, -0.01]) cube([1.4, 11, 0.6]);
  }
}
// IMU clamp: the slot lets it reach the end of either board.
module imu_clamp() difference() {
  translate([-4, -4, 0]) cube([8, 15.5, 2.5]);
  hull() { translate([0, 0, -1]) cylinder(d = 3.4, h = 5); translate([0, 5, -1]) cylinder(d = 3.4, h = 5); }
}
// ---- Fit test: regions cut out of the real parts, so what fits here fits the full print --------
fit_z = 1;                                // the cheek is thinned to 1.2 mm to save time
// Left half: IMU pad, fence and boss, the divider's foot, and the ESP32 seat's two ends (stop,
// hooks, rails, ledges) joined by a strip of cheek, so the board's real length is tested.
module fit_esp() translate([0, 0, -fit_z]) intersection() {
  half();
  in_grip() {
    translate([grip_c - 16.5, -(s_esp + 7), fit_z]) cube([33, s_esp + 7 - (s_imu - 9), esp_top + 3 - fit_z]);
    translate([grip_c - 16.5, -(s_end + 2.5), fit_z]) cube([33, 9.5, esp_top + 3 - fit_z]);
    translate([grip_c - 5, -(s_end - 6), fit_z]) cube([10, s_end - s_esp - 12, wall - fit_z]);
  }
}
// Cradle: a band across both snap lips and the detent, and the +x ends of both cover grooves,
// joined by a strip of the back. Push the holder's edge into the band; slide fit_cover in the grooves.
fit_x = hold[0] / 2 - 5;
module fit_cradle() translate([0, 0, -0.6]) intersection() {
  cradle();
  translate([0, 0, 0.6]) {
    translate([-50, cradle[1] / 2 + 3.5, 0]) cube([100, 6.5, 50]);
    translate([fit_x, -0.1, 0]) cube([50, ct + 4.1, 50]);
    translate([fit_x, ct + hold[1] - 4, 0]) cube([50, ct + 4.1, 50]);
    translate([fit_x, 0, 0]) cube([5, cradle[1], cb - 0.6]);
  }
}
module fit_cover() intersection() { cover(); translate([fit_x, 0, -1]) cube([50, 100, 5]); }
module fit_test() {
  fit_esp();
  translate([head_len - 25, -cradle[1] - 10, 0]) fit_cradle();
  translate([head_len, -cradle[1] - 10, 0]) fit_cover();
  translate([head_len - 40, -cradle[1] - 5, 0]) imu_clamp();
}
module cradle_frame() multmatrix([[0, 0, 1, gx], [0, 1, 0, ys + 0.1], [-1, 0, 0, h]]) children();

module parts() {
  thumb_frame() p_thumb(face_buttons, inline = true);
  in_grip() {
    multmatrix([[-1, 0, 0, grip_c], [0, -1, 0, -s_esp], [0, 0, 1, esp_z]]) p_devkit();
    multmatrix([[0, 0, 1, grip_d - 1.4], [0, 1, 0, -s_fsr], [-1, 0, 0, h]]) p_fsr();
    translate([imu_x0 + imu[1] / 2, -(s_imu + imu[0] / 2), imu_z]) rotate([0, 0, -90]) p_imu(plugs = true);
    color("steelblue") translate([imu_boss[0], -imu_boss[1] - 0.5, imu_z + 1.6]) mirror([0, 1, 0]) imu_clamp();
  }
  multmatrix([[0, 0, 1, gx + cb], [1, 0, 0, ys + 0.1 + ct + 0.3], [0, 1, 0, h - battery[1] / 2]]) p_battery();
}

module assembly() rotate([90, 0, 0]) translate([0, 0, -h]) {
  color("tan") half();
  if (!cut) color("burlywood") translate([0, 0, 2 * h]) mirror([0, 0, 1]) half(right = true);
  color("slategray") difference() {
    cradle_frame() cradle();
    if (cut) translate([-500, -500, h]) cube(1000);
  }
  color("steelblue") difference() {
    cradle_frame() translate([0, 0, w_p]) cover();
    if (cut) translate([-500, -500, h]) cube(1000);
  }
  parts();
}

if (part == "assembly") assembly();
else if (part == "half_l") half();
else if (part == "half_r") mirror([0, 1, 0]) half(right = true);
else if (part == "cradle") cradle();
else if (part == "cover") cover();
else if (part == "imu_clamp") imu_clamp();
else if (part == "fit_test") fit_test();
else if (part == "fit_esp") fit_esp();
else if (part == "fit_cradle") fit_cradle();
else if (part == "fit_cover") fit_cover();
else if (part == "print") {
  color("tan") half();
  color("burlywood") translate([0, 24, 0]) mirror([0, 1, 0]) half(right = true);
  color("slategray") translate([head_len + 50, -cradle[1], 0]) cradle();
  color("steelblue") translate([head_len + 50, 12, 0]) cover();
  color("steelblue") translate([head_len + 10, -60, 0]) imu_clamp();
}
else assert(false, str("unknown part: ", part));
