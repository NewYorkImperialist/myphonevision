// Concept B, "stand-up": the upright grip of cases/controller.scad, with the battery moved
// from the head to a pod under the hand. Thin head, low weight, stands on a table.
//
//   head       thumb face; print face down
//   head_base  closes the head, socket for the grip; print head side down (socket up)
//   spine      grip tube on the pod's lid: ESP32, trigger, grip button; print lid down
//   pod        battery tray; print floor down
//   assembly, print (all parts as they sit on the bed)
// Front is -y. No part needs supports.

include <common.scad>
part = "assembly";

head = [max(joy_board[0] + 2, face_buttons * btn_pitch) + 2 * wall,
        joy_board[1] / 2 + btn_first + button_body / 2 + 3 + 2 * wall];
head_h = top_t + max(joy_stack - top_t, button_reach - top_t + imu_h + 1) + 1;
y_joy = head[1] / 2 - wall - 1 - joy_board[1] / 2;

grip_in = [devkit[1] + 2, devkit_h + 2];
grip_out = [grip_in[0] + 2 * wall, grip_in[1] + 2 * wall];
spine_len = max(wall + 2 + devkit[0] + 2 + (grip_button ? button_body + 3 : 0) + fsr_d + 8, 95) + socket_depth;   // at least 95 mm for the hand
fsr_z = spine_len - socket_depth - 4 - fsr_d / 2;
grip_z = fsr_z - fsr_d / 2 - 3 - button_body / 2;

pod = [battery[1] + 1 + 2 * wall, battery[0] + 1 + 2 * wall, wall + battery[2] + 1];

assert(button_reach <= grip_in[1], "grip button deeper than the grip");
echo(str("B stand-up: head ", head[0], " x ", head[1], " x ", head_h + wall, "; grip ", grip_out[0], " x ", grip_out[1],
         ", ", spine_len - socket_depth, " between pod and head; overall height ", pod[2] + spine_len + wall + head_h));

module cbox(size, rad) translate([-size[0] / 2, -size[1] / 2, 0]) rbox(size, rad);
// Screw ears at the front and back of a part len long.
module ears(len, h) for (s = [-1, 1]) translate([0, s * (len / 2 + 2), 0]) cylinder(d = 9, h = h);
module ear_holes(len, d, z, h) for (s = [-1, 1]) translate([0, s * (len / 2 + 2), z]) cylinder(d = d, h = h);

// Top face at z = 0, open toward +z.
module head() {
  difference() {
    union() { cbox([head[0], head[1], head_h], 6); ears(head[1], head_h); }
    translate([0, 0, top_t]) cbox([head[0] - 2 * wall, head[1] - 2 * wall, head_h], 6 - wall);
    translate([0, y_joy, 0]) thumb_cuts(face_buttons);
    ear_holes(head[1], joy_post_bore, head_h - 10, 11);
  }
  translate([0, y_joy, 0]) joy_posts();
}

// Head side at z = 0, socket collar toward +z.
module head_base() {
  difference() {
    union() {
      cbox([head[0], head[1], wall], 6);
      ears(head[1], wall);
      cbox([grip_out[0] + 2 * wall + 2 * fit, grip_out[1] + 2 * wall + 2 * fit, wall + socket_depth], 3);
    }
    translate([0, 0, wall]) cbox([grip_out[0] + 2 * fit, grip_out[1] + 2 * fit, socket_depth + 1], 2);
    translate([-10, grip_in[1] / 2 - 16, -1]) cube([20, 16, wall + 2]);     // wires
    ear_holes(head[1], 3.4, -1, wall + 2);
    translate([0, grip_out[1] / 2, wall + socket_depth / 2]) rotate([-90, 0, 0]) cylinder(d = 3.4, h = 2 * wall);  // locking screw
  }
}

// Pod lid at z = 0, grip rising from it. Front is -y.
module spine() {
  difference() {
    union() {
      cbox([pod[0], pod[1], wall], 4);
      ears(pod[1], wall);
      cbox([grip_out[0], grip_out[1], spine_len], 2);
    }
    translate([-grip_in[0] / 2, -grip_in[1] / 2, wall]) cube([grip_in[0], grip_in[1], spine_len]);
    // USB and battery leads, through the lid into the pod.
    translate([-usb_slot[0] / 2, -grip_in[1] / 2, -1]) cube([usb_slot[0], usb_slot[1], wall + 2]);
    ear_holes(pod[1], 3.4, -1, wall + 2);
    // FSR pocket (0.8 mm floor) and the slit for its tail.
    translate([0, -grip_out[1] / 2 - 1, fsr_z]) rotate([-90, 0, 0]) cylinder(d = fsr_d + 0.6, h = 1 + wall - 0.8);
    translate([-fsr_tail_w / 2 - 0.3, -grip_out[1] / 2 - 1, fsr_z - fsr_d / 2 - 1.2]) cube([fsr_tail_w + 0.6, wall + 2, 1.6]);
    if (grip_button) translate([0, -grip_out[1] / 2 - 1, grip_z]) rotate([-90, 0, 0]) cylinder(d = button_d, h = wall + 2);
    translate([0, grip_out[1] / 2 - wall - 1, spine_len - socket_depth / 2]) rotate([-90, 0, 0]) cylinder(d = joy_post_bore, h = wall + 2);
  }
}

module pod() {
  difference() {
    union() { cbox(pod, 4); ears(pod[1], pod[2]); }
    translate([0, 0, wall]) cbox([pod[0] - 2 * wall, pod[1] - 2 * wall, pod[2]], 1);
    ear_holes(pod[1], joy_post_bore, pod[2] - 10, 11);
  }
}

z_spine = pod[2];
z_plate = z_spine + spine_len + wall;      // top of the head base plate
z_top = z_plate + head_h;

module parts() {
  translate([0, y_joy, z_top]) mirror([0, 0, 1]) p_thumb(face_buttons);
  translate([battery[1] / 2, -battery[0] / 2, wall]) rotate([0, 0, 90]) p_battery();
  translate([0, -grip_in[1] / 2 + 4, z_spine + wall + 2 + devkit[0]]) rotate([-90, 0, 0]) p_devkit();
  translate([0, -grip_out[1] / 2 + 1.4, z_spine + fsr_z]) rotate([90, 0, 0]) p_fsr();
  if (grip_button) translate([0, -grip_out[1] / 2, z_spine + grip_z]) rotate([-90, 0, 0]) p_button();
  translate([0, -head[1] / 2 + wall + 2 + imu[1] / 2, z_plate]) p_imu();
}

module assembly() {
  shell("slategray") pod();
  shell("lightblue") translate([0, 0, z_spine]) spine();
  shell("orange") translate([0, 0, z_plate]) mirror([0, 0, 1]) head_base();
  shell("tan") translate([0, 0, z_top]) mirror([0, 0, 1]) head();
  parts();
}

if (part == "assembly") assembly();
else if (part == "head") head();
else if (part == "head_base") head_base();
else if (part == "spine") spine();
else if (part == "pod") pod();
else if (part == "print") {
  color("tan") head();
  color("orange") translate([head[0] + 10, 0, 0]) head_base();
  color("lightblue") translate([0, head[1] + 20, 0]) spine();
  color("slategray") translate([head[0] + 10, head[1] + 20, 0]) pod();
}
else assert(false, str("unknown part: ", part));
