#!/usr/bin/env bash
# Patch ALVR's Linux server driver so every frame is tagged with the newest head pose.
#
# On Linux, ALVR's Vulkan layer can't find the pose SteamVR rendered with (SteamVR 2.18's
# vrcompositor is stripped), so PoseHistory::GetBestPoseMatch compares against an all-zero
# pose: every sample ties, the tag is an arbitrary sample up to 3 s old, and the phone
# freezes whenever it passes ~2.2 s. This swaps one cmova for a mov so the loop always
# keeps the last (newest) sample.
#
#   tools/linux/alvr-pose-patch.sh ~/Apps/alvr-v21.0.0-dev14/alvr_streamer_linux
#
# Only for ALVR v21.0.0-dev14 nightly 2026.11.10; the bytes are checked first. The original
# is kept as driver_alvr_server.so.orig. Restart SteamVR afterwards.
set -euo pipefail
root=${1:?usage: $0 <alvr_streamer_linux folder>}
so=$root/lib64/alvr/bin/linux64/driver_alvr_server.so
[[ -f $so ]] || { echo "not found: $so" >&2; exit 1; }
python3 - "$so" <<'EOF'
import os, shutil, sys
so = sys.argv[1]
off = 0xbf99fb                      # vaddr 0xbfa9fb in GetBestPoseMatch
orig, new = bytes.fromhex("480f47c8"), bytes.fromhex("4889c190")  # cmova rax,rcx -> mov rax,rcx; nop
b = bytearray(open(so, "rb").read())
cur = bytes(b[off:off + 4])
if cur == new:
    print("already patched")
    sys.exit(0)
if cur != orig:
    sys.exit(f"unexpected bytes {cur.hex()} at {off:#x}: different ALVR build, not patching")
if not os.path.exists(so + ".orig"):
    shutil.copy2(so, so + ".orig")
b[off:off + 4] = new
open(so + ".new", "wb").write(b)
os.chmod(so + ".new", 0o755)
os.replace(so + ".new", so)        # new inode, so a running vrserver keeps the old mapping
print("patched; restart SteamVR")
EOF
