#!/usr/bin/env bash
set -euo pipefail

# SoloCraft macOS Release & Notarization Script for Copilot Quota
#
# Usage:
#   1. Ensure your "Developer ID Application" certificate is installed in Keychain
#      (Xcode -> Settings -> Accounts -> Manage Certificates -> + -> Developer ID Application)
#   2. Store your notarization credentials once in Keychain:
#      xcrun notarytool store-credentials "solocraft-notary" \
#        --apple-id "YOUR_APPLE_ID_EMAIL" \
#        --team-id "YOUR_TEAM_ID" \
#        --password "YOUR_APP_SPECIFIC_PASSWORD"
#   3. Run:
#      ./scripts/release.sh
#
# Without a Developer ID certificate the script still produces ad-hoc
# artifacts (Gatekeeper requires one-time approval via xattr / Open Anyway).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Copilot Quota"
APP_PATH="$ROOT/build/$APP_NAME.app"
NOTARY_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-solocraft-notary}"

echo "==> 1. Building Release $APP_NAME.app..."
./scripts/build-app.sh
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")"
ZIP_PATH="$ROOT/build/CopilotQuota-${VERSION}.zip"
DMG_PATH="$ROOT/build/CopilotQuota-${VERSION}.dmg"

echo "==> 2. Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
SIGN_INFO="$(codesign -dvv "$APP_PATH" 2>&1)"
echo "$SIGN_INFO" | grep -E "Identifier=|Authority=|TeamIdentifier=" || true

if echo "$SIGN_INFO" | grep -q "Authority=Developer ID Application"; then
  echo "==> 3. Creating zip archive for Apple Notarization..."
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

  if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "==> 4. Submitting to Apple Notary Service (profile: $NOTARY_PROFILE)..."
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

    echo "==> 5. Stapling notarization ticket to $APP_NAME.app..."
    xcrun stapler staple "$APP_PATH"
    spctl --assess --type execute --verbose "$APP_PATH"

    # Re-create zip with the stapled app bundle
    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
  else
    echo "⚠️  Note: Keychain profile '$NOTARY_PROFILE' not found yet. Skipping cloud notarization."
    echo "   To enable automatic notarization, run once:"
    echo "   xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <EMAIL> --team-id <TEAM_ID> --password <APP_SPECIFIC_PASSWORD>"
  fi
else
  echo "⚠️  Built with ad-hoc signature (no Developer ID Application certificate found in Keychain yet)."
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
fi

echo "==> 6. Creating distributable DMG ($DMG_PATH)..."
rm -f "$DMG_PATH"
STAGING_DIR="$(mktemp -d)"
cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$STAGING_DIR"

echo ""
echo "✅ Release artifacts ready (v$VERSION):"
echo "   • App Bundle : $APP_PATH"
echo "   • DMG Image  : $DMG_PATH"
echo "   • ZIP Archive: $ZIP_PATH"
