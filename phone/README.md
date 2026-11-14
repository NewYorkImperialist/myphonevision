# Phone and streaming

The Pixel 7 runs a PhoneVR client that receives SteamVR video from ALVR on the laptop over USB. It also sends head pose back: Cardboard IMU orientation, plus ARCore position after fork change 2.

## First light (hour 0–3)

1. On the laptop, install SteamVR and **ALVR v20.8.0**. That's the version PhoneVR names; don't take the latest.
2. Install the stock PhoneVR APK on the Pixel. Connect over USB (see [Link](#link-usb)).
3. Get SteamVR Home onto the phone with any viewer, even lenses held by hand. Write down the latency you see; it's the baseline.
4. At the same time, build the PR #458 branch (`./setup.sh`, then build `pr-458`). Pair it with the ALVR nightly tagged **v21.0.0-dev14** (Nov 8–10, 2026 builds), because ALVR only connects matching versions. Whichever pair reaches SteamVR Home first wins.

Stock PhoneVR has open issues: crashes on connect under Android 16, and USB never working with v20.8.0. That's why both run side by side.

## Link (USB)

1. Turn on USB tethering on the Pixel first. That gives a real network interface that carries UDP and charges the phone.
2. If no interface appears, use ALVR's Wired mode (v20.12+) or adb forwarding: `../tools/windows/adb-forward.ps1`.
3. Windows needs its UsbNcm driver for the Pixel and puts the tether on a Public network. Allow ALVR through the firewall: `../tools/windows/alvr-firewall.ps1` (run as admin).

ALVR server settings: **disable ALVR's own controllers**, so the VMT controllers take the left and right hand roles. Set the floor height once ARCore position works.

## Fork work

Run `./setup.sh` to clone PhoneVR into `phone/PhoneVR` (gitignored) and check out PR #458. PR #458 already moves the client to the ALVR v21 API, adds ARCore 6DoF with a complementary filter, supports Wired mode, and cuts display prediction to 30 ms. That leaves:

1. **Rotational reprojection (highest priority).** `alvr_get_frame` writes each frame's pose into a dummy variable. Keep that pose. At draw time, take the latest Cardboard head pose and compute the rotation delta from the frame's pose. Rotate the eye-pass texture lookup by that delta before Cardboard's distortion pass. About 100–200 lines.
2. **ARCore head position: tuning only if #458 works.** Keep orientation from the Cardboard tracker (IMU rate) and position from ARCore (30 Hz on the Pixel 7, so predict between frames). Pull Cardboard yaw toward ARCore yaw continuously. Hold the last position when tracking is lost. Add a recenter gesture. Start ARCore only after video is flowing.
3. **Viewer parameters.** Hard-code this headset's lens separation, screen-to-lens distance, tray-to-lens offset and k1/k2 distortion in place of the QR scan. Tune k1/k2 with a debug slider over a grid, then bake the values in. Get the distances from `headset/headset.scad`'s echo output.

When the fork works, push it to a fork of PhoneVR. It stays out of this repo because PhoneVR has its own license and history.

## Thermals

The Pixel 7 throttles under video decode plus ARCore plus full brightness. Cap brightness, stream at 60–72 Hz, and keep demo sessions to about 5 minutes with cool-downs between them.
