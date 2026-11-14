// Minimal register-level MPU-6050 driver (GY-521 breakout, AD0 low = 0x68).
#pragma once
#include <Arduino.h>
#include <Wire.h>

class Mpu6050 {
 public:
  static constexpr uint8_t kAddr = 0x68;
  static constexpr float kGyroScale = (2000.0f / 32768.0f) * (PI / 180.0f);  // rad/s per LSB
  static constexpr float kAccelScale = 8.0f / 32768.0f;                      // g per LSB

  bool begin(TwoWire &wire) {
    wire_ = &wire;
    if (read8(0x75) != 0x68) {  // WHO_AM_I; clones sometimes answer 0x70/0x72
      uint8_t who = read8(0x75);
      if (who != 0x70 && who != 0x72) return false;
    }
    write8(0x6B, 0x01);  // wake, clock from gyro X PLL
    delay(10);
    write8(0x1A, 0x03);  // DLPF ~44 Hz
    write8(0x19, 0x00);  // sample rate = 1 kHz / (1 + 0)
    write8(0x1B, 0x18);  // gyro +-2000 dps
    write8(0x1C, 0x10);  // accel +-8 g
    return true;
  }

  // Gyro in rad/s, accel in g, both in the sensor's own axes.
  bool read(float gyro[3], float accel[3]) {
    uint8_t b[14];
    wire_->beginTransmission(kAddr);
    wire_->write(0x3B);
    if (wire_->endTransmission(false) != 0) return false;
    if (wire_->requestFrom(kAddr, (uint8_t)14) != 14) return false;
    for (auto &v : b) v = wire_->read();
    for (int i = 0; i < 3; i++) {
      accel[i] = (int16_t)(b[i * 2] << 8 | b[i * 2 + 1]) * kAccelScale;
      gyro[i] = (int16_t)(b[8 + i * 2] << 8 | b[9 + i * 2]) * kGyroScale;
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
