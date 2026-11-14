#!/usr/bin/env bash
# Upload print files to the UMass Physical Computing Makerspace portal
# (https://make.cs.umass.edu/upload/) and print the pickup code. Enter the
# code at the PCM kiosk, then slice and print there. Files expire after 48 h.
#
#   tools/upload-print.sh build/stl/fit_tests-phone.stl build/stl/fit_tests-joystick.stl
#
# Every code is also appended to build/print-uploads.log, so it isn't lost.
# Portal limits: 10 files, 95 MB total; .stl .obj .step .stp .3mf (no G-code).
set -euo pipefail
cd "$(dirname "$0")/.."

(( $# > 0 )) || { echo "usage: $0 FILE..." >&2; exit 2; }
(( $# <= 10 )) || { echo "the portal takes at most 10 files per upload" >&2; exit 2; }

total=0
args=()
for f in "$@"; do
  [[ -f $f ]] || { echo "not a file: $f" >&2; exit 2; }
  # tr and wc instead of ${f,,} and stat -c: macOS ships bash 3.2 and BSD stat.
  case "$(printf '%s' "$f" | tr '[:upper:]' '[:lower:]')" in
    *.stl|*.obj|*.step|*.stp|*.3mf) ;;
    *) echo "the portal won't take $f (3D: .stl .obj .step .stp .3mf)" >&2; exit 2 ;;
  esac
  total=$(( total + $(wc -c < "$f") ))
  args+=(-F "files[]=@$f")
done
(( total <= 95 * 1024 * 1024 )) || { echo "over the portal's 95 MB limit" >&2; exit 2; }

resp=$(curl -sS -w '\n%{http_code}' -H 'X-Requested-With: FilePortal' "${args[@]}" \
  https://make.cs.umass.edu/api/upload.php)
status=${resp##*$'\n'}
body=${resp%$'\n'*}

mkdir -p build
printf '%s %s\n' "$(date '+%F %R')" "$body" >> build/print-uploads.raw  # raw replies, in case parsing fails
STATUS=$status FILES="$*" python3 -c '
import json, os, sys, datetime
status, files = int(os.environ["STATUS"]), os.environ["FILES"]
try:
    r = json.loads(sys.stdin.read())
except ValueError:
    sys.exit("upload failed: unexpected response (HTTP %d)" % status)
for f in r.get("results", []):
    ok = f.get("status") == "success"
    print(("ok   " if ok else "FAIL ") + f.get("originalName", "?") + ("" if ok else ": " + f.get("reason", "upload failed")))
code, until = r.get("code"), r.get("expiresAt", "?")
if not 200 <= status < 300 or not code:
    sys.exit("upload failed: %s" % r.get("error", "no pickup code returned"))
print("\nPickup code: %s   (until %s)" % (code, until))
with open("build/print-uploads.log", "a") as log:
    log.write("%s  %s  until %s  %s\n" % (datetime.datetime.now().strftime("%Y-%m-%d %H:%M"), code, until, files))
' <<<"$body"
