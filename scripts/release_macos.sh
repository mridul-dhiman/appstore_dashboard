#!/usr/bin/env bash
# Builds a distributable macOS app: release build, signed with a hardened runtime, notarized and stapled.
#
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   ASC_KEY_PATH=~/keys/AuthKey_ABC123.p8 ASC_KEY_ID=ABC123 ASC_ISSUER_ID=xxxxxxxx-... \
#   scripts/release_macos.sh
#
# Notarization uses an App Store Connect API key (the same kind this app manages), so no Apple ID password is needed.
# NOTARIZE=0 skips notarization (sign only). SIGN_IDENTITY=- signs ad hoc for a local check of the hardened runtime;
# an ad-hoc build can not be notarized.
set -euo pipefail

cd "$(dirname "$0")/.."
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your \"Developer ID Application: …\" identity (security find-identity -v -p codesigning), or - for ad hoc}"
NOTARIZE="${NOTARIZE:-1}"
[[ "$SIGN_IDENTITY" == "-" ]] && NOTARIZE=0

APP="build/macos/Build/Products/Release/appstore_dashboard.app"
ENTITLEMENTS="macos/Runner/Release.entitlements"
OUT="build/release"

flutter build macos --release

# Sign inside out: nested frameworks and helpers first, then the app, all with the hardened runtime.
TIMESTAMP=(--timestamp)
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  TIMESTAMP=() # Apple's timestamp server only signs real identities
  # Ad-hoc code has no Team ID, so the hardened runtime's library validation would refuse to load Flutter's own
  # frameworks. Only for this local check, allow it; a Developer ID build signs everything with one team and keeps
  # library validation on.
  ADHOC_ENT="$(mktemp -t adhoc-entitlements).plist"
  cp "$ENTITLEMENTS" "$ADHOC_ENT"
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$ADHOC_ENT"
  ENTITLEMENTS="$ADHOC_ENT"
fi
while IFS= read -r -d '' item; do
  codesign --force --options runtime ${TIMESTAMP[@]+"${TIMESTAMP[@]}"} --sign "$SIGN_IDENTITY" "$item"
done < <(find "$APP/Contents/Frameworks" \( -name "*.framework" -o -name "*.dylib" \) -print0 2>/dev/null)
codesign --force --options runtime ${TIMESTAMP[@]+"${TIMESTAMP[@]}"} --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

mkdir -p "$OUT"
ZIP="$OUT/appstore_dashboard.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if [[ "$NOTARIZE" == "1" ]]; then
  : "${ASC_KEY_PATH:?Set ASC_KEY_PATH to the .p8 file}" "${ASC_KEY_ID:?Set ASC_KEY_ID}" "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID}"
  xcrun notarytool submit "$ZIP" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP" # re-zip with the ticket stapled
  spctl --assess --type execute --verbose "$APP"
fi

echo "Done: $APP"
echo "      $ZIP"
