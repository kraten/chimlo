#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_PATH="$PROJECT_DIR/dist/Chimlo.app"
INFO_PLIST="$APP_PATH/Contents/Info.plist"

if [[ ! -d "$APP_PATH" ]]; then
  print -u2 "Missing app bundle: $APP_PATH"
  print -u2 "Run 'make release-app' before packaging the disk image."
  exit 1
fi

if ! /usr/bin/codesign --verify --deep --strict "$APP_PATH"; then
  print -u2 "Refusing to package an app with an invalid code signature."
  exit 1
fi

APP_VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")"
VOLUME_NAME="Chimlo $APP_VERSION"
OUTPUT_PATH="${1:-$PROJECT_DIR/dist/Chimlo-$APP_VERSION.dmg}"

if [[ "$OUTPUT_PATH" != /* ]]; then
  OUTPUT_PATH="$PROJECT_DIR/$OUTPUT_PATH"
fi

if [[ "${OUTPUT_PATH:e:l}" != "dmg" ]]; then
  print -u2 "Disk image output must end in .dmg: $OUTPUT_PATH"
  exit 1
fi

STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/chimlo-dmg.XXXXXX")"
VOLUME_ROOT="$STAGING_ROOT/$VOLUME_NAME"
TEMP_DMG="$STAGING_ROOT/Chimlo.dmg"
MOUNT_POINT="$STAGING_ROOT/mount"
MOUNTED=0

cleanup_staging() {
  if (( MOUNTED )); then
    /usr/bin/hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  rm -rf "$STAGING_ROOT"
}
trap cleanup_staging EXIT

mkdir -p "$VOLUME_ROOT" "${OUTPUT_PATH:h}"
/usr/bin/ditto "$APP_PATH" "$VOLUME_ROOT/Chimlo.app"
ln -s /Applications "$VOLUME_ROOT/Applications"

/usr/bin/hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$VOLUME_ROOT" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$TEMP_DMG"

if [[ -n "${CHIMLO_DMG_CODE_SIGN_IDENTITY:-}" ]]; then
  /usr/bin/codesign \
    --force \
    --sign "$CHIMLO_DMG_CODE_SIGN_IDENTITY" \
    --timestamp \
    "$TEMP_DMG"
  /usr/bin/codesign --verify --strict "$TEMP_DMG"
fi

/usr/bin/hdiutil verify "$TEMP_DMG"
mkdir -p "$MOUNT_POINT"
/usr/bin/hdiutil attach \
  -readonly \
  -nobrowse \
  -mountpoint "$MOUNT_POINT" \
  "$TEMP_DMG" \
  >/dev/null
MOUNTED=1

if [[ ! -d "$MOUNT_POINT/Chimlo.app" ]]; then
  print -u2 "Disk image is missing Chimlo.app."
  exit 1
fi

if [[ ! -L "$MOUNT_POINT/Applications" ]] \
  || [[ "$(readlink "$MOUNT_POINT/Applications")" != "/Applications" ]]; then
  print -u2 "Disk image is missing the Applications shortcut."
  exit 1
fi

/usr/bin/codesign --verify --deep --strict "$MOUNT_POINT/Chimlo.app"
/usr/bin/hdiutil detach "$MOUNT_POINT" >/dev/null
MOUNTED=0
rmdir "$MOUNT_POINT"

mv -f "$TEMP_DMG" "$OUTPUT_PATH"

trap - EXIT
rm -rf "$STAGING_ROOT"

echo "$OUTPUT_PATH"
