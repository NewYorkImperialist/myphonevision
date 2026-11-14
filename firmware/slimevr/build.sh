#!/usr/bin/env bash
# Build (and optionally flash) SlimeVR tracker firmware for our boards:
# ESP32-DevKitC + two MPU-6050s (0x68 primary, 0x69 extension) on SDA 21 / SCL 22.
#
#   ./build.sh                     build only
#   ./build.sh upload              build and flash the board on USB
#   WIFI_SSID=x WIFI_PASS=y ./build.sh upload   bake in the PC hotspot credentials
#
# The sensor list lives in tracker.json and replaces SlimeVR's BOARD_WROOM32
# defaults (which assume BNO085s) through SLIMEVR_OVERRIDE_DEFAULTS.
set -euo pipefail
cd "$(dirname "$0")"

SLIME_TAG=v0.7.4
SRC=SlimeVR-Tracker-ESP

if [ ! -d "$SRC" ]; then
  git clone --depth 1 --branch "$SLIME_TAG" https://github.com/SlimeVR/SlimeVR-Tracker-ESP.git "$SRC"
fi

export SLIMEVR_OVERRIDE_DEFAULTS="$(python3 -c 'import json,sys; print(json.dumps(json.load(open("tracker.json"))))')"
if [ -n "${WIFI_SSID:-}" ]; then
  export PLATFORMIO_BUILD_FLAGS="-DWIFI_CREDS_SSID='\"${WIFI_SSID}\"' -DWIFI_CREDS_PASSWD='\"${WIFI_PASS:-}\"'"
fi

cd "$SRC"
if [ "${1:-}" = "upload" ]; then
  pio run -e BOARD_WROOM32 -t upload
  echo "Flashed. Open the SlimeVR server; the tracker should appear once it's on the hotspot."
else
  pio run -e BOARD_WROOM32
fi
