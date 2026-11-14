# SlimeVR body trackers

Use stock SlimeVR: its firmware, server and SteamVR driver. VRChat already supports it. The only work here is wiring, configuration, cases and straps. The full-body skeleton hangs off the HMD's position, so this needs ARCore head position (fork change 2). With a 3DoF head the body stays pinned in place.

## Boards

Three ESP32-DevKitC-32UE boards, each with two MPU-6050s: the primary at 0x68 (AD0 low) and an extension at 0x69 (AD0 high).

| Board | Primary IMU (0x68) | Extension IMU (0x69) | Power |
| --- | --- | --- | --- |
| Waist | Hip | Chest | Anker PowerCore Slim on the belt |
| Left thigh | Left knee/thigh | Left ankle | 4×AA holder |
| Right thigh | Right knee/thigh | Right ankle | 4×AA holder |

- Keep extension cables under 80 cm. Don't run SDA and SCL side by side; put ground between them.
- The 32UE has a U.FL connector and no PCB antenna. Fit a 2.4 GHz antenna from the desk, or solder a 31 mm wire to the U.FL center pin.

## Firmware

`build.sh` builds SlimeVR v0.7.4 for our setup: a DevKitC with two MPU-6050s on SDA 21 / SCL 22 at 0x68 and 0x69. It clones SlimeVR into `SlimeVR-Tracker-ESP/` (gitignored) and swaps the board's default sensor list (which assumes BNO085s) for [tracker.json](tracker.json). No SlimeVR files are edited.

```sh
./build.sh                                        # build only (checked: compiles)
WIFI_SSID=myhotspot WIFI_PASS=secret ./build.sh upload   # flash one board, hotspot baked in
```

Run `upload` once per board, plugged in over micro-USB. Without `WIFI_SSID`, set the Wi-Fi from the SlimeVR server after flashing. The first build downloads SlimeVR's toolchain (Arduino-ESP32 3.0.1), so run it once on good internet before the hackathon.

- **Different IMU** (if the desk's sensor turns out to be a BNO085 or ICM part): change `"imu"` in `tracker.json`, for example to `IMU_BNO085` or `IMU_ICM42688`.
- **One IMU on a board:** delete the second entry.
- **Mounting rotation:** leave it at `DEG_0` and set each tracker's mounting in the SlimeVR server.

## Network

The firmware can't join UMass enterprise Wi-Fi. Start a 2.4 GHz Windows Mobile Hotspot on the laptop and give the trackers its SSID through the SlimeVR server's Wi-Fi setup.

## Drift

The MPU-6050 needs a reset every 1–5 minutes. Bind SlimeVR's full reset to a key and reset before each demo run.

## If IMU trackers slip

Camera-based tracking needs nothing worn but is worse: the player must face the camera. Options are PinoFBT (iPhone; free for chest and hip, legs need its subscription) and [MediaPipe-VR-Fullbody-Tracking](https://github.com/ju1ce/Mediapipe-VR-Fullbody-Tracking) (webcam or phone camera on the PC).
