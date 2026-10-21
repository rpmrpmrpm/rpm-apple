#!/bin/sh
# Xcode Cloud runs this after xcodebuild. After an archive it checks the app that was built: the
# Font Awesome Pro files are in RPMUI's resource bundle, and Info.plist holds the workflow's key.
# A failed check fails the build.
set -eu

# Only an archive has an app to check.
[ -n "${CI_ARCHIVE_PATH:-}" ] || exit 0

app="$CI_ARCHIVE_PATH/Products/Applications/rpm.app"

for font in fa-solid-900.ttf fa-regular-400.ttf; do
    if [ ! -f "$app/RPMUI_RPMUI.bundle/$font" ]; then
        echo "error: $font is not in the app (RPMUI_RPMUI.bundle)" >&2
        exit 1
    fi
done

key="$(/usr/libexec/PlistBuddy -c 'Print :RPMAppKey' "$app/Info.plist" 2>/dev/null)" || key=""
if [ -z "$key" ] || [ "$key" != "${RPM_APP_KEY:-}" ]; then
    echo "error: RPMAppKey in the app's Info.plist is not the workflow's RPM_APP_KEY" >&2
    exit 1
fi

echo "checked: icon fonts and API key are in the app"
