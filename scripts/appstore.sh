#!/usr/bin/env bash
# Archives Tweaksec for the Mac App Store and exports a signed .pkg into dist/appstore/.
# Optional: TEAM_ID (defaults to BLUEKEI, VUTD52J473), BUILD_NUMBER (defaults to a timestamp),
# UPLOAD=1 to upload to App Store Connect instead of exporting (needs the account signed in to Xcode).
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID="${TEAM_ID:-VUTD52J473}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
ARCHIVE=build/Tweaksec.xcarchive
OPTIONS=build/ExportOptions.plist

xcodegen generate --quiet
xcodebuild -project Tweaksec.xcodeproj -scheme Tweaksec -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" archive -quiet

mkdir -p build
cp scripts/ExportOptions.plist "$OPTIONS"
/usr/libexec/PlistBuddy -c "Add :teamID string $TEAM_ID" "$OPTIONS"
if [[ "${UPLOAD:-0}" == 1 ]]; then
  /usr/libexec/PlistBuddy -c "Set :destination upload" "$OPTIONS"
fi

rm -rf dist/appstore
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTIONS" \
  -exportPath dist/appstore -allowProvisioningUpdates -quiet
echo "Build $BUILD_NUMBER: $([[ "${UPLOAD:-0}" == 1 ]] && echo 'uploaded to App Store Connect' || echo 'exported to dist/appstore/')"
