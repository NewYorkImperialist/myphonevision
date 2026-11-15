"""myphonevision PC bridge: controller packets in (hub serial or UDP), VMT OSC out.

    python -m myphonevision_bridge --serial COM5
    python -m myphonevision_bridge --udp 39600          # controllers in UDP mode
    python -m myphonevision_bridge --serial COM5 --no-hmd --debug   # bench test
"""

from __future__ import annotations

import argparse
import queue
import socket
import struct
import sys
import threading
import time

from . import protocol as P
from . import quat as Q
from . import vmt as V
from .hmd import FixedHmd, SteamVrHmd
from .pose import MOUNTS, ArmModel, ControllerOrientation, with_pitch_trim
from .tuner import Tuner

HOLD_TO_SNAP_S = 1.0
HOLD_TO_SYSTEM_S = 3.0  # stick hold: keep holding past the snap for a system click
STICK_CENTERED = 0.3    # a stick hold only counts with the stick near center (not sprinting)
SYSTEM_TAP_S = 0.05

# What the FSR squeeze drives. Index grip grabs; the trigger selects in menus and
# fires in games. With only one analog input, "both" works in the most games.
SQUEEZE_TARGETS = {"both": (V.GRIP, V.TRIGGER), "grip": (V.GRIP,), "trigger": (V.TRIGGER,)}


# --- Transports ---------------------------------------------------------------

class SerialSource:
    def __init__(self, port: str, packets: "queue.Queue[P.ControllerPacket]") -> None:
        import serial

        self._ser = serial.Serial(port, 921600, timeout=0.05)
        self._packets = packets
        self._lock = threading.Lock()
        threading.Thread(target=self._run, daemon=True).start()

    def _run(self) -> None:
        dec = P.FrameDecoder()
        while True:
            data = self._ser.read(self._ser.in_waiting or 1)
            for payload in dec.feed(data):
                pkt = P.parse_controller(payload)
                if pkt:
                    self._packets.put(pkt)

    def send_haptic(self, hand: int, amplitude: float, duration_s: float) -> None:
        with self._lock:
            self._ser.write(P.frame(P.build_haptic(hand, amplitude, duration_s)))


class UdpSource:
    def __init__(self, port: int, packets: "queue.Queue[P.ControllerPacket]") -> None:
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._sock.bind(("0.0.0.0", port))
        self._packets = packets
        self._addr: dict[int, tuple[str, int]] = {}
        threading.Thread(target=self._run, daemon=True).start()

    def _run(self) -> None:
        while True:
            data, addr = self._sock.recvfrom(64)
            pkt = P.parse_controller(data)
            if pkt:
                self._addr[pkt.hand] = addr
                self._packets.put(pkt)

    def send_haptic(self, hand: int, amplitude: float, duration_s: float) -> None:
        if hand in self._addr:
            self._sock.sendto(P.build_haptic(hand, amplitude, duration_s), self._addr[hand])


def find_hub_port() -> str:
    from serial.tools import list_ports

    from .preflight import find_hubs

    ports, hubs = find_hubs()
    if len(hubs) == 1:
        return next(iter(hubs))
    if not hubs and len(ports) == 1:
        return ports[0]  # a silent hub: no controller is on yet
    listing = "\n".join(f"  {p.device}: {p.description}" for p in list_ports.comports())
    sys.exit(f"Pass --serial PORT; couldn't pick the hub automatically. Ports:\n{listing}")


# --- Haptics from VMT -----------------------------------------------------------

def start_haptic_listener(port: int, send_haptic) -> None:
    from pythonosc.dispatcher import Dispatcher
    from pythonosc.osc_server import ThreadingOSCUDPServer

    seen: set[str] = set()

    def on_haptic(address: str, *args) -> None:
        # (index, frequency, amplitude, duration), per VMT's driver source.
        if len(args) >= 4 and int(args[0]) in (0, 1):
            send_haptic(int(args[0]), float(args[2]), float(args[3]))

    def on_any(address: str, *args) -> None:
        if address not in seen:
            seen.add(address)
            print(f"[vmt out] {address} {args}")

    d = Dispatcher()
    d.map("/VMT/Out/Haptic", on_haptic)
    d.set_default_handler(on_any)
    try:
        server = ThreadingOSCUDPServer(("127.0.0.1", port), d)
    except OSError:
        print(f"Port {port} is busy (VMT Manager open?). Haptics disabled.")
        return
    threading.Thread(target=server.serve_forever, daemon=True).start()


# --- Main loop ------------------------------------------------------------------

class StickHold:
    """Click and hold the thumbstick, kept near center: at 1 s the heading snaps to the
    head's (the drift reset); keep holding to 3 s for a system click (SteamVR menu).
    The controllers have no system button, so this replaces its hold and tap. Stick
    clicks still reach games as usual; a click while pushing the stick (e.g. sprint)
    never counts."""

    def __init__(self) -> None:
        self.down_at: float | None = None
        self.stage = 0  # 0 holding, 1 snapped, 2 system sent

    def update(self, clicked: bool, stick: tuple[float, float], now: float) -> str | None:
        if not clicked or max(abs(stick[0]), abs(stick[1])) > STICK_CENTERED:
            self.down_at = None
            return None
        if self.down_at is None:
            self.down_at, self.stage = now, 0
        held = now - self.down_at
        if self.stage == 0 and held >= HOLD_TO_SNAP_S:
            self.stage = 1
            return "snap"
        if self.stage == 1 and held >= HOLD_TO_SYSTEM_S:
            self.stage = 2
            return "system"
        return None


class Hand:
    def __init__(self, hand: int, mount: Q.Quat) -> None:
        self.hand = hand
        self.enable = V.ENABLE_INDEX_LEFT if hand == P.HAND_LEFT else V.ENABLE_INDEX_RIGHT
        self.orient = ControllerOrientation(mount=mount)
        self.prev_buttons = 0
        self.prev_states: tuple[bool, bool, bool] | None = None
        self.system_down_at: float | None = None
        self.snapped = False
        self.system_release_at: float | None = None
        self.stick_hold = StickHold()
        self.count = 0
        self.last: P.ControllerPacket | None = None


PHONE_PORT = 39601


def phone_packet(hand: int, pos: Q.Vec, rot: Q.Quat, buttons: int = 0, command: tuple[int, int] = (0, 0)) -> bytes:
    """Hand pose for the iPhone app's sword game: b"MPVH", hand, buttons (bit 0 A,
    bit 1 stick click, bit 2 "realign" from the tuner page), command, command sequence
    (the phone runs a command once each time the sequence changes), then
    position x y z (m) and rotation w x y z, little-endian floats, in SteamVR axes
    (+X right, +Y up, -Z forward; the head at x = z = 0 with --no-hmd)."""
    return struct.pack("<4sBBBB7f", b"MPVH", hand, buttons & 0xFF, command[0] & 0xFF, command[1] & 0xFF, *pos, *rot)


def main() -> None:
    ap = argparse.ArgumentParser(prog="myphonevision_bridge", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    src = ap.add_mutually_exclusive_group()
    src.add_argument("--serial", help="hub serial port (default: auto-detect)")
    src.add_argument("--udp", type=int, metavar="PORT", help="listen for UDP controllers instead")
    ap.add_argument("--vmt-host", default="127.0.0.1")
    ap.add_argument("--no-hmd", action="store_true", help="don't query SteamVR; assume a fixed head")
    ap.add_argument("--mount", choices=sorted(MOUNTS), default="flat-x-forward")
    ap.add_argument("--pitch-trim", type=float, default=0.0, metavar="DEG",
                    help="tilt the controller nose-up by this many degrees (fix hand angle in games)")
    ap.add_argument("--debug-follow", action="store_true",
                    help="pin both controllers 0.3 m in front of the head (checks the coordinate space)")
    ap.add_argument("--debug", action="store_true", help="print per-hand status every second")
    ap.add_argument("--phone", metavar="HOST", help="also send hand poses to the iPhone app's sword game "
                    "(USB hotspot: 172.20.10.1); use with --no-hmd when SteamVR isn't running")
    ap.add_argument("--squeeze", choices=sorted(SQUEEZE_TARGETS), default="both",
                    help="what the FSR squeeze sends: grip (grab), trigger (menus, firing) or both (default)")
    args = ap.parse_args()

    packets: "queue.Queue[P.ControllerPacket]" = queue.Queue()
    if args.udp is not None:
        source = UdpSource(args.udp, packets)
        print(f"Listening for UDP controllers on {args.udp}")
    else:
        port = args.serial or find_hub_port()
        source = SerialSource(port, packets)
        print(f"Reading hub on {port}")

    if args.no_hmd:
        hmd = FixedHmd()
    else:
        try:
            hmd = SteamVrHmd()
        except Exception as e:  # noqa: BLE001 - openvr raises its own types
            sys.exit(f"Couldn't reach SteamVR ({e}). Start SteamVR first, or pass --no-hmd.")

    vmt = V.Vmt(args.vmt_host)
    phone_sock, phone_addr = None, None
    if args.phone:   # IPv4 or IPv6 (e.g. fe80::...%en0 on an IPv6-only hotspot)
        fam, _, _, _, phone_addr = socket.getaddrinfo(args.phone, PHONE_PORT, type=socket.SOCK_DGRAM)[0]
        phone_sock = socket.socket(fam, socket.SOCK_DGRAM)
        print(f"Sending hand poses to the phone at {args.phone} port {PHONE_PORT}")
    tuner = Tuner() if args.phone else None
    if tuner:
        tuner.serve()
    squeeze_to = SQUEEZE_TARGETS[args.squeeze]
    arm = ArmModel()
    mount = with_pitch_trim(MOUNTS[args.mount], args.pitch_trim)
    hands = {h: Hand(h, mount) for h in (P.HAND_LEFT, P.HAND_RIGHT)}
    start_haptic_listener(V.VMT_OUT_PORT, source.send_haptic)
    next_report = time.monotonic() + 1.0

    while True:
        try:
            pkt = packets.get(timeout=0.02)
        except queue.Empty:
            pkt = None
        now = time.monotonic()

        if pkt:
            h = hands[pkt.hand]
            h.count += 1
            h.last = pkt
            head_pos, head_rot = hmd.pose()
            rot = h.orient.world(pkt.quat)
            if tuner:
                rot = tuner.apply(pkt.hand, rot)
            if args.debug_follow:
                pos = Q.add(head_pos, Q.rotate(Q.rot_y(Q.yaw(head_rot)),
                                               (-0.1 if pkt.hand == 0 else 0.1, -0.1, -0.3)))
            else:
                pos = arm.position(pkt.hand, head_pos, head_rot, rot)
            if tuner:
                pos = tuner.offset_pos(pkt.hand, pos)
            vmt.pose(pkt.hand, h.enable, pos, rot)
            if phone_sock:
                try:
                    btn = (1 if pkt.buttons & P.BTN_A else 0) | (2 if pkt.buttons & P.BTN_STICK else 0)
                    phone_sock.sendto(phone_packet(pkt.hand, pos, rot, btn | tuner.realign_bit(), tuner.command()), phone_addr)
                    tuner.record(pkt.hand, rot, bool(pkt.buttons & P.BTN_A), pkt.gyro_calibrated)
                except OSError:
                    pass   # phone not reachable yet; keep going

            b, changed = pkt.buttons, pkt.buttons ^ h.prev_buttons
            for bit, idx in ((P.BTN_A, V.BUTTON_A), (P.BTN_B, V.BUTTON_B)):
                if changed & bit:
                    vmt.button_touch(pkt.hand, idx, bool(b & bit))
                    vmt.button(pkt.hand, idx, bool(b & bit))
            if changed & P.BTN_STICK:
                vmt.joystick_click(pkt.hand, V.JOYSTICK, bool(b & P.BTN_STICK))
            # The FSR squeeze drives the grip, the trigger or both (--squeeze); a grip
            # switch, if wired, also counts.
            squeeze = max(pkt.trigger, 1.0 if b & P.BTN_GRIP else 0.0)
            for t in squeeze_to:
                vmt.trigger(pkt.hand, t, squeeze)
            vmt.joystick(pkt.hand, V.JOYSTICK, pkt.stick[0], pkt.stick[1])
            # Edge-triggered touch/click states derived from the analog values.
            states = (squeeze > 0.05, squeeze > 0.9,
                      bool(b & P.BTN_STICK) or abs(pkt.stick[0]) + abs(pkt.stick[1]) > 0)
            if states != h.prev_states:
                for t in squeeze_to:
                    vmt.trigger_touch(pkt.hand, t, states[0])
                    vmt.trigger_click(pkt.hand, t, states[1])
                vmt.joystick_touch(pkt.hand, V.JOYSTICK, states[2])
                h.prev_states = states

            # System: a tap is a system click; a 1 s hold snaps yaw to the head.
            if changed & P.BTN_SYSTEM:
                if b & P.BTN_SYSTEM:
                    h.system_down_at, h.snapped = now, False
                else:
                    if not h.snapped:
                        vmt.button(pkt.hand, V.BUTTON_SYSTEM, True)
                        h.system_release_at = now + SYSTEM_TAP_S
                    h.system_down_at = None
            name = "left" if pkt.hand == 0 else "right"
            if h.system_down_at and not h.snapped and now - h.system_down_at >= HOLD_TO_SNAP_S:
                h.orient.snap_yaw(pkt.quat, Q.yaw(head_rot))
                h.snapped = True
                source.send_haptic(pkt.hand, 0.7, 0.15)
                print(f"{name}: yaw snapped to head")
            # Stick hold: the same snap at 1 s, then a system click at 3 s.
            gesture = h.stick_hold.update(bool(b & P.BTN_STICK), pkt.stick, now)
            if gesture == "snap" and not args.phone:   # the phone game aligns blades itself (triple-click A)
                h.orient.snap_yaw(pkt.quat, Q.yaw(head_rot))
                source.send_haptic(pkt.hand, 0.7, 0.15)
                print(f"{name}: yaw snapped to head (stick hold)")
            elif gesture == "system":
                vmt.button(pkt.hand, V.BUTTON_SYSTEM, True)
                h.system_release_at = now + SYSTEM_TAP_S
                source.send_haptic(pkt.hand, 1.0, 0.4)
                print(f"{name}: system click (stick hold)")
            h.prev_buttons = b

        for h in hands.values():
            if h.system_release_at and now >= h.system_release_at:
                vmt.button(h.hand, V.BUTTON_SYSTEM, False)
                h.system_release_at = None

        if args.debug and now >= next_report:
            next_report = now + 1.0
            for h in hands.values():
                name = "left " if h.hand == 0 else "right"
                if not h.last:
                    print(f"{name}: no packets")
                    continue
                p = h.last
                print(f"{name}: {h.count:3d} Hz  q=({p.quat[0]:+.2f},{p.quat[1]:+.2f},"
                      f"{p.quat[2]:+.2f},{p.quat[3]:+.2f})  stick=({p.stick[0]:+.2f},{p.stick[1]:+.2f})"
                      f"  squeeze={p.trigger:.2f}  buttons={p.buttons:05b}"
                      f"{'' if p.gyro_calibrated else '  GYRO UNCALIBRATED'}")
                h.count = 0


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
