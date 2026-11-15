# Wiring guide

Build order, wiring and a test after each step, for the ESP32-DevKitC version of the controllers, the hub and the SlimeVR trackers. Pin numbers are GPIO numbers as printed on the DevKitC. **Test after every step.** A fault found right after soldering it takes a minute to fix; found at the end, it takes an hour.

## Before you start

- **Parts per controller:** DevKitC, GY-521 (MPU-6050), joystick module, FSR + 10 kΩ resistor, 5 push buttons, vibration motor, NPN transistor (2N2222 / S8050 from the Elgoo kit), 1 kΩ resistor, diode (1N4007 or 1N4148), 4×AA holder, Schottky diode (1N5817 or similar).
- **Antenna:** the -32UE boards have a U.FL connector and no PCB antenna. Clip on a 2.4 GHz antenna, or solder a 31 mm wire to the U.FL center pin. Without one, range drops to under a meter.
- **Power everything from 3V3, not 5V,** except the motor and the battery input. The ESP32's inputs are 3.3 V only.
- **Breadboard first, solder second.** Get each controller working on a breadboard with the bench test, then move it into the case.

## 1. Hub (5 minutes)

Nothing to wire: fit the antenna, plug the DevKitC into the laptop and flash it.

```sh
cd firmware/hub && pio run -t upload
```

**Test:** later, when a controller is on, `python -m myphonevision_bridge --debug` shows packets arriving.

## 2. Controller

### 2a. Board and motion sensor

```
GY-521          DevKitC
VCC  ────────── 3V3
GND  ────────── GND
SCL  ────────── GPIO 22
SDA  ────────── GPIO 21
AD0  ────────── GND        (address 0x68; the GY-521 also pulls it low on its own)
```

Flash and open the monitor:

```sh
cd firmware/controller
pio run -e devkit_left -t upload && pio device monitor     # devkit_right for the other one
```

**Test:** it prints "Gyro bias …" after 2 s (keep it still). If it repeats "MPU-6050 not found," check SDA/SCL aren't swapped. Type `d`: roll and pitch should follow when you tilt the board.

### 2b. Joystick

```
Joystick        DevKitC
GND  ────────── GND
+5V  ────────── 3V3        (3V3, not 5V: the ESP32 can't read above 3.3 V)
VRx  ────────── GPIO 34
VRy  ────────── GPIO 35
SW   ────────── GPIO 13
```

**Test:** with `d` on, `stick raw` sits near 1800–2000 centered and swings to about 0 and 4095. Pressing the stick shows `K` in the button list. If up and down are reversed, flip `STICK_INVERT_Y` in `include/config.h`.

### 2c. Trigger (FSR)

```
3V3 ──── FSR ────┬──── GPIO 32
                 │
               10 kΩ
                 │
                GND
```

**Test:** `trigger raw` rises as you squeeze. Write down the value at rest and at a firm squeeze; those are `TRIGGER_RAW_MIN` and `TRIGGER_RAW_MAX` in `config.h`. Reflash after changing them.

### 2d. Buttons

Each button goes between its pin and GND. The firmware turns on the internal pull-ups, so no resistors are needed.

| Button | GPIO |
| --- | --- |
| A | 25 |
| B | 26 |
| System | 27 |
| Grip | 14 |

**Test:** each press shows its letter: `A`, `B`, `S` (system), `G` (grip).

### 2e. Vibration motor

**Dropped on the as-built controllers (2026-11-15), to make room in the case.** Skip this step; GPIO 23 stays unconnected and the firmware doesn't mind.

```
                 5V
                  │
         ┌────────┤
         │      (motor)
  diode  ▲        │          diode across the motor, stripe (cathode) to 5V
         │        │
         └────────┤
                  │
                  C
GPIO 23 ── 1 kΩ ── B   NPN
                  E
                  │
                 GND
```

**Test:** type `h` in the monitor and the motor buzzes. It also buzzes once at power-on.

### 2f. Battery

```
4×AA (+) ── Schottky diode ──▶ 5V pin      (stripe toward the board)
4×AA (−) ──────────────────── GND
```

The diode stops USB power from back-feeding the batteries. **Unplug the batteries while the board is on USB,** to be safe.

**Test:** unplug USB. The controller should buzz on power-up (if it has a motor), and the bridge's `--debug` view should show it at about 200 Hz.

### 2g. Into the case

Build guide for **case D** (the pistol grip, `cases/mockups/controller/d_ergo.scad`; print files and screws in issue #12, pickup code 2DUQ). Written from the design file and renders before the first build: fix any step that turns out wrong. The pictures: `cases/mockups/controller/img/d_ergo-cutaway.png` (everything in place), `d_ergo-inside_l.png` and `d_ergo-inside_r.png` (the empty halves).

**Per controller:** plate A (`half_l`, `imu_clamp`, `cover`) and plate B (`half_r`, `cradle`), 4 × M3×12, 4 × M3×8, 1 × M3×6 (no countersunk heads), about 7 zip ties 2.5 mm wide, electrical tape. The wiring must already pass the tests in 2a–2f: it's hard to fix once it's closed.

1. **Prep the prints.** Peel off any brim. Run each screw into its hole once and back out, so the threads are cut before parts are in the way. Snug only, every screw: the threads are printed plastic.
2. **ESP32 into `half_l`.** Lay `half_l` cheek down, open side up. The ESP32 lies flat on the ledges between the two rails, plugs pointing up out of the half, **USB end toward the bottom of the grip**. Slide the top end under the wedge stop first, then press the USB end down until the two hooks click. The USB port should line up with the slot in the heel, so you can still plug in a cable to reflash.
3. **IMU onto its pad** (above the ESP32, on the same cheek). Chip up, header edge (with the plugs) toward the **front** of the grip. Push it into the corner the two fences make; the wire on the VCC pin goes through the notch at that corner. Put the `imu_clamp` over it and fasten with the **M3×6**. It must not wiggle at all, or the controller jitters in VR. Same orientation on both controllers, so one `--mount` serves both.
4. **Joystick into the head.** Pin header toward the **wrist** (the back of the head; `STICK_INVERT_Y 0` assumes this). Its plugs hang straight down into the top of the grip. Screw it to the four ribs with the **4 × M3×8**. The knob sticks up through the round hole.
5. **A button** through the hole in front of the joystick, ring on the outside, nut on the inside.
6. **FSR (grip)** into the round pocket on the front of the grip, under your fingers, pad facing out. Its tail goes through the slit next to the pocket into the grip, past the IMU's plugs. A strip of tape holds the pad flat in the pocket.
7. **Antenna.** The case has no spot for it (there's no vibration motor; it was dropped for space). Run the antenna along the inside wall of the head or arm, away from the battery and the ESP32's metal can.
8. **Battery holder into the `cradle`.** It snaps in under the two lips, cells facing out. Lay its leads in the channels behind it and out through the exits at the top or bottom. Then slide the cradle's rails into the notches in the arm and the bow of `half_l`. The cradle is clamped by both halves, so it goes in **before** closing.
9. **Route and tie the wires.** Everything crossing between the ESP32 and the joystick or IMU goes through the window in the divider wall. Zip-tie bundles to the anchors in the head, the arm and the grip, so no wire sits on the split line or in a screw hole. Trim the tie tails.
10. **Test before closing.** Batteries in, keep it still for 3 s while the gyro calibrates, then run `python -m myphonevision_bridge --no-hmd --debug` and check the stick, A, grip and tilt.
11. **Close it.** Put `half_r` on, checking that no wire is pinched along the edge. Fasten with the **4 × M3×12**. If it won't close flat, a wire or plug is in the way: open it and re-route, don't force it.
12. **Cover on.** Slide the `cover` across the cells from the side. Cells swap without opening the case.

**After assembly:** run the test from step 10 again, and pick the bridge's `--mount` preset to match how the IMU faces (`firmware/controller/README.md`).

### 2h. As built (2026-11-14): what goes in each shell

Both controllers are wired and tested (wireless on batteries: LEFT ~195 Hz, RIGHT ~148 Hz). Use these parts for the shell, not the plan's list above.

| Part | Size (mm) | Notes |
| --- | --- | --- |
| ESP32 kit (CP2102N) | 51.5 × 28.23 (measured, issue #7); **35 tall** with the jumper plugs on (estimate) | Female jumpers on the header pins, held with electrical tape. 35 is deeper than the current 28.4 handle |
| U.FL antenna | not measured | Clips on; tape it along the inside wall, away from the battery |
| Joystick, Adafruit 512 | 38.08 square, M3 at 30.5 (measured, issue #7) | **Pin header toward the wrist**: `STICK_INVERT_Y 0` assumes that orientation |
| **A button only** | 16 mm-class panel mount: thread 14.84, ring 19.19 (issue #7) | GPIO 25. **No B, system or grip buttons.** Click and hold the stick (centered): 1 s = recenter, 3 s = system (bridge) |
| FSR **grip** (grab, not trigger) | pad 18.5, tail 7.3 wide | GPIO 32 + 10 kΩ to GND |
| IMU, LEFT | GY-521 | Flat, chip up |
| IMU, RIGHT | **Adafruit BNO055**, 25.35 × 20.3 | Flat, chip up, turned the same way as LEFT's GY-521 (one `--mount` serves both hands). Firmware detects it |
| ~~Vibration motor~~ | | **Dropped (2026-11-15) to make room.** Take out the motor, NPN, 1 kΩ and diode; GPIO 23 stays unconnected |
| 4×AA holder | 61.68 × 57.7 × 15 | Through a 1N5819 to 5V, **stripe toward the board** (backwards = no power, the first-try mistake on LEFT) |

All 3V3 parts (IMU, joystick, FSR) chain off the IMU's VCC pin.

## 3. SlimeVR trackers

Three boards, each with two GY-521s on the same I2C wires. The **primary** sits on the board in the case; the **extension** goes on a cable to a second body part.

| Board | Primary (in the case) | Extension (on the cable) | Power |
| --- | --- | --- | --- |
| Waist | Hip | Chest | Anker bank on USB |
| Left leg | Left thigh | Left ankle | 4×AA + Schottky (as in 2f) |
| Right leg | Right thigh | Right ankle | 4×AA + Schottky |

```
                 DevKitC
               3V3 GND 21 22
                │   │   │  │
     ┌──────────┼───┼───┼──┼──────────────────┐   4-wire cable, under 80 cm
     │          │   │   │  │                   │   (Qwiic / JST cable works)
Primary GY-521  │   │   │  │       Extension GY-521
VCC ────────────┘   │   │  │       VCC ── 3V3
GND ────────────────┘   │  │       GND ── GND
SDA ────────────────────┘  │       SDA ── GPIO 21
SCL ───────────────────────┘       SCL ── GPIO 22
AD0 ── GND  (0x68)                 AD0 ── 3V3  (0x69)   <- the one difference
```

- **The extension's AD0 must go to 3V3.** Otherwise both sensors answer at the same address and neither works.
- **In the cable, don't run SDA and SCL next to each other.** Put GND between them, for example in the order VCC, SDA, GND, SCL.

Flash each board (bake in the laptop hotspot so it connects on its own):

```sh
WIFI_SSID=yourhotspot WIFI_PASS=yourpass firmware/slimevr/build.sh upload
```

**Test:** start the laptop's 2.4 GHz Mobile Hotspot and the SlimeVR server. Each board shows up with two trackers; move each sensor and watch its tracker move. If only one sensor appears, check the extension's AD0 and its cable.

**Cases:** the primary goes in `leg_case` or `waist_case`, the extension in a `pod_case`. Foam-tape every sensor flat so it can't move. Strap them on with the ACE bandages through the case ears.

## When something doesn't work

| Symptom | Likely cause |
| --- | --- |
| "MPU-6050 not found" | SDA/SCL swapped, loose wire, or the sensor on 5V without a common GND |
| Stick stuck at 4095 or 0 | Joystick powered from 5V, or VRx/VRy not connected |
| Controller works on USB, dies on battery | Schottky diode backwards (stripe goes toward the board), or flat batteries |
| Bridge shows no packets | Hub has no antenna, controller and hub flashed from different code versions, or the controller is in a `_udp` build |
| Controller slowly turns in VR | Normal IMU drift: click and hold the thumbstick 1 s (stick centered) to snap it back |
| Only one tracker per SlimeVR board | Extension AD0 not tied to 3V3, or its cable is too long or has SDA/SCL side by side |
