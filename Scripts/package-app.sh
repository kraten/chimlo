#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
MEDIAREMOTE_SOURCE_DIR="$PROJECT_DIR/Vendor/MediaRemoteAdapter"
ICON_SOURCE_PATH="$PROJECT_DIR/.github/chimlo-icon.png"
source "$SCRIPT_DIR/signing-common.sh"

PACKAGE_VARIANT="${CHIMLO_PACKAGE_VARIANT:-development}"
case "$PACKAGE_VARIANT" in
  development)
    APP_BUNDLE_NAME="Chimlo Dev"
    APP_BUNDLE_IDENTIFIER="dev.chimlo.mac.development"
    ;;
  release)
    APP_BUNDLE_NAME="Chimlo"
    APP_BUNDLE_IDENTIFIER="dev.chimlo.mac"
    CHIMLO_CODE_SIGN_IDENTITY="${CHIMLO_CODE_SIGN_IDENTITY:-$CHIMLO_RELEASE_SIGNING_IDENTITY_DEFAULT}"
    CHIMLO_CODE_SIGN_KEYCHAIN="${CHIMLO_CODE_SIGN_KEYCHAIN:-$CHIMLO_RELEASE_SIGNING_KEYCHAIN_DEFAULT}"
    CHIMLO_CODE_SIGN_PASSWORD_FILE="${CHIMLO_CODE_SIGN_PASSWORD_FILE:-$CHIMLO_RELEASE_SIGNING_PASSWORD_FILE_DEFAULT}"
    CHIMLO_REQUIRE_STABLE_SIGNING=1
    ;;
  *)
    print -u2 "Unknown Chimlo package variant: $PACKAGE_VARIANT"
    print -u2 "Expected 'development' or 'release'."
    exit 1
    ;;
esac

TARGET_APP_DIR="$PROJECT_DIR/dist/$APP_BUNDLE_NAME.app"

cd "$PROJECT_DIR"
./Scripts/swift.sh build -c release --product ChimloApp
./Scripts/swift.sh build -c release --product chimlo

if [[ -n "${CHIMLO_SDK_PATH:-}" ]]; then
  BIN_DIR="$(SDKROOT="$CHIMLO_SDK_PATH" CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/chimlo-clang-module-cache" SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/chimlo-swiftpm-cache" swift build --disable-sandbox -c release --show-bin-path --sdk "$CHIMLO_SDK_PATH")"
else
  BIN_DIR="$(swift build --disable-sandbox -c release --show-bin-path)"
fi

STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/chimlo-package.XXXXXX")"
APP_DIR="$STAGING_ROOT/$APP_BUNDLE_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
HELPERS_DIR="$CONTENTS_DIR/Helpers"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MEDIAREMOTE_DESTINATION_DIR="$RESOURCES_DIR/MediaRemoteAdapter"

cleanup_staging() {
  rm -rf "$STAGING_ROOT"
}
trap cleanup_staging EXIT

mkdir -p "$MACOS_DIR" "$HELPERS_DIR" "$FRAMEWORKS_DIR" "$MEDIAREMOTE_DESTINATION_DIR"
cp "$PROJECT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -replace CFBundleDisplayName -string "$APP_BUNDLE_NAME" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -replace CFBundleName -string "$APP_BUNDLE_NAME" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string "$APP_BUNDLE_IDENTIFIER" "$CONTENTS_DIR/Info.plist"

if [[ "$PACKAGE_VARIANT" == "release" ]]; then
  if [[ -n "${CHIMLO_VERSION:-}" ]]; then
    /usr/bin/plutil -replace CFBundleShortVersionString \
      -string "${CHIMLO_VERSION#v}" \
      "$CONTENTS_DIR/Info.plist"
  fi
  if [[ -n "${CHIMLO_BUILD_NUMBER:-}" ]]; then
    /usr/bin/plutil -replace CFBundleVersion \
      -string "$CHIMLO_BUILD_NUMBER" \
      "$CONTENTS_DIR/Info.plist"
  fi
else
  for sparkle_key in \
    SUFeedURL \
    SUPublicEDKey \
    SUEnableAutomaticChecks \
    SUScheduledCheckInterval \
    SUAllowsAutomaticUpdates \
    SUAutomaticallyUpdate \
    SUVerifyUpdateBeforeExtraction \
    SURequireSignedFeed; do
    /usr/bin/plutil -remove "$sparkle_key" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true
  done
fi

if [[ ! -d "$BIN_DIR/Sparkle.framework" ]]; then
  print -u2 "Missing Sparkle.framework in SwiftPM build products: $BIN_DIR"
  exit 1
fi

cp "$BIN_DIR/ChimloApp" "$MACOS_DIR/Chimlo"
cp "$BIN_DIR/chimlo" "$HELPERS_DIR/chimlo"
/usr/bin/ditto "$BIN_DIR/Sparkle.framework" "$FRAMEWORKS_DIR/Sparkle.framework"
cp "$MEDIAREMOTE_SOURCE_DIR/mediaremote-adapter.pl" "$MEDIAREMOTE_DESTINATION_DIR/mediaremote-adapter.pl"
cp "$MEDIAREMOTE_SOURCE_DIR/LICENSE" "$MEDIAREMOTE_DESTINATION_DIR/LICENSE"
cp -R "$MEDIAREMOTE_SOURCE_DIR/MediaRemoteAdapter.framework" "$MEDIAREMOTE_DESTINATION_DIR/MediaRemoteAdapter.framework"

ICONSET_DIR="$STAGING_ROOT/Chimlo.iconset"
mkdir -p "$ICONSET_DIR"
for icon_size in 16 32 128 256 512; do
  /usr/bin/sips \
    --resampleHeightWidth "$icon_size" "$icon_size" \
    "$ICON_SOURCE_PATH" \
    --out "$ICONSET_DIR/icon_${icon_size}x${icon_size}.png" \
    >/dev/null

  retina_size="$((icon_size * 2))"
  /usr/bin/sips \
    --resampleHeightWidth "$retina_size" "$retina_size" \
    "$ICON_SOURCE_PATH" \
    --out "$ICONSET_DIR/icon_${icon_size}x${icon_size}@2x.png" \
    >/dev/null
done
CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/chimlo-clang-module-cache" \
  swift "$SCRIPT_DIR/build-icns.swift" "$ICONSET_DIR" "$RESOURCES_DIR/Chimlo.icns"
rm -rf "$ICONSET_DIR"

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
  if [[ "${CHIMLO_REQUIRE_STABLE_SIGNING:-0}" == "1" && "$CHIMLO_SIGNING_MODE" == "adhoc" ]]; then
    print -u2 "Refusing to create a public release with an ad-hoc signature."
    print -u2 "Run 'make release-signing-identity' first."
    exit 1
  fi
  chimlo_sign_app_bundle "$APP_DIR"

  if [[ "$CHIMLO_SIGNING_MODE" == "adhoc" ]]; then
    print -u2 "Warning: Chimlo was signed ad hoc. Accessibility permission may reset after a rebuild."
    print -u2 "Run 'make signing-identity' once to install a stable local identity."
  else
    print "Signed with: $CHIMLO_ACTIVE_SIGNING_IDENTITY"
  fi
fi

mkdir -p "${TARGET_APP_DIR:h}"
rm -rf "$TARGET_APP_DIR"
mv "$APP_DIR" "$TARGET_APP_DIR"
rmdir "$STAGING_ROOT"
trap - EXIT

echo "$TARGET_APP_DIR"
