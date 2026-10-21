#!/bin/sh
# Copies the Font Awesome 5 Pro files into RPMUI's resources from a checkout of the private
# rpm-fonts-pro repo next to this repo (or the folder given as the first argument). The licence does
# not allow publishing them, so they are not in this repo. Without them the apps build and run, and
# the icons that use them are blank. The script fails when a file is not found, so a build that runs
# it (RPM.iOS/ci_scripts) cannot ship blank icons.
set -eu

here="$(cd "$(dirname "$0")/.." && pwd)"
from="${1:-$here/../rpm-fonts-pro}"
to="$here/RPM.iOS/Modules/RPMUI/Sources/RPMUI/Resources"

missing=0
for font in fa-solid-900.ttf fa-regular-400.ttf; do
    if [ -f "$from/$font" ]; then
        cp "$from/$font" "$to/$font"
        echo "copied $font"
    else
        echo "not found: $from/$font" >&2
        missing=1
    fi
done
exit "$missing"
