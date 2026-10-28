#!/bin/bash
# A Developer ID–signed, notarized DMG of PureClean for your own Macs (testing outside the App
# Store). It is the same sandboxed app; copies that don't come from the App Store never ask for the
# subscription. Not a distribution channel — PureClean is sold on the Mac App Store.
#
# Needs a "Developer ID Application" certificate in the login keychain (Xcode → Settings →
# Accounts → Manage Certificates → + → Developer ID Application) and an App Store Connect API key
# for notarization:
#
#   TEAM_ID=ABCDE12345 ASC_KEY_ID=… ASC_ISSUER_ID=… Scripts/build_personal_dmg.sh
#     [ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_<id>.p8]   (default location)
#     [ARCHIVE=dist/PureClean-AppStore.xcarchive]   reuse an archive instead of building a new one
#
# → dist/PureClean-<version>-personal.dmg (app and DMG both notarized and stapled)
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TEAM_ID:?Set TEAM_ID to your Apple Developer team ID}"
: "${ASC_KEY_ID:?Set ASC_KEY_ID (App Store Connect API key, used to notarize)}"
: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID}"
KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8}"
[[ -f "$KEY_PATH" ]] || { echo "error: no API key at $KEY_PATH" >&2; exit 1; }
IDENTITY=$(security find-identity -v -p codesigning | sed -nE "s/.*\"(Developer ID Application: .*\($TEAM_ID\))\"/\1/p" | head -1)
[[ -n "$IDENTITY" ]] || { echo "error: no Developer ID Application certificate for team $TEAM_ID" >&2; exit 1; }
NOTARY=(--key "$KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
VERSION=$(grep -m1 'MARKETING_VERSION = ' PureClean.xcodeproj/project.pbxproj | sed -E 's/.*= ([^;]+);/\1/')
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

ARCHIVE="${ARCHIVE:-}"
if [[ -z "$ARCHIVE" ]]; then
  ARCHIVE="$WORK/PureClean.xcarchive"
  echo "==> Archive $VERSION"
  xcodebuild -project PureClean.xcodeproj -scheme PureClean -configuration Release -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" DEVELOPMENT_TEAM="$TEAM_ID" -allowProvisioningUpdates archive -quiet
fi

echo "==> Export (Developer ID)"
cat > "$WORK/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM_ID</string>
</dict></plist>
EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$WORK/ExportOptions.plist" \
  -exportPath "$WORK/export" -allowProvisioningUpdates -quiet
APP="$WORK/export/PureClean.app"
codesign -dvv "$APP" 2>&1 | grep -q "Authority=Developer ID Application" || { echo "error: not Developer ID signed" >&2; exit 1; }

echo "==> Notarize the app"
ditto -c -k --keepParent "$APP" "$WORK/PureClean.zip"
xcrun notarytool submit "$WORK/PureClean.zip" "${NOTARY[@]}" --wait
xcrun stapler staple "$APP"

echo "==> DMG"
mkdir -p "$WORK/dmg" dist
ditto "$APP" "$WORK/dmg/PureClean.app"
ln -s /Applications "$WORK/dmg/Applications"
DMG="dist/PureClean-$VERSION-personal.dmg"
rm -f "$DMG"
hdiutil create -volname "PureClean $VERSION" -srcfolder "$WORK/dmg" -fs HFS+ -format UDZO -ov "$DMG" -quiet
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
xcrun notarytool submit "$DMG" "${NOTARY[@]}" --wait
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG"
echo "==> Done: $DMG"
