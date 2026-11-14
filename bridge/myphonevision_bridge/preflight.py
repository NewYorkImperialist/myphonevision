"""Pre-demo checklist: is everything plugged in and running?

    python -m myphonevision_bridge.preflight

Run it before starting the bridge (it briefly listens on VMT's output port,
which the bridge also uses). Each line is OK, WARN or FAIL with what to do.
"""

from __future__ import annotations

import socket
import sys
import time

from . import protocol as P
from . import vmt as V

SLIMEVR_GUI_PORT = 21110  # SlimeVR server's websocket for its GUI

results: list[tuple[str, str, str]] = []


def report(status: str, what: str, hint: str = "") -> None:
    results.append((status, what, hint))
    line = f"[{status:4s}] {what}"
    if hint:
        line += f"\n         -> {hint}"
    print(line)


USB_SERIAL_KEYS = ("CP210", "Silicon Labs", "CH340", "CH910", "USB-SERIAL", "UART")


def hands_seen(data: bytes) -> set[int]:
    """Hands with at least one valid controller frame in raw hub output."""
    return {p.hand for p in map(P.parse_controller, P.FrameDecoder().feed(data)) if p}


def find_hubs(seconds: float = 1.5) -> tuple[list[str], dict[str, set[int]]]:
    """USB-serial ports, and which of them stream controller frames (hand numbers seen).

    Controllers and the hub use the same USB chips, so only the traffic tells them apart.
    A hub with no controller switched on is silent and can't be told apart either.
    """
    import serial
    from serial.tools import list_ports

    ports = [p.device for p in list_ports.comports()
             if any(k in (p.description or "") + (p.manufacturer or "") for k in USB_SERIAL_KEYS)]
    hubs: dict[str, set[int]] = {}
    for dev in ports:
        try:
            with serial.Serial(dev, 921600, timeout=0.1) as s:
                end, data = time.monotonic() + seconds, b""
                while time.monotonic() < end:
                    data += s.read(4096)
        except serial.SerialException:
            continue
        if seen := hands_seen(data):
            hubs[dev] = seen
    return ports, hubs


def check_hub() -> None:
    try:
        ports, hubs = find_hubs()
    except ImportError:
        report("FAIL", "pyserial not installed", "pip install -e bridge/")
        return
    if not ports:
        report("FAIL", "no ESP-NOW hub found", "plug the hub DevKitC into the laptop (data cable)")
    elif len(hubs) == 1:
        dev, seen = next(iter(hubs.items()))
        names = " and ".join(n for h, n in ((0, "left"), (1, "right")) if h in seen)
        report("OK", f"ESP-NOW hub on {dev}, receiving {names}")
    elif hubs:
        report("WARN", f"controller packets on several ports: {', '.join(hubs)}",
               "pass --serial to the bridge with the hub's port")
    else:
        report("WARN", f"no controller packets on {', '.join(ports)}",
               "switch a controller on; if still nothing, the board on USB is a controller, "
               "not the hub (or the port is busy: close pio device monitor)")


def check_vmt_alive(timeout: float = 3.0) -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.bind(("127.0.0.1", V.VMT_OUT_PORT))
    except OSError:
        report("WARN", f"port {V.VMT_OUT_PORT} busy, can't listen for VMT",
               "the bridge or VMT Manager is already running; close VMT Manager during play")
        return
    sock.settimeout(timeout)
    try:
        data, _ = sock.recvfrom(4096)
        if b"/VMT/Out/" in data:
            report("OK", "VMT driver is talking (OSC on 39571)")
        else:
            report("WARN", "something sent data on 39571, but not VMT")
    except socket.timeout:
        report("FAIL", f"no message from VMT in {timeout:.0f} s",
               "install VMT and start SteamVR; check VMT is enabled in SteamVR's startup add-ons")
    finally:
        sock.close()


def check_slimevr() -> None:
    try:
        with socket.create_connection(("127.0.0.1", SLIMEVR_GUI_PORT), timeout=1.0):
            report("OK", "SlimeVR server is running")
    except OSError:
        report("WARN", "SlimeVR server not detected",
               "start the SlimeVR server (only needed for body tracking)")


def check_steamvr() -> None:
    try:
        import openvr
    except ImportError:
        report("FAIL", "openvr module not installed (Windows only)", "pip install openvr")
        return
    try:
        system = openvr.init(openvr.VRApplication_Background)
    except Exception as e:  # noqa: BLE001 - openvr raises its own error types
        report("FAIL", f"SteamVR not reachable ({e})", "start SteamVR first")
        return
    try:
        hmd = vmt_ctrls = slime = 0
        for i in range(openvr.k_unMaxTrackedDeviceCount):
            if not system.isTrackedDeviceConnected(i):
                continue
            cls = system.getTrackedDeviceClass(i)
            def prop(p):
                try:
                    return system.getStringTrackedDeviceProperty(i, p)
                except Exception:  # noqa: BLE001
                    return ""
            serial = prop(openvr.Prop_SerialNumber_String)
            system_name = prop(openvr.Prop_TrackingSystemName_String)
            if cls == openvr.TrackedDeviceClass_HMD:
                hmd += 1
            if "vmt" in (serial + system_name).lower():
                vmt_ctrls += 1
            if "slime" in (serial + system_name).lower():
                slime += 1
        if hmd:
            report("OK", "headset connected in SteamVR (ALVR + phone)")
        else:
            report("FAIL", "no headset in SteamVR", "start ALVR and connect the phone over USB")
        if vmt_ctrls >= 2:
            report("OK", f"{vmt_ctrls} VMT controllers in SteamVR")
        else:
            report("WARN", f"{vmt_ctrls} VMT controllers in SteamVR",
                   "start the bridge and turn both controllers on; they appear on their first packet")
        if slime:
            report("OK", f"{slime} SlimeVR trackers in SteamVR")
        else:
            report("WARN", "no SlimeVR trackers in SteamVR",
                   "power the trackers; they need the PC hotspot and the SlimeVR server")
    finally:
        openvr.shutdown()


def main() -> None:
    print("myphonevision preflight\n")
    check_hub()
    check_vmt_alive()
    check_slimevr()
    check_steamvr()
    fails = sum(1 for s, _, _ in results if s == "FAIL")
    warns = sum(1 for s, _, _ in results if s == "WARN")
    print(f"\n{fails} FAIL, {warns} WARN")
    print("Before each run: reset SlimeVR (full reset key), hold system 1 s on each controller "
          "to snap yaw, and let the phone cool between sessions.")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
