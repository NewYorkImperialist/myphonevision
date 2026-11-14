# iPhone client (iPhone 16 Pro)

The headset phone runs our own ALVR client. It receives SteamVR video from ALVR on the Windows laptop, shows it through the lenses, and sends 6DoF head pose back from ARKit. To SteamVR it's just an HMD, so everything that runs on SteamVR runs on it. Owner: Nafis (Nofees4Novembah). Discussion: issue #3. The Pixel 7 path ([../README.md](../README.md)) stays ready as the fallback until the team's go/no-go time.

Target phone: iPhone 16 Pro, 6.3" OLED, 2622×1206 at 460 ppi, 120 Hz. It sits landscape in the headset tray, screen toward the lenses.

## Start

- Code: [app/](app/) is a copy of [kotleni/iPhoneVR](https://github.com/kotleni/iPhoneVR) at d3683bc (MIT, LICENSE kept), an unofficial ALVR client for iOS. Its README calls it "very unstable": basic streaming, the lobby and ARKit tracking work; side-by-side view, distortion and reprojection don't. If it's too broken, adapt the official [alvr-visionos](https://github.com/alvr-org/alvr-visionos) client (Swift/Metal) instead.
- **ALVR v20.8.0** (commit 1d121fa). `app/fetch_alvr.sh` downloads that source into `app/ALVR/` (git-ignored). **The laptop's ALVR server must be v20.8.0 too**, not the Pixel fallback's v21.0.0-dev14.
- Build: `app/build_and_repack.sh` builds ALVR's client library for iOS into `ALVRClientCore.xcframework` (needs Rust; it adds the `aarch64-apple-ios` target and cbindgen). Then open `app/ALVRClient.xcodeproj` in Xcode and run on the phone.
- Signing: put your own settings in `app/Override.xcconfig` (git-ignored): `DEVELOPMENT_TEAM = <your team ID>` and `PRODUCT_BUNDLE_IDENTIFIER = <unique id>`. A free Apple ID works; the app expires after 7 days (re-run from Xcode). Turn on Developer Mode on the phone.

## Milestones

Each one is a checkpoint; post on issue #3 when it lands.

1. **Video.** Connects to the laptop over Wi-Fi and shows SteamVR Home, mono is fine. In the ALVR server, turn off ALVR's own controllers: ours arrive through VMT.
2. **Head pose from ARKit.** `ARWorldTrackingConfiguration`; each frame send `frame.camera.transform` as the head pose.
   - ARKit world space and SteamVR are both right-handed, Y up, −Z forward. ARKit's camera axes follow the camera sensor (landscape), so rotate for how the phone sits in the tray; check by tilting your head.
   - Offset from the camera to between the eyes (a few cm), so turning your head doesn't swing the view.
   - Hold the last pose when tracking is lost (`camera.trackingState`). Add a recenter gesture (a tap) that resets yaw and position.
   - ARKit runs at 60 Hz. Predict the pose forward to display time; ALVR asks for a target timestamp.
3. **Two eyes through the lenses.** Split the frame into left and right eye halves and run a small Metal pass with radial distortion, r' = r(1 + k1·r² + k2·r⁴), per eye. Start at k1 0.24, k2 0.30, IPD 63 mm, screen-to-lens = `lens_f` − 2.5 mm (the headset's `focus_back_off`). Tune k1 with a debug slider while looking at a grid in SteamVR, then bake the values in.
4. **Rotational reprojection (most important for comfort).** The stream is 50–150 ms behind your head. Keep the pose each frame was rendered for. At draw time, rotate the texture lookup by the rotation between that pose and the newest ARKit pose. If no new frame arrived, re-show the last one, re-rotated. This makes head turns feel instant even when video lags. PhoneVR PR #458 does the same thing (`alvr_rotation_delta`, `reprojection_rotation` in its `alvr_main.cpp`); read it for reference.
5. **USB link (optional).** iPhone USB Personal Hotspot should give the laptop a network interface like the Pixel's tethering. Untested: it may need Apple's Windows drivers, and the carrier must allow hotspot. The laptop's Wi-Fi hotspot is the fallback.

## Gotchas

- **120 Hz:** set `CADisableMinimumFrameDurationOnPhone` to YES in Info.plist, or the display stays at 60 Hz. Stream at 60–72 Hz first, for heat.
- **Screen sleep:** `UIApplication.shared.isIdleTimerDisabled = true`.
- **Heat:** video decode, ARKit and full brightness together heat the phone fast. Cap brightness, keep demo sessions to about 5 minutes, cool down between them.
- **Body tracking depends on this:** webcam full-body tracking ([../../docs/webcam-fbt.md](../../docs/webcam-fbt.md)) hangs the body off the head position, so milestone 2 gates full-body tracking.
