#!/usr/bin/env bash
set -euo pipefail

# Build "Copilot Quota.app" (universal) into build/, Developer ID-signed when
# a certificate is available, ad-hoc otherwise.
#
#   ./scripts/build-app.sh            # Release (default)
#
# Override detection explicitly with CODE_SIGN_IDENTITY:
#   CODE_SIGN_IDENTITY="Developer ID Application: You (TEAMID)" ./scripts/build-app.sh
#   CODE_SIGN_IDENTITY="-" ./scripts/build-app.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Copilot Quota"
DERIVED="$ROOT/build/DerivedData"
OUTPUT="$ROOT/build/$APP_NAME.app"

SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:-auto}"
if [[ "$SIGNING_IDENTITY" == "auto" ]]; then
  DETECTED_ID="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -n 1)"
  if [[ -n "$DETECTED_ID" ]]; then
    SIGNING_IDENTITY="$DETECTED_ID"
    echo "==> Using detected Developer ID certificate: $SIGNING_IDENTITY"
  else
    SIGNING_IDENTITY="-"
    echo "==> No Developer ID certificate found — building with ad-hoc signature."
  fi
fi

XCODEBUILD_ARGS=(
  -project "$ROOT/CopilotQuota.xcodeproj"
  -scheme CopilotQuota
  -configuration Release
  -derivedDataPath "$DERIVED"
  ARCHS="arm64 x86_64"
  ONLY_ACTIVE_ARCH=NO
  ENABLE_HARDENED_RUNTIME=YES   # required for notarization
)

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  XCODEBUILD_ARGS+=(CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual)
else
  XCODEBUILD_ARGS+=(CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" CODE_SIGN_STYLE=Manual)
  TEAM_ID="$(sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p' <<<"$SIGNING_IDENTITY")"
  [[ -n "$TEAM_ID" ]] && XCODEBUILD_ARGS+=(DEVELOPMENT_TEAM="$TEAM_ID")
fi

echo "==> Building Release (universal)..."
LOG="$ROOT/build/xcodebuild.log"
mkdir -p "$ROOT/build"
if ! xcodebuild "${XCODEBUILD_ARGS[@]}" build >"$LOG" 2>&1; then
  echo "xcodebuild failed — last 50 lines of $LOG:"
  tail -50 "$LOG"
  exit 1
fi

BUILT="$DERIVED/Build/Products/Release/$APP_NAME.app"
rm -rf "$OUTPUT"
cp -R "$BUILT" "$OUTPUT"

echo "==> Verifying signatures (app + embedded widget)..."
codesign --verify --deep --strict --verbose=2 "$OUTPUT" >/dev/null
codesign --verify --strict --verbose=2 "$OUTPUT/Contents/PlugIns/CopilotQuotaWidget.appex" >/dev/null

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$OUTPUT/Contents/Info.plist")"
echo "$OUTPUT (v$VERSION)"
