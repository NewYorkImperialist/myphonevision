# myphonevision

> **Start here:** [CLAUDE.md](CLAUDE.md) has the current plan, what each teammate does next, and the state of every part. Claude Code reads it automatically when you open this repo.

A SteamVR-native phone headset built for HackUMass. A Pixel 7 is the display and the inside-out 6DoF head tracker, tethered over USB to a Windows GPU laptop running ALVR. Two 3D-printed ESP32 controllers show up in SteamVR as Valve Index controllers through Virtual Motion Tracker (VMT), and a SlimeVR set adds lower-body tracking. Every device registers as a standard SteamVR device, so VRChat, Beat Saber and SteamVR Home run unmodified.

```
 Pixel 7 (PhoneVR fork) ──USB──▶ ALVR ─┐
                                       │
 Controllers ──ESP-NOW──▶ hub ──USB──▶ bridge ──OSC──▶ VMT ─┼──▶ SteamVR ──▶ games
                                       │
 SlimeVR trackers ──PC hotspot──▶ SlimeVR server ─┘
```

The phone is the only part on a cable. Controllers use ESP-NOW and trackers use a private hotspot, so venue Wi-Fi never touches the tracking path.

## Before anything else: the two gates (by hour 3)

1. **A Windows laptop with a hardware video encoder**: NVIDIA GTX 1000+ (NVENC), AMD (AMF) or Intel (VPL). No such laptop means re-planning as a standalone Android app, which loses SteamVR.
2. **A matched pair of lenses**: 40–50 mm focal length, 25–35 mm diameter. The headset CAD can't be finalized without them. See [headset/README.md](headset/README.md).

The full plan, parts list and risks are in [docs/plan.md](docs/plan.md). Step-by-step wiring for the controllers, hub and trackers is in [docs/wiring.md](docs/wiring.md).

## Layout

| Path | What | Workstream |
| --- | --- | --- |
| [headset/](headset/) | Parametric OpenSCAD shell, lens focus jig | Optics and industrial design |
| [cases/](cases/) | Tracker cases and controller shells (OpenSCAD) | Optics and industrial design |
| [phone/](phone/) | PhoneVR setup script and fork notes | Phone and streaming |
| [firmware/controller/](firmware/controller/) | ESP32 controller firmware: DevKitC or Xiao ESP32S3 (PlatformIO) | Controllers |
| [firmware/hub/](firmware/hub/) | ESP-NOW to USB-serial hub, DevKitC (PlatformIO) | Controllers |
| [firmware/shared/packet.h](firmware/shared/packet.h) | Radio packet format | Controllers |
| [bridge/](bridge/) | Python bridge: hub serial to VMT OSC, arm model, yaw snap | Controllers |
| [firmware/slimevr/](firmware/slimevr/) | SlimeVR tracker wiring and config | Body tracking |
| [tools/windows/](tools/windows/) | adb forwarding and firewall scripts | Phone and streaming |
| [tools/export-stl.sh](tools/export-stl.sh) | Export every printable part to `build/stl/` | Optics and industrial design |
| [tools/cardboard_qr.py](tools/cardboard_qr.py) | Headset lens settings as a Cardboard QR code for the phone | Phone and streaming |

## Quick start

```sh
# Controllers (any OS with PlatformIO)
cd firmware/hub && pio run -t upload
cd firmware/controller && pio run -e devkit_left -t upload    # then devkit_right

# Bridge (on the Windows laptop, with SteamVR and VMT running)
cd bridge && pip install -e . && python -m myphonevision_bridge --debug

# Phone
./phone/setup.sh
```

## Status

| Part | State |
| --- | --- |
| Controller and hub firmware | Compiles for DevKitC and Xiao (espressif32 6.12.0), with a serial bench test; not yet run on hardware |
| Bridge | Unit tests and a UDP-to-OSC smoke test pass; pre-demo check (`preflight`) added; not yet run against SteamVR |
| Headset CAD | Renders and exports cleanly; supports stacked lenses, top strap; not printed; needs lens measurements |
| Tracker and controller cases | Render and export cleanly; not printed; sizes from datasheets until parts are measured |
| PhoneVR | No build needed: the PR #458 author publishes an APK (v1.0.1, with reprojection and a Mali GPU fix). Lens settings come from a generated QR code (`tools/cardboard_qr.py`) |
| SlimeVR | `firmware/slimevr/build.sh` builds stock SlimeVR v0.7.4 for DevKitC + 2× MPU-6050; not yet flashed |
