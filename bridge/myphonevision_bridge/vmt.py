"""OSC messages for Virtual Motion Tracker (VMT).

Every message starts with (index, enable-or-input-index, timeoffset). Poses use
/VMT/Raw/Driver (raw driver space), which needs no room matrix; /VMT/Room/*
would be rejected until one is set.
"""

from __future__ import annotations

from pythonosc.udp_client import SimpleUDPClient

from . import quat as Q

VMT_PORT = 39570
VMT_OUT_PORT = 39571  # haptics come back here; close VMT Manager while playing

ENABLE_INDEX_LEFT = 5
ENABLE_INDEX_RIGHT = 6
ENABLE_DISABLED = 0

# Index-compatible (enable 5/6) input indices, from VMT's driver source
# (vmt_driver/TrackedDeviceServerDriver.cpp): Button0 = system, Button1 = a,
# Button3 = b, Trigger0 = trigger, Trigger1 = grip value, Joystick1 = thumbstick.
TRIGGER = 0
GRIP = 1
BUTTON_SYSTEM = 0
BUTTON_A = 1
BUTTON_B = 3
JOYSTICK = 1


class Vmt:
    def __init__(self, host: str = "127.0.0.1", port: int = VMT_PORT) -> None:
        self._osc = SimpleUDPClient(host, port)

    def pose(self, index: int, enable: int, pos: Q.Vec, rot: Q.Quat, timeoffset: float = 0.0) -> None:
        w, x, y, z = rot
        self._osc.send_message(
            "/VMT/Raw/Driver",
            [int(index), int(enable), float(timeoffset),
             float(pos[0]), float(pos[1]), float(pos[2]),
             float(x), float(y), float(z), float(w)],
        )

    # VMT reads arguments with strict types: (int, int, float, int|float...).
    def button(self, index: int, button: int, pressed: bool) -> None:
        self._osc.send_message("/VMT/Input/Button", [int(index), int(button), 0.0, int(pressed)])

    def button_touch(self, index: int, button: int, touched: bool) -> None:
        self._osc.send_message("/VMT/Input/Button/Touch", [int(index), int(button), 0.0, int(touched)])

    def trigger_click(self, index: int, trigger: int, pressed: bool) -> None:
        self._osc.send_message("/VMT/Input/Trigger/Click", [int(index), int(trigger), 0.0, int(pressed)])

    def trigger_touch(self, index: int, trigger: int, touched: bool) -> None:
        self._osc.send_message("/VMT/Input/Trigger/Touch", [int(index), int(trigger), 0.0, int(touched)])

    def joystick_click(self, index: int, stick: int, pressed: bool) -> None:
        self._osc.send_message("/VMT/Input/Joystick/Click", [int(index), int(stick), 0.0, int(pressed)])

    def joystick_touch(self, index: int, stick: int, touched: bool) -> None:
        self._osc.send_message("/VMT/Input/Joystick/Touch", [int(index), int(stick), 0.0, int(touched)])

    def trigger(self, index: int, trigger: int, value: float) -> None:
        self._osc.send_message("/VMT/Input/Trigger", [int(index), int(trigger), 0.0, float(value)])

    def joystick(self, index: int, stick: int, x: float, y: float) -> None:
        self._osc.send_message("/VMT/Input/Joystick", [int(index), int(stick), 0.0, float(x), float(y)])
