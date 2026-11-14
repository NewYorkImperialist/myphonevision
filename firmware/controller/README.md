# Controller firmware

Each Xiao ESP32S3 Sense reads an MPU-6050, a thumbstick, an FSR trigger and five buttons. It fuses orientation with a Mahony filter and sends a 200 Hz packet ([../shared/packet.h](../shared/packet.h)) by ESP-NOW broadcast on channel 1 to the hub. Haptic packets come back the same way.

```sh
pio run -e left -t upload      # left hand
pio run -e right -t upload     # right hand
pio device monitor             # status, gyro bias, IMU errors
```

**After power-on, keep the controller still for 2 s** while it calibrates the gyro. It buzzes once when ready. If it moved, it runs uncalibrated and the bridge's `--debug` output says so; power-cycle to retry.

## Wiring

| Part | Xiao pin | Notes |
| --- | --- | --- |
| MPU-6050 SDA / SCL | D4 / D5 | VCC to 3V3, AD0 to GND (0x68) |
| Joystick VRx / VRy | D0 / D1 | VCC to 3V3 |
| Joystick SW | D9 | to GND when pressed |
| FSR trigger | D2 | FSR from 3V3 to D2, 10 kΩ from D2 to GND |
| Button A | D3 | button to GND (internal pull-up) |
| Button B | D6 | button to GND |
| System | D7 | button to GND; tap = system, hold 1 s = snap yaw to head |
| Grip | D8 | button to GND |
| Haptic motor | D10 | 1 kΩ to an NPN base; motor from 5V to collector; flyback diode across the motor |
| Power | 5V pin | 4×AA through a Schottky diode (Seeed requires one) |
| Antenna | U.FL | the Xiao has no PCB antenna: fit its antenna or a 31 mm wire |

Pins, deadzone, trigger calibration and inversion are in [include/config.h](include/config.h). Watch the serial monitor while squeezing the trigger to set `TRIGGER_RAW_MIN` and `TRIGGER_RAW_MAX`.

## IMU mounting

The bridge converts the IMU's frame to the controller's frame with `--mount`. The default, `flat-x-forward`, assumes the GY-521 lies flat, components up, with its X arrow pointing out of the controller's tip. Other presets are in `bridge/myphonevision_bridge/pose.py`.

## UDP fallback

If the hub dies, build `-e left_udp` / `-e right_udp` after setting the hotspot SSID, password and PC address in `config.h`. Then run the bridge with `--udp 39600`.
