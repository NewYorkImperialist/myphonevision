> **These are the original goals from 2026-11-13, and the build changed:** an iPhone 16 Pro instead of the Pixel 7 (now the fallback), a Fedora Linux laptop with VMT built for Linux, a laser-cut cardboard headset, no body tracking, and controllers with only a stick, an A button and an FSR grip (no rumble). See [README.md](../README.md) for the current build.

# Goals

The end goal: **a phone-and-printed-parts VR kit that works with the whole desktop VR ecosystem.** Any PC VR game runs unmodified, because every device shows up in SteamVR as a standard device. We write drivers and bridges, never game-specific code. From the proposal of 2026-11-13, updated for the iPhone 16 Pro headset (issue #3). The decisions, parts and risks are in [plan.md](plan.md).

## What "the whole ecosystem" means

| Layer | How we reach it | State |
| --- | --- | --- |
| SteamVR (OpenVR) games | The phone is an ALVR HMD; controllers are Index controllers through VMT; body trackers through SlimeVR or webcam FBT | The path we're building |
| OpenXR PC games | SteamVR is an OpenXR runtime, so they run through the same devices | Comes free once SteamVR works; test one OpenXR title |
| Oculus/Meta PC-only games | [Revive](https://github.com/LibreVR/Revive) translates them to SteamVR | Stretch; unverified with our setup |
| Game input | Index controller emulation, so games' default Index bindings apply | Bridge maps stick, trigger, A, B, system, grip; rumble back from VMT |

Demo ladder, easiest to hardest: SteamVR Home, Fruit Ninja VR, Beat Saber, Minecraft (Vivecraft), VRChat with full-body tracking. Pick the hero demo before choosing a controller tracking rung (below).

## Principles

- **Standard SteamVR devices only.** HMD through ALVR, controllers through VMT, trackers through SlimeVR or MediaPipe FBT. Nothing a game has to know about.
- **Venue Wi-Fi never touches the tracking path.** Phone on USB (or the laptop's hotspot), controllers on ESP-NOW to a USB hub, trackers on a private hotspot.
- **Every tier has a working fallback**, so the demo degrades instead of failing: iPhone app → Pixel APK; 6DoF head → 3DoF plus reprojection; IMU trackers → webcam; controller position → arm model.
- **Missing a gate means taking its fallback, not moving the gate.**
- **Measure, then print.** Every CAD size is a parameter; fit tests before long prints.

## Timeline (36 hours, 4 gates)

| Hours | Phase | Work | Gate at the end |
| --- | --- | --- | --- |
| 0–3 | Gates and first light | Check out scarce parts; lens run; SteamVR + ALVR on the laptop; first light with the Pixel APK while the iPhone app starts | **Hour 3:** SteamVR Home on a phone over USB; lenses in hand |
| 3–10 | Bring-up | Lens fit tests, then the headset shell; iPhone app milestones 1–2; one controller in SteamVR via VMT; webcam FBT running | **Hour 10:** a controller and body tracking in SteamVR; iPhone video + ARKit pose, or commit to the Pixel |
| 10–20 | Build, overnight | Print headset and controller shells; iPhone reprojection and distortion; both controllers in shells with stick, trigger, buttons, rumble | **Hour 20:** 6DoF head and full body in a mirror, else ship 3DoF |
| 20–30 | Integrate and stretch | Controller rung 2 or 3; calibration and reset flow; strap and foam fit; script the hero demo | **Hour 30:** feature freeze; only fixes and finish after |
| 30–36 | Polish and demo | Rehearse end to end; record a backup video; Devpost write-up; fresh batteries, phone cool-down, spare cable | Demo |

## Ideas and stretch goals

**Controller position, in rungs.** Ship each before trying the next.

1. **Arm model** (built, in the bridge): shoulder from the 6DoF head plus fixed offsets, elbow and wrist from controller orientation. Good for pointing, menus and VRChat; Beat Saber feels wrong.
2. **iPhone on each controller:** ZIG SIM Pro (paid) streams ARKit 6DoF pose over OSC at up to 60 fps. The ESP32 still does buttons. Align each phone to the head frame with one press while the controller sits in a printed dock on the headset; gravity is shared, so only yaw and offset are solved. Required for Beat Saber. Now that we write iOS code, a small ARKit-to-OSC app of our own is an alternative to ZIG SIM.
3. **Leap Motion** (the lab has four): mounted on the headset front it gives hand position relative to the head, no frame alignment. Fuse with the controller IMU's orientation. SDraw's SteamVR Leap driver is archived, so read the Leap SDK in the bridge.

**Headset**

- Optics targets: 40–50 mm focal length, 25–35 mm lenses. Expect about 66° vertical FOV at 50 mm, 56° at 62 mm.
- Adjustable IPD (a slider instead of the fixed 63 mm).
- Reuse a donor viewer's strap and face foam; elastic and velcro otherwise.

**Tracking quality**

- A better IMU than the MPU-6050 (BNO085 or ICM) if the desk's unidentified sensors turn out to be one: much less drift.
- Drift handling: gyro bias calibration on boot (2 s still), system button held 1 s snaps controller yaw to head yaw, SlimeVR full reset on a key before each run.
- Back to SlimeVR IMU body tracking if 3 more ESP32 boards and 5–6 gyro IMUs turn up.

**If there's no Windows GPU laptop** (gate 1 fails): a standalone phone app with controllers over BLE. It loses SteamVR and the ecosystem, so it's the last resort.
