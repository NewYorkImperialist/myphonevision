#!/usr/bin/env bash
# The sword game in the headset with both controllers, in one command (Linux laptop).
#
# Before running it: the phone is on the cable with Personal Hotspot on, SteamVR was
# started from the ALVR dashboard, the hub is plugged in, and both controllers are on.
#
#   game/play.sh                          # starts the bridge (unless one is running), then the game
#   game/play.sh --throw                  # extra arguments go to the game
#   PYTHON=~/venv/bin/python game/play.sh # use the Python environment the bridge is installed in
set -euo pipefail
cd "$(dirname "$0")/.."
PY=${PYTHON:-python3}

if ! pgrep -x vrserver >/dev/null; then
  echo "SteamVR isn't running. Plug in the phone, then start SteamVR from the ALVR dashboard." >&2
  exit 1
fi

if pgrep -f "myphonevision_bridge" >/dev/null; then
  echo "bridge: already running, using it"
else
  log=${TMPDIR:-/tmp}/myphonevision-bridge.log
  (cd bridge && exec "$PY" -u -m myphonevision_bridge --debug) >"$log" 2>&1 &
  bridge=$!
  trap 'kill "$bridge" 2>/dev/null || true' EXIT
  sleep 3
  if ! kill -0 "$bridge" 2>/dev/null; then
    echo "The bridge stopped. Its output:" >&2
    cat "$log" >&2
    exit 1
  fi
  echo "bridge: running, log in $log"
  # Last status line per hand, e.g. "left : 195 Hz ..." or "right: no packets" (turn it on).
  for hand in "left :" "right:"; do
    grep -a "^$hand" "$log" | tail -n 1 || echo "$hand nothing yet (is it on?)"
  done
fi

echo "Starting the game. Hold a thumbstick in for 1 s to recenter that hand. Esc in the mirror window quits."
"$PY" game/saber_playground.py "$@"
