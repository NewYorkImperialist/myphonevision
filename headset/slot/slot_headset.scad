// myphonevision "slot" headset: the Carson TriView TV-36 magnifiers stay whole.
// Each eye's magnifier (three lens frames swung out and stacked, the 8.5x setup
// in the manual) drops into a well from the top; the case stays outside, above
// the headset. Tested with OpenSCAD 2026 (snapshot, manifold backend).
//
// Print one file at a time, fit_test first.
//   fit_test    lens-frame cradle + phone/USB end slice (print first, ~20 min)
//   body        face plate, lens wells, viewing chamber, phone pocket; face plate down
//   back        screwed clamp plate behind the phone (camera window, vents,
//               foam-pad recesses, cable tongue); inner face up
//   face_rim    foam seat for the face gasket; body side down
//   keeper      holds one side of a magnifier in its well; print 4, on end
//   shims       focus shim set for one eye (U shaped); print 2 sets
//   foam_face_2d / foam_phone_2d   flat patterns (export as .svg / .dxf)
//   assembly / exploded / cutaway / retention / layout   views, don't print
//
// Units mm. X along the phone's long edge (camera end at -X, USB at +X), Y up,
// Z from the face plate (z = 0) toward the phone. Lens axes at (+-ipd/2, 0).

part = "assembly";

// ---- Magnifier stand-in: Carson TriView TV-36 ------------------------------
// [manual] = printed in TV-36_guide_EN.pdf. [measured] = calipers on the real part. [UNMEASURED] = placeholder read off
// the manual's pictures; measure with calipers (or trace the outline) and pass
// with -D before printing anything but fit_test.
mag_glass_d  = 30.0;    // [manual] lens diameter
mag_case_t   = 27.9;    // [manual] 1.1 in: thickness, lids included
mag_case_w   = 40.6;    // [manual] 1.6 in: widest point of the case
mag_long     = 109.2;   // [manual] 4.3 in: ASSUMED to be the opened length (lenses swung out 180 deg)
mag_frame_od = 38.75;   // [measured, Nafis's calipers, issue #4] outside diameter of a lens frame's round rim
mag_stack_t  = 21.09;   // [measured, Nafis's calipers, issue #4] three stacked frames, flat face to flat face
mag_lid_t    = (mag_case_t - mag_stack_t) / 2;  // [UNMEASURED] one case lid; placeholder = what the manual's 27.9 leaves
mag_tab_len  = 3.0;     // [UNMEASURED] thumb tab: how far it sticks out past the rim
mag_tab_w    = 6.0;     // [UNMEASURED] thumb tab width
mag_boss_d   = 10.0;    // [UNMEASURED] diameter of the pivot boss
// [UNMEASURED] pivot centre to lens centre. Placeholder: half the opened length,
// if the lens nests concentric with the case's round end when folded.
mag_pivot    = (mag_long - mag_frame_od / 2 - mag_tab_len - mag_case_w / 2) / 2;
mag_waist_w  = 20.0;    // [UNMEASURED] widest thing (neck, pivot boss, case nose) between
                        //   keeper_y0 above the lens centre and the headset's top
mag_fence_w  = 30.0;    // [UNMEASURED] case width where the fence fins touch it (fence_y above the lens centre)
mag_glass_recess = 1.0; // [UNMEASURED] glass below the frame's flat face
mag_case_angle = 180;   // case swung straight up (view only)

// ---- Optics ----------------------------------------------------------------
ipd = 63.0;
focus_min    = 14.0;    // [UNMEASURED] rear frame face to screen with every shim in front
shim_set     = [1, 2, 4, 9];   // any subset sums to 0..16 in 1 mm steps
focus_travel = 16.0;    // = sum(shim_set)
shims_front  = 6;       // shown in the views: mm of shims on the eye side
eye_recess   = 10.0;    // [estimate] cornea behind the brow/cheek plane the foam sits on

// ---- Foam ------------------------------------------------------------------
foam_t   = 10.0;        // [UNMEASURED] face foam, relaxed
foam_c   = 6.0;         // [UNMEASURED] face foam, squeezed by the strap
foam_w   = 12.0;        // width of the face-foam band
pfoam_t  = 3.0;         // [UNMEASURED] phone pad foam, relaxed
pfoam_c  = 2.0;         // [UNMEASURED] phone pad foam, compressed
pad_recess = 0.5;       // depth of the pad recesses

// ---- Phone: iPhone 16 Pro (values from headset.scad, 5003bd8 / 9736821) ----
phone_w = 149.6;
phone_h = 71.5;
phone_t = 8.95;         // measured
cam_bump = 3.65;        // 12.6 total at the bump - phone_t
cam_from_top = 3;
cam_len = 40.5;         // 3..43.5 mm from the top
cam_span = phone_h + 0.6;   // [UNMEASURED] bump size across the phone; default = full width, never blocks ARKit
screen_w = 144.8;
screen_h = 66.7;
btn_free = 18;          // [UNMEASURED] length at each end of the long edges with no button
usb_w = 13.0;           // [UNMEASURED] plug overmold width + clearance
usb_h = 8.0;            // [UNMEASURED] plug overmold thickness + clearance
usb_len = 25.0;         // [UNMEASURED] overmold length, phone edge to where the cable flexes
cable_d = 4.0;          // [UNMEASURED] cable diameter

// ---- Shell -----------------------------------------------------------------
wall = 1.6;
wall_u = 2.0;           // well walls
face_t = 1.6;
slot_fit = 0.6;         // well width minus frame OD
stop_h = 1.5;           // ledge the frame faces sit on
ledge_h = 5.0;
plate_t = 2.0;
rim_t = 2.0;
lip_w = 1.2;
lip_h = 1.0;
keeper_t = 2.4;
case_fence = true;
fence_h = 18;
strap_slot = [4, 32];   // same as headset.scad (issue #9)
ear_t = 10;
top_strap = true;
nose_w = 38;
nose_h = 28;
nose_z0 = 4;
nose_len = 28;
screw_d = 2.8;          // M3 self-tapping into PLA
screw_clear = 3.4;
boss_y = 24;
bed = 220;
$fn = 72;

// ---- Derived ---------------------------------------------------------------
frame_r = mag_frame_od / 2;
slot_r = frame_r + slot_fit / 2;
frame_t = mag_stack_t / 3;
ap_d = mag_glass_d + 3;
lid_y = frame_r - 2;                     // above this the wells are open for the case lids
keeper_y0 = frame_r * 0.5;
z_slot0 = face_t + mag_lid_t + 0.4;
slot_len = mag_stack_t + focus_travel + 0.4;
z_slot1 = z_slot0 + slot_len;
z_stop = z_slot1 + stop_h + 1.0;
z_s = z_slot0 + focus_travel + mag_stack_t + focus_min;   // screen plane
z_rim = z_s + phone_t + pfoam_c - pad_recess;             // back plate's inner face
z_port = z_s + phone_t / 2;
// Pocket: datum pads on -Y (gravity side) and the +X end wall; foam on +Y and -X.
px0 = -(phone_w / 2 + pfoam_c);
px1 = phone_w / 2 + 0.2;
btn_relief = 1.0;
py0 = -(phone_h / 2 + 0.2 + btn_relief);
py1 = phone_h / 2 + pfoam_c;
ox0 = px0 - wall; ox1 = px1 + wall; oy0 = py0 - wall; oy1 = py1 + wall;
rail_w = 8;
kh = [face_t + 7, z_stop - 7];           // keeper screw positions along z
tongue_len = usb_len + 14;
saddle_h = (z_rim - z_port) - cable_d / 2;
rim_holes = [[-60, -30], [60, -30], [-66, 30], [66, 30]];

assert(focus_travel == shim_set[0] + shim_set[1] + shim_set[2] + shim_set[3]);
assert(ipd - 2 * (slot_r + wall_u + rail_w) > 2, "wells and rails don't fit between the eyes");
assert(z_s - ledge_h > z_stop, "screen too close to the wells: raise focus_min");
assert(mag_pivot - mag_boss_d / 2 > keeper_y0, "pivot too close to the lens for the keepers");
assert(ap_d < mag_frame_od - 2, "frame rim too narrow to seat");
echo(str("rear frame face to screen: ", focus_min, " .. ", focus_min + focus_travel, " mm"));
echo(str("eye relief (cornea to first glass) with ", shims_front, " mm of front shims: ",
         eye_recess + foam_c + rim_t + z_slot0 + shims_front + mag_glass_recess, " mm"));
echo(str("body ", ox1 - ox0, " x ", oy1 - oy0, " x ", z_rim, " mm"));

// ---- 2D profiles -----------------------------------------------------------
// Well section, lens centre at the origin. The frame's rim rests on two flat
// 45-degree lands (a V block: centres any rim diameter), with room under it
// for the thumb tabs; straight walls above.
module seat2d(r, top) {
  b = min(r * sqrt(2), r + mag_tab_len + 1);
  c = r * sqrt(2) - b;
  polygon([[-r, top], [-r, -r * (sqrt(2) - 1)], [-c, -b], [c, -b], [r, -r * (sqrt(2) - 1)], [r, top]]);
}
module box2d(inset = 0)
  translate([ox0 + inset, oy0 + inset]) square([ox1 - ox0 - 2 * inset, oy1 - oy0 - 2 * inset]);
module nose2d()   // origin: bottom centre
  hull() {
    translate([-nose_w / 2, -1]) square([nose_w, 1]);
    translate([0, nose_h - nose_w / 3]) circle(r = nose_w * 0.33);
  }
module window2d() square([screen_w + 1, screen_h + 1], center = true);

// Face outline: the body's front, rounded, with the nose arch.
module face2d() difference() {
  offset(r = 6) offset(delta = -6) box2d();
  translate([0, oy0]) nose2d();
}
module rim_ring2d() difference() {
  face2d();
  offset(delta = -(foam_w + 2 * lip_w)) face2d();
}
// Foam band: sits between the lips, and overhangs the nose arch by 2 mm so no
// printed edge meets the nose.
module foam_face2d() difference() {
  union() {
    offset(delta = -lip_w - 0.3) face2d();
    intersection() { offset(delta = 2) face2d(); translate([0, oy0]) offset(delta = lip_w + 2) nose2d(); box2d(lip_w + 0.3); }
  }
  offset(delta = -(foam_w + lip_w) + 0.3) face2d();
  translate([0, oy0]) offset(delta = -2) nose2d();
}

// Phone pads: [x, y, w, h] on the back plate; side and end pads on the walls.
back_pads = [[-12, 20, 20, 20], [-12, -20, 20, 20], [52, 20, 20, 20], [52, -20, 20, 20]];
side_pad = [25, phone_t - 1.5];
end_pad = [30, phone_t - 1.5];
side_pad_x = [-(phone_w / 2 - 22), phone_w / 2 - 22];
module foam_phone2d() {
  for (i = [0 : 3]) translate([i * 24, 0]) square([back_pads[i][2] - 0.6, back_pads[i][3] - 0.6]);
  for (i = [0 : 1]) translate([i * 29, 26]) square(side_pad - [0.6, 0]);
  translate([62, 26]) square(end_pad - [0.6, 0]);
}

// ---- Body ------------------------------------------------------------------
module nose_solid(grow, s, extra) translate([0, oy0, 0]) {
  translate([0, 0, -1]) linear_extrude(nose_z0 + 1.01) offset(delta = grow) nose2d();
  translate([0, 0, nose_z0]) linear_extrude(nose_len, scale = s) offset(delta = grow) nose2d();
  if (extra > 0) translate([0, 0, nose_z0 + nose_len - 0.01]) linear_extrude(extra) scale(s) offset(delta = grow) nose2d();
}

module well_cut() {
  translate([0, 0, -1]) cylinder(d = ap_d, h = z_stop + 2);
  // Room for the case lids above the frames, front and back.
  translate([0, 0, face_t]) linear_extrude(z_stop - face_t + 0.01)
    intersection() { seat2d(slot_r, oy1 + 5); translate([-50, lid_y]) square([100, 100]); }
  translate([0, 0, z_slot0]) linear_extrude(slot_len) seat2d(slot_r, oy1 + 5);
  hull() {   // 45-degree rear stop: prints without support
    translate([0, 0, z_slot1 - 0.01]) linear_extrude(0.01) seat2d(slot_r, oy1 + 5);
    translate([0, 0, z_slot1 + stop_h]) linear_extrude(0.01) offset(delta = -stop_h) seat2d(slot_r, oy1 + 5);
  }
  translate([0, 0, z_slot1]) linear_extrude(z_stop - z_slot1 + 1) offset(delta = -stop_h) seat2d(slot_r, oy1 + 5);
  // The roof closes behind the well with a pointed end, not a bridge.
  hull() {
    translate([-slot_r, oy1 - wall - 1, face_t]) cube([2 * slot_r, wall + 2, z_stop - face_t]);
    translate([-0.1, oy1 - wall - 1, z_stop + slot_r]) cube([0.2, wall + 2, 0.1]);
  }
  for (s = [-1, 1], z = kh)
    translate([s * (slot_r + wall_u + rail_w / 2), oy1 + 1, z]) rotate([90, 0, 0]) cylinder(d = screw_d, h = rail_w + 1);
}

module well_block() {
  linear_extrude(z_stop) offset(delta = wall_u) seat2d(slot_r, oy1);
  for (s = [-1, 1]) translate([s * (slot_r + wall_u + rail_w / 2) - rail_w / 2 - (s > 0 ? 0.5 : -0.5), oy1 - rail_w, 0])
    cube([rail_w, rail_w, z_stop]);
}

module ledge() difference() {
  translate([0, 0, z_s - ledge_h]) linear_extrude(ledge_h) box2d(wall - 0.01);
  hull() {
    translate([0, 0, z_s - 0.8]) linear_extrude(0.01) window2d();
    translate([0, 0, z_s - ledge_h - 0.01]) linear_extrude(0.01) offset(delta = ledge_h - 0.8) window2d();
  }
  translate([0, 0, z_s - 0.81]) linear_extrude(2) window2d();
}

module boss(sx, sy) {
  x = sx > 0 ? ox1 : ox0 - 7;
  hull() {
    translate([x, sy * boss_y - 4, z_rim - 9]) cube([7, 8, 9]);
    translate([sx > 0 ? ox1 - 0.1 : ox0, sy * boss_y - 4, z_rim - 16]) cube([0.1, 8, 0.1]);
  }
}
function boss_x(sx) = sx > 0 ? ox1 + 3.5 : ox0 - 3.5;

module body() difference() {
  union() {
    difference() {
      linear_extrude(z_rim) box2d();
      translate([0, 0, face_t]) linear_extrude(z_rim) box2d(wall);
    }
    intersection() {
      linear_extrude(z_rim) box2d();
      union() {
        for (s = [-1, 1]) translate([s * ipd / 2, 0, 0]) well_block();
        translate([-0.8, oy0, 0]) cube([1.6, oy1 - oy0, z_s - 0.8]);        // septum
        ledge();
        nose_solid(wall * 1.5, 0.2, 1.2);
        // Datum pads on the -Y wall, at the button-free ends.
        for (x = [px0, px1 - btn_free]) translate([x, py0, z_s]) cube([btn_free, btn_relief, z_rim - z_s]);
        for (p = rim_holes) translate([p[0], p[1], 0]) cylinder(d = 7, h = 8);
      }
    }
    for (sx = [-1, 1]) {
      // Strap ears: same 4 x 32 slot as headset.scad.
      translate([sx > 0 ? ox1 - 1 : ox0 - 13, -(strap_slot[1] + 10) / 2, 0]) cube([14, strap_slot[1] + 10, ear_t]);
      for (sy = [-1, 1]) boss(sx, sy);
    }
  }
  for (s = [-1, 1]) translate([s * ipd / 2, 0, 0]) well_cut();
  nose_solid(0, 0.05, 0);
  for (sx = [-1, 1]) {
    translate([(sx > 0 ? ox1 + 7 : ox0 - 7) - strap_slot[0] / 2, -strap_slot[1] / 2, -1]) cube([strap_slot[0], strap_slot[1], ear_t + 2]);
    for (sy = [-1, 1]) translate([boss_x(sx), sy * boss_y, z_rim - 17]) cylinder(d = screw_d, h = 18);
  }
  for (p = rim_holes) translate([p[0], p[1], -1]) cylinder(d = screw_d, h = 9);
  // USB plug notch, open to the back so the phone drops in with the cable plugged.
  translate([px1 - 1, -usb_w / 2, z_port - usb_h / 2]) cube([wall + 2, usb_w, z_rim]);
  // Foam pad recesses on the +Y wall and the -X end.
  for (x = side_pad_x) translate([x - side_pad[0] / 2, py1 - 0.01, z_s + 0.8]) cube([side_pad[0], pad_recess, z_rim]);
  translate([px0 - pad_recess, -end_pad[0] / 2, z_s + 0.8]) cube([pad_recess + 0.01, end_pad[0], z_rim]);
}

// ---- Keeper: fills the well beside the magnifier's neck, bears on the frames'
// rims, screws to the roof rail. One half; its mirror image is the same part
// flipped end for end.
module kblock(xi) difference() {
  translate([xi, keeper_y0]) square([slot_r - 0.25 - xi, oy1 - keeper_y0]);
  circle(r = frame_r + 0.4);
}
module keeper2d() {
  xi = mag_waist_w / 2 + 0.3;
  difference() {
    kblock(xi);
    offset(delta = -2) kblock(xi);   // hollow: prints as a 2 mm shell
  }
  translate([xi, oy1]) square([slot_r + wall_u + rail_w - xi, keeper_t]);
  if (case_fence) translate([max(xi, mag_fence_w / 2 + 0.3), oy1 + keeper_t - 0.01]) square([2, fence_h]);
}
keeper_len = z_stop - face_t - 0.6;
module keeper() translate([0, 0, face_t + 0.3]) difference() {
  linear_extrude(keeper_len) keeper2d();
  for (z = kh) translate([slot_r + wall_u + rail_w / 2, oy1 + keeper_t + 1, z - face_t - 0.3]) rotate([90, 0, 0]) cylinder(d = screw_clear, h = keeper_t + 2);
}

module shim(t) linear_extrude(t) difference() {
  intersection() { seat2d(slot_r - 0.2, keeper_y0 - 0.5); translate([-50, -50]) square([100, 50 + keeper_y0 - 0.5]); }
  offset(delta = -2.5) seat2d(slot_r - 0.2, 60);
}

// ---- Back plate (modeled as printed: inner face up) -------------------------
module back2d() {
  translate([ox0, oy0 - 2]) square([ox1 - ox0, oy1 - oy0 + 4]);
  for (sx = [-1, 1], sy = [-1, 1]) translate([boss_x(sx) - 4.5, sy * boss_y - 4.5]) square(9);
  translate([ox1 - 1, -11]) square([tongue_len + 1, 22]);
}
cam_x0 = -phone_w / 2 + cam_from_top - 0.3;
sad_x = phone_w / 2 + usb_len + 3;
module back() difference() {
  union() {
    linear_extrude(plate_t) back2d();
    // Lips outside the long walls: stiffen the plate and locate it.
    for (y = [oy1 + 0.4, oy0 - 2]) translate([ox0, y, plate_t - 0.01]) cube([ox1 - ox0, 1.6, 4]);
    for (y = [-11, 9.4]) translate([ox1 + 0.5, y, plate_t - 0.01]) cube([tongue_len - 0.5, 1.6, 3]);
    translate([sad_x, -5.5, plate_t - 0.01]) cube([8, 11, saddle_h + cable_d * 0.35]);   // cable saddle
  }
  translate([cam_x0, -cam_span / 2, -1]) cube([cam_len + 0.6, cam_span, plate_t + 2]);
  for (p = back_pads) translate([p[0] - p[2] / 2, p[1] - p[3] / 2, plate_t - pad_recess]) cube([p[2], p[3], 1]);
  for (x = [-20 : 9 : 62]) translate([x, -8, -1]) cube([3, 16, plate_t + 2]);            // vents
  for (sx = [-1, 1], sy = [-1, 1]) translate([boss_x(sx), sy * boss_y, -1]) cylinder(d = screw_clear, h = plate_t + 2);
  translate([sad_x - 1, 0, plate_t + saddle_h + cable_d / 2]) rotate([0, 90, 0]) cylinder(d = cable_d, h = 10);
  for (y = [-9, 7]) translate([sad_x + 1.5, y, -1]) cube([5, 2, plate_t + 2]);            // zip-tie slots
}

// ---- Face rim (modeled as printed: body side down, foam seat up) ------------
module face_rim() difference() {
  union() {
    linear_extrude(rim_t) rim_ring2d();
    translate([0, 0, rim_t - 0.01]) linear_extrude(lip_h) {
      difference() {   // outer lip, left off around the nose
        face2d(); offset(delta = -lip_w) face2d();
        translate([0, oy0]) offset(delta = lip_w + 1.5) nose2d();
      }
      difference() { offset(delta = -(foam_w + lip_w)) face2d(); offset(delta = -(foam_w + 2 * lip_w)) face2d(); }
    }
    if (top_strap) linear_extrude(rim_t) translate([-(strap_slot[1] + 10) / 2, oy1 - 1]) square([strap_slot[1] + 10, 15]);
  }
  if (top_strap) translate([-strap_slot[1] / 2, oy1 + 6, -1]) cube([strap_slot[1], strap_slot[0], rim_t + 2]);
  for (p = rim_holes) translate([p[0], p[1], -1]) cylinder(d = screw_clear, h = rim_t + 3);
}

// ---- Stand-ins (views only) -------------------------------------------------
module frame2d() {
  hull() { circle(r = frame_r); translate([0, mag_pivot]) circle(d = mag_boss_d); }
  translate([-mag_tab_w / 2, -frame_r - mag_tab_len]) square([mag_tab_w, mag_tab_len + 2]);
}
module case2d() hull() {
  circle(d = mag_boss_d + 4);
  translate([0, mag_pivot]) circle(d = mag_case_w);
}
// Front frame face at z = 0, lens centre at the origin, pivot at +Y.
module magnifier() {
  for (i = [0 : 2]) translate([0, 0, i * frame_t]) {
    color("dimgray") linear_extrude(frame_t - 0.3) difference() { frame2d(); circle(d = mag_glass_d); }
    color("lightcyan", 0.5) translate([0, 0, mag_glass_recess]) cylinder(d = mag_glass_d, h = frame_t - 2 * mag_glass_recess);
  }
  color("slategray") translate([0, mag_pivot, 0]) rotate(mag_case_angle - 180) {
    for (z = [-mag_lid_t, mag_stack_t]) translate([0, 0, z]) linear_extrude(mag_lid_t) case2d();
    translate([0, 0, -mag_lid_t]) cylinder(d = mag_boss_d * 0.6, h = mag_case_t);
  }
}
module phone() {
  color([0.13, 0.13, 0.15]) {
    linear_extrude(phone_t) offset(r = 8) offset(delta = -8) square([phone_w, phone_h], center = true);
    translate([-phone_w / 2 + cam_from_top, phone_h / 2 - 3 - 38, phone_t]) cube([cam_len, 38, cam_bump]);
  }
  color("white") translate([phone_w / 2, 0, phone_t / 2]) {
    translate([0, -(usb_w - 1) / 2, -(usb_h - 1.5) / 2]) cube([usb_len, usb_w - 1, usb_h - 1.5]);
    rotate([0, 90, 0]) cylinder(d = cable_d, h = usb_len + 45);
  }
}
module phone_foam() color("gold") {
  for (p = back_pads) translate([p[0] - p[2] / 2 + 0.3, p[1] - p[3] / 2 + 0.3, z_s + phone_t]) cube([p[2] - 0.6, p[3] - 0.6, pfoam_c]);
  for (x = side_pad_x) translate([x - side_pad[0] / 2 + 0.3, phone_h / 2, z_s + 1]) cube([side_pad[0] - 0.6, pfoam_c, side_pad[1]]);
  translate([px0, -end_pad[0] / 2 + 0.3, z_s + 1]) cube([pfoam_c, end_pad[0] - 0.6, end_pad[1]]);
}

module everything(e = 0) {
  color("tan") body();
  color("lightblue") translate([0, 0, z_rim + plate_t + e * 40]) mirror([0, 0, 1]) back();
  color("salmon") translate([0, 0, -e * 25]) mirror([0, 0, 1]) face_rim();
  color("gold") translate([0, 0, -rim_t - foam_c - e * 45]) linear_extrude(foam_c) foam_face2d();
  translate([0, 0, e * 22]) { translate([0, 0, z_s]) phone(); phone_foam(); }
  for (s = [-1, 1]) translate([s * ipd / 2, e * 75, 0]) {
    translate([0, 0, z_slot0 + shims_front]) magnifier();
    color("orange") {
      translate([0, 0, z_slot0]) shim(shims_front);
      translate([0, 0, z_slot0 + shims_front + mag_stack_t]) shim(focus_travel - shims_front);
    }
    color("seagreen") translate([0, e * 30, 0]) { keeper(); mirror([1, 0, 0]) keeper(); }
  }
}

module fit_test() {
  // Lens-frame cradle: seat, V lands, tab room, aperture (check it is concentric with the glass).
  translate([-ipd / 2 - 26, 0, 0]) intersection() {
    body();
    translate([ipd / 2 - slot_r - wall_u, -slot_r - mag_tab_len - 4, 0]) cube([2 * (slot_r + wall_u), slot_r + mag_tab_len + 12, z_slot0 + 6]);
  }
  // USB end of the phone pocket: ledge, datum pad, foam recess, plug notch, screw bosses.
  translate([-px1 + 25, 0, -(z_s - 2.5)]) intersection() {
    body();
    translate([px1 - 25, oy0 - 1, z_s - 2.5]) cube([40, oy1 - oy0 + 2, z_rim]);
  }
}

module layout() {
  color("white", 0.3) translate([-bed / 2, -bed / 2, -0.6]) cube([bed, bed, 0.5]);
  color("tan") translate([-(ox0 + ox1) / 2, 45, 0]) body();
  color("lightblue") translate([-(ox0 + ox1 + tongue_len) / 2, -48, 0]) back();
  translate([300, 0, 0]) {
    color("white", 0.3) translate([-bed / 2, -bed / 2, -0.6]) cube([bed, bed, 0.5]);
    color("salmon") translate([0, 55, 0]) face_rim();
    color("seagreen") for (i = [0 : 1], j = [0 : 1]) translate([62 + i * 24, -28 - j * 56 - oy1, -face_t - 0.3]) keeper();
    color("orange") for (e = [0, 1], i = [0 : 3]) translate([-86 + i * 43, -30 - e * 36, 0]) shim(shim_set[i]);
  }
}

if (part == "assembly") everything(0);
else if (part == "exploded") everything(1);
else if (part == "cutaway") {
  difference() { everything(0); translate([ipd / 2, -200, -200]) cube(400); }
  color("red") translate([ipd / 2, 0, -30]) cylinder(d = 0.8, h = z_s + 30);
}
else if (part == "retention") {
  color("tan") body();
  translate([0, 0, z_s]) phone(); phone_foam();
  color("lightblue") translate([0, 0, z_rim + plate_t + 30]) mirror([0, 0, 1]) back();
}
else if (part == "layout") layout();
else if (part == "body") body();
else if (part == "back") back();
else if (part == "face_rim") face_rim();
else if (part == "keeper") translate([0, -oy1, -face_t - 0.3]) keeper();
else if (part == "shims") for (i = [0 : 3]) translate([i * 44, 0, 0]) shim(shim_set[i]);
else if (part == "fit_test") fit_test();
else if (part == "foam_face_2d") foam_face2d();
else if (part == "foam_phone_2d") foam_phone2d();
else assert(false, str("unknown part: ", part));
