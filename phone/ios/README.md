# iPhone client (iPhone 16 Pro)

The headset phone runs our own ALVR client. It receives SteamVR video from ALVR on the Windows laptop, shows it through the lenses, and sends 6DoF head pose back from ARKit. To SteamVR it's just an HMD, so everything that runs on SteamVR runs on it. Owner: Nafis (Nofees4Novembah), building on his Mac. Discussion: issue #3. The Pixel 7 path ([../README.md](../README.md)) stays ready as the fallback until the team's go/no-go time.

Target phone: iPhone 16 Pro, 6.3" OLED, 2622×1206 at 460 ppi, 120 Hz. It sits landscape in the headset tray, screen toward the lenses.

## Build

- Code: [app/](app/) started as a copy of [kotleni/iPhoneVR](https://github.com/kotleni/iPhoneVR) at d3683bc (MIT, LICENSE kept), an unofficial ALVR client for iOS. Tracking, the lens pass, reprojection, 120 Hz and test mode are ours.
- **ALVR v21.0.0-dev14** (commit [9f11839](https://github.com/alvr-org/ALVR/commit/9f11839431f95f0df6764790d9a16f8e308a0d79), the source of the 2026.09.30 to 10.03 nightlies and the same commit the Pixel's PhoneVR Release-v1.0.1 is built on). `app/fetch_alvr.sh` downloads that source into `app/ALVR/` (git-ignored), plus the headers of its `openvr` submodule (which GitHub tarballs leave out). **The laptop runs the v21.0.0-dev14 nightly**, the same server as the Pixel fallback.
- `app/build_and_repack.sh` builds ALVR's client library for iOS into `ALVRClientCore.xcframework` (needs Rust; ALVR pins Rust 1.97.1 in `rust-toolchain.toml`, which rustup installs on first use; the script adds the `aarch64-apple-ios` target and cbindgen). Xcode 26 also needs `xcodebuild -downloadComponent MetalToolchain` once.
- Signing: put your own settings in `app/Override.xcconfig` (git-ignored): `DEVELOPMENT_TEAM = <your team ID>` and `PRODUCT_BUNDLE_IDENTIFIER = <unique id>`. A free Apple ID works; the app expires after 7 days (re-run from Xcode). Turn on Developer Mode on the phone, and trust the developer under Settings → General → VPN & Device Management.
- Open `app/ALVRClient.xcodeproj` in Xcode and run, or from the command line:
  ```sh
  cd phone/ios/app
  xcodebuild -project ALVRClient.xcodeproj -scheme ALVRClient -configuration Debug \
    -destination 'platform=iOS,name=<phone name>' -allowProvisioningUpdates build
  xcrun devicectl device install app --device <id from 'xcrun devicectl list devices'> \
    ~/Library/Developer/Xcode/DerivedData/ALVRClient-*/Build/Products/Debug-iphoneos/ALVRClient.app
  xcrun devicectl device process launch --terminate-existing --device <id> <bundle id>
  ```

## Using the app

- **Start** connects to ALVR on the laptop. **Test mode (no server)** shows a built-in room through the same lens pass, tracking and reprojection as the stream: blue wall ahead, red right, green left, yellow behind, 0.5 m grid, a yellow ball 1.5 m ahead.
- In either mode: **tap** to recenter (forward = where you look, head at the eye-height setting), **hold 1 s** to return to the lobby.
- Lobby settings (saved on the phone): k1, k2, screen-to-lens, IPD and lens height (lens pass); eye height; reprojection on/off; 120 Hz on/off; test mode's simulated latency.
- **With lenses:** set screen-to-lens to `lens_f` − 2.5 mm, then tune k1 in test mode until the grid lines look straight through the lenses.

## Milestones

| # | Milestone | State |
| --- | --- | --- |
| 1 | **Video:** SteamVR Home on the phone | Code ported to the v21 API (library builds, Swift typechecks); **needs the laptop** with the ALVR v21.0.0-dev14 nightly (below) |
| 2 | **Head pose from ARKit** | Done, checked in test mode: landscape left/right, camera-to-eyes offset (estimate: `WorldTracker.eyesFromCamera`), hold position when tracking is limited, tap to recenter, rotation predicted to display time (≤ 50 ms) |
| 3 | **Two eyes through the lenses** | Done (`Shaders.metal`: `screenToEye`, `frameUV`); k1/k2 untuned until there are lenses |
| 4 | **Rotational reprojection** | Done, checked in test mode with 150 ms simulated latency |
| 5 | **USB link** | Needs the laptop (below) |
| – | **120 Hz display** | Done; stream at 60–72 Hz, the display reprojects at 120 |

How the stream path works (ALVR v21 API): every display refresh, `EventHandler.sendTracking()` sends the head pose as the `/user/head` device motion, tagged with a target time = now + the prediction offset (nanoseconds). The two eye views (±IPD/2 along x, in head space, with each eye's FOV from the lens model) go separately through `alvr_send_view_params`, only when the IPD or lens settings change. v21's C API doesn't expose ALVR's prediction offset, so the app learns it: each new frame's display time minus its timestamp nudges the offset (`EventHandler.updatePrediction`, 0 to 100 ms). Video arrives through `alvr_set_decoder_input_callback` on ALVR's video thread and goes straight into VideoToolbox; refusing a frame (decoder error, stall) makes ALVR request a key frame. When a frame is first shown, `alvr_report_compositor_start` returns the eye poses it was rendered for; the lens pass rotates every eye ray from the current head into that pose (rotation-only reprojection) and looks it up in that eye's half of the frame.

## Laptop setup for milestone 1 (Windows)

1. SteamVR installed. **ALVR v21.0.0-dev14** streamer from the [ALVR nightlies](https://github.com/alvr-org/ALVR-nightly/releases) (any `v21.0.0-dev14+nightly.*` build; the same one the Pixel uses, since ALVR only connects matching versions). Run the ALVR dashboard once so it registers its SteamVR driver.
2. In the ALVR dashboard: **Headset → Controllers off** (ours come through VMT). Video: preferred refresh rate 60 or 72 to start; H.264 or HEVC both decode on the iPhone; foveated encoding off.
3. Network: put the laptop and phone on the same network. **The laptop's Wi-Fi hotspot** is the safe choice (campus Wi-Fi usually blocks device-to-device traffic).
4. On the phone: Start. The iPhone should appear in the ALVR dashboard as a new device: **Trust** it. SteamVR starts streaming; the screen shows SteamVR Home through the lens pass.
5. If it doesn't connect: same ALVR version on both sides? Windows firewall allowing ALVR on private networks? The phone app's lobby shows the hostname it advertises.

## Milestone 5: USB link (optional)

An iPhone's **Personal Hotspot over USB** gives the laptop a wired network to the phone, like the Pixel's USB tethering. Untested:
- Windows needs Apple's drivers: the **Apple Devices** app (Microsoft Store) or iTunes.
- On the phone: Settings → Personal Hotspot → **Allow Others to Join** on. The carrier plan has to allow hotspot; the cellular data itself isn't used.
- Plug in, tap **Trust** on the phone. Windows should show a new "Apple Mobile Device Ethernet" adapter with a 172.20.10.x address. Then start the app as usual; ALVR finds it over that network.
- If hotspot isn't available, stay on the laptop's Wi-Fi hotspot.

## Gotchas

- **Heat:** video decode, ARKit and full brightness at 120 Hz heat the phone fast. Cap brightness, keep demo sessions to about 5 minutes, cool down between them; switch the lobby's 120 Hz off if it throttles.
- **Camera-to-eyes offset** is an estimate for the 16 Pro in the tray (55 mm sideways, 15 mm vertical, 60 mm back). If nodding or turning makes the world swing, measure it on the printed headset and update `WorldTracker.eyesFromCamera`.
- **Body tracking depends on this:** webcam full-body tracking ([../../docs/webcam-fbt.md](../../docs/webcam-fbt.md)) hangs the body off the head position, so milestone 2 gates full-body tracking.
- **AR mode** (camera passthrough, issue #5) is a stretch goal for after hour 20.
