#!/bin/bash
set -euo pipefail

ARCHIVE_PATH="${1:?archive path is required}"
OUTPUT_DIRECTORY="${2:?output directory is required}"
APPLICATIONS_DIRECTORY="$ARCHIVE_PATH/Products/Applications"

APP_PATH="$(find "$APPLICATIONS_DIRECTORY" -maxdepth 1 -type d -name '*.app' -print -quit)"
if [[ -z "${APP_PATH:-}" || ! -d "$APP_PATH" ]]; then
  echo "::error::No archived iOS application was produced"
  exit 1
fi

INFO_PLIST="$APP_PATH/Info.plist"
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
EXECUTABLE_PATH="$APP_PATH/$EXECUTABLE"

echo "Bundle ID: $BUNDLE_ID"
echo "Executable: $EXECUTABLE"
/usr/bin/file "$EXECUTABLE_PATH"

ARCHITECTURES="$(/usr/bin/lipo -archs "$EXECUTABLE_PATH")"
echo "Device architectures: $ARCHITECTURES"
if ! grep -qw arm64 <<<"$ARCHITECTURES"; then
  echo "::error::Archive is not an arm64 iPhoneOS build"
  exit 1
fi

rm -rf "$APP_PATH/_CodeSignature"
rm -f "$APP_PATH/embedded.mobileprovision"
if /usr/bin/codesign -dv "$APP_PATH" >/dev/null 2>&1; then
  echo "::error::Expected an unsigned application, but codesign found a signature"
  exit 1
fi

mkdir -p "$OUTPUT_DIRECTORY"
PACKAGE_ROOT="$OUTPUT_DIRECTORY/ipa-root"
IPA_PATH="$OUTPUT_DIRECTORY/CAPlayground-device-unsigned.ipa"
rm -rf "$PACKAGE_ROOT"
mkdir -p "$PACKAGE_ROOT/Payload"
/usr/bin/ditto "$APP_PATH" "$PACKAGE_ROOT/Payload/CAPlayground.app"
(
  cd "$PACKAGE_ROOT"
  /usr/bin/zip -qry "$IPA_PATH" Payload
)

/usr/bin/shasum -a 256 "$IPA_PATH" | tee "$IPA_PATH.sha256"
/usr/bin/unzip -l "$IPA_PATH" | head -100
echo "Verified unsigned arm64 IPA: $IPA_PATH"
