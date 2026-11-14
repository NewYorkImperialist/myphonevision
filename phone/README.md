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

## Linux laptop (Fedora, Intel Arc iGPU)

The streaming laptop runs SteamVR and ALVR on Linux. Tested on Fedora 44, Intel Core Ultra 200V (Arc 140V, `xe` driver), SteamVR 2.18.4, ALVR `v21.0.0-dev14+nightly.2026.11.10`. ALVR v20.8.0 never got past error 307 here; use v21.

1. **ALVR:** extract `alvr_streamer_linux.tar.gz` from the nightly, run `bin/alvr_dashboard`, finish the wizard and **always start SteamVR from the dashboard** (Launch SteamVR). Without the dashboard, the ALVR driver loads but adds no headset ("headset not detected").
2. **SteamVR settings:** with SteamVR closed, add these to `"steamvr"` in `~/.local/share/Steam/config/steamvr.vrsettings`:
   ```json
   "forceDisableLinuxVulkanAsync": true,
   "disableLinuxWaitForPresent": true
   ```
   The first stops the compositor hanging at 100% CPU after "Insufficient permission to create high priority queue" (error 307). The second stops it crashing a second after "Startup Complete" (null `vkWaitForPresentKHR` through ALVR's Vulkan layer).
3. **vrmonitor crash:** SteamVR's Qt expects OpenSSL 1.0 and crashes on Fedora's 3.x while loading CA certificates. Link the Steam runtime's copies into a folder of their own:
   ```sh
   R=~/.local/share/Steam/steamapps/common/LegacySteamRuntime/steam-runtime/lib/x86_64-linux-gnu
   mkdir -p ~/Apps/steamvr-openssl10 && ln -sf $R/libssl.so.1.0.0 $R/libcrypto.so.1.0.0 ~/Apps/steamvr-openssl10/
   ```
   and set SteamVR's launch options (Steam → SteamVR → Properties) to
   `LD_LIBRARY_PATH=$HOME/Apps/steamvr-openssl10${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH} ~/.local/share/Steam/steamapps/common/SteamVR/bin/vrmonitor.sh %command%`
4. **Controllers:** `../tools/linux/vmt.sh` builds VMT for Linux and registers it; the bridge works unchanged.
5. **Network:** turn off any VPN (Mullvad blocks LAN traffic) or allow local network sharing. The iPhone app can't advertise itself over mDNS, so add it in the dashboard (Devices → Add device manually) with the hostname from its lobby (e.g. `4119.client.local.`) and its IP.

Still showing after all this: SteamVR's "Something is wrong (303)" status alert. It doesn't stop streaming.

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
