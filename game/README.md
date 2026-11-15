# Saber playground (our own SteamVR test game)

A glowing blade in each hand and cubes floating around you. A fast swing through a cube slices it; a slow touch only pushes it. Cross the two blades for sparks. You don't need any buttons. It's a quick way to check the headset, both controllers and the arm model together, without buying or setting up a game.

It runs on the laptop as a normal SteamVR app, so ALVR streams it to the iPhone app like any other SteamVR game; nothing changes on the phone. The blades follow the two controllers that the bridge feeds to SteamVR through VMT.

Not a copy of any game: original code, shapes drawn from cubes and capsules, no assets.

## Run it in the headset (the Linux laptop)

1. Get the normal setup running: phone on the cable with Personal Hotspot on, then SteamVR started from the ALVR dashboard ([phone/README.md](../phone/README.md)). Plug in the hub and turn on both controllers.
2. Install once, in the same Python environment as the bridge:
   ```
   pip install -e bridge && pip install -r game/requirements.txt
   ```
3. Start the bridge and the game together:
   ```
   game/play.sh
   ```
   It checks that SteamVR is running, starts the bridge (or uses one that's already running), shows each controller's packet rate, then starts the game. The phone shows the game. A window on the laptop mirrors the left eye, so the audience can watch. Closing the game stops the bridge it started. If the bridge is in a virtualenv, run `PYTHON=path/to/venv/bin/python game/play.sh`.

   To run them by hand instead: `cd bridge && python -m myphonevision_bridge --debug` in one terminal, `python game/saber_playground.py` in another.

**Keys on the laptop:** `T` turns on cubes thrown at you, `R` resets, `C` changes the blade colors, `Esc` quits. Extra arguments go to the game, e.g. `game/play.sh --throw`.

**If the blades don't line up with your hands,** for example pointing at the floor when the controller points forward, restart with `game/play.sh --blade-pitch 30` (tilts the blades up 30°; negative tilts down). `--blade-length 0.8` makes them shorter.

**If a hand points the wrong way,** hold that thumbstick in for 1 s to recenter it (the bridge does this, not the game).

**If a blade is missing,** that controller isn't tracked: the game prints `hands L-` or `hands -R` every 5 s. Check that it's on and that the bridge log shows packets for it.

## Run it without a headset

```
python game/saber_playground.py --desktop             # the blade tip follows the mouse; hold the left button for the left blade
python game/saber_playground.py --desktop --autoplay  # both blades swing by themselves
```

## Status

- Desktop mode tested on macOS (OpenGL 4.1): rendering, slicing, sparks, blade clash, score.
- **Not yet run in SteamVR.** The first time, check that the frames reach the phone and the blades follow the controllers. The game picks the left and right hand controllers SteamVR reports, preferring VMT's.
- The as-built controllers have no vibration motor, so hits don't buzz. The game still sends SteamVR's haptic pulse; nothing happens with it.
