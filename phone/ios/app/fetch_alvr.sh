#!/bin/bash
# Fetch ALVR at the commit this client was built against, into ./ALVR (git-ignored).
# The laptop's ALVR server must be the same version: v20.8.0.
set -e
cd "$(dirname "$0")"
ALVR_COMMIT=1d121fa7e0761ef26473c6b3f3fbd9b6051ce033   # ALVR v20.8.0

if [ "$(cat ALVR/.commit 2>/dev/null)" = "$ALVR_COMMIT" ]; then
    echo "ALVR already at $ALVR_COMMIT"
    exit 0
fi
rm -rf ALVR
mkdir ALVR
curl -fsSL "https://codeload.github.com/alvr-org/ALVR/tar.gz/$ALVR_COMMIT" | tar -xz -C ALVR --strip-components 1
echo "$ALVR_COMMIT" > ALVR/.commit
echo "ALVR at $ALVR_COMMIT (v20.8.0)"
