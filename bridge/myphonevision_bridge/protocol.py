"""Mirror of firmware/shared/packet.h, plus the hub's serial framing.

Serial frame (both directions): 0xA5 0x5A <len> <payload> <xor of payload>.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass

MAGIC = 0x4D50
VERSION = 1
PKT_CONTROLLER = 1
PKT_HAPTIC = 2

HAND_LEFT = 0
HAND_RIGHT = 1

BTN_A = 1 << 0
BTN_B = 1 << 1
BTN_SYSTEM = 1 << 2
BTN_GRIP = 1 << 3
BTN_STICK = 1 << 4

_CONTROLLER = struct.Struct("<HBBBBHffffhhHHH")
_HAPTIC = struct.Struct("<HBBBBH")
assert _CONTROLLER.size == 34 and _HAPTIC.size == 8

SYNC = b"\xa5\x5a"


@dataclass
class ControllerPacket:
    hand: int
    gyro_calibrated: bool
    seq: int
    quat: tuple[float, float, float, float]  # w, x, y, z; IMU world frame, Z up
    stick: tuple[float, float]  # -1..1
    trigger: float  # 0..1
    buttons: int
    battery_mv: int


def parse_controller(payload: bytes) -> ControllerPacket | None:
    if len(payload) != _CONTROLLER.size:
        return None
    (magic, version, ptype, hand, flags, seq, qw, qx, qy, qz,
     sx, sy, trig, buttons, batt) = _CONTROLLER.unpack(payload)
    if magic != MAGIC or version != VERSION or ptype != PKT_CONTROLLER or hand > 1:
        return None
    return ControllerPacket(
        hand=hand,
        gyro_calibrated=bool(flags & 1),
        seq=seq,
        quat=(qw, qx, qy, qz),
        stick=(sx / 32767.0, sy / 32767.0),
        trigger=trig / 65535.0,
        buttons=buttons,
        battery_mv=batt,
    )


def build_haptic(hand: int, amplitude: float, duration_s: float) -> bytes:
    amp = max(0, min(255, round(amplitude * 255)))
    ms = max(0, min(65535, round(duration_s * 1000)))
    return _HAPTIC.pack(MAGIC, VERSION, PKT_HAPTIC, hand, amp, ms)


def frame(payload: bytes) -> bytes:
    x = 0
    for b in payload:
        x ^= b
    return SYNC + bytes([len(payload)]) + payload + bytes([x])


class FrameDecoder:
    """Incremental decoder for the hub's serial stream; resyncs on garbage."""

    def __init__(self) -> None:
        self._buf = bytearray()

    def feed(self, data: bytes) -> list[bytes]:
        self._buf += data
        out: list[bytes] = []
        while True:
            start = self._buf.find(SYNC)
            if start < 0:
                # Keep a trailing 0xA5 in case the next read starts with 0x5A.
                del self._buf[: max(0, len(self._buf) - 1)]
                return out
            del self._buf[:start]
            if len(self._buf) < 3:
                return out
            n = self._buf[2]
            if len(self._buf) < 3 + n + 1:
                return out
            payload = bytes(self._buf[3 : 3 + n])
            check = self._buf[3 + n]
            x = 0
            for b in payload:
                x ^= b
            if n > 0 and x == check:
                out.append(payload)
                del self._buf[: 3 + n + 1]
            else:
                del self._buf[:2]  # bad frame: skip this sync and search again
