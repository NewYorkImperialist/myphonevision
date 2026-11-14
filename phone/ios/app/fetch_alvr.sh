#!/bin/bash
# Fetch ALVR at the commit this client was built against, into ./ALVR (git-ignored).
# The laptop's ALVR server must be the same version: v21.0.0-dev14, the nightly the
# Pixel's PhoneVR app (righthandpaw/PhoneVR Release-v1.0.1) is built from, so one
# server works for both phones.
set -e
cd "$(dirname "$0")"
ALVR_COMMIT=9f11839431f95f0df6764790d9a16f8e308a0d79     # ALVR v21.0.0-dev14 (nightlies 2026.09.30 to 10.03)
OPENVR_COMMIT=0924064316de3effbcd1acf1e309182a2deb1c05   # ALVR's openvr submodule at that commit

if [ "$(cat ALVR/.commit 2>/dev/null)" = "$ALVR_COMMIT" ]; then
    echo "ALVR already at $ALVR_COMMIT"
    exit 0
fi
rm -rf ALVR
mkdir ALVR
curl -fsSL "https://codeload.github.com/alvr-org/ALVR/tar.gz/$ALVR_COMMIT" | tar -xz -C ALVR --strip-components 1
# GitHub tarballs leave out submodules; the build needs only openvr's headers.
mkdir -p ALVR/openvr
curl -fsSL "https://codeload.github.com/ValveSoftware/openvr/tar.gz/$OPENVR_COMMIT" \
    | tar -xz -C ALVR/openvr --strip-components 1 "openvr-$OPENVR_COMMIT/headers"
echo "$ALVR_COMMIT" > ALVR/.commit
echo "ALVR at $ALVR_COMMIT (v21.0.0-dev14)"
