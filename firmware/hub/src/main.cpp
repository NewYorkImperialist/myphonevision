// ESP-NOW hub. Controllers broadcast on channel 1; the hub forwards each valid
// packet to USB serial as a frame, and forwards haptic frames from the bridge
// to the controller that owns that hand.
//
// Serial frame (both directions): 0xA5 0x5A <len> <payload...> <xor of payload>
#include <Arduino.h>
#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>

#include "packet.h"

static constexpr uint8_t kSync0 = 0xA5, kSync1 = 0x5A;

// Packets arrive in the Wi-Fi task; hand them to loop() through a small ring.
struct Slot {
  uint8_t mac[6];
  MpvControllerPacket pkt;
};
static Slot ring[16];
static volatile uint8_t head = 0, tail = 0;

static uint8_t handMac[2][6];
static bool handKnown[2] = {false, false};

// Arduino-ESP32 3.x passes recv info; 2.x passes the sender MAC.
#if ESP_ARDUINO_VERSION_MAJOR >= 3
static void onRecv(const esp_now_recv_info_t *info, const uint8_t *data, int len) {
  const uint8_t *mac = info->src_addr;
#else
static void onRecv(const uint8_t *mac, const uint8_t *data, int len) {
#endif
  if (len != sizeof(MpvControllerPacket)) return;
  uint8_t next = (head + 1) % 16;
  if (next == tail) return;  // full: drop
  memcpy(ring[head].mac, mac, 6);
  memcpy(&ring[head].pkt, data, sizeof(MpvControllerPacket));
  // Release: the slot's bytes must be visible before loop() (other core) sees head move.
  __atomic_store_n(&head, next, __ATOMIC_RELEASE);
}

static void writeFrame(const uint8_t *payload, uint8_t len) {
  uint8_t x = 0;
  for (int i = 0; i < len; i++) x ^= payload[i];
  uint8_t hdr[3] = {kSync0, kSync1, len};
  Serial.write(hdr, 3);
  Serial.write(payload, len);
  Serial.write(x);
}

static void learnPeer(uint8_t hand, const uint8_t mac[6]) {
  if (hand > 1) return;
  if (handKnown[hand] && memcmp(handMac[hand], mac, 6) == 0) return;
  if (handKnown[hand]) esp_now_del_peer(handMac[hand]);
  memcpy(handMac[hand], mac, 6);
  esp_now_peer_info_t peer = {};
  memcpy(peer.peer_addr, mac, 6);
  peer.channel = 1;
  peer.encrypt = false;
  esp_now_add_peer(&peer);
  handKnown[hand] = true;
}

// Parse haptic frames from the bridge.
static void pollSerial() {
  static uint8_t state = 0, len = 0, idx = 0, buf[64];
  while (Serial.available()) {
    uint8_t c = Serial.read();
    switch (state) {
      case 0: state = (c == kSync0) ? 1 : 0; break;
      case 1: state = (c == kSync1) ? 2 : (c == kSync0 ? 1 : 0); break;
      case 2:
        len = c;
        idx = 0;
        state = (len > 0 && len <= sizeof(buf)) ? 3 : 0;
        break;
      case 3:
        buf[idx++] = c;
        if (idx == len) state = 4;
        break;
      case 4: {
        uint8_t x = 0;
        for (int i = 0; i < len; i++) x ^= buf[i];
        state = 0;
        if (x != c || len != sizeof(MpvHapticPacket)) break;
        MpvHapticPacket p;
        memcpy(&p, buf, sizeof(p));
        if (p.magic == MPV_MAGIC && p.type == MPV_PKT_HAPTIC && p.hand <= 1 && handKnown[p.hand])
          esp_now_send(handMac[p.hand], buf, len);
        break;
      }
    }
  }
}

void setup() {
  Serial.begin(921600);
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  esp_wifi_set_ps(WIFI_PS_NONE);
  esp_wifi_set_channel(1, WIFI_SECOND_CHAN_NONE);
  if (esp_now_init() != ESP_OK) {
    while (true) {
      Serial.println("ESP-NOW init failed");
      delay(1000);
    }
  }
  esp_now_register_recv_cb(onRecv);
}

void loop() {
  while (tail != __atomic_load_n(&head, __ATOMIC_ACQUIRE)) {
    Slot &s = ring[tail];
    if (s.pkt.magic == MPV_MAGIC && s.pkt.version == MPV_VERSION && s.pkt.type == MPV_PKT_CONTROLLER) {
      learnPeer(s.pkt.hand, s.mac);
      writeFrame(reinterpret_cast<const uint8_t *>(&s.pkt), sizeof(s.pkt));
    }
    tail = (tail + 1) % 16;
  }
  pollSerial();
}
