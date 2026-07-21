#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="$PROJECT_DIR/dist/Chimlo.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
HELPERS_DIR="$CONTENTS_DIR/Helpers"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MEDIAREMOTE_SOURCE_DIR="$PROJECT_DIR/Vendor/MediaRemoteAdapter"
MEDIAREMOTE_DESTINATION_DIR="$RESOURCES_DIR/MediaRemoteAdapter"
source "$SCRIPT_DIR/signing-common.sh"

cd "$PROJECT_DIR"
./Scripts/swift.sh build -c release --product ChimloApp
./Scripts/swift.sh build -c release --product chimlo

if [[ -n "${CHIMLO_SDK_PATH:-}" ]]; then
  BIN_DIR="$(SDKROOT="$CHIMLO_SDK_PATH" CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/chimlo-clang-module-cache" SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/chimlo-swiftpm-cache" swift build --disable-sandbox -c release --show-bin-path --sdk "$CHIMLO_SDK_PATH")"
else
  BIN_DIR="$(swift build --disable-sandbox -c release --show-bin-path)"
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$HELPERS_DIR" "$MEDIAREMOTE_DESTINATION_DIR"
cp "$PROJECT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$BIN_DIR/ChimloApp" "$MACOS_DIR/Chimlo"
cp "$BIN_DIR/chimlo" "$HELPERS_DIR/chimlo"
cp "$MEDIAREMOTE_SOURCE_DIR/mediaremote-adapter.pl" "$MEDIAREMOTE_DESTINATION_DIR/mediaremote-adapter.pl"
cp "$MEDIAREMOTE_SOURCE_DIR/LICENSE" "$MEDIAREMOTE_DESTINATION_DIR/LICENSE"
cp -R "$MEDIAREMOTE_SOURCE_DIR/MediaRemoteAdapter.framework" "$MEDIAREMOTE_DESTINATION_DIR/MediaRemoteAdapter.framework"

chmod 755 \
  "$MACOS_DIR/Chimlo" \
  "$HELPERS_DIR/chimlo" \
  "$MEDIAREMOTE_DESTINATION_DIR/mediaremote-adapter.pl" \
  "$MEDIAREMOTE_DESTINATION_DIR/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter"

if command -v codesign >/dev/null 2>&1; then
  # Finder and downloaded vendor artifacts can carry provenance or quarantine
  # metadata into the generated bundle. Strip it from the disposable package
  # copy so codesign can replace nested signatures deterministically.
  /usr/bin/xattr -cr "$APP_DIR"
  chimlo_configure_signing
  chimlo_sign_app_bundle "$APP_DIR"

  if [[ "$CHIMLO_SIGNING_MODE" == "adhoc" ]]; then
    print -u2 "Warning: Chimlo was signed ad hoc. Accessibility permission may reset after a rebuild."
    print -u2 "Run 'make signing-identity' once to install a stable local identity."
  else
    print "Signed with: $CHIMLO_ACTIVE_SIGNING_IDENTITY"
  fi
fi

echo "$APP_DIR"
