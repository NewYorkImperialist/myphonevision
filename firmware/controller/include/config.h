// Per-build settings for the controller. Pin numbers are Xiao ESP32S3 "Dx"
// aliases. Analog inputs must stay on ADC1 pins (D0-D5, D8-D10) because ADC2
// stops working while the radio is on.
#pragma once

#ifndef MPV_HAND
#error "Build with -DMPV_HAND=0 (left) or -DMPV_HAND=1 (right); use a pio env"
#endif

// --- Pins -------------------------------------------------------------------
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

// Buttons are wired pin -> button -> GND and use the internal pull-up.

// --- Tuning ---------------------------------------------------------------
#define SEND_HZ 200
#define STICK_DEADZONE 0.08f   // fraction of full scale
#define STICK_INVERT_X 0
#define STICK_INVERT_Y 1       // most breakout joysticks read low when pushed up
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
