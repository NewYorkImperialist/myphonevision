# ALVR-over-USB fallback when USB tethering doesn't come up.
# Forwards ALVR's ports to the phone, as PhoneVR's README documents.
# Needs adb (Android platform-tools) on PATH and USB debugging on the Pixel.
$ErrorActionPreference = "Stop"
adb devices
adb forward tcp:9943 tcp:9943
adb forward tcp:9944 tcp:9944
adb forward --list
