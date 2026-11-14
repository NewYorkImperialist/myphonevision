#!/usr/bin/env bash
# Clone PhoneVR into phone/PhoneVR (gitignored) with two branches:
#   stock   the upstream default branch, for first light against ALVR v20.8.0
#   pr-458  the open v21 / ARCore 6DoF pull request; our fork starts here
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d PhoneVR ]; then
  git clone --recurse-submodules https://github.com/PhoneVR-Developers/PhoneVR.git
fi
cd PhoneVR
git fetch origin
default_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD | sed 's|^origin/||')
git branch -f stock "origin/$default_branch"
git fetch origin pull/458/head:pr-458 --force
git checkout pr-458
git submodule update --init --recursive

echo
echo "PhoneVR is at phone/PhoneVR on branch pr-458 (stock is branch 'stock')."
echo "Head tracking lives in code/mobile/android/PhoneVR/app/src/main/cpp/alvr_main.cpp."
echo "Build with Android Studio, or: cd code/mobile/android/PhoneVR && ./gradlew assembleDebug"
