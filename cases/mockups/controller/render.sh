#!/usr/bin/env bash
# Render every mockup view to img/ and export the printable parts to stl/ (for print-time estimates).
#   OPENSCAD=/path/to/openscad ./render.sh [a|b|c ...]
# Needs a 2026 snapshot (Manifold backend keeps the colors with --render).
set -euo pipefail
cd "$(dirname "$0")"
OPENSCAD=${OPENSCAD:-openscad}
export QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-offscreen}
mkdir -p img stl
png() {  # file, view name, camera rotation, extra -D ...
  local f=$1 name=$2 rot=$3; shift 3
  "$OPENSCAD" -q --backend=manifold --render --imgsize=1400,1050 --projection=p --colorscheme=Tomorrow \
    --camera=0,0,0,$rot,0 --viewall --autocenter "$@" -o "img/${f%.scad}-$name.png" "$f"
}
stl() { "$OPENSCAD" -q --backend=manifold -D "part=\"$2\"" -o "stl/${1%.scad}-$2.stl" "$1"; }
for c in ${@:-a b c d}; do
  case $c in
    a) f=a_paddle.scad; parts="top bottom"; cutcam=72,0,62 ;;
    b) f=b_standup.scad; parts="head head_base spine pod"; cutcam=72,0,62 ;;
    c) f=c_pistol.scad; parts="half_l half_r guard"; cutcam=78,0,12 ;;
    d) f=d_ergo.scad; parts="half_l half_r cradle cover imu_clamp fit_test fit_esp fit_cradle fit_cover"; cutcam=80,0,10
       png $f fit_test 45,0,25 -D 'part="fit_test"'; png $f fit_test_top 0,0,0 -D 'part="fit_test"'
       png $f side 88,0,0; png $f hero 68,0,28; png $f nose 75,0,90
       png $f inside_l 32,0,15 -D 'part="half_l"'; png $f inside_r 32,0,15 -D 'part="half_r"'
       png $f cradle 45,0,25 -D 'part="cradle"' ;;
    *) echo "unknown concept: $c" >&2; exit 1 ;;
  esac
  png $f front 60,0,35
  png $f back 62,0,215
  png $f under 118,0,30
  png $f cutaway $cutcam -D cut=true
  png $f print 50,0,30 -D 'part="print"'
  for p in $parts; do stl $f $p; done
done
