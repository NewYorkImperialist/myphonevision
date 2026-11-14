// Mahony complementary filter: gyro integration with accelerometer tilt
// correction. No magnetometer, so yaw drifts; the bridge resets it against
// the headset's yaw when the system button is held.
#pragma once
#include <math.h>

class Mahony {
 public:
  float q[4] = {1, 0, 0, 0};  // w, x, y, z; sensor -> world, world Z up

  Mahony(float kp, float ki) : kp_(kp), ki_(ki) {}

  // Seed orientation from gravity so the filter doesn't spend seconds converging.
  void initFromAccel(const float a[3]) {
    float roll = atan2f(a[1], a[2]);
    float pitch = atan2f(-a[0], sqrtf(a[1] * a[1] + a[2] * a[2]));
    float cr = cosf(roll / 2), sr = sinf(roll / 2);
    float cp = cosf(pitch / 2), sp = sinf(pitch / 2);
    q[0] = cr * cp;
    q[1] = sr * cp;
    q[2] = cr * sp;
    q[3] = -sr * sp;
  }

  void update(float gx, float gy, float gz, float ax, float ay, float az, float dt) {
    float norm = sqrtf(ax * ax + ay * ay + az * az);
    // Only trust the accelerometer near 1 g, so swings don't tilt the estimate.
    if (norm > 0.7f && norm < 1.3f) {
      ax /= norm; ay /= norm; az /= norm;
      // Gravity direction predicted by the current orientation.
      float vx = 2 * (q[1] * q[3] - q[0] * q[2]);
      float vy = 2 * (q[0] * q[1] + q[2] * q[3]);
      float vz = q[0] * q[0] - q[1] * q[1] - q[2] * q[2] + q[3] * q[3];
      float ex = ay * vz - az * vy;
      float ey = az * vx - ax * vz;
      float ez = ax * vy - ay * vx;
      if (ki_ > 0) {
        ix_ += ki_ * ex * dt; iy_ += ki_ * ey * dt; iz_ += ki_ * ez * dt;
      }
      gx += kp_ * ex + ix_;
      gy += kp_ * ey + iy_;
      gz += kp_ * ez + iz_;
    }
    float hdt = 0.5f * dt;
    float w = q[0], x = q[1], y = q[2], z = q[3];
    q[0] += (-x * gx - y * gy - z * gz) * hdt;
    q[1] += (w * gx + y * gz - z * gy) * hdt;
    q[2] += (w * gy - x * gz + z * gx) * hdt;
    q[3] += (w * gz + x * gy - y * gx) * hdt;
    float n = sqrtf(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]);
    for (float &c : q) c /= n;
  }

 private:
  float kp_, ki_;
  float ix_ = 0, iy_ = 0, iz_ = 0;
};
