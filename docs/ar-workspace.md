# AR workspace: research (stretch goal)

Research notes from 2026-11-14. Nothing here is built. It's a stretch goal for after the hour-20 gate: it needs the iPhone app's video, 6DoF head pose and reprojection working first.

**The idea:** an "AR mode" in the iPhone app that shows the phone's rear camera behind the SteamVR stream. With [Desktop+](https://github.com/elvissteinjr/DesktopPlus) running on the laptop, your PC's windows float in your real room: an AR workspace, like Immersed or Apple's Mac Virtual Display, built from a phone. It keeps the project's main principle: no game-specific code, everything still goes through SteamVR.

**Why bother:** AR has won at HackUMass before. AR Cube Cannon won Best Hardware (XIII), RealityPaint won Third Prize (XII), and VR Breadboard won Best AR/VR (XII). "It does VR games *and* AR" is a strong demo moment.

## How the pieces fit

```
laptop: Desktop+ (windows as SteamVR overlays) + an empty scene in a key color
        └─ ALVR streams the composited frame to the phone (unchanged)
iPhone: ARKit already captures camera frames for tracking
        └─ AR mode: per eye, draw the camera image, then the ALVR frame on top,
           with key-colored pixels made transparent; then the lens pass
```

| Piece | Status | Notes |
| --- | --- | --- |
| Desktop+ | Exists: free on Steam, GPL-3.0, very positive reviews | Mirrors whole desktops or single windows as SteamVR overlays; adjustable size, position, curvature, opacity; low latency. Window capture needs Windows 10 2004+ for full support. Some users report windows losing their source |
| ALVR passthrough | **Not usable.** v20.8.0 (the iPhone client's version) has no passthrough setting. v20.12.0 added `passthrough: AugmentedReality / Blend` (alpha-based), but the iPhone client is pinned to v20.8.0 | So the compositing has to be done in the iPhone app |
| Camera frames | Free: ARKit already captures them for tracking (`ARFrame.capturedImage`, YCbCr) | No extra camera cost; the same Y/CbCr → RGB conversion as `displayTexture` |
| Key color behind the overlays | **To build and verify** | SteamVR's empty environment isn't a solid color. Options: a tiny OpenVR scene app that submits a solid key color (e.g. magenta) every frame (pyopenvr, ~100 lines), or key on near-black (simpler, but it eats dark-mode window content) |

## Making the camera line up with the lenses

The lens pass already computes, per screen pixel, the direction the eye looks (`screenToEye` → `tanAngle`). For AR mode, use that same direction to sample the camera image:

1. Rotate the eye's ray into camera axes (the fixed phone-to-head transform `WorldTracker` already has; `eyesFromCamera` is the offset).
2. Project it with ARKit's camera intrinsics (`frame.camera.intrinsics`, scaled to `capturedImage`'s size) to get a pixel in the camera image.
3. Ignore parallax between eye and camera (about 6 cm) by assuming everything is ~1.5 m away; fine for a workspace.

That gives correct scale and alignment for both eyes, distorted by the same lens model, with no separate calibration.

## Limits to expect

- **Mono passthrough:** one rear camera, so both eyes see the same image and there's no depth. Prior phone-headset AR projects report it gets uncomfortable fast. Keep AR sessions short, and favor a workspace (flat windows) over close-up interaction.
- **Stream lag vs. camera:** the camera image matches the head instantly (ARKit gives frame and pose together), but the streamed windows lag behind. **Without reprojection the windows will swim against the room**, so milestone 4 (reprojection) is a prerequisite.
- **Video compression smears key-color edges:** use a tolerance on the key and a soft edge.
- **Heat:** small extra cost (ARKit already runs the camera), but full brightness plus video decode is already near the phone's thermal limit.

## Steps, smallest first

1. **Camera background in test mode** (no server): draw the camera image through the lens pass behind the test room. Proves alignment. About 2–3 h.
2. **AR mode with the stream:** composite camera + ALVR frame with a key. About 2–3 h.
3. **Key-color scene on the laptop** (or near-black keying to start). About 1 h.
4. **Desktop+** set up with 2–3 windows placed around the user. About 30 min.

## Prior art and sources

- [Desktop+](https://github.com/elvissteinjr/DesktopPlus) ([Steam](https://store.steampowered.com/app/1494460)): desktop and window overlays for SteamVR.
- ALVR passthrough settings: `alvr/session/src/settings.rs` at [v20.12.0](https://github.com/alvr-org/ALVR/blob/v20.12.0/alvr/session/src/settings.rs) (present) vs. [v20.8.0](https://github.com/alvr-org/ALVR/blob/v20.8.0/alvr/session/src/settings.rs) (absent).
- [iOS ARKit headset view](https://github.com/hanleyweng/iOS-Stereoscopic-ARKit-Template): stereo ARKit passthrough for Cardboard-style viewers using `capturedImage`.
- [Nexus Studios ARKit Cardboard experiment](https://nexusstudios.com/?p=5271) and [Road to VR on ARKit inside-out tracking](https://roadtovr.com/using-apples-arkit-company-built-inside-tracking-vr-headset/): passthrough AR in a Cardboard headset; notes on mono camera limits.
- [openxr-steamvr-passthrough](https://gh.r-mj.com/JFrit/openxr-steamvr-passthrough): blend modes (alpha, additive, masked key color) for camera passthrough in SteamVR, for headsets with cameras.
- Commercial references: [Immersed on Vision Pro](https://www.uploadvr.com/immersed-for-apple-vision-pro-virtual-extra-mac-monitors/) (up to 5 virtual monitors), Xreal glasses (one large virtual screen).
