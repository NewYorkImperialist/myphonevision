# myphonevision: read this first

HackUMass project: a SteamVR headset built from a Pixel 7 (display and head tracking, ALVR over USB to a Windows laptop), two 3D-printed ESP32 controllers that SteamVR sees as Index controllers (through the VMT driver), and SlimeVR body trackers. See [README.md](README.md) for the layout and [docs/plan.md](docs/plan.md) for the full plan.

**When a teammate starts a session here, tell them their next steps from the plan below.** Ask which role they have if you can't tell.

## Current plan (as of 2026-11-14, early morning)

Four people. Three are in Amherst; Jayden arrives about 12 hours in and takes controllers + body tracking, then integration and the night shift. **The Amherst team is getting the lenses.** Best: a phone VR viewer (lenses, strap and foam in one; ask the Discord and organizers for an old Cardboard). Otherwise identical magnifiers: two of 5x or stronger, or four of 3x stacked two per eye (about 5–6x combined). Each lens must be under about 50 mm (2 in) across so two fit side by side. Measure the diameter, the thickness (of the whole stack if stacking) and the focal length (focus a window onto paper; lens-to-paper distance), then share the three numbers: they drive the headset CAD and the phone's lens QR code. See [headset/README.md](headset/README.md).

### Pixel owner: phone and streaming
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
1. Check out parts at the hardware desk, P0 first (ESP32 boards, GY-521 / motion sensors). Ask whether you can take Jayden's share (the limit is one of each item per attendee).
2. Ask the desk: which chip is the "Accelerometer/Gyroscopic Sensor"? Are there 2.4 GHz U.FL antennas? Is the limit per item or per pack?
3. Measure the lab's 4×AA battery holder, joystick board (and its screw-hole spacing) and push buttons; send the numbers to industrial design.
4. Flash one controller and wire one motion sensor on a breadboard: [docs/wiring.md](docs/wiring.md) step 2a. Prove the parts work.

### Everyone
- Decide the main demo: **VRChat with full-body tracking** (the arm model is enough) or **Beat Saber** (needs controller position tracking, rung 2: an iPhone running ZIG SIM, not built yet).

### Jayden (from hour 12)
Build both controllers and all three SlimeVR boards from the tested parts ([docs/wiring.md](docs/wiring.md)), run the bridge, then integration, demo and pitch.

## State of the code

| Part | State |
| --- | --- |
| `firmware/controller`, `firmware/hub` | Compile for DevKitC (default) and Xiao ESP32S3 (PlatformIO, espressif32 6.12.0); reviewed; **not yet run on hardware** |
| `firmware/slimevr/build.sh` | Builds stock SlimeVR v0.7.4 for DevKitC + 2× MPU-6050; not yet flashed |
| `bridge/` (Python) | Hub serial or UDP to VMT OSC as Index controllers; 8 tests pass; `preflight` checks the setup; not yet run with SteamVR |
| `headset/`, `cases/` (OpenSCAD) | All parts render and export; sizes from datasheets until real parts are measured; nothing printed yet |
| PhoneVR | Use the published APK (above); lens settings via `tools/cardboard_qr.py` |

## Rules for working in this repo

- **No Claude attribution.** Don't add `Co-Authored-By: Claude` or "Generated with Claude Code" lines to commits or PR descriptions. Commits are authored by the teammate making them.
- **Measure before printing.** Every CAD size is a parameter; pass measured values with `-D` instead of editing defaults blindly. Print fit tests before long prints.
- **Keep firmware and bridge in sync:** the packet format lives in `firmware/shared/packet.h` and is mirrored in `bridge/myphonevision_bridge/protocol.py`. Change both or neither.
- **Verify, don't assume:** after changing firmware, run `pio run` in that folder. After changing the bridge, run `pytest` in `bridge/`. After changing CAD, render the part and look at it.
- **Update this file** when the plan or the state above changes (who's doing what, what's done, what's blocked), so the next person's Claude starts with the truth.
