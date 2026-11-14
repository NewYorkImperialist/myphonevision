# myphonevision: read this first

HackUMass project: a SteamVR headset built from a Pixel 7 (display and head tracking, ALVR over USB to a Windows laptop), two 3D-printed ESP32 controllers that SteamVR sees as Index controllers (through the VMT driver), and SlimeVR body trackers. See [README.md](README.md) for the layout, [docs/goals.md](docs/goals.md) for the end goal (the whole desktop VR ecosystem, unmodified games) and timeline, and [docs/plan.md](docs/plan.md) for the full plan.

**When a teammate starts a session here, tell them their next steps from the plan below.** Ask which role they have if you can't tell.

## Current plan (as of 2026-11-14, early morning)

Four people. Three are in Amherst; Jayden arrives about 12 hours in and takes controllers + body tracking, then integration and the night shift. **The Amherst team is getting the lenses.** Best: a phone VR viewer (lenses, strap and foam in one; ask the Discord and organizers for an old Cardboard). Otherwise identical magnifiers: two of 5x or stronger, or four of 3x stacked two per eye (about 5–6x combined). Each lens must be under about 50 mm (2 in) across so two fit side by side. Measure the diameter, the thickness (of the whole stack if stacking) and the focal length (focus a window onto paper; lens-to-paper distance), then share the three numbers: they drive the headset CAD and the phone's lens QR code. See [headset/README.md](headset/README.md).

### Hardware on hand (2026-11-14)

| Have | Use |
| --- | --- |
| 2 ESP32 kits | Left and right controllers (`devkit_left`, `devkit_right`) |
| 1 generic ESP32-WROOM-32 board (FCC ID 2BB77-ESP32-32X, PCB antenna) | Hub (`firmware/hub`) |
| 3 MPU-6050 (GY-521) | One per controller, one spare |
| 2 Adafruit 512 analog thumb joysticks | One per controller; check the Y direction with `d` in the bench test (`STICK_INVERT_Y`) |
| 2 FSRs | Triggers |
| 3 push buttons | Face buttons |
| 2 lab "accelerometer/gyroscopic" sensors | Unidentified: read the chip markings |
| 1 Pololu IMU (label "imu0b 0j3865") | Unidentified MinIMU-9 version: read the back of the board |
| Logitech webcam | Camera body-tracking fallback |
| 2 Grove 3-axis digital accelerometers (±1.5 g, MMA7660) | Useless for tracking (tilt only, no gyro): return them |

**Still needed:** 5 more push buttons (each controller needs A, B, system, grip; 8 total), 2 vibration motors, 2 battery holders + AA cells (or the Anker pack). **Body tracking is short:** SlimeVR needs 3 more ESP32 boards and 5–6 gyro IMUs. Unless teammates can still check out DevKitCs, plan on webcam body tracking.

### Phone and streaming (TSVRN9)
**Headset phone is now a friend's iPhone 16 Pro; the Pixel 7 is the fallback** (issue #3: CAD `-D` values, software plan). The iPhone path is our own client built from [kotleni/iPhoneVR](https://github.com/kotleni/iPhoneVR) with ARKit pose; **Nafis (Nofees4Novembah) builds it on his Mac** ([phone/ios/README.md](phone/ios/README.md)); it's pinned to **ALVR v20.8.0**, so the laptop runs the v20.8.0 server for the iPhone (README: "Laptop setup for milestone 1") and the v21.0.0-dev14 nightly below only for the Pixel fallback. Keep the Pixel steps below working until the team picks a go/no-go time.

1. Confirm the Windows laptop's GPU is NVIDIA, AMD or Intel (hardware video encoder). If not, stop and re-plan (docs/plan.md, gate 1).
2. Install SteamVR and the **ALVR nightly v21.0.0-dev14** (ALVR only connects matching versions).
3. **Don't build PhoneVR.** Install the ready-made PR #458 app: `PhoneVR-v21.0.0-dev14-ARcore-v21-release-v1.0.1.apk` from https://github.com/righthandpaw/PhoneVR/releases. It already has reprojection and a Mali GPU fix (the Pixel 7 has a Mali GPU).
4. Get SteamVR Home onto the phone over USB: [phone/README.md](phone/README.md). Disable ALVR's own controllers.
5. Once the lenses are measured, run `tools/cardboard_qr.py` and scan the QR code with the app's "switch viewer" button.

### Industrial design
1. Install OpenSCAD: `brew install --cask openscad@snapshot` on macOS (the plain `openscad` cask is disabled), or a snapshot from openscad.org.
2. **Get the lenses** (see above) and measure them.
3. **Print fit tests first** ([cases/fit_tests.scad](cases/fit_tests.scad)): the **phone** slice now; **lens_seats** once the lenses are measured.
4. Export with the measured numbers: `tools/export-stl.sh -D lens_d=… -D lens_thk=… -D lens_f=…`, then start the headset print (about 6 h; `front` first).
5. Then the tracker cases and controller shells. Measure the real parts first ([cases/README.md](cases/README.md)).

### Third person: parts and bring-up
**Status (ygrfhf):** HUB, LEFT and RIGHT flashed and labeled; LEFT's GY-521 soldered and tested; end-to-end LEFT → hub → bridge works. 2 of 3 GY-521s are dead, so RIGHT needs a new one. Still to do: antennas (step 5), measurements (step 3), breadboard joystick/trigger/buttons (step 8, after Jayden's soldering). Handoff details in the Jayden issue.
1. Check out parts at the hardware desk, P0 first (ESP32 boards, GY-521 / motion sensors). Ask whether you can take Jayden's share (the limit is one of each item per attendee).
2. Ask the desk: which chip is the "Accelerometer/Gyroscopic Sensor"? Are there 2.4 GHz U.FL antennas? Is the limit per item or per pack?
3. Measure the lab's 4×AA battery holder, joystick board (and its screw-hole spacing) and push buttons; send the numbers to industrial design.
4. **Flash and label every board** (tape labels: HUB, LEFT, RIGHT, WAIST, L-LEG, R-LEG): hub `cd firmware/hub && pio run -t upload`; controllers `cd firmware/controller && pio run -e devkit_left -t upload` (and `devkit_right`); trackers `firmware/slimevr/build.sh upload` (add `WIFI_SSID=… WIFI_PASS=…` for the laptop hotspot).
5. **Antennas on every board:** U.FL antenna, or a 31 mm wire soldered to the U.FL center pin. Without one, range is under 1 m.
6. **Test every GY-521 before soldering it in:** wire each to a controller board ([docs/wiring.md](docs/wiring.md) step 2a), type `d` in `pio device monitor`, tilt it, and check roll/pitch follow. Set dead ones aside.
7. **Soldering prep:** header pins on the GY-521s and joysticks; 3 extension cables (chest, L ankle, R ankle), 4 wires, under 80 cm, order VCC, SDA, GND, SCL; **AD0 to 3V3 on each extension sensor**; Schottky diodes on the battery leads (stripe toward the board).
8. **One full controller on a breadboard** ([docs/wiring.md](docs/wiring.md) steps 2a–2e), then on the laptop run `python -m myphonevision_bridge --no-hmd --debug` and watch its packets arrive through the hub.
9. Leave final soldering, case fitting and tuning for Jayden (hour 12). If there's time, breadboard the second controller too.

### Everyone
- Decide the main demo: **VRChat with full-body tracking** (the arm model is enough) or **Beat Saber** (needs controller position tracking, rung 2: an iPhone running ZIG SIM, not built yet).

### Jayden (from hour 12)
Build both controllers from the tested parts ([docs/wiring.md](docs/wiring.md)), run the bridge, then body tracking, integration, demo and pitch.

- **Buttons:** each controller needs 4 (A, B, system, grip; stick click is on the joystick), so 8 total. 3 on hand, parts is sourcing 5 more (issue #2). If short, the **system** button goes on both controllers first: holding it 1 s is the drift reset.
- **Body tracking:** not enough ESP32 boards or gyro IMUs for SlimeVR (all 3 boards and 2 of 3 MPU-6050s go to the controllers and hub). Plan on **webcam tracking**: [docs/webcam-fbt.md](docs/webcam-fbt.md) (MediaPipe v0.7-beta, VRChat OSC mode, so it can't clash with VMT). Like SlimeVR, it needs head position working (ARKit on the iPhone, ARCore on the Pixel fallback). Switch back to SlimeVR only if 3 more boards and 5–6 gyro IMUs turn up.
- **Demo games:** native SteamVR games need no changes. Easiest to hardest: SteamVR Home, Fruit Ninja VR, Beat Saber, Minecraft (Vivecraft mod), VRChat with full-body tracking.

## State of the code

| Part | State |
| --- | --- |
| `firmware/controller`, `firmware/hub` | Compile for DevKitC (default) and Xiao ESP32S3 (PlatformIO, espressif32 6.12.0). **Running on hardware:** HUB, LEFT and RIGHT flashed; LEFT (with its GY-521) → ESP-NOW → hub → bridge at about 185 Hz. Gyro calibration retries 3× at boot (send `c` to recalibrate). Joystick, trigger and buttons not tested yet; RIGHT has no working GY-521 |
| `firmware/slimevr/build.sh` | Builds stock SlimeVR v0.7.4 for DevKitC + 2× MPU-6050; not yet flashed |
| `bridge/` (Python) | Hub serial or UDP to VMT OSC as Index controllers; 8 tests pass; `preflight` checks the setup; receives real hub packets (`--serial <port> --no-hmd --debug`); not yet run with SteamVR |
| `headset/`, `cases/` (OpenSCAD) | All parts render and export; sizes from datasheets until real parts are measured; nothing printed yet |
| PhoneVR | Use the published APK (above); lens settings via `tools/cardboard_qr.py` |
| `phone/ios/app` (iPhone client) | Builds and runs on the 16 Pro (free Apple ID). ARKit head pose, lens pass, rotational reprojection and 120 Hz done and checked in test mode (no server); **not yet streamed from SteamVR** (needs the laptop on ALVR v20.8.0); k1/k2 untuned until there are lenses |

## Working together (four people, four Claudes, one repo)

GitHub logins: NewYorkImperialist = Jayden, TSVRN9 = Pixel owner, Nofees4Novembah = Nafis, industrial design (headset, controller shells, lenses) and the iPhone app, ygrfhf = parts (add your role here on first commit).

- **Stay in your folders.** Pixel owner: `phone/`, `tools/windows/`, `tools/cardboard_qr.py`. Industrial design: `headset/`, `cases/`, `tools/export-stl.sh`; Nafis also `phone/ios/`. Parts and Jayden: `firmware/`, `bridge/`, `docs/wiring.md`. Need a change in someone else's folder? Open an issue for them instead of editing it.
- **Push small commits straight to `main`.** `git pull --rebase` before every push; never force-push. No PRs; they're too slow for a 36-hour build.
- **In this file, edit only your role's section and your rows of the state table.** Shared files (`README.md`, `docs/plan.md`) and the packet contract (`firmware/shared/packet.h` + `bridge/myphonevision_bridge/protocol.py`) change only after an issue that names everyone affected.

### Messaging between Claudes: GitHub issues

Issues are the team's message board, for people and their Claudes alike. One issue = one conversation (a question, a handoff, a measurement, a blocker). Everything you post goes out under your human's GitHub account.

- **Start a conversation:** `gh issue create --assignee <login> --title "Lens numbers for the headset" --body "…"`. Put the ask in the title. Assign whoever has to act; `@login` in the body pulls in anyone else.
- **Reply:** `gh issue comment N --body "…"`. Read a thread: `gh issue view N --comments`.
- **Finish:** close it when answered or done, from a commit (`Fixes #N`) or with `gh issue close N --comment "…"`.
- **Be self-contained:** the other Claude can't see your session. Include numbers, file paths and commit hashes, not "as discussed".
- **What goes in an issue:** measurements (lens diameter, thickness and focal length; battery holder and joystick sizes), requests to change someone else's folder or the packet contract, hardware swaps, and anything that blocks you.
- **Your inbox is automatic.** Hooks in `.claude/settings.json` run `tools/inbox.sh`: at session start it pulls `main` and lists every open issue involving you; after that it shows only issues someone else has updated, on each prompt and mid-task after tool calls (at most every 2 minutes), and when you try to finish (at most every 30 seconds; it holds you back once to handle new messages, then lets you finish). When messages appear, tell your human, then answer or act on them. Ask your human before anything big, destructive or outside your role.
- **Don't reply just to acknowledge.** Comment only with an answer, a result or a question; two Claudes trading "thanks, got it" will wake each other up forever.
- Needs `gh` installed and logged in (`gh auth login`). Approve the project hooks when Claude Code asks.

## Rules for working in this repo

- **No Claude attribution.** Don't add `Co-Authored-By: Claude` or "Generated with Claude Code" lines to commits or PR descriptions. Commits are authored by the teammate making them.
- **Measure before printing.** Every CAD size is a parameter; pass measured values with `-D` instead of editing defaults blindly. Print fit tests before long prints.
- **Keep firmware and bridge in sync:** the packet format lives in `firmware/shared/packet.h` and is mirrored in `bridge/myphonevision_bridge/protocol.py`. Change both or neither.
- **Verify, don't assume:** after changing firmware, run `pio run` in that folder. After changing the bridge, run `pytest` in `bridge/`. After changing CAD, render the part and look at it.
- **Update this file** when the plan or the state above changes (who's doing what, what's done, what's blocked), so the next person's Claude starts with the truth.
