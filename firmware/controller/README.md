# Controller firmware

Runs on an **ESP32-DevKitC** (default) or a **Seeed Xiao ESP32S3**. Each controller reads an IMU (an MPU-6050 or a BNO055, whichever answers on I2C), a thumbstick with click, an FSR grip and an A button. It fuses orientation with a Mahony filter and sends a 200 Hz packet ([../shared/packet.h](../shared/packet.h)) by ESP-NOW broadcast on channel 1 to the hub (as built, the bridge sees LEFT at about 195 Hz and RIGHT at about 150 Hz). The firmware also reads B, system and grip buttons and drives a vibration motor from haptic packets, but the as-built controllers have none of those, so nothing buzzes.

```sh
pio run -e devkit_left -t upload    # DevKitC, left hand (devkit_right for right)
pio run -e xiao_left -t upload      # Xiao ESP32S3 instead
pio device monitor             # status, gyro bias, IMU errors
```

**After power-on, keep the controller still for 2 s, and don't touch the stick,** while it calibrates the gyro and measures the stick's resting center. There's no motor to signal ready: the serial monitor prints `Gyro bias …` when it's done, and the bridge's `--debug` output shows the controller's packets. If it moved, it tries up to 3 times, then runs uncalibrated and the bridge's `--debug` output says so; type `c` in the monitor or power-cycle to retry.

## Wiring

Buttons go from the pin to GND (internal pull-up). Wire the FSR (the grip) from 3V3 to its pin, with 10 kΩ from that pin to GND. The code calls that pin `PIN_TRIGGER`.

| Part | DevKitC GPIO | Xiao pin | Notes |
| --- | --- | --- | --- |
| MPU-6050 SDA / SCL | 21 / 22 | D4 / D5 | VCC to 3V3, AD0 to GND (0x68). LEFT has this one (GY-521) |
| BNO055 SDA / SCL | 21 / 22 | D4 / D5 | Instead of the MPU-6050: power from 3V3, ADR low (0x28). RIGHT has this one (Adafruit breakout); the firmware detects it |
| Joystick VRx / VRy | 34 / 35 | D0 / D1 | VCC to 3V3 |
| FSR grip | 32 | D2 | The bridge sends the squeeze as grip and trigger |
| Joystick SW | 13 | D9 | Stick click. Hold it 1 s (stick centered) to recenter, 3 s for a system click (bridge) |
| Button A | 25 | D3 | |
| Button B | 26 | D6 | Not fitted on the as-built controllers |
| System | 27 | D7 | Not fitted on the as-built controllers (they use the stick hold). If fitted: tap = system, hold 1 s = snap yaw to head |
| Grip | 14 | D8 | Not fitted on the as-built controllers (the FSR is the grip) |
| Haptic motor | 23 | D10 | Not fitted on the as-built controllers. If fitted: 1 kΩ to an NPN base; motor from 5V to collector; flyback diode across the motor |
| Power | 5V pin | 5V pin | 4×AA through a Schottky diode, or an Anker bank on the USB port |
| Antenna | U.FL | U.FL | the -32UE and the Xiao have no PCB antenna: fit one, or a 31 mm wire |

On the DevKitC, GPIO34–39 are input-only with no pull-ups, so they carry only the analog inputs.

Pins, deadzone, FSR calibration and inversion are in [include/config.h](include/config.h). Watch the serial monitor while squeezing the FSR to set `TRIGGER_RAW_MIN` and `TRIGGER_RAW_MAX`.

## Bench test

Open `pio device monitor` and type:

| Key | Does |
| --- | --- |
| `d` | Toggle a live printout: raw stick and FSR (`trigger raw`) values, buttons (A B S G K; the as-built controllers only show A and K), roll, pitch, yaw |
| `h` | Buzz the haptic motor (does nothing on the as-built controllers, which have none) |
| `c` | Recalibrate the gyro and stick center (hold still 2 s); the heading is kept, so no re-snap needed |

To check wiring: press A and the stick and watch `A` and `K` appear, move the stick to both ends, and tilt the controller and watch roll and pitch follow. Squeeze the FSR to find `TRIGGER_RAW_MIN` and `TRIGGER_RAW_MAX` for `config.h`. This needs no hub, bridge or SteamVR.

## IMU mounting

The bridge converts the IMU's frame to the controller's frame with `--mount`. The default, `flat-x-forward`, assumes the GY-521 lies flat, components up, with its X arrow pointing out of the controller's tip. Other presets are in `bridge/myphonevision_bridge/pose.py`.

## UDP fallback

If the hub dies, build the `_udp` env (e.g. `devkit_left_udp`) after setting the hotspot SSID, password and PC address in `config.h`. Then run the bridge with `--udp 39600`.
