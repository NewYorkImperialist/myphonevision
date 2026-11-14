// Wire format shared by the controller firmware, the ESP-NOW hub and (by
// mirror) bridge/myphonevision_bridge/protocol.py. Keep all three in sync.
#pragma once
#include <stdint.h>

#define MPV_MAGIC 0x4D50  // "MP"
#define MPV_VERSION 1

enum MpvPacketType : uint8_t {
  MPV_PKT_CONTROLLER = 1,  // controller -> hub/PC
  MPV_PKT_HAPTIC = 2,      // hub -> controller
};

enum MpvHand : uint8_t {
  MPV_HAND_LEFT = 0,
  MPV_HAND_RIGHT = 1,
};

// Button bit positions in MpvControllerPacket::buttons.
enum MpvButton : uint16_t {
  MPV_BTN_A = 1 << 0,
  MPV_BTN_B = 1 << 1,
  MPV_BTN_SYSTEM = 1 << 2,
  MPV_BTN_GRIP = 1 << 3,
  MPV_BTN_STICK = 1 << 4,
};

#pragma pack(push, 1)
struct MpvControllerPacket {
  uint16_t magic;     // MPV_MAGIC
  uint8_t version;    // MPV_VERSION
  uint8_t type;       // MPV_PKT_CONTROLLER
  uint8_t hand;       // MpvHand
  uint8_t flags;      // bit0: gyro calibrated
  uint16_t seq;       // wraps
  float qw, qx, qy, qz;  // IMU orientation, sensor world frame (Z up, gravity aligned)
  int16_t stick_x;    // -32767..32767, right positive
  int16_t stick_y;    // -32767..32767, up positive
  uint16_t trigger;   // 0..65535
  uint16_t buttons;   // MpvButton bits
  uint16_t battery_mv;  // 0 if unknown
};  // 34 bytes

struct MpvHapticPacket {
  uint16_t magic;
  uint8_t version;
  uint8_t type;       // MPV_PKT_HAPTIC
  uint8_t hand;
  uint8_t amplitude;  // 0..255
  uint16_t duration_ms;
};
#pragma pack(pop)

static_assert(sizeof(MpvControllerPacket) == 34, "controller packet layout changed");
static_assert(sizeof(MpvHapticPacket) == 8, "haptic packet layout changed");
