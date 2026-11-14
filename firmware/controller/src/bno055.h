// Minimal register-level BNO055 driver (Adafruit breakout, ADR low = 0x28).
// Runs in ACCGYRO mode (raw sensors, no on-chip fusion) so the same Mahony filter
// and gyro calibration work as with the MPU-6050.
#pragma once
#include <Arduino.h>
#include <Wire.h>

class Bno055 {
 public:
  static constexpr uint8_t kAddr = 0x28;
  static constexpr float kGyroScale = (1.0f / 16.0f) * (PI / 180.0f);  // rad/s per LSB (dps unit)
  static constexpr float kAccelScale = 1.0f / 100.0f / 9.80665f;        // g per LSB (m/s^2 unit)

  bool begin(TwoWire &wire) {
    wire_ = &wire;
    if (read8(0x00) != 0xA0) {  // CHIP_ID; it needs ~650 ms after power-on to answer
      delay(700);
      if (read8(0x00) != 0xA0) return false;
    }
    write8(0x3D, 0x00);  // OPR_MODE = CONFIG
    delay(25);
    write8(0x07, 0x01);  // page 1
    write8(0x0A, 0x10);  // GYR_CONFIG_0: +-2000 dps, 116 Hz bandwidth (default 32 Hz lags)
    write8(0x07, 0x00);  // page 0
    write8(0x3B, 0x00);  // UNIT_SEL: m/s^2, dps
    write8(0x3D, 0x05);  // OPR_MODE = ACCGYRO
    delay(100);          // let the outputs settle before the boot stillness check
    return true;
  }

  // Gyro in rad/s, accel in g, both in the sensor's own axes.
  bool read(float gyro[3], float accel[3]) {
    uint8_t b[18];  // 0x08..0x19: accel, mag (unused in this mode), gyro; little-endian
    wire_->beginTransmission(kAddr);
    wire_->write(0x08);
    if (wire_->endTransmission(false) != 0) return false;
    if (wire_->requestFrom(kAddr, (uint8_t)18) != 18) return false;
    for (auto &v : b) v = wire_->read();
    for (int i = 0; i < 3; i++) {
      accel[i] = (int16_t)(b[1 + i * 2] << 8 | b[i * 2]) * kAccelScale;
      gyro[i] = (int16_t)(b[13 + i * 2] << 8 | b[12 + i * 2]) * kGyroScale;
    }
    return true;
  }

 private:
  TwoWire *wire_ = nullptr;

  void write8(uint8_t reg, uint8_t val) {
    wire_->beginTransmission(kAddr);
    wire_->write(reg);
    wire_->write(val);
    wire_->endTransmission();
  }
  uint8_t read8(uint8_t reg) {
    wire_->beginTransmission(kAddr);
    wire_->write(reg);
    wire_->endTransmission(false);
    wire_->requestFrom(kAddr, (uint8_t)1);
    return wire_->available() ? wire_->read() : 0xFF;
  }
};
