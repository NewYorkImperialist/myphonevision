"""Pre-demo checklist: is everything plugged in and running?

    python -m myphonevision_bridge.preflight

Run it before starting the bridge (it briefly listens on VMT's output port,
which the bridge also uses). Each line is OK, WARN or FAIL with what to do.
"""

from __future__ import annotations

import socket
import sys
import time

from . import vmt as V

SLIMEVR_GUI_PORT = 21110  # SlimeVR server's websocket for its GUI

results: list[tuple[str, str, str]] = []


def report(status: str, what: str, hint: str = "") -> None:
    results.append((status, what, hint))
    line = f"[{status:4s}] {what}"
    if hint:
        line += f"\n         -> {hint}"
    print(line)


def check_hub() -> None:
    try:
        from serial.tools import list_ports
    except ImportError:
        report("FAIL", "pyserial not installed", "pip install -e bridge/")
        return
    ports = [p for p in list_ports.comports()
             if any(k in (p.description or "") + (p.manufacturer or "")
                    for k in ("CP210", "Silicon Labs", "CH340", "CH910", "USB-SERIAL", "UART"))]
    if len(ports) == 1:
        report("OK", f"ESP-NOW hub on {ports[0].device} ({ports[0].description})")
    elif ports:
        names = ", ".join(p.device for p in ports)
        report("WARN", f"several USB-serial devices: {names}",
               "unplug tracker boards from the laptop, or pass --serial to the bridge")
    else:
        report("FAIL", "no ESP-NOW hub found", "plug the hub DevKitC into the laptop (data cable)")


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
