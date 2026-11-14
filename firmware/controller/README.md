# Controller firmware

Runs on an **ESP32-DevKitC** (default) or a **Seeed Xiao ESP32S3**. Each controller reads an MPU-6050, a thumbstick, an FSR trigger and five buttons. It fuses orientation with a Mahony filter and sends a 200 Hz packet ([../shared/packet.h](../shared/packet.h)) by ESP-NOW broadcast on channel 1 to the hub. Haptic packets come back the same way.

```sh
pio run -e devkit_left -t upload    # DevKitC, left hand (devkit_right for right)
pio run -e xiao_left -t upload      # Xiao ESP32S3 instead
pio device monitor             # status, gyro bias, IMU errors
```

**After power-on, keep the controller still for 2 s** while it calibrates the gyro. It buzzes once when ready. If it moved, it runs uncalibrated and the bridge's `--debug` output says so; power-cycle to retry.

## Wiring

Buttons go from the pin to GND (internal pull-up). Wire the FSR from 3V3 to the trigger pin, with 10 kΩ from that pin to GND.

| Part | DevKitC GPIO | Xiao pin | Notes |
| --- | --- | --- | --- |
| MPU-6050 SDA / SCL | 21 / 22 | D4 / D5 | VCC to 3V3, AD0 to GND (0x68) |
| Joystick VRx / VRy | 34 / 35 | D0 / D1 | VCC to 3V3 |
| FSR trigger | 32 | D2 | |
| Joystick SW | 13 | D9 | |
| Button A | 25 | D3 | |
| Button B | 26 | D6 | |
| System | 27 | D7 | tap = system, hold 1 s = snap yaw to head |
| Grip | 14 | D8 | |
| Haptic motor | 23 | D10 | 1 kΩ to an NPN base; motor from 5V to collector; flyback diode across the motor |
| Power | 5V pin | 5V pin | 4×AA through a Schottky diode, or an Anker bank on the USB port |
| Antenna | U.FL | U.FL | the -32UE and the Xiao have no PCB antenna: fit one, or a 31 mm wire |

On the DevKitC, GPIO34–39 are input-only with no pull-ups, so they carry only the analog inputs.

Pins, deadzone, trigger calibration and inversion are in [include/config.h](include/config.h). Watch the serial monitor while squeezing the trigger to set `TRIGGER_RAW_MIN` and `TRIGGER_RAW_MAX`.

## Bench test

Open `pio device monitor` and type:

| Key | Does |
| --- | --- |
| `d` | Toggle a live printout: raw stick and trigger values, buttons (A B S G K), roll, pitch, yaw |
| `h` | Buzz the haptic motor |
| `c` | Recalibrate the gyro (hold still 2 s) |

To check wiring: press each button and watch its letter appear, move the stick to both ends, and tilt the controller and watch roll and pitch follow. Squeeze the trigger to find `TRIGGER_RAW_MIN` and `TRIGGER_RAW_MAX` for `config.h`. This needs no hub, bridge or SteamVR.

## IMU mounting

The bridge converts the IMU's frame to the controller's frame with `--mount`. The default, `flat-x-forward`, assumes the GY-521 lies flat, components up, with its X arrow pointing out of the controller's tip. Other presets are in `bridge/myphonevision_bridge/pose.py`.

## UDP fallback

If the hub dies, build the `_udp` env (e.g. `devkit_left_udp`) after setting the hotspot SSID, password and PC address in `config.h`. Then run the bridge with `--udp 39600`.
