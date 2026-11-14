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

1. Clone [SlimeVR-Tracker-ESP](https://github.com/SlimeVR/SlimeVR-Tracker-ESP) and open it in PlatformIO. (PlatformIO is restored at `~/.platformio` on the Mac.)
2. In `platformio.ini`, select the `esp32dev` environment.
3. In `src/defines.h`, set the IMUs explicitly. The firmware does **not** auto-detect the MPU-6050. On the versions in our notes that means:

   ```c
   #define IMU IMU_MPU6050
   #define SECOND_IMU IMU_MPU6050
   #define BOARD BOARD_WROOM32
   #define PIN_IMU_SDA 21
   #define PIN_IMU_SCL 22
   ```

   Newer firmware may describe sensors in a list macro instead. Follow the comments in the `defines.h` you cloned, keeping the same chips, addresses and pins. If the desk's "Accelerometer/Gyroscopic Sensor" turns out to be a BNO085 or ICM part, use that IMU type instead.
4. Flash one board with one IMU first, and check that it appears in the SlimeVR server.

## Network

The firmware can't join UMass enterprise Wi-Fi. Start a 2.4 GHz Windows Mobile Hotspot on the laptop and give the trackers its SSID through the SlimeVR server's Wi-Fi setup.

## Drift

The MPU-6050 needs a reset every 1–5 minutes. Bind SlimeVR's full reset to a key and reset before each demo run.

## If IMU trackers slip

Camera-based tracking needs nothing worn but is worse: the player must face the camera. Options are PinoFBT (iPhone; free for chest and hip, legs need its subscription) and [MediaPipe-VR-Fullbody-Tracking](https://github.com/ju1ce/Mediapipe-VR-Fullbody-Tracking) (webcam or phone camera on the PC).
