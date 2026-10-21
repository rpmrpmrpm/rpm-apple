#!/bin/sh
# Xcode Cloud runs this after it clones the repo, before it builds the Apple TV app. The build needs
# the official API key, which is not in this public repo. When it is missing, the build stops here.
# The TV app does not use the Font Awesome Pro files, so this script does not copy them.
set -eu

repo="$CI_PRIMARY_REPOSITORY_PATH"

# The key is the workflow's secret environment variable RPM_APP_KEY. Signing.xcconfig sets
# RPM_APP_KEY to empty and then includes Local.xcconfig, so the key is written there. The
# environment variable alone does not replace a value that an xcconfig sets.
if [ -z "${RPM_APP_KEY:-}" ]; then
    echo "error: RPM_APP_KEY is not set in the Xcode Cloud workflow" >&2
    exit 1
fi
printf 'RPM_APP_KEY = %s\n' "$RPM_APP_KEY" > "$repo/RPM.tvOS/Local.xcconfig"
