# Webcam body tracking (fallback for SlimeVR)

Use this if there aren't enough ESP32 boards and gyro IMUs for SlimeVR (we have 3 MPU-6050s and 3 boards, all needed for the controllers and hub). [MediaPipe-VR-Fullbody-Tracking](https://github.com/ju1ce/Mediapipe-VR-Fullbody-Tracking) watches you through the Logitech webcam and turns your pose into hip and foot trackers. Nothing is worn. It's less accurate than IMU trackers: you have to stay in the camera's view, and depth is weak.

**It hangs the skeleton off the headset's position, like SlimeVR.** With a 3DoF head (no ARCore position), the body stays pinned in place. Get the phone's ARCore position working first.

## Which version

| Version | How it reaches the game | Use when |
| --- | --- | --- |
| **v0.7-beta, "VRChat OSC" backend** (recommended) | Sends trackers straight to VRChat over OSC (port 9000). No SteamVR driver | The demo is VRChat. It can't conflict with VMT, our controller driver |
| v0.6 (stable) | Installs its own SteamVR driver ("apriltagtrackers") that spawns 3 Vive trackers | You need the trackers in SteamVR itself (other games) |

Downloads, from the [releases page](https://github.com/ju1ce/Mediapipe-VR-Fullbody-Tracking/releases): `mediapipepose-0.7-beta-windows.zip` (153 MB) or `MediaPipePose-v0.6.zip` (179 MB). Download on good Wi-Fi before you need it.

Port check: VMT uses 39570/39571 and VRChat OSC uses 9000, so the three don't clash.

## Setup (v0.7-beta, VRChat OSC)

1. **Place the webcam:** it must see your **whole body, head to feet**, ideally mounted high and tilted down. Light from the camera's direction, no bright window behind you, clothes that contrast with the background. Leave about 2–3 m between you and the camera.
2. Unzip the release anywhere and run `start_mediapipepose.bat`.
3. In the settings window:
   - **IP or ID of camera:** `0` for the Logitech webcam (try 1, 2… if 0 doesn't open; close Discord or other camera apps first).
   - **Backend:** VRChat OSC. Leave the IP at the default: VRChat runs on the same laptop.
   - Leave the other options at their defaults. Press **Save and continue**.
4. A camera window and a runtime-settings window open. Check the skeleton overlay follows you in the camera window.
5. Start SteamVR (headset streaming through ALVR, controllers through the bridge), then VRChat. In VRChat, enable OSC (Action menu → Options → OSC → Enabled).
6. **Calibrate:** stand straight, look straight ahead, then press **Recalibrate** in the runtime window (from the SteamVR dashboard's desktop view). In OSC mode, auto-calibration doesn't fix Y rotation: turn the rotation slider until the skeleton faces the way you face.
7. In VRChat, run its full-body calibration as usual.

## Setup differences for v0.6 (SteamVR driver)

- Before the first run, install the driver: `driver_files/install_driver.exe`. Check SteamVR → Settings → Startup → Add-ons that "apriltagtrackers" is enabled.
- After the first launch, **controllers may vanish or stop working. Restart SteamVR** (the README notes this). Run `python -m myphonevision_bridge.preflight` after the restart to confirm the VMT controllers are back.
- Calibrate from inside VR with **Recalibrate** while standing straight; you should then see 3 trackers at your hips and feet.

## Tuning

| Setting | Start at | Notes |
| --- | --- | --- |
| Model complexity (advanced mode) | 1; try **0** | The laptop is also encoding ALVR video, so CPU is tight. 0 is faster, slightly less accurate |
| Smoothing window | 0.5 | Higher is smoother but laggier |
| Additional smoothing | 0.7 | OSC mode uses this instead of the smoothing window |
| HMD-to-neck offset (advanced) | default (0.2 m down, 0.1 m back) | If tilting your head moves your legs, nudge it: [README troubleshooting](https://github.com/ju1ce/Mediapipe-VR-Fullbody-Tracking#troubleshooting) |

## When it goes wrong

| Symptom | Fix |
| --- | --- |
| Camera doesn't open | Try IDs 0–3; close other apps using the camera; set the width and height to the camera's resolution |
| "Connection to SteamVR fails" (v0.6) | SteamVR open with the headset connected; driver installed and enabled; if SteamVR runs as admin, run `bin/mediapipepose.exe` as admin too. Or switch to v0.7 OSC mode |
| Body pinned in place, legs move but you don't travel | The headset has no position (3DoF). Fix ARCore in the PhoneVR app first |
| Jittery legs | More light, contrasting clothes, whole body in frame; raise the smoothing |
| Controllers gone after installing v0.6 | Restart SteamVR |
| DLL load failed on startup | Windows "N" edition: install the Media Feature Pack |

## Demo tips

- Mount the webcam before the demo and mark the floor spot where the player stands.
- Judges only need to see legs move in a mirror in VRChat. Short runs, recalibrate between players.
- The tool can also spawn hand trackers from the webcam (a dev option) for rough controller position. Its author calls it poor; ignore it unless controller position becomes urgent.

Source: the project's [README](https://github.com/ju1ce/Mediapipe-VR-Fullbody-Tracking) and [releases](https://github.com/ju1ce/Mediapipe-VR-Fullbody-Tracking/releases) (v0.7-beta, May 2023; v0.6, March 2022), read 2026-11-14.
