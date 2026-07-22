#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
TAG="${1:-}"
BUILD_NUMBER="${2:-}"
ARTIFACT_ROOT="${CHIMLO_RELEASE_ARTIFACT_ROOT:-$PROJECT_DIR/dist/releases}"
PUBLIC_CERTIFICATE_PATH="${CHIMLO_RELEASE_PUBLIC_CERTIFICATE_PATH:-$PROJECT_DIR/Packaging/Signing/ChimloRelease.cer}"
REQUIREMENT_PATH="${CHIMLO_RELEASE_REQUIREMENT_PATH:-$PROJECT_DIR/Packaging/Signing/ChimloRelease.designated-requirement}"
SPARKLE_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-dev.chimlo.mac}"
SIGN_UPDATE="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update"

if [[ ! "$TAG" =~ '^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$' ]] \
  || [[ ! "$BUILD_NUMBER" =~ '^[1-9][0-9]*$' ]]; then
  print -u2 "Usage: $0 <tag-vX.Y.Z> <positive-build-number>"
  exit 64
fi

cd "$PROJECT_DIR"

if [[ "${CHIMLO_RELEASE_ALLOW_DIRTY:-0}" != "1" ]] \
  && [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  print -u2 "Release worktree is not clean. Commit the reviewed release inputs before building."
  exit 1
fi

if [[ "${CHIMLO_RELEASE_ALLOW_UNTAGGED:-0}" != "1" ]]; then
  TAG_COMMIT="$(git rev-list -n 1 "$TAG" 2>/dev/null || true)"
  HEAD_COMMIT="$(git rev-parse HEAD)"
  if [[ -z "$TAG_COMMIT" || "$TAG_COMMIT" != "$HEAD_COMMIT" ]]; then
    print -u2 "The release tag must exist and point at the checked-out commit: $TAG"
    exit 1
  fi
fi

if [[ ! -f "$PUBLIC_CERTIFICATE_PATH" || ! -f "$REQUIREMENT_PATH" ]]; then
  print -u2 "Release identity inputs are incomplete."
  print -u2 "Expected: $PUBLIC_CERTIFICATE_PATH"
  print -u2 "Expected: $REQUIREMENT_PATH"
  exit 1
fi

if [[ ! -x "$SIGN_UPDATE" ]]; then
  print -u2 "Sparkle's sign_update tool is unavailable. Run 'swift package resolve' first."
  exit 1
fi

ARTIFACT_DIR="$ARTIFACT_ROOT/$TAG"
if [[ -e "$ARTIFACT_DIR" ]]; then
  print -u2 "Refusing to overwrite an existing release directory: $ARTIFACT_DIR"
  exit 1
fi

make check
if [[ "${CHIMLO_RELEASE_ACKNOWLEDGE_SKIPPED_TESTS:-0}" == "1" ]]; then
  print -u2 "Warning: Swift tests were explicitly skipped for this disposable release run."
else
  make test
fi

CHIMLO_VERSION="$TAG" \
CHIMLO_BUILD_NUMBER="$BUILD_NUMBER" \
CHIMLO_PACKAGE_VARIANT=release \
  "$SCRIPT_DIR/package-app.sh"

APP_PATH="$PROJECT_DIR/dist/Chimlo.app"
CHIMLO_RELEASE_REQUIREMENT_PATH="$REQUIREMENT_PATH" \
  "$SCRIPT_DIR/verify-release-identity.sh" "$APP_PATH"

mkdir -p "$ARTIFACT_DIR"
DMG_PATH="$ARTIFACT_DIR/Chimlo-$TAG.dmg"
APPCAST_PATH="$ARTIFACT_DIR/appcast.xml"

"$SCRIPT_DIR/package-dmg.sh" "$DMG_PATH"
CHIMLO_RELEASE_TAG="$TAG" \
SPARKLE_KEY_ACCOUNT="$SPARKLE_ACCOUNT" \
  "$SCRIPT_DIR/generate-appcast.sh" "$DMG_PATH" "$APPCAST_PATH"

/usr/bin/xmllint --noout "$APPCAST_PATH"
"$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" --verify "$APPCAST_PATH"

EXPECTED_URL="https://github.com/kraten/chimlo/releases/download/$TAG/${DMG_PATH:t}"
ACTUAL_URL="$(/usr/bin/xmllint --xpath \
  'string(//*[local-name()="enclosure"]/@url)' "$APPCAST_PATH")"
ARCHIVE_SIGNATURE="$(/usr/bin/xmllint --xpath \
  'string(//*[local-name()="enclosure"]/@*[local-name()="edSignature"])' "$APPCAST_PATH")"
APPCAST_LENGTH="$(/usr/bin/xmllint --xpath \
  'string(//*[local-name()="enclosure"]/@length)' "$APPCAST_PATH")"
ACTUAL_LENGTH="$(/usr/bin/stat -f '%z' "$DMG_PATH")"

if [[ "$ACTUAL_URL" != "$EXPECTED_URL" ]]; then
  print -u2 "Appcast download URL does not match the exact release artifact."
  exit 1
fi

if [[ -z "$ARCHIVE_SIGNATURE" || "$APPCAST_LENGTH" != "$ACTUAL_LENGTH" ]]; then
  print -u2 "Appcast archive metadata is incomplete or stale."
  exit 1
fi

"$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" --verify "$DMG_PATH" "$ARCHIVE_SIGNATURE"

INFO_PLIST="$APP_PATH/Contents/Info.plist"
APP_VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")"
APP_BUILD="$(/usr/bin/plutil -extract CFBundleVersion raw "$INFO_PLIST")"
BUNDLE_IDENTIFIER="$(/usr/bin/plutil -extract CFBundleIdentifier raw "$INFO_PLIST")"
DESIGNATED_REQUIREMENT="$(<"$REQUIREMENT_PATH")"
CDHASH="$(/usr/bin/codesign -d --verbose=4 "$APP_PATH" 2>&1 \
  | /usr/bin/sed -n 's/^CDHash=//p')"
CERTIFICATE_SHA256="$(/usr/bin/shasum -a 256 "$PUBLIC_CERTIFICATE_PATH" \
  | /usr/bin/awk '{ print $1 }')"
COMMIT="$(git rev-parse HEAD)"
MANIFEST_PATH="$ARTIFACT_DIR/RELEASE-MANIFEST.txt"

{
  print "Tag: $TAG"
  print "Commit: $COMMIT"
  print "Version: $APP_VERSION"
  print "Build: $APP_BUILD"
  print "Bundle identifier: $BUNDLE_IDENTIFIER"
  print "Designated requirement: $DESIGNATED_REQUIREMENT"
  print "App CDHash: $CDHASH"
  print "Release certificate DER SHA-256: $CERTIFICATE_SHA256"
  print "Sparkle key account: $SPARKLE_ACCOUNT"
  print "DMG: ${DMG_PATH:t}"
  print "Appcast: ${APPCAST_PATH:t}"
} > "$MANIFEST_PATH"

(
  cd "$ARTIFACT_DIR"
  /usr/bin/shasum -a 256 "${DMG_PATH:t}" "${APPCAST_PATH:t}" "${MANIFEST_PATH:t}" \
    > SHA256SUMS.txt
)

print "Release artifacts are complete and have not been uploaded."
print "$ARTIFACT_DIR"
