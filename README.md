# myphonevision

A SteamVR headset built from a phone, a cardboard box and two magnifiers, made at HackUMass XIV. An iPhone 16 Pro running our own ALVR client is the display and the head tracker, on a USB cable to a Fedora Linux laptop running SteamVR. Two ESP32 controllers show up in SteamVR as Valve Index controllers through Virtual Motion Tracker (VMT). Every device registers as a standard SteamVR device, so SteamVR Home and SteamVR games run unmodified (games through Proton on Linux).

```
 iPhone 16 Pro (our client) ◀──USB──▶ ALVR ───────────────────┐
                                                              ├──▶ SteamVR ──▶ games
 Controllers ──ESP-NOW──▶ hub ──USB──▶ bridge ──OSC──▶ VMT ───┘
```

Nothing goes over venue Wi-Fi: the phone streams over USB, and the controllers talk to the hub by ESP-NOW. There is no body tracking; the planned SlimeVR trackers were cut.

## Phone

A friend's iPhone 16 Pro runs our own client ([phone/ios/](phone/ios/)), built from [kotleni/iPhoneVR](https://github.com/kotleni/iPhoneVR) on ALVR v21.0.0-dev14. It tracks the head with ARKit, filled in by the gyro, and shows the stream through a lens distortion pass at 120 Hz, reprojecting each frame to the latest head pose. It also has an optional AR passthrough mode. A Pixel 7 running PhoneVR is the fallback ([phone/README.md](phone/README.md)).

## Headset

Laser-cut corrugated cardboard ([headset/cardboard/](headset/cardboard/), picture guide [build-guide.pdf](headset/cardboard/build-guide.pdf), v2 in [headset/cardboard/v2/](headset/cardboard/v2/)). It holds two Carson TriView TV-36 magnifiers at 5.5x: on each, the top and bottom lenses are swung out and the middle one is left in. The 3D-printed headset in [headset/](headset/) is parked.

## Laptop

Fedora Linux on an Intel Arc 140V, running SteamVR and ALVR v21.0.0-dev14. It streams to the iPhone over USB, through the iPhone's Personal Hotspot, at 60 fps with about 36 ms total latency. The Linux setup and its fixes are in [phone/README.md](phone/README.md#linux-laptop-fedora-intel-arc-igpu). Two of the fixes are scripts: [tools/linux/alvr-pose-patch.sh](tools/linux/alvr-pose-patch.sh) patches ALVR's server so the stream stops freezing every few seconds, and [tools/linux/vmt.sh](tools/linux/vmt.sh) builds VMT, which only ships for Windows, as a Linux SteamVR driver.

## Controllers

Two ESP32 controllers, each with an IMU, an analog thumbstick, an A button and an FSR grip, on 4×AA. LEFT has a GY-521 (MPU-6050) and RIGHT an Adafruit BNO055. They send to a hub ESP32 by ESP-NOW, LEFT at about 195 Hz and RIGHT at about 150 Hz. The hub passes the packets over USB serial to a Python bridge ([bridge/](bridge/)), which places each hand with an arm model and sends it to VMT, so SteamVR sees two Valve Index controllers.

To reset drift, click and hold the thumbstick (centered) for 1 s. Hold it for 3 s for a system click (the SteamVR menu).

Firmware is in [firmware/controller/](firmware/controller/) and [firmware/hub/](firmware/hub/) (PlatformIO), wiring in [docs/wiring.md](docs/wiring.md), and the shell (concept D, a pistol grip) in [cases/mockups/controller/d_ergo.scad](cases/mockups/controller/d_ergo.scad).

## Test game

[game/saber_playground.py](game/saber_playground.py) is our own SteamVR app: a blade in each hand for slicing floating cubes. It runs on the laptop like any SteamVR game, so ALVR streams it to the iPhone app, and each blade follows one of the two controllers. `game/play.sh` starts the bridge and the game in one command. `--desktop` runs it in a window without a headset.

## How to run it

On the Fedora laptop:

1. **Headset:** set up SteamVR and ALVR v21.0.0-dev14 with the fixes in [phone/README.md](phone/README.md#linux-laptop-fedora-intel-arc-igpu), install the iPhone app ([phone/ios/README.md](phone/ios/README.md)), plug the phone in with Personal Hotspot on, then start SteamVR from the ALVR dashboard.
2. **Controllers:** run `tools/linux/vmt.sh` once and restart SteamVR. Plug in the hub, turn on both controllers, and in `bridge/` run `pip install -e . && python -m myphonevision_bridge --debug`.
3. **Play:** start SteamVR Home or a game from Steam. For our sword game, run `pip install -r game/requirements.txt` once, then `game/play.sh` from the repo root: it starts the bridge if step 2's isn't running, then the game, and the phone shows it ([game/README.md](game/README.md)).

## Layout

| Path | What |
| --- | --- |
| [phone/ios/](phone/ios/) | iPhone client (ALVR v21, from kotleni/iPhoneVR) |
| [phone/](phone/) | Linux laptop setup and fixes, and the Pixel 7 fallback |
| [tools/linux/](tools/linux/) | VMT as a Linux SteamVR driver (`vmt.sh`) and the ALVR server pose patch (`alvr-pose-patch.sh`) |
| [headset/cardboard/](headset/cardboard/) | Cardboard headset: cut files, picture guide, v2 in `v2/` |
| [headset/](headset/) | 3D-printed headset in OpenSCAD (parked) |
| [cases/](cases/) | Controller shells in OpenSCAD; the one in use is [cases/mockups/controller/d_ergo.scad](cases/mockups/controller/d_ergo.scad) |
| [firmware/controller/](firmware/controller/) | ESP32 controller firmware; detects an MPU-6050 or BNO055 (PlatformIO) |
| [firmware/hub/](firmware/hub/) | ESP-NOW to USB-serial hub (PlatformIO) |
| [firmware/shared/packet.h](firmware/shared/packet.h) | Radio packet format, mirrored in [bridge/myphonevision_bridge/protocol.py](bridge/myphonevision_bridge/protocol.py) |
| [bridge/](bridge/) | Python bridge: hub serial to VMT OSC, arm model, drift reset |
| [game/](game/) | Saber playground, our SteamVR test game |
| [docs/wiring.md](docs/wiring.md) | Controller and hub wiring, and what goes in each shell |
| [firmware/slimevr/](firmware/slimevr/), [tools/windows/](tools/windows/), [tools/cardboard_qr.py](tools/cardboard_qr.py), [tools/export-stl.sh](tools/export-stl.sh) | Not in the current build: SlimeVR trackers (cut), Windows and Pixel 7 tools, STL export for the printed parts |
