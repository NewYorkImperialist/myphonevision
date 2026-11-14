# myphonevision

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

The full plan, parts list and risks are in [docs/plan.md](docs/plan.md).

## Layout

| Path | What | Workstream |
| --- | --- | --- |
| [headset/](headset/) | Parametric OpenSCAD shell, lens focus jig | Optics and industrial design |
| [phone/](phone/) | PhoneVR setup script and fork notes | Phone and streaming |
| [firmware/controller/](firmware/controller/) | ESP32 controller firmware: DevKitC or Xiao ESP32S3 (PlatformIO) | Controllers |
| [firmware/hub/](firmware/hub/) | ESP-NOW to USB-serial hub, DevKitC (PlatformIO) | Controllers |
| [firmware/shared/packet.h](firmware/shared/packet.h) | Radio packet format | Controllers |
| [bridge/](bridge/) | Python bridge: hub serial to VMT OSC, arm model, yaw snap | Controllers |
| [firmware/slimevr/](firmware/slimevr/) | SlimeVR tracker wiring and config | Body tracking |
| [tools/windows/](tools/windows/) | adb forwarding and firewall scripts | Phone and streaming |

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
| Controller and hub firmware | Compiles (espressif32 6.12.0); not yet run on hardware |
| Bridge | Unit tests and a UDP-to-OSC smoke test pass; not yet run against SteamVR |
| Headset CAD | Written, not yet rendered or printed; needs lens measurements |
| PhoneVR fork | Not started; `phone/setup.sh` checks out PR #458 |
| SlimeVR | Config notes only; uses stock SlimeVR |
