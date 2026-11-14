// myphonevision controller: reads the IMU, stick, trigger and buttons, fuses
// orientation, and sends a 200 Hz packet to the ESP-NOW hub (default) or
// straight to the PC bridge over UDP (MPV_TRANSPORT_UDP=1).
#include <Arduino.h>
#include <WiFi.h>
#include <Wire.h>

#include "config.h"
#include "mahony.h"
#include "mpu6050.h"
#include "packet.h"

#if MPV_TRANSPORT_UDP
#include <WiFiUdp.h>
static WiFiUDP udp;
static IPAddress targetIp;
#else
#include <esp_now.h>
#include <esp_wifi.h>
static const uint8_t kBroadcast[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
#endif

static Mpu6050 imu;
static Mahony filter(MAHONY_KP, MAHONY_KI);
static float gyroBias[3] = {0, 0, 0};
static bool gyroCalibrated = false;
static uint16_t seq = 0;
static volatile uint32_t hapticUntilMs = 0;
static volatile uint8_t hapticAmp = 0;
static int stickCenter[2] = {2048, 2048};  // measured at power-on
static bool filterSeeded = false;

#define HAPTIC_MIN_MS 40  // games send ~4 ms pulses; a coin motor needs ~40 ms to spin up

static void startHaptic(uint8_t amp, uint16_t ms) {
  if (amp > 0 && ms < HAPTIC_MIN_MS) ms = HAPTIC_MIN_MS;
  hapticAmp = amp;
  hapticUntilMs = millis() + ms;
}

static void handleIncoming(const uint8_t *data, int len) {
  if (len != sizeof(MpvHapticPacket)) return;
  MpvHapticPacket p;
  memcpy(&p, data, sizeof(p));
  if (p.magic != MPV_MAGIC || p.version != MPV_VERSION || p.type != MPV_PKT_HAPTIC ||
      p.hand != MPV_HAND)
    return;
  startHaptic(p.amplitude, p.duration_ms);
}

#if !MPV_TRANSPORT_UDP
#if ESP_ARDUINO_VERSION_MAJOR >= 3
static void onEspNowRecv(const esp_now_recv_info_t *info, const uint8_t *data, int len) {
#else
static void onEspNowRecv(const uint8_t *mac, const uint8_t *data, int len) {
#endif
  handleIncoming(data, len);
}
#endif

static void setupRadio() {
#if MPV_TRANSPORT_UDP
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.begin(UDP_SSID, UDP_PASSWORD);
  Serial.print("Joining hotspot");
  while (WiFi.status() != WL_CONNECTED) {
    delay(250);
    Serial.print('.');
  }
  Serial.printf("\nIP %s\n", WiFi.localIP().toString().c_str());
  targetIp.fromString(UDP_TARGET_IP);
  udp.begin(UDP_TARGET_PORT);
#else
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  esp_wifi_set_ps(WIFI_PS_NONE);  // no modem sleep: steady 200 Hz and prompt haptics
  esp_wifi_set_channel(1, WIFI_SECOND_CHAN_NONE);  // hub listens on channel 1
  if (esp_now_init() != ESP_OK) {
    Serial.println("ESP-NOW init failed");
    return;
  }
  esp_now_register_recv_cb(onEspNowRecv);
  esp_now_peer_info_t peer = {};
  memcpy(peer.peer_addr, kBroadcast, 6);
  peer.channel = 1;
  peer.encrypt = false;
  esp_now_add_peer(&peer);
  Serial.printf("ESP-NOW up, MAC %s\n", WiFi.macAddress().c_str());
#endif
}

static void send(const MpvControllerPacket &p) {
#if MPV_TRANSPORT_UDP
  udp.beginPacket(targetIp, UDP_TARGET_PORT);
  udp.write(reinterpret_cast<const uint8_t *>(&p), sizeof(p));
  udp.endPacket();
#else
  esp_now_send(kBroadcast, reinterpret_cast<const uint8_t *>(&p), sizeof(p));
#endif
}

static void pollIncoming() {
#if MPV_TRANSPORT_UDP
  uint8_t buf[32];
  int n = udp.parsePacket();
  if (n > 0) {
    n = udp.read(buf, sizeof(buf));
    handleIncoming(buf, n);
  }
#endif
}

static void calibrateGyro() {
  Serial.println("Calibrating gyro: keep the controller still (don't touch the stick)");
  float sum[3] = {0, 0, 0}, g[3], a[3], first[3] = {0, 0, 0};
  long stickSum[2] = {0, 0};
  int n = 0;
  bool still = true;
  uint32_t start = millis();
  while (millis() - start < GYRO_CAL_MS) {
    if (imu.read(g, a)) {
      if (n == 0) memcpy(first, g, sizeof(first));
      for (int i = 0; i < 3; i++) {
        sum[i] += g[i];
        if (fabsf(g[i] - first[i]) > 0.1f) still = false;  // ~6 deg/s
      }
      stickSum[0] += analogRead(PIN_STICK_X);
      stickSum[1] += analogRead(PIN_STICK_Y);
      n++;
    }
    delay(2);
  }
  if (n > 0 && still) {
    for (int i = 0; i < 3; i++) gyroBias[i] = sum[i] / n;
    gyroCalibrated = true;
    Serial.printf("Gyro bias %.4f %.4f %.4f rad/s\n", gyroBias[0], gyroBias[1], gyroBias[2]);
    for (int i = 0; i < 2; i++) {
      int c = stickSum[i] / n;
      // Ignore a center reading far off mid-scale (stick held, or unplugged).
      if (c > 1200 && c < 2900) stickCenter[i] = c;
    }
    Serial.printf("Stick center %d %d\n", stickCenter[0], stickCenter[1]);
  } else {
    Serial.println("Moved during calibration; running uncalibrated (power-cycle to retry)");
  }
  // Seed tilt from gravity only once: re-seeding on a later recalibration ('c')
  // would reset yaw and invalidate the bridge's yaw snap.
  if (!filterSeeded && imu.read(g, a)) {
    filter.initFromAccel(a);
    filterSeeded = true;
  }
}

static int16_t readStickAxis(int pin, int center, bool invert) {
  // Scale each side of the measured center separately, so an off-center
  // resting reading (typical on the ESP32 ADC) still maps to 0.
  int raw = analogRead(pin);
  float v = raw < center ? (float)(raw - center) / center : (float)(raw - center) / (4095 - center);
  if (invert) v = -v;
  float mag = fabsf(v);
  if (mag < STICK_DEADZONE) return 0;
  v = (v > 0 ? 1 : -1) * (mag - STICK_DEADZONE) / (1.0f - STICK_DEADZONE);
  return (int16_t)(constrain(v, -1.0f, 1.0f) * 32767);
}

static uint16_t readTrigger() {
  int raw = analogRead(PIN_TRIGGER);
  float t = (float)(raw - TRIGGER_RAW_MIN) / (TRIGGER_RAW_MAX - TRIGGER_RAW_MIN);
  return (uint16_t)(constrain(t, 0.0f, 1.0f) * 65535);
}

static uint16_t readButtons() {
  uint16_t b = 0;
  if (!digitalRead(PIN_BTN_A)) b |= MPV_BTN_A;
  if (!digitalRead(PIN_BTN_B)) b |= MPV_BTN_B;
  if (!digitalRead(PIN_BTN_SYSTEM)) b |= MPV_BTN_SYSTEM;
  if (!digitalRead(PIN_BTN_GRIP)) b |= MPV_BTN_GRIP;
  if (!digitalRead(PIN_BTN_STICK)) b |= MPV_BTN_STICK;
  return b;
}

// Bench test over the USB serial monitor (pio device monitor):
//   d  toggle a 10 Hz printout of raw inputs and orientation
//   h  buzz the haptic motor
//   c  re-run gyro calibration (hold still)
static void printDebugLine() {
  const float *q = filter.q;
  float roll = atan2f(2 * (q[0] * q[1] + q[2] * q[3]), 1 - 2 * (q[1] * q[1] + q[2] * q[2]));
  float pitch = asinf(constrain(2 * (q[0] * q[2] - q[3] * q[1]), -1.0f, 1.0f));
  float yaw = atan2f(2 * (q[0] * q[3] + q[1] * q[2]), 1 - 2 * (q[2] * q[2] + q[3] * q[3]));
  uint16_t b = readButtons();
  Serial.printf("stick raw %4d %4d | trigger raw %4d (%3d%%) | buttons %c%c%c%c%c | "
                "roll %6.1f pitch %6.1f yaw %6.1f deg%s\n",
                analogRead(PIN_STICK_X), analogRead(PIN_STICK_Y), analogRead(PIN_TRIGGER),
                (int)(readTrigger() * 100UL / 65535),
                b & MPV_BTN_A ? 'A' : '-', b & MPV_BTN_B ? 'B' : '-',
                b & MPV_BTN_SYSTEM ? 'S' : '-', b & MPV_BTN_GRIP ? 'G' : '-',
                b & MPV_BTN_STICK ? 'K' : '-',
                roll * RAD_TO_DEG, pitch * RAD_TO_DEG, yaw * RAD_TO_DEG,
                gyroCalibrated ? "" : "  (gyro uncalibrated)");
}

static void pollSerialCommands() {
  static bool debug = false;
  static uint32_t lastPrintMs = 0;
  while (Serial.available()) {
    switch (Serial.read()) {
      case 'd': debug = !debug; break;
      case 'h': startHaptic(255, 300); break;
      case 'c': calibrateGyro(); break;
    }
  }
  if (debug && millis() - lastPrintMs >= 100) {
    lastPrintMs = millis();
    printDebugLine();
  }
}

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.printf("myphonevision controller, hand %d\n", MPV_HAND);

  for (int pin : {PIN_BTN_A, PIN_BTN_B, PIN_BTN_SYSTEM, PIN_BTN_GRIP, PIN_BTN_STICK})
    pinMode(pin, INPUT_PULLUP);
  pinMode(PIN_HAPTIC, OUTPUT);
  analogWrite(PIN_HAPTIC, 0);
  analogReadResolution(12);

  Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL, 400000);
  while (!imu.begin(Wire)) {
    Serial.println("MPU-6050 not found on I2C; check wiring");
    delay(1000);
  }
  calibrateGyro();
  setupRadio();
  startHaptic(180, 150);  // buzz once: ready
}

void loop() {
  static uint32_t lastImuUs = micros();
  static uint32_t lastSendUs = 0;

  float g[3], a[3];
  if (imu.read(g, a)) {
    uint32_t now = micros();
    float dt = (now - lastImuUs) * 1e-6f;
    lastImuUs = now;
    if (dt > 0 && dt < 0.1f)
      filter.update(g[0] - gyroBias[0], g[1] - gyroBias[1], g[2] - gyroBias[2],
                    a[0], a[1], a[2], dt);
  }

  uint32_t now = micros();
  if (now - lastSendUs >= 1000000UL / SEND_HZ) {
    lastSendUs = now;
    MpvControllerPacket p = {};
    p.magic = MPV_MAGIC;
    p.version = MPV_VERSION;
    p.type = MPV_PKT_CONTROLLER;
    p.hand = MPV_HAND;
    p.flags = gyroCalibrated ? 1 : 0;
    p.seq = seq++;
    p.qw = filter.q[0];
    p.qx = filter.q[1];
    p.qy = filter.q[2];
    p.qz = filter.q[3];
    p.stick_x = readStickAxis(PIN_STICK_X, stickCenter[0], STICK_INVERT_X);
    p.stick_y = readStickAxis(PIN_STICK_Y, stickCenter[1], STICK_INVERT_Y);
    p.trigger = readTrigger();
    p.buttons = readButtons();
    send(p);
  }

  pollIncoming();
  pollSerialCommands();
  // analogWrite reconfigures the LEDC timer on every call in core 2.0.x, so
  // only write when the level changes.
  static int lastHaptic = -1;
  int level = (int32_t)(hapticUntilMs - millis()) > 0 ? hapticAmp : 0;
  if (level != lastHaptic) {
    analogWrite(PIN_HAPTIC, level);
    lastHaptic = level;
  }
}
