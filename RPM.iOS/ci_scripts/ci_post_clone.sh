#!/bin/sh
# Xcode Cloud runs this after it clones the repo, before it builds the iPhone app. The build needs
# two things that are not in this public repo: the official API key and the Font Awesome Pro files.
# When one of them is missing, the build stops here.
set -eu

repo="$CI_PRIMARY_REPOSITORY_PATH"

# The key is the workflow's secret environment variable RPM_APP_KEY. Signing.xcconfig sets
# RPM_APP_KEY to empty and then includes Local.xcconfig, so the key is written there. The
# environment variable alone does not replace a value that an xcconfig sets.
if [ -z "${RPM_APP_KEY:-}" ]; then
    echo "error: RPM_APP_KEY is not set in the Xcode Cloud workflow" >&2
    exit 1
fi
printf 'RPM_APP_KEY = %s\n' "$RPM_APP_KEY" > "$repo/RPM.iOS/Local.xcconfig"

# The fonts are in the private rpm-fonts-pro repo. The workflow has access to it as an additional
# repository.
fonts="$(mktemp -d)/rpm-fonts-pro"
git clone --quiet --depth 1 https://github.com/rpmrpmrpm/rpm-fonts-pro.git "$fonts"
"$repo/scripts/copy-icon-fonts.sh" "$fonts"
