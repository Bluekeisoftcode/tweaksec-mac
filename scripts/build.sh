#!/usr/bin/env bash
# Builds a Release Tweaksec.app into dist/ and zips it.
# Set SIGN_IDENTITY="Developer ID Application: ..." to sign for distribution (ad-hoc otherwise).
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_IDENTITY="${SIGN_IDENTITY:--}"

xcodegen generate --quiet
xcodebuild -project Tweaksec.xcodeproj -scheme Tweaksec -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build CODE_SIGN_IDENTITY="$SIGN_IDENTITY" build -quiet

rm -rf dist && mkdir -p dist
cp -R build/Build/Products/Release/Tweaksec.app dist/
ditto -c -k --keepParent dist/Tweaksec.app dist/Tweaksec.zip
echo "Built dist/Tweaksec.app and dist/Tweaksec.zip"
