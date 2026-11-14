# PC bridge

Reads controller packets from the ESP-NOW hub (USB serial, 921600 baud) or straight from controllers over UDP. Sends them to [Virtual Motion Tracker](https://github.com/gpsnmeajp/VirtualMotionTracker) as Index-compatible controllers over OSC on port 39570.

```sh
pip install -e .              # on Windows and Linux this also installs openvr
python -m myphonevision_bridge --debug               # auto-detects the hub's COM port
python -m myphonevision_bridge --serial COM5
python -m myphonevision_bridge --udp 39600           # controllers built with *_udp
python -m myphonevision_bridge --no-hmd --debug      # bench test without SteamVR
```

Start SteamVR first: the bridge reads the headset pose through OpenVR.

## Pre-demo check

```sh
python -m myphonevision_bridge.preflight
```

Run it before starting the bridge. It checks for the hub on USB, the VMT driver (VMT sends `/VMT/Out/Alive` every few seconds on its own, per its source), the SlimeVR server, and, through SteamVR, the headset, both VMT controllers and the SlimeVR trackers. Each line says OK, WARN or FAIL with the fix, and the exit code is non-zero if anything failed.

## What it does

- **Pose:** `/VMT/Raw/Driver`, with enable 5 (left) / 6 (right) from the first packet, because VMT latches the device type on first sight. VMT still rejects every pose until a room matrix has been set once (VMT Manager on Windows; `tools/linux/vmt.sh` sets one on Linux), though raw poses don't use it.
- **Position (rung 1, arm model):** a shoulder fixed under the head, an elbow that follows the controller 40%, and a forearm along the controller. Good for pointing, menus and VRChat; Beat Saber will feel wrong.
- **Orientation:** IMU quaternion, then the `--mount` preset, then a yaw offset. **Click and hold the thumbstick for 1 s** (stick centered) to snap the controller's heading to the head's; it buzzes when done. Keep holding to 3 s for a system click (SteamVR menu; a longer buzz). The controllers have no system button; a board that has one still works the same way (hold 1 s to snap, tap for a system click). A stick click while pushing the stick (sprint) never snaps. It works pointing at the floor or ceiling too, but holding it level is most accurate. If hands look tilted up or down in games, add `--pitch-trim DEG` (positive raises the nose); VMT hands games the Index profile's grip pose, which can sit at an angle to the raw one. The MPU-6050 drifts, so expect to snap every 1–5 minutes.
- **Inputs:** trigger (value, touch, click above 0.9), grip (as a 0/1 value), A, B, system, and thumbstick (axes, click, touch), using VMT's Index mapping.
- **Haptics:** listens for `/VMT/Out/Haptic` on port 39571 and forwards it to the right controller. VMT Manager also uses 39571, so close it while playing.

VMT's message formats and Index input indices were checked against its driver source, `vmt_driver/CommunicationManager.cpp` and `TrackedDeviceServerDriver.cpp`.

## Check on site

- Run `--debug-follow` once. Both controllers should float 30 cm in front of the headset. If they're somewhere else, the OpenVR raw universe and VMT's raw driver space don't match on this setup. Then switch to `/VMT/Room/Driver` after setting the room matrix from VMT Manager.
- SteamVR may need the hand roles reassigned once if ALVR's controllers are still enabled. Turn them off in ALVR.

## Not built yet

- Rung 2: an iPhone on each controller running ZIG SIM Pro (ARKit pose over OSC), aligned to the head with a docking press.
- Rung 3: Leap Motion hand position from the Leap SDK.

## Tests

```sh
pip install -e '.[dev]' && pytest
```
