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
**Headset phone is now a friend's iPhone 16 Pro; the Pixel 7 is the fallback** (issue #3: CAD `-D` values, software plan). The iPhone path is our own client built from [kotleni/iPhoneVR](https://github.com/kotleni/iPhoneVR) with ARKit pose; **Nafis (Nofees4Novembah) builds it on his Mac** ([phone/ios/README.md](phone/ios/README.md)); it's on ALVR v21.0.0-dev14 (62e0fc3). **Streaming works end to end over USB** (iPhone Personal Hotspot, 172.20.10.1): 60 fps, ~36 ms total latency, smooth with reprojection on and head prediction off (`ios-app` 0f26fda: 60 Hz ARKit + gyro fill-in). Linux fixes are in [phone/README.md](phone/README.md) steps 6–9, including `tools/linux/alvr-pose-patch.sh` (without it the stream freezes every few seconds). **The streaming laptop runs Fedora Linux** (Intel Arc 140V): ALVR v20.8.0 fails there with error 307; use v21.0.0-dev14. VMT is Windows-only upstream, so `tools/linux/vmt.sh` builds VMT v0.15 as a Linux driver and registers it; the bridge talks to it unchanged. Keep the Pixel steps below working until the team picks a go/no-go time.

1. Confirm the Windows laptop's GPU is NVIDIA, AMD or Intel (hardware video encoder). If not, stop and re-plan (docs/plan.md, gate 1).
2. Install SteamVR and the **ALVR nightly v21.0.0-dev14** (ALVR only connects matching versions).
3. **Don't build PhoneVR.** Install the ready-made PR #458 app: `PhoneVR-v21.0.0-dev14-ARcore-v21-release-v1.0.1.apk` from https://github.com/righthandpaw/PhoneVR/releases. It already has reprojection and a Mali GPU fix (the Pixel 7 has a Mali GPU).
4. Get SteamVR Home onto the phone over USB: [phone/README.md](phone/README.md). Disable ALVR's own controllers.
5. Once the lenses are measured, run `tools/cardboard_qr.py` and scan the QR code with the app's "switch viewer" button.

### Industrial design
**Status (Nafis, 2026-11-14 evening):**
- **Controller parts measured, on `main`** (merge 46eba10). Joystick: hole 25.8 and 13.5 mm posts (`joy_depth` 15.9), after two fit test prints. Panel-mount buttons: thread 14.84, ring 19.19, 14.46 deep. ESP32: 51.5 × 28.23. Jayden's `controller-shells` (A button only, measured battery and FSR, `handle_fit` test) builds on these.
- **Headset:** the phone slice v2 fits; the phone holder redesign is parked. Lenses are two Carson TriView TV-26, 3 stacked per eye. Jayden's `lens-tubes` (sliding focus tubes) is printing `front`, `tube` and `tube_fit`.
- **Face foam:** got it. **Strap:** a teammate is getting one from a friend (#9); not on Nafis.
- **Headset vs. Cardboard:** the team may build a Google Cardboard-style viewer instead if the printed headset won't be ready in time. Not decided; if it's Cardboard, the iPhone app's lens defaults change and the tube reprints stop.

1. Lens sizes measured with calipers: ring **38.75**, stack **21.09** (`lens-tubes` 7bd3826). The tube keeps its 41.5 outside, so the printed front still fits; **reprint `tube_fit`, 2 × `tube` and 2 × `lens_ring`** from 7bd3826 (#4). Focal length and phone distance are estimates the focus tubes' travel covers.
2. Once `tube_fit` slides right, merge `lens-tubes` into `main`.
3. OpenSCAD: `brew install --cask openscad@snapshot` on macOS (the plain `openscad` cask is disabled). It crashes inside Claude Code's sandbox (a "neon" Qt error); run it outside, or with the sandbox off.
4. Print one file at a time, the part's fit test first (`tools/upload-print.sh FILE` gives the makerspace pickup code).

### Third person: parts and bring-up
**Status (ygrfhf):** both controllers wired and tested, running wirelessly on 4×AA through the hub (LEFT ~195 Hz, RIGHT ~148 Hz). Each has IMU, joystick, A button, FSR grip (RIGHT's needs replacing; the bridge sends it as grip, there is no trigger), antenna (vibration dropped 2026-11-15 to make room in the case). LEFT has a GY-521, RIGHT an Adafruit BNO055. Grip, B and system buttons dropped. What goes in the shells, with sizes: [docs/wiring.md](docs/wiring.md) step 2h.
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

### Jayden (on site since 2026-11-14 midday)
Build both controllers from the tested parts ([docs/wiring.md](docs/wiring.md)), run the bridge, then integration, demo and pitch. **Lenses:** two Carson TriView **TV-36** magnifiers (Jayden has them); Nafis's calipers: ring 38.75, stack 21.09. **Tonight's headset is cardboard** (`headset/cardboard/`, #10) with the whole magnifiers, **not cut out**, at **5.5x** (top and bottom lenses swung out, middle left in; screen ~30 mm behind the bottom lens, TSVRN9's bench test). Template regenerated at 0e05757: reprint `template.pdf` if printed earlier. The printed `lens-tubes` headset is parked; the tube in Jayden's first print (38.3 seat) is too small for these rings. Face foam: Nafis has it; strap: coming from a teammate's friend (#9).

- **Controllers (issue #2):** both built by ygrfhf and running wirelessly on 4×AA (LEFT GY-521, RIGHT BNO055). **One button each (A)**; B, system and grip are dropped. **Drift reset = click and hold the thumbstick 1 s** (stick centered); hold to 3 s for a system click (SteamVR menu). **Shells: TSVRN9's concept D** (`cases/mockups/controller/`; fit test passed; plates A + B = one controller, PCM pickup code 2DUQ, #10). Jayden's `controller-shells` / `handle_fit` are dropped. Yaw drift fix to flash and test: #11.
- **Test game: `game/saber_playground.py`** (our own SteamVR app: a blade per hand, slice floating cubes, haptics on hits; `game/README.md`). Desktop mode tested on macOS; **not yet run in SteamVR**. Needs `pip install -r game/requirements.txt` on the laptop.
- **Body tracking: cut for now** (team decision, 2026-11-14). Focus on the headset and both controllers. If it comes back: the laptop runs Linux, so `docs/webcam-fbt.md` (a Windows download and Windows-only driver) won't work as written; the idea was our own MediaPipe webcam tracker feeding VMT trackers through the bridge.
- **Demo games:** native SteamVR games need no changes, but the laptop runs Linux, so most run through Proton (Steam → Settings → Compatibility → enable Steam Play for all titles; start SteamVR before the game). Check a game on db.vronlinux.org or ProtonDB before buying. Easiest to hardest: SteamVR Home, Fruit Ninja VR, Beat Saber, Minecraft (Vivecraft mod).

## State of the code

| Part | State |
| --- | --- |
| `firmware/controller`, `firmware/hub` | Compile for DevKitC (default) and Xiao ESP32S3 (PlatformIO, espressif32 6.12.0). **Running on hardware:** HUB, LEFT, RIGHT; both controllers → ESP-NOW → hub → bridge on battery. Auto-detects MPU-6050 or BNO055; `STICK_INVERT_Y 0` for the Adafruit 512. Gyro calibration retries 3× at boot (send `c` to recalibrate). BNO055 tilt not yet checked in a shell |
| `firmware/slimevr/build.sh` | Builds stock SlimeVR v0.7.4 for DevKitC + 2× MPU-6050; not yet flashed |
| `bridge/` (Python) | Hub serial or UDP to VMT OSC as Index controllers; 8 tests pass; `preflight` checks the setup; receives real hub packets (`--serial <port> --no-hmd --debug`); not yet run with SteamVR |
| `headset/`, `cases/` (OpenSCAD) | All parts render and export. **Controller:** joystick, buttons and ESP32 measured; joystick mount checked with two fit test prints. **Headset:** phone thickness and bump measured, phone slice printed and fits; lens rings 38.75 and stack 21.09 measured (Carson TriView 3-stack), focal length estimated and covered by the focus tubes (#4); `front` from `lens-tubes` still fits; `tube`, `tube_fit`, `lens_ring` need reprinting from 7bd3826 (not merged) |
| PhoneVR | Use the published APK (above); lens settings via `tools/cardboard_qr.py` |
| `tools/linux/vmt.sh` (VMT on Linux) | Builds and loads in SteamVR 2.18.4 next to ALVR v21; answers `/VMT/Out/Alive`; test poses show up as VMT_0 left / VMT_1 right Index controllers (preflight OK); button and trigger input reach SteamVR. **End to end on Linux:** LEFT → hub → bridge (~197 Hz) → VMT → SteamVR, tracked (Running_OK) on the left-hand role. VMT rejects every pose until a room matrix is set (if `setting.json` goes missing, send `/VMT/SetRoomMatrix` with an identity matrix). **Test 2026-11-14 18:00 (as-built, latest bridge):** LEFT ~195 Hz, tilt tracks, stick full range + click OK, FSR grip only reaches 26% (`TRIGGER_RAW_MAX` 3500 too high), A not seen (LEFT was off for the retest). RIGHT ~150 Hz with a dropout (antenna?), A works, FSR reads 0. Haptics untested |
| `phone/ios/app` (iPhone client) | Builds and runs on the 16 Pro (free Apple ID). **ALVR v21.0.0-dev14** (62e0fc3, the laptop's nightly), merged with AR passthrough (LiDAR depth, people/hand occlusion; objects drift in 3D: open). ARKit head pose filled in by the gyro, lens pass, rotational reprojection, 120 Hz, USB link over Personal Hotspot. Checked in test mode (no server); **not yet streamed from SteamVR**. Lens defaults for the TriView 3-stack (screen to lens 30.5 mm, FOV 45° per side); k1/k2 untuned until the stack is in the headset |

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
- **Print one file at a time, test file first.** Never send a whole STL folder to the printer (it prints every part in it). Before any long print, print that part's small test file alone and check it by hand: headset `tube_fit` (branch `lens-tubes`), controller `handle_fit` (branch `controller-shells`), or a `cases/fit_tests.scad` part. When telling someone what to print, name the single file.
- **Keep firmware and bridge in sync:** the packet format lives in `firmware/shared/packet.h` and is mirrored in `bridge/myphonevision_bridge/protocol.py`. Change both or neither.
- **Verify, don't assume:** after changing firmware, run `pio run` in that folder. After changing the bridge, run `pytest` in `bridge/`. After changing CAD, render the part and look at it.
- **Update this file** when the plan or the state above changes (who's doing what, what's done, what's blocked), so the next person's Claude starts with the truth.
