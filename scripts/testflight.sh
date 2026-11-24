#!/usr/bin/env bash
# Archive Siren, upload it to App Store Connect and hand it to the internal
# TestFlight group. Signing is automatic through the Apple account signed in to
# Xcode: with the API key flags, Xcode gets a 401 when it registers Siren's IDs
# (2026-11-24). The key in .asc.local is used for the App Store Connect API
# calls in scripts/asc.mjs. The Release build number is a timestamp set by the
# app target's "Set Build Number" phase.
#
# Usage: scripts/testflight.sh [what-to-test.txt]

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

[[ -f .asc.local ]] || { echo "Missing .asc.local (App Store Connect API key flags)." >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Commit first: the build should match a commit." >&2; exit 1; }
node scripts/asc.mjs check

ARCHIVE=build/Siren.xcarchive
LOG=build/testflight.log
mkdir -p build
: > "$LOG"

echo "Archiving..."
xcodebuild -project Siren/Siren.xcodeproj -scheme Siren -configuration Release \
  -destination generic/platform=iOS -archivePath "$ARCHIVE" -allowProvisioningUpdates archive >>"$LOG" 2>&1 \
  || { grep -E "error" "$LOG" | sort -u | tail -20; echo "Archive failed; see $LOG." >&2; exit 1; }

BUILD=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" "$ARCHIVE/Info.plist")
echo "Uploading build $BUILD..."
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath build/export -allowProvisioningUpdates >>"$LOG" 2>&1 \
  || { grep -E "error" "$LOG" | sort -u | tail -20; echo "Upload failed; see $LOG." >&2; exit 1; }

NOTES=${1:-build/what-to-test.txt}
if [[ -z "${1:-}" ]]; then git log -10 --format='- %s' > "$NOTES"; fi
node scripts/asc.mjs testflight "$BUILD" "$NOTES"
git tag "build/$BUILD"
echo "Build $BUILD is on TestFlight (tagged build/$BUILD)."
