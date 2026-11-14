// Per-build settings for the controller. Analog inputs must stay on ADC1
// pins because ADC2 stops working while the radio is on.
#pragma once

#ifndef MPV_HAND
#error "Build with -DMPV_HAND=0 (left) or -DMPV_HAND=1 (right); use a pio env"
#endif

// --- Pins -------------------------------------------------------------------
#if MPV_BOARD_DEVKIT
// ESP32-DevKitC (-32E / -32UE). GPIO34-39 are input-only with no pull-ups,
// so they only take the analog inputs; buttons use pins with pull-ups.
#define PIN_STICK_X 34      // joystick VRx (ADC1)
#define PIN_STICK_Y 35      // joystick VRy (ADC1)
#define PIN_TRIGGER 32      // FSR divider (ADC1)
#define PIN_I2C_SDA 21
#define PIN_I2C_SCL 22
#define PIN_BTN_A 25
#define PIN_BTN_B 26
#define PIN_BTN_SYSTEM 27
#define PIN_BTN_GRIP 14
#define PIN_BTN_STICK 13    // joystick SW
#define PIN_HAPTIC 23
#else
// Seeed Xiao ESP32S3 "Dx" aliases (ADC1: D0-D5, D8-D10).
#define PIN_STICK_X D0      // joystick VRx
#define PIN_STICK_Y D1      // joystick VRy
#define PIN_TRIGGER D2      // FSR divider (FSR to 3V3, 10k to GND)
#define PIN_BTN_A D3
#define PIN_I2C_SDA D4      // MPU-6050 SDA
#define PIN_I2C_SCL D5      // MPU-6050 SCL
#define PIN_BTN_B D6        // shares UART0 TX; fine while Serial is USB CDC
#define PIN_BTN_SYSTEM D7   // shares UART0 RX
#define PIN_BTN_GRIP D8
#define PIN_BTN_STICK D9    // joystick SW
#define PIN_HAPTIC D10      // NPN base through 1k; motor on 5V with flyback diode
#endif

// Buttons are wired pin -> button -> GND and use the internal pull-up.

// --- Tuning ---------------------------------------------------------------
#define SEND_HZ 200
#define STICK_DEADZONE 0.08f   // fraction of full scale
#define STICK_INVERT_X 0
#define STICK_INVERT_Y 0       // Adafruit 512 reads high when pushed up (header toward the wrist), tested on LEFT
#define TRIGGER_RAW_MIN 150    // ADC counts with the trigger released
#define TRIGGER_RAW_MAX 3500   // ADC counts at a firm squeeze
#define GYRO_CAL_MS 2000       // hold still this long after power-on
#define MAHONY_KP 1.0f         // accel correction gain; raise if tilt drifts
#define MAHONY_KI 0.0f

// --- UDP fallback (MPV_TRANSPORT_UDP=1) -----------------------------------
#define UDP_SSID "myphonevision"      // the PC's Mobile Hotspot
#define UDP_PASSWORD "change-me"
#define UDP_TARGET_IP "192.168.137.1" // Windows Mobile Hotspot host address
#define UDP_TARGET_PORT 39600         // bridge --udp port
