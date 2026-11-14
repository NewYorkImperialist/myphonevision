#!/bin/bash
# Fetch ALVR at the commit this client was built against, into ./ALVR (git-ignored).
# The laptop's ALVR server must be the same version: v21.0.0-dev14. This is the exact
# source of nightly v21.0.0-dev14+nightly.2026.11.10, the server on the laptop (issue #3).
# Other dev14 nightlies pass ALVR's version check but can differ in the settings the
# server sends, so match the laptop's build.
set -e
cd "$(dirname "$0")"
ALVR_COMMIT=62e0fc3d8d3d990d2dd6d0db9e2f5ec3189b8227     # ALVR v21.0.0-dev14 (nightlies 2026.11.09 and 11.10)
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
