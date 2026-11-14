#!/usr/bin/env bash
# Export every printable part to build/stl/. Needs OpenSCAD (2026 snapshot;
# on macOS: brew install --cask openscad@snapshot).
#
#   tools/export-stl.sh                              defaults
#   tools/export-stl.sh -D lens_d=45 -D lens_thk=10 -D lens_f=62
#
# Extra arguments go to every openscad call, so pass your measured values.
# A -D that a file doesn't use is ignored there.
set -euo pipefail
cd "$(dirname "$0")/.."
out=build/stl
mkdir -p "$out"

export_parts() {
  local file=$1; shift
  local parts=("$@")
  for p in "${parts[@]}"; do
    printf '%-28s' "$(basename "$file" .scad)/$p"
    openscad --backend=manifold -q -D "part=\"$p\"" ${EXTRA[@]+"${EXTRA[@]}"} -o "$out/$(basename "$file" .scad)-$p.stl" "$file"
    echo ok
  done
}

EXTRA=("$@")
export_parts headset/headset.scad front tray door shim spacer lens_ring jig jig_ring
export_parts cases/trackers.scad leg_case leg_lid waist_case waist_lid pod_case pod_lid
export_parts cases/controller.scad head head_base handle
export_parts cases/fit_tests.scad buttons lens_seats lens_rings phone frames joystick straps
echo "STL files are in $out/"
