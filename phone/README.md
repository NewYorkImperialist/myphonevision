# Phone and streaming

**The headset phone is now an iPhone 16 Pro running our own client: [ios/README.md](ios/README.md).** This page is the Pixel 7 fallback.

The Pixel 7 runs a PhoneVR client that receives SteamVR video from ALVR on the laptop over USB. It also sends head pose back: Cardboard IMU orientation, plus ARCore position after fork change 2.

## First light (hour 0–3)

1. On the laptop, install SteamVR and **ALVR v20.8.0**. That's the version PhoneVR names; don't take the latest.
2. Install the stock PhoneVR APK on the Pixel. Connect over USB (see [Link](#link-usb)).
3. Get SteamVR Home onto the phone with any viewer, even lenses held by hand. Write down the latency you see; it's the baseline.
4. At the same time, install the **PR #458 app, already built by its author**: [PhoneVR-v21.0.0-dev14-ARcore-v21-release-v1.0.1.apk](https://github.com/righthandpaw/PhoneVR/releases/download/Release-v1.0.1/PhoneVR-v21.0.0-dev14-ARcore-v21-release-v1.0.1.apk) (13 MB, from [righthandpaw/PhoneVR releases](https://github.com/righthandpaw/PhoneVR/releases), Nov 5, 2026). It's newer than the PR, includes reprojection, and adds a Mali GPU fix (the Pixel 7's GPU is a Mali). No Android Studio needed. Pair it with the ALVR nightly tagged **v21.0.0-dev14** (Nov 8–10, 2026 builds), because ALVR only connects matching versions. Whichever pair reaches SteamVR Home first wins.

Stock PhoneVR has open issues: crashes on connect under Android 16, and USB never working with v20.8.0. That's why both run side by side.

## Link (USB)

1. Turn on USB tethering on the Pixel first. That gives a real network interface that carries UDP and charges the phone.
2. If no interface appears, use ALVR's Wired mode (v20.12+) or adb forwarding: `../tools/windows/adb-forward.ps1`.
3. Windows needs its UsbNcm driver for the Pixel and puts the tether on a Public network. Allow ALVR through the firewall: `../tools/windows/alvr-firewall.ps1` (run as admin).

ALVR server settings: **disable ALVR's own controllers**, so the VMT controllers take the left and right hand roles. Set the floor height once ARCore position works.

## Fork work

**You don't need to build it:** use the APK above. `./setup.sh` clones the source into `phone/PhoneVR` (gitignored), only needed to read or change the code. PR #458 moves the client to the ALVR v21 API, adds ARCore 6DoF, its own head-orientation filter (Mahony with gyro-bias estimation) and a seated neck model, supports Wired mode, and cuts display prediction to 30 ms.

1. **Rotational reprojection: already in PR #458.** Each refresh, `alvr_main.cpp` computes the rotation between the pose a frame was rendered for and the current head pose (`alvr_rotation_delta`) and passes it to ALVR's renderer as `reprojection_rotation`. When no new frame has arrived, it re-shows the last one, re-rotated. The stock client lacks this. Nothing to write; check that head turns feel instant once the PR build streams.
2. **ARCore head position: tune only.** Check jitter and drift, that the last position holds when tracking drops, and that recentering works. ARCore starts only after video is flowing (`ARCORE_START_AFTER_VIDEO`).
3. **Viewer parameters: no code needed.** Scan a viewer QR code generated from the headset's measurements (next section).

When the build works, push it to a fork of PhoneVR. It stays out of this repo because PhoneVR has its own license and history.

## Headset QR code (lens settings)

The app's "switch viewer" button scans Cardboard viewer QR codes. `tools/cardboard_qr.py` makes one from the headset's numbers. It encodes the same `https://google.com/cardboard/cfg?p=…` format as Google's own viewer codes, and the phone decodes it offline.

```sh
pip install segno                                   # for the QR images
python3 tools/cardboard_qr.py --lens-f 62 --lens-d 45            # one code
python3 tools/cardboard_qr.py --lens-f 62 --lens-d 45 --k1-sweep 0.1 0.2 0.3 0.4   # tuning set
```

Use the same `lens_f` and `focus_back_off` as `headset/headset.scad`. The images land in `build/qr/`; open one on a laptop screen and scan it from the phone.

**Tuning distortion (k1, k2):** show a grid in SteamVR (or any straight lines) and scan each code in the sweep. Keep the one where straight lines look straightest near the edges of the view. If lines bend one way at the lowest k1 and the other way at the highest, the right value is in between; sweep more finely around it. Defaults start from Google's Cardboard v2 values (k1 0.24, k2 0.30). `--decode URL` prints what's inside any viewer code.

## Thermals

The Pixel 7 throttles under video decode plus ARCore plus full brightness. Cap brightness, stream at 60–72 Hz, and keep demo sessions to about 5 minutes with cool-downs between them.
