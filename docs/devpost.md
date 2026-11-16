# myphonevision

An iPhone in a laser-cut cardboard box, two Carson magnifiers for lenses, and two homemade ESP32 controllers. SteamVR thinks it's a normal headset with two Index controllers.

## Inspiration

One rule: write drivers and bridges, never game code. If every device shows up in SteamVR as a standard headset or Index controller, games can't tell, and the desktop VR library should just run.

The plan was a Pixel 7 and a Windows laptop. A few hours in, the phone was a friend's iPhone 16 Pro, and the laptop we actually had runs Fedora.

## What it does

The iPhone sits behind two Carson TriView TV-36 magnifiers set to 5.5x and runs our own ALVR client. SteamVR video comes in over a USB cable (the phone's Personal Hotspot) and the ARKit head pose goes back. From a Fedora laptop with an Intel Arc 140V iGPU: 60 fps and about 36 ms total latency.

Each controller is an ESP32 with an IMU, a thumbstick, one A button and a force-sensing resistor in the grip, on 4×AA. They send over ESP-NOW to a hub ESP32 on the laptop, and a Python bridge passes them to the VMT driver as Index controllers. LEFT runs at about 195 Hz, RIGHT 148. The IMUs only know orientation, so an arm model hung off the head places the hands. With one button, the bridge reads a held stick click as the rest: 1 s recenters, 3 s opens the SteamVR menu (not yet tried on the real controllers).

## How we built it

The iOS client started as kotleni/iPhoneVR, pinned to ALVR v20.8.0. On the laptop, v20.8.0 died with error 307 on every launch and the v21.0.0-dev14 nightly didn't, so we ported the client to v21's C API and pinned it to that nightly's exact commit (62e0fc3). v21 has no `alvr_poll_nal` and no prediction-offset call, so video goes from a decoder callback straight into VideoToolbox and the app learns its own offset. ARKit tracking, the Metal lens pass and rotation-only reprojection are ours.

Linux needed two SteamVR Vulkan settings, the Steam runtime's OpenSSL 1.0 for vrmonitor, and a byte patch to ALVR's server driver (see below). VMT is Windows-only, so `tools/linux/vmt.sh` patches its source with sed until g++ builds it, then registers it with SteamVR. VMT drops every pose until a room matrix is set. On Windows its manager app sets one. On Linux nothing does, so the script writes an identity matrix.

The controller shell is a pistol grip in OpenSCAD. The first joystick fit print moved the hole from 28 to 25.8 mm. The second showed the 14.5 mm posts sat 1 mm too tall. The shell's own fit test passed.

The headset was going to be printed, with three lenses stacked per eye in sliding focus tubes, but the first tube came out too small for the lenses. On the bench at 5.5x (top and bottom lenses out, middle one left in the case) the screen focused about 30 mm behind the bottom lens, and there wasn't time to reprint, so `gen.py` draws a cardboard viewer around that number, checks its own sizes and writes the template and laser files. v2 doubled the face ring and strap ears.

Four people and four Claude Code sessions shared one repo and talked through GitHub issues. The iPhone thread, #3, has 26 comments.

## Challenges we ran into

The first stream froze and jumped every few seconds. ALVR said the phone was showing 0.1 to 0.3 frames a second, with 1 to 2 s of game latency. Part of that was ours: code inherited from upstream refused any frame stamped more than 600 ms old, and every frame looked old. Removing it (11a826a) got 55 to 60 frames a second shown. The latency number still climbed about 1 ms per ms and reset near 3 s.

We guessed the server was breaking ties between identical head poses and made the phone tag each pose with a tiny unique yaw offset. Nothing changed. 984 samples, median 1.4 s.

The cause was on the laptop. On Linux, ALVR's Vulkan layer finds the pose a frame was rendered with by walking the compositor's call stack for `CRenderThread::Update` by name. SteamVR 2.18.4's vrcompositor is stripped: `readelf` and `nm` showed 434 exported symbols and neither name. Every frame got an all-zero pose, every sample in the 3 s history was equally far from it, and float rounding picked the match. The picture froze whenever that random sample got older than about 2.2 s. `tools/linux/alvr-pose-patch.sh` patches the prebuilt driver to take the newest sample. Median latency went from about 1300 ms to 43.

Venue Wi-Fi didn't help. In one test we logged 113 gaps of over 250 ms with no frame shown, the longest about 15 s. A 25 s capture over USB had 2.

Then reprojection jittered with the phone held still. A 1 kHz capture of SteamVR's head pose showed it changing at 29.9 Hz: 232 of 239 changes exactly 4 samples apart. ARKit was giving us about 30 frames a second, and the app always extrapolated 50 ms past the last one, which turned hand tremor into jumps. ARKit now runs at 60 Hz on its own queue with CoreMotion's gyro filling in at 200 Hz. It's smooth with reprojection on and head prediction off, and that's how we demo.

Two of our three GY-521 IMUs were dead. One lit its LED but never answered on I2C, even after reflowing. RIGHT got a BNO055 and the firmware learned to detect it. We had 3 push buttons for a design that needed 8, hence A only. The vibration motors came out to make room. And with the squeeze wired as grip, nothing could click in the SteamVR menu, so it drives the trigger too.

RIGHT's hand jumped about 52 cm in one frame with zero rotation, three times in 30 s. The data was clean. The arm model pulled the elbow toward the controller's full rotation, and near 180° the shortest path flips sides: 2 × 0.28 m × sin 72° ≈ 53 cm. Now the elbow follows only where the controller points. Worst step in 40 s of waving: 14 cm, during a 20° swing.

## Accomplishments that we're proud of

Desktop SteamVR on a borrowed iPhone, from a Linux laptop with an integrated GPU, at 60 fps. And the stripped-compositor bug: that ALVR file hasn't changed upstream since 2022, and we couldn't find an issue about it.

## What we learned

ALVR reported over a second of game latency. It was the server matching frames to the wrong pose, and we spent a phone build pushing that number down before checking where it came from.

The ruler said 38 mm for the lens ring, so the tube's seat printed at 38.3. Calipers said 38.75, after the tube was already printed.

## What's next

- RIGHT's FSR reads 0. LEFT's tops out at 26%: `TRIGGER_RAW_MAX` (3500) is too high.
- Yaw drift, which a mentor asked about. RIGHT drifted 2.4° in 5 minutes on the desk. Branch `gyro-auto-bias` relearns the gyro bias whenever a controller is set down; it compiles, but only a simulation has run it.
- Vibration motors back in. The bridge forwards VMT's haptics, untested.
- Set the app's screen-to-lens to about 40 mm for 5.5x (it still defaults to 30.5, from the three-lens plan) and tune k1 and k2 in the headset.
- Our saber test game (`game/saber_playground.py`) has only run in desktop mode. Then Fruit Ninja VR and Beat Saber through Proton, none tried yet.
- Real hand position: an iPhone on each controller, or one of the lab's Leap Motions on the headset.
- Body tracking, which we cut.

## Built with

- Swift, SwiftUI, Metal, ARKit, CoreMotion, VideoToolbox
- ALVR v21.0.0-dev14 (Rust client library for iOS, server on Linux), based on kotleni/iPhoneVR
- SteamVR, OpenVR, Virtual Motion Tracker (VMT) v0.15 built for Linux
- ESP32, Arduino, PlatformIO, ESP-NOW, C++
- MPU-6050 (GY-521), Adafruit BNO055, Adafruit 512 thumbstick, force-sensing resistors
- Python: pyserial, python-osc, openvr, pytest, numpy, PyOpenGL, GLFW, shapely
- OpenSCAD, Prusa Core One, Epilog laser cutter
- Fedora Linux, Intel Arc 140V
- Carson TriView TV-36 magnifiers, corrugated cardboard
- GitHub Issues
