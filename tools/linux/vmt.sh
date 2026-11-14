#!/usr/bin/env bash
# Build VMT (Virtual Motion Tracker) v0.15 as a Linux SteamVR driver and register it.
# VMT only ships for Windows; its driver needs just these source fixes to build with g++.
# The bridge talks to it unchanged (OSC on 39570, replies on 39571).
set -euo pipefail
VMT_COMMIT=336155b93e2049195b2bc707d959c8207b3da1ef   # VMT v0.15
cd "$(dirname "$0")/../.."
B=$PWD/build/vmt-linux
STEAMVR=${STEAMVR:-$HOME/.local/share/Steam/steamapps/common/SteamVR}

mkdir -p "$B"
[ -f "$B/vmt-$VMT_COMMIT.tar.gz" ] ||
    curl -fsSL "https://codeload.github.com/gpsnmeajp/VirtualMotionTracker/tar.gz/$VMT_COMMIT" -o "$B/vmt-$VMT_COMMIT.tar.gz"
rm -rf "$B/src" && mkdir "$B/src"
tar -xzf "$B/vmt-$VMT_COMMIT.tar.gz" -C "$B/src" --strip-components 1

cd "$B/src/vmt_driver"
sed -i 's|#include <windows.h>||' framework.h DirectOSC.h
sed -i 's|__declspec( dllexport )|__attribute__((visibility("default")))|' dllmain.h
sed -i '/^\/\/DLLの基本処理/,/^}/d' dllmain.cpp                      # DllMain
sed -i 's/\* VMTDriver::Get/* Get/' dllmain.cpp                       # MSVC-only qualification
sed -i 's/static void OSCReceiver::/static void /' CommunicationManager.h
sed -i 's/, __VA_ARGS__)/, ##__VA_ARGS__)/' Log.h                     # Log macros with no varargs
sed -i '1i #include <cstdarg>' Log.cpp
sed -i '/::CreateMutexA(nullptr, FALSE, "VMT_Mutex");/d' ServerTrackedDeviceProvider.cpp  # only tells the Windows installer it's running
sed -i 's/\bif (isnan(/if (std::isnan(/' TrackedDeviceServerDriver.cpp
sed -i 's|"\\\\setting.json"|"/setting.json"|' Config.cpp

O=../oscpack_1_1_0
mkdir -p ../build/vmt/bin/linux64
g++ -std=c++17 -shared -fPIC -O2 -w -I. -I../eigen-3.3.7 -I../openvr-1.23.7/headers -I.. -I$O \
    *.cpp $O/osc/OscOutboundPacketStream.cpp $O/osc/OscReceivedElements.cpp $O/osc/OscTypes.cpp \
    $O/ip/IpEndpointName.cpp $O/ip/posix/*.cpp \
    -o ../build/vmt/bin/linux64/driver_vmt.so
nm -D --defined-only ../build/vmt/bin/linux64/driver_vmt.so | grep HmdDriverFactory >/dev/null  # not -q: an early exit fails pipefail

# Install outside src/ so a failed rebuild leaves the last working driver registered.
rm -rf "$B/vmt" && cp -r ../build/vmt "$B/vmt"
# VMT rejects every pose until a room matrix is set (VMT Manager does it on Windows).
# The bridge's raw poses ignore its value, so identity is enough.
echo '{"RoomMatrix":[1,0,0,0, 0,1,0,0, 0,0,1,0]}' > "$B/vmt/setting.json"
"$STEAMVR/bin/vrpathreg.sh" adddriver "$B/vmt"
echo "VMT driver registered: $B/vmt (restart SteamVR to load it)"
