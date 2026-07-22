#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_PATH="${1:-$PROJECT_DIR/dist/Chimlo.app}"
MODE="${2:-}"
REQUIREMENT_PATH="${CHIMLO_RELEASE_REQUIREMENT_PATH:-$PROJECT_DIR/Packaging/Signing/ChimloRelease.designated-requirement}"
EXPECTED_BUNDLE_IDENTIFIER="dev.chimlo.mac"

if [[ ! -d "$APP_PATH" ]]; then
  print -u2 "Missing release app: $APP_PATH"
  exit 1
fi

if [[ -n "$MODE" && "$MODE" != "--initialize" ]]; then
  print -u2 "Usage: $0 [Chimlo.app] [--initialize]"
  exit 64
fi

/usr/bin/codesign --verify --deep --strict "$APP_PATH"

INFO_PLIST="$APP_PATH/Contents/Info.plist"
BUNDLE_IDENTIFIER="$(/usr/bin/plutil -extract CFBundleIdentifier raw "$INFO_PLIST")"
if [[ "$BUNDLE_IDENTIFIER" != "$EXPECTED_BUNDLE_IDENTIFIER" ]]; then
  print -u2 "Release bundle identifier changed."
  print -u2 "Expected: $EXPECTED_BUNDLE_IDENTIFIER"
  print -u2 "Actual:   $BUNDLE_IDENTIFIER"
  exit 1
fi

DESIGNATED_REQUIREMENT="$(/usr/bin/codesign -d -r- "$APP_PATH" 2>&1 \
  | /usr/bin/sed -n 's/^designated => //p')"
CDHASH="$(/usr/bin/codesign -d --verbose=4 "$APP_PATH" 2>&1 \
  | /usr/bin/sed -n 's/^CDHash=//p')"

if [[ -z "$DESIGNATED_REQUIREMENT" || -z "$CDHASH" ]]; then
  print -u2 "Could not read Chimlo's code signing identity."
  exit 1
fi

if [[ "$DESIGNATED_REQUIREMENT" == cdhash* ]]; then
  print -u2 "Release app is ad-hoc signed and tied to a changing CDHash."
  exit 1
fi

if [[ -f "$REQUIREMENT_PATH" ]]; then
  EXPECTED_REQUIREMENT="$(<"$REQUIREMENT_PATH")"
  if [[ "$EXPECTED_REQUIREMENT" != "$DESIGNATED_REQUIREMENT" ]]; then
    print -u2 "Release designated requirement changed."
    print -u2 "Expected: $EXPECTED_REQUIREMENT"
    print -u2 "Actual:   $DESIGNATED_REQUIREMENT"
    exit 1
  fi
elif [[ "$MODE" == "--initialize" ]]; then
  mkdir -p "${REQUIREMENT_PATH:h}"
  umask 022
  print -r -- "$DESIGNATED_REQUIREMENT" > "$REQUIREMENT_PATH"
  print "Initialized release requirement baseline: $REQUIREMENT_PATH"
else
  print -u2 "Missing release requirement baseline: $REQUIREMENT_PATH"
  print -u2 "After creating the release certificate, run 'make release-signing-freeze' once, review the file, and commit it before tagging a release."
  exit 1
fi

print "PASS: Chimlo satisfies the frozen release identity."
print "Bundle identifier: $BUNDLE_IDENTIFIER"
print "Designated requirement: $DESIGNATED_REQUIREMENT"
print "CDHash: $CDHASH"

