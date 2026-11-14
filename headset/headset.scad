// myphonevision headset shell, fully parametric. Tested with OpenSCAD 2026.10 (snapshot).
//
// Print one file at a time, never a whole folder: tube_fit first (the test), then
// front, then the tubes once tube_fit slides right.
//
// Pick a part to export (or pass -D 'part="front"' on the command line):
//   assembly   all parts in place, for checking fit (don't print)
//   front      lens plate + spacer body as one print; print lens-plate-down
//   tray       phone tray; print back-down (camera slot on the bed)
//   door       sliding end door; print flat
//   shim       focus shim, shim_t thick; print as many as focus needs
//   spacer     rails that slide in behind the phone (after it's in) to take up
//              the room left for the camera bar; print flat
//   lens_ring  press-fit ring that locks a lens (stack) in its seat (or tube); print 2
//   tube       focus tube (focus_tubes = true): holds one eye's lens stack and
//              slides in the lens plate to focus; print 2, face end down
//   tube_fit   short slice of the tube and its bore: print first to check the
//              slide is snug (~15 min)
//   jig        single-lens focus test tube (print this first, ~20 min)
//   jig_ring   1 mm spacer ring for the jig
//
// Units are mm. Axes: X along the phone's long edge, Y up, Z from the face
// (z = 0) toward the phone.

part = "assembly";

// ---- Measure these first (see headset/README.md) --------------------------
// Stacked lenses (e.g. two 3x magnifiers per eye): measure the stack as one
// lens. lens_thk = the whole stack's thickness; lens_f = the stack's focal length.
// Defaults: two Carson TriView TV-26 magnifiers, all three lenses stacked per
// eye, cut off the swivel (Jayden, 2026-11-14). Rough hand measurements; the
// focus tubes cover the error.
lens_d = 38.0;          // lens diameter, calipers (here: the plastic ring's outside)
lens_thk = 21.1;        // lens (or stack) thickness at the rim
lens_f = 33.0;          // focal length (here: phone ~20 mm behind the back glass, plus half the stack)
focus_back_off = 2.5;   // sit the screen this much inside the focal length
ipd = 63.0;             // lens center spacing

// ---- Phone: iPhone 16 Pro (check with calipers; add a case's thickness if used)
phone_w = 149.6;        // long edge
phone_h = 71.5;         // short edge
phone_t = 8.95;          // body thickness, not counting the camera bump (measured)
cam_bar_h = 3.65;        // bump past the back: 12.6 total at the bump (fits the printed slice) - phone_t
screen_w = 144.8;
screen_h = 66.7;
cam_from_top = 3;    // phone top edge to the near edge of the camera bar
cam_bar_len = 40.5;     // camera bar size along the long edge, plus clearance

usb_w        = 13.0;  // USB-C plug housing width
usb_h        = 8.0;   // USB-C plug housing height
// ---- Shell ----------------------------------------------------------------
wall = 2.4;
clear = 0.6;            // phone clearance per side
lens_lip = 1.2;         // ledge on the face side that the lens rests on
ring_t = 1.6;           // lens retaining ring thickness
// Focus tubes: each eye's lens stack sits in its own tube that slides in a
// snug bore through the lens plate. Pushed fully in, the tube is flush with
// the face side and the lenses are closest to the phone; it sits at nominal
// focus pulled out by tube_in, and pulls out further for longer focus. Lets each
// wearer (and each eye) focus, e.g. a nearsighted judge without glasses.
focus_tubes = true;
tube_wall = 1.6;
tube_fit = 0.3;         // bore minus tube diameter; print tube_fit first, tape the tube if loose
tube_in = 6.0;          // travel toward the phone from nominal (push in)
tube_id = lens_d + 0.3;
tube_od = tube_id + 2 * tube_wall;
tube_len = lens_lip + lens_thk + ring_t;
bore_d = tube_od + tube_fit;
stop_h = (bore_d - tube_id) / 2;   // 45-degree stop at the phone end of the bore: prints without support
plate_t = focus_tubes ? tube_len + stop_h + 0.5
                      : max(4.0, lens_lip + lens_thk + ring_t);  // grows to fit a lens stack
lip = 2.0;              // tray lip that holds the phone's screen edge
shim_t = 1.0;           // focus shim thickness
shim_count = focus_tubes ? 0 : 2;  // shims fitted at nominal focus (the tubes replace them)
nose_w = 38;
nose_h = 30;
strap_slot = [4, 32];   // width, height of each strap slot (height = strap width)
top_strap = true;       // add an ear on top for an over-the-head strap
bolt_d = 3.4;           // M3 clearance, or a zip tie
door_t = 2.4;
vent_w = 3;
$fn = 96;

// ---- Derived --------------------------------------------------------------
in_w = phone_w + 2 * clear;
in_h = phone_h + 2 * clear;
W = in_w + 2 * wall;
H = in_h + 2 * wall;
lens_screen = lens_f - focus_back_off;
lens_center_z = lens_lip + lens_thk / 2           // lens optical center, from the face
                - (focus_tubes ? tube_in : 0);   // (tubes: at nominal, pulled out by tube_in)
tray_face_to_screen = lip;                       // screen sits on the lip
body_len = lens_screen - (plate_t - lens_center_z) - tray_face_to_screen - shim_count * shim_t;
// The pocket is deep enough for the camera bar to slide through; once the
// phone is in, the spacer rails fill the gap behind its body.
pocket_t = phone_t + cam_bar_h + clear;
tray_t = lip + pocket_t + wall;
flange = 9;             // corner flange size for bolts / zip ties

// Shrink the nose notch if big lenses would break into it: keep its round tip
// at least 2.5 mm clear of each lens seat.
seat_r = focus_tubes ? bore_d / 2 : (lens_d + 0.3) / 2;
nose_tip_r = nose_w * 0.33;
nose_clear_y = sqrt(max(0, pow(seat_r + nose_tip_r + 2.5, 2) - pow(ipd / 2, 2)));
nose_h_fit = min(nose_h, H / 2 - nose_clear_y + nose_w / 3);

assert(body_len > 5, str("body_len ", body_len, " is too short: check lens_f and plate_t"));
assert(ipd / 2 + seat_r + 1 < W / 2, "lenses don't fit across the shell");
assert(seat_r + 1.5 < H / 2, "lens seats are taller than the shell");
assert(ipd - 2 * seat_r > 6, str("lens seats nearly touch: ", ipd - 2 * seat_r, " mm between them"));
echo(str("lens-to-screen ", lens_screen, " mm; spacer body ", body_len,
         " mm; lens plate ", plate_t, " mm; each shim moves focus ", shim_t, " mm"));
if (focus_tubes)
  echo(str("focus tubes: lens center to screen ", lens_screen - tube_in, " mm pushed fully in, ",
           lens_screen, " at nominal (", tube_in, " mm out), ", lens_screen + 8,
           " at 14 mm out; tube ", tube_od, " x ", tube_len, " mm, bore ", bore_d, " mm"));
if (nose_h_fit < nose_h) echo(str("nose notch reduced to ", nose_h_fit, " mm to clear the lenses"));

// Lens centers, relative to the shell's center.
lens_pos = [[-ipd / 2, 0], [ipd / 2, 0]];

module centered_box(w, h, t) { translate([-w / 2, -h / 2, 0]) cube([w, h, t]); }

module nose(t) {
  // Rounded notch up from the bottom edge, between the lenses.
  translate([0, -H / 2 - 1, -1])
    hull() {
      translate([-nose_w / 2, 0, 0]) cube([nose_w, 1, t + 2]);
      translate([0, nose_h_fit - nose_w / 3, 0]) cylinder(r = nose_tip_r, h = t + 2);
    }
}

module corner_holes(t) {
  for (sx = [-1, 1], sy = [-1, 1])
    translate([sx * (W / 2 + flange / 2 - 1), sy * (H / 2 - flange / 2), -1])
      cylinder(d = bolt_d, h = t + 2);
}

module flanges(t) {
  difference() {
    for (sx = [-1, 1], sy = [-1, 1])
      translate([sx * (W / 2 + flange / 2 - 1) - flange / 2, sy * (H / 2 - flange / 2) - flange / 2, 0])
        cube([flange, flange, t]);
    corner_holes(t);
  }
}

module lens_plate() {
  difference() {
    union() {
      centered_box(W, H, plate_t);
      // Strap ears on both sides.
      for (sx = [-1, 1])
        translate([sx * (W / 2 + 6), 0, 0])
          difference() {
            centered_box(14, strap_slot[1] + 10, plate_t);
            translate([sx * 1, 0, -1]) centered_box(strap_slot[0], strap_slot[1], plate_t + 2);
          }
      // Top ear for an over-the-head strap.
      if (top_strap)
        translate([0, H / 2 + 6, 0])
          difference() {
            centered_box(strap_slot[1] + 10, 14, plate_t);
            translate([0, 1, -1]) centered_box(strap_slot[1], strap_slot[0], plate_t + 2);
          }
    }
    for (p = lens_pos) translate([p[0], p[1], 0]) {
      if (focus_tubes) {
        translate([0, 0, -1]) cylinder(d = bore_d, h = tube_len + 1);        // tube bore
        translate([0, 0, tube_len - 0.01]) cylinder(d1 = bore_d, d2 = tube_id, h = stop_h + 0.02);  // stop
        translate([0, 0, -1]) cylinder(d = tube_id, h = plate_t + 2);        // aperture
      } else {
        translate([0, 0, -1]) cylinder(d = lens_d - 2 * 1.2, h = plate_t + 2);  // aperture
        translate([0, 0, lens_lip]) cylinder(d = lens_d + 0.3, h = plate_t);   // seat
      }
    }
    nose(plate_t);
  }
}

module body() {
  translate([0, 0, plate_t]) {
    difference() {
      centered_box(W, H, body_len);
      translate([0, 0, -1]) centered_box(W - 2 * wall, H - 2 * wall, body_len + 2);
      translate([0, 0, -plate_t]) nose(body_len + plate_t);
    }
    // Septum between the eyes, so each eye sees only its half of the screen.
    difference() {
      centered_box(1.6, H - 2 * wall, body_len);
      translate([0, 0, -plate_t]) nose(body_len + plate_t);
    }
    translate([0, 0, body_len - 3]) flanges(3);
  }
}

module front() { lens_plate(); body(); }

module shim() {
  difference() {
    union() {
      centered_box(W, H, shim_t);
      flanges(shim_t);
    }
    translate([0, 0, -1]) centered_box(W - 2 * wall, H - 2 * wall, shim_t + 2);
  }
}

// Phone tray. The phone slides in from the +X end (its USB end) with the
// screen facing -Z; a door dropped in from the top closes that end and is
// locked by a 1.75 mm filament pin through the tray's ear and the door's tab.
// The camera bar end is -X. The tray runs past the shell at +X to hold the door.
door_x0 = in_w / 2 + 0.2;                  // inner face of the door slot
door_slot = door_t + 0.4;
tray_x1 = door_x0 + door_slot + 1.6;       // +X end of the tray
door_z0 = lip - 1;                         // grooves bite 1 mm into lip and back
door_len_z = pocket_t + 2 - 0.3;
pin_y = H / 2 + 3;
pin_z = lip + phone_t / 2;

module tray() {
  difference() {
    union() {
      translate([-W / 2, -H / 2, 0]) cube([tray_x1 + W / 2, H, tray_t]);
      flanges(3);
      // Latch ear on top, just inside the door slot.
      translate([door_x0 - 7, H / 2 - 0.01, lip]) cube([6.8, 6, pocket_t]);
    }
    // Phone pocket, open at the +X end.
    translate([-in_w / 2, -in_h / 2, lip]) cube([tray_x1 + in_w / 2 + 1, in_h, pocket_t]);
    // Screen window through the lip.
    translate([0, 0, -1]) centered_box(screen_w, screen_h, lip + 2);
    // Camera bar slot through the back, full height so the raised bar clears.
    translate([-in_w / 2 + cam_from_top, -in_h / 2, lip]) cube([cam_bar_len, in_h, tray_t]);
    // Vents across the back, clear of the camera slot.
    for (x = [-in_w / 2 + cam_from_top + cam_bar_len + 8 : vent_w * 3 : in_w / 2 - 10])
      translate([x, -in_h / 2 + 10, tray_t - wall - 1]) cube([vent_w, in_h - 20, wall + 2]);
    // Door slot, open through the top wall.
    translate([door_x0, -in_h / 2 - 0.01, door_z0]) cube([door_slot, H, door_len_z + 0.3]);
    // Pin hole through the ear (continues through the door's tab).
    translate([door_x0 - 8, pin_y, pin_z]) rotate([0, 90, 0]) cylinder(d = 2.2, h = 8);
  }
}

// Modeled in place (tray coordinates, door seated).
module door() {
  difference() {
    translate([door_x0 + 0.2, -in_h / 2, door_z0 + 0.15])
      cube([door_t, in_h + wall + 6, door_len_z]);
    // USB-C pass-through, centered on the phone's edge.
    translate([door_x0 - 1, -usb_w / 2, pin_z - usb_h / 2])
      cube([door_t + 2, usb_w, usb_h]);
    translate([door_x0 - 1, pin_y, pin_z]) rotate([0, 90, 0]) cylinder(d = 2.2, h = door_t + 2);
  }
}

// Holds one eye's lens stack: face lip at z = 0, stack, then a lens_ring
// pressed in behind it. Print face end down.
module tube() {
  difference() {
    cylinder(d = tube_od, h = tube_len);
    translate([0, 0, -1]) cylinder(d = lens_d - 2 * 1.2, h = tube_len + 2);  // aperture
    translate([0, 0, lens_lip]) cylinder(d = tube_id, h = tube_len);       // seat
  }
}

// 8 mm of tube and of its bore with a little plate around it: the tube
// should slide with a firm push and stay put. Too loose: tape round the tube,
// or lower tube_fit. Too tight: raise tube_fit by 0.1-0.2.
module tube_fit() {
  translate([-(tube_od / 2 + bore_d / 2 + 10), 0, 0])
    difference() {
      cylinder(d = tube_od, h = 8);
      translate([0, 0, -1]) cylinder(d = tube_id, h = 10);
    }
  difference() {
    cylinder(d = bore_d + 8, h = 8);
    translate([0, 0, -1]) cylinder(d = bore_d, h = 10);
  }
}

module lens_ring() {
  // Press it into the seat behind the lens; a dab of glue if it's loose.
  difference() {
    cylinder(d = lens_d + 0.15, h = ring_t);
    translate([0, 0, -1]) cylinder(d = lens_d - 3, h = ring_t + 2);
  }
}

module jig() {
  // Stand it on the phone screen showing a grid; look through the lens.
  // Add jig_rings until the grid is sharp; ring count tells you the error.
  jig_h = lens_screen - lens_thk / 2 - 2;  // lens center 2 mm short of focus, so rings add
  difference() {
    cylinder(d = lens_d + 6, h = jig_h + lens_thk);
    translate([0, 0, -1]) cylinder(d = lens_d - 3, h = jig_h + lens_thk + 2);
    translate([0, 0, jig_h]) cylinder(d = lens_d + 0.3, h = lens_thk + 1);
  }
  echo(str("jig: screen to lens center = ", jig_h + lens_thk / 2,
           " mm with no rings; each ring adds 1 mm"));
}

module jig_ring() {
  difference() {
    cylinder(d = lens_d + 6, h = 1);
    translate([0, 0, -1]) cylinder(d = lens_d - 3, h = 3);
  }
}

// Two rails along the top and bottom edges of the phone's back plus a
// crossbar at the USB end, clear of the camera bar and the vents. Modeled in
// tray coordinates at its installed position.
spacer_t = cam_bar_h + clear - 0.6;  // 0.6: this printer prints the pocket ~0.27 mm shallow
spacer_x0 = -in_w / 2 + cam_from_top + cam_bar_len + 1;
spacer_x1 = in_w / 2 - 0.2;
rail_w = 9;
module spacer() {
  z = lip + phone_t;
  for (y = [-in_h / 2 + 0.3, in_h / 2 - 0.3 - rail_w])
    translate([spacer_x0, y, z]) cube([spacer_x1 - spacer_x0, rail_w, spacer_t]);
  translate([spacer_x1 - 8, -in_h / 2 + 0.3, z]) cube([8, in_h - 0.6, spacer_t]);
}

module phone_ghost() {
  color("black", 0.6) {
    translate([-phone_w / 2, -phone_h / 2, 0]) cube([phone_w, phone_h, phone_t]);
    // Camera bar across the back, near the -X (top) end.
    translate([-phone_w / 2 + cam_from_top + 1, -phone_h / 2 + 1, phone_t]) cube([cam_bar_len - 2, phone_h - 2, cam_bar_h]);
  }
}

module assembly() {
  color("tan") front();
  stack = plate_t + body_len;
  for (i = [0 : shim_count - 1]) color("orange") translate([0, 0, stack + i * shim_t]) shim();
  tray_z = stack + shim_count * shim_t;
  color("lightblue") translate([0, 0, tray_z]) tray();
  translate([0, 0, tray_z + lip]) phone_ghost();
  color("green") translate([0, 0, tray_z]) spacer();
  color("salmon") translate([0, 0, tray_z]) door();
  out = focus_tubes ? tube_in : 0;  // tubes shown at nominal focus
  for (p = lens_pos) translate([p[0], p[1], -out]) {
    if (focus_tubes) color("gray") tube();
    color("white", 0.5) translate([0, 0, lens_lip]) cylinder(d = lens_d, h = lens_thk);
  }
}

if (part == "assembly") assembly();
else if (part == "front") front();
else if (part == "tray") tray();
else if (part == "door") rotate([0, 90, 0]) translate([-door_x0 - 0.2 - door_t, 0, 0]) door();
else if (part == "shim") shim();
else if (part == "spacer") translate([0, 0, -(lip + phone_t)]) spacer();
else if (part == "lens_ring") lens_ring();
else if (part == "tube") tube();
else if (part == "tube_fit") tube_fit();
else if (part == "jig") jig();
else if (part == "jig_ring") jig_ring();
else assert(false, str("unknown part: ", part));
