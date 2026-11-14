# Plan

Proposal dated 2026-11-13. Build details live in each folder's README; this page holds the decisions, parts, people and risks.

## Gates (clear by hour 3)

1. **Windows laptop with a hardware encoder.** ALVR wants NVIDIA GTX 1000+ (NVENC), AMD (AMF) or Intel (VPL); most Intel laptops qualify through their iGPU. VMT is Windows-only, and ALVR's Linux support is partial. If this fails, the fallback is a standalone Android app (Unity + Cardboard XR + ARCore) with controllers over BLE, which drops SteamVR.
2. **Matched lenses.** 40–50 mm focal length (+20 to +25 D), 25–35 mm diameter, two identical. One person goes on the lens run in hour 1.

**First light (hour 0–3):** stock PhoneVR against ALVR v20.8.0 over USB, and the PR #458 build against the v21.0.0-dev14 nightly, side by side. Whichever reaches SteamVR Home first wins. Note the latency as the baseline.

## Team

| Workstream | Owner | Owns | First task (hour 0–1) |
| --- | --- | --- | --- |
| Optics and industrial design | TBD | Lenses, headset shell, controller shells, tracker cases, straps | Buy lenses; print the focus jig on return |
| Phone and streaming | Pixel owner | ALVR + PhoneVR first light, USB link, fork changes 1–3, thermals | Install SteamVR, ALVR v20.8.0 and the PhoneVR APK |
| Controllers | TBD | Controller firmware, hub, bridge, VMT bindings, arm model, rung 2 or 3 | Check out lab parts; get one IMU quaternion on serial |
| Body tracking, integration, demo | TBD | SlimeVR trackers, PC hotspot, calibration flow, demo world, pitch, video | Flash SlimeVR firmware on one DevKitC + MPU-6050 |

The controller and body-tracking owners share the soldering station and the IMU and ESP32 stock. Agree on the IMU split at checkout.

**Pick the hero demo before choosing controller rung 2 or 3.** Beat Saber needs rung 2 (iPhone ARKit pose). VRChat with full-body tracking works with rung 1 (arm model).

## Hardware requests

The lab allows one of each item per attendee, so each person requests their own column. Get every P0 item before anything else.

| Priority | Item | Pixel owner | B | C | D | Total | If it's gone |
| --- | --- | --- | --- | --- | --- | --- | --- |
| P0 | Xiao ESP32S3 Sense (2 in stock) | 1 | 1 | – | – | 2 | Two DevKitCs in larger handles |
| P0 | HiLetGo GY-521 MPU-6050, 3-pack (2 in stock) | 1 | 1 | – | – | 2 packs | Accelerometer/Gyroscopic Sensors if they have a gyro; ask the CICS makerspace |
| P0 | ESP32-DevKitC-32UE | 1 | 1 | 1 | 1 | 4 | Drop the hub, use UDP; cut body tracking to 2 boards |
| P0 | Accelerometer/Gyroscopic Sensor | 1 | 1 | 1 | 1 | 4 | The 6 GY-521s alone: 2 controllers + 4 body |
| P1 | Vibrator Motor (6 in stock) | 1 | 1 | – | – | 2 | Skip haptics |
| P1 | Analog Joystick | 1 | 1 | – | – | 2 | Grove Thumb Joystick (MLH table) |
| P1 | Force Sensing Resistor | 1 | 1 | – | – | 2 | Push button as a digital trigger |
| P1 | Push Buttons & Button Switches | 1 | 1 | 1 | 1 | max | Grove Button (MLH) or makerspace bins |
| P2 | Battery Holder | 1 | 1 | 1 | 1 | 4 | Battery Enclosure, or Anker banks |
| P2 | Anker PowerCore Slim | 1 | 1 | – | – | 2 | Battery holders |
| P2 | USB A – Micro cable | 1 | 1 | 1 | 1 | 4 | Any micro-USB data cable |
| P2 | Alkaline AA / AAA | – | – | 1 | 1 | as allowed | Free AA at the CICS makerspace; buy more |
| P3 | Elgoo Arduino Kit | 1 | – | – | – | 1 | Arduino Kit (MLH) or makerspace bins |
| P3 | Sparkfun Qwiic Cable kit | – | 1 | – | – | 1 | Jumper wires (MLH) |
| P3 | JST Connector 4 pin | – | – | 1 | – | 1 | Solder cables directly |
| P3 | Breadboards | – | – | 1 | 1 | 2 | Breadboard (MLH) |
| P3 | Leap Motion | – | – | 1 | – | 1 | Skip controller rung 3 |
| P3 | Digital Multimeter | – | – | – | 1 | 1 | Makerspace multimeter |
| P3 | Logitech Webcam (MLH table) | – | – | – | 1 | 1 | Phone camera for the camera-FBT fallback |

That's 10 IMUs for 8 roles (6 body + 2 controllers) and 6 ESP32s for exactly 6 roles (2 Xiao controllers, 3 SlimeVR boards, 1 hub). ESP-01 modules can stand in for the hub, since ESP-NOW runs on the ESP8266.

The CICS makerspace (CSL E302) has free consumables, soldering stations, printers and a laser cutter, and is closed weekends. Do the solder-heavy work there today.

**Ask the hardware desk:**

- [ ] What chip is the "Accelerometer/Gyroscopic Sensor"? A BNO085 or ICM part beats the MPU-6050.
- [ ] Are there 2.4 GHz U.FL antennas for the 32UE boards and the Xiaos?
- [ ] Is the limit per item or per pack, for buttons, batteries and GY-521 packs?
- [x] Is there a soldering station, and filament or a print queue?

**Bring or buy:**

- [ ] Lenses: a phone VR viewer, or two identical 5x magnifiers
- [ ] 2 m USB-C cable for the Pixel (the lab has only A-to-C adapters)
- [ ] Two USB-C data cables for the Xiaos
- [ ] Elastic strap and velcro
- [ ] AA and AAA batteries (four 4×AA holders need 16)
- [ ] Zip ties
- [ ] Soldering iron, solder, flux, header pins, heat-shrink, Schottky diodes for the Xiaos, filament and a 6–10 h printer slot

**Pre-download:** SteamVR, ALVR v20.8.0 and the v21.0.0-dev14 nightly, VMT, SlimeVR server, VRChat (and make an account). ZIG SIM Pro (paid) on two iPhones only if going for controller rung 2.

**Already rejected:** the lab's 5" LCDs and Mobile Pixels monitors (the Pixel's OLED is sharper, faster and already has the IMU); Myo armbands (dead SDK).

## Risks and fallbacks

| Risk | Sign | Fallback |
| --- | --- | --- |
| No Windows GPU laptop | Gate 1 fails | Standalone Android app with BLE controllers; loses SteamVR |
| No lenses today | Gate 2 fails | Magnifiers, then Discord/organizers, then thrift store; the shell is parametric |
| PhoneVR won't pair with ALVR or current SteamVR | First light fails | PR #458 + v21 nightly; roll SteamVR back via beta branches; PhoneVR's legacy server; VRidge or iVRy for display only |
| USB tethering fails | No interface on the PC | adb forward (`tools/windows/adb-forward.ps1`); last resort a 5 GHz PC hotspot |
| ARCore jitter or phone overheating | Head pose jumps; throttling | 3DoF head plus reprojection; SlimeVR legs still move but the body is pinned |
| MPU-6050 drift | Limbs slowly rotate | Reset keybind before each run; better desk IMU if there is one; short runs |
| ESP32-32UE range | Drops beyond 1 m | U.FL antenna, or a 31 mm wire |
| Printer queue | Shell not ready by hour 20 | 0.28 mm draft prints; donor viewer as the headset with printed add-ons |
| VRChat OSC port clash | VRChat OSC misbehaves | VMT uses 39570/39571, VRChat uses 9000; keep it that way |

## Unverified: check on site

- [ ] Which chip the lab's "Accelerometer/Gyroscopic Sensor" is.
- [ ] Whether the 32UE and Xiao boards come with antennas.
- [ ] Whether "1 per attendee" is per item or per pack.
- [ ] In-store stock of viewers or 5x magnifiers. Call before driving.
- [ ] ALVR v20.8.0 under the current SteamVR, and PR #458 with the v21.0.0-dev14 nightly on the Pixel 7.
- [ ] Whether the Anker banks shut off at one ESP32's low current draw.
- [ ] Real motion-to-photon latency over USB (PhoneVR's ~150 ms has no stated conditions).
- [ ] That VMT and the SlimeVR driver load together. (VMT's haptic message, `/VMT/Out/Haptic index, frequency, amplitude, duration`, is confirmed from its source.)
- [ ] That OpenVR's raw universe matches VMT's raw driver space (`bridge --debug-follow`).
- [ ] ZIG SIM Pro's ARKit mode on your iPhones: rate, stability, price.

## Sources

- [PhoneVR](https://github.com/PhoneVR-Developers/PhoneVR): ALVR v20.8.0 requirement, USB modes, latency table, `alvr_main.cpp`
- [PhoneVR PR #458](https://github.com/PhoneVR-Developers/PhoneVR/pull/458): ALVR v21 migration, ARCore 6DoF
- [ALVR](https://github.com/alvr-org/ALVR): GPU encoder requirements
- [Virtual Motion Tracker](https://github.com/gpsnmeajp/VirtualMotionTracker): OSC messages, Index input mapping, ports
- [SlimeVR-Tracker-ESP](https://github.com/SlimeVR/SlimeVR-Tracker-ESP): tracker firmware
- [MediaPipe-VR-Fullbody-Tracking](https://github.com/ju1ce/Mediapipe-VR-Fullbody-Tracking): camera FBT fallback
- HackUMass hardware lab inventory, read 2026-11-13
