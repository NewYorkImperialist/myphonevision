# PC bridge

Reads controller packets from the ESP-NOW hub (USB serial, 921600 baud) or straight from controllers over UDP. Sends them to [Virtual Motion Tracker](https://github.com/gpsnmeajp/VirtualMotionTracker) as Index-compatible controllers over OSC on port 39570.

```sh
pip install -e .              # on Windows this also installs openvr
python -m myphonevision_bridge --debug               # auto-detects the hub's COM port
python -m myphonevision_bridge --serial COM5
python -m myphonevision_bridge --udp 39600           # controllers built with *_udp
python -m myphonevision_bridge --no-hmd --debug      # bench test without SteamVR
```

Start SteamVR first: the bridge reads the headset pose through OpenVR.

## What it does

- **Pose:** `/VMT/Raw/Driver`, with enable 5 (left) / 6 (right) from the first packet, because VMT latches the device type on first sight. Raw driver space needs no room matrix.
- **Position (rung 1, arm model):** a shoulder fixed under the head, an elbow that follows the controller 40%, and a forearm along the controller. Good for pointing, menus and VRChat; Beat Saber will feel wrong.
- **Orientation:** IMU quaternion, then the `--mount` preset, then a yaw offset. **Hold system for 1 s** to snap the controller's heading to the head's; it buzzes when done. A short tap is a normal system click. The MPU-6050 drifts, so expect to snap every 1–5 minutes.
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
