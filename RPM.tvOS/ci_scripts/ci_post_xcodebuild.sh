#!/bin/sh
# Xcode Cloud runs this after xcodebuild. After an archive it checks that the app's Info.plist
# holds the workflow's key. A failed check fails the build.
set -eu

# Only an archive has an app to check.
[ -n "${CI_ARCHIVE_PATH:-}" ] || exit 0

app="$CI_ARCHIVE_PATH/Products/Applications/rpm.app"

key="$(/usr/libexec/PlistBuddy -c 'Print :RPMAppKey' "$app/Info.plist" 2>/dev/null)" || key=""
if [ -z "$key" ] || [ "$key" != "${RPM_APP_KEY:-}" ]; then
    echo "error: RPMAppKey in the app's Info.plist is not the workflow's RPM_APP_KEY" >&2
    exit 1
fi

echo "checked: API key is in the app"
