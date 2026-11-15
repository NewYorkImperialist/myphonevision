# Saber playground (our own SteamVR test game)

A glowing blade in each hand and cubes floating around you. A fast swing through a cube slices it; a slow touch only pushes it. Cross the two blades for sparks. Every hit buzzes that controller. You don't need any buttons. It's a quick way to check the headset, both controllers, the haptics and the arm model together, without buying or setting up a game.

Not a copy of any game: original code, shapes drawn from cubes and capsules, no assets.

## Run it in the headset (the Linux laptop)

1. Get the normal setup running first: the phone streaming through ALVR, SteamVR, the bridge, and both controllers on (`phone/README.md`, `bridge/README.md`).
2. Install once, in the same Python environment as the bridge:
   ```
   pip install -r game/requirements.txt
   ```
3. Start it:
   ```
   python game/saber_playground.py
   ```
   The phone shows the game. A window on the laptop mirrors the left eye, so the audience can watch.

**Keys on the laptop:** `T` turns on cubes thrown at you, `R` resets, `C` changes the blade colors, `Esc` quits.

**If the blades don't line up with your hands,** for example pointing at the floor when the controller points forward, restart with `--blade-pitch 30` (tilts the blades up 30°; negative tilts down). `--blade-length 0.8` makes them shorter.

**If a hand points the wrong way,** hold the thumbstick in for 1 s to recenter it (the bridge does this, not the game).

## Run it without a headset

```
python game/saber_playground.py --desktop             # the mouse swings the right blade
python game/saber_playground.py --desktop --autoplay  # both blades swing by themselves
```

## Status

- Desktop mode tested on macOS (OpenGL 4.1): rendering, slicing, sparks, blade clash, score.
- **Not yet run in SteamVR.** Things to check the first time: the frames reach the phone, the blades follow the controllers, and the buzz works. The buzz uses SteamVR's old haptic call (`TriggerHapticPulse`); the firmware stretches each pulse to 40 ms.
