#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
SOURCE_APP="$PROJECT_DIR/dist/Chimlo.app"
source "$SCRIPT_DIR/signing-common.sh"

if [[ ! -d "$SOURCE_APP" ]]; then
  print -u2 "Build the app first: make app"
  exit 1
fi

chimlo_configure_signing
if [[ "$CHIMLO_SIGNING_MODE" == "adhoc" ]]; then
  print -u2 "Stable-signing check requires a real signing identity."
  print -u2 "Run: make signing-identity"
  exit 1
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/chimlo-signing-check.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

FIRST_APP="$TEMP_DIR/First.app"
SECOND_APP="$TEMP_DIR/Second.app"
cp -R "$SOURCE_APP" "$FIRST_APP"
cp -R "$SOURCE_APP" "$SECOND_APP"

mkdir -p "$SECOND_APP/Contents/Resources"
print -r -- "different signed payload" > "$SECOND_APP/Contents/Resources/signing-check.txt"

chimlo_sign_app_bundle "$FIRST_APP"
chimlo_sign_app_bundle "$SECOND_APP"

requirement_for() {
  /usr/bin/codesign -d -r- "$1" 2>&1 | /usr/bin/sed -n 's/^designated => //p'
}

cdhash_for() {
  /usr/bin/codesign -d --verbose=4 "$1" 2>&1 | /usr/bin/sed -n 's/^CDHash=//p'
}

FIRST_REQUIREMENT="$(requirement_for "$FIRST_APP")"
SECOND_REQUIREMENT="$(requirement_for "$SECOND_APP")"
FIRST_CDHASH="$(cdhash_for "$FIRST_APP")"
SECOND_CDHASH="$(cdhash_for "$SECOND_APP")"

if [[ -z "$FIRST_REQUIREMENT" || -z "$SECOND_REQUIREMENT" ]]; then
  print -u2 "Could not read the signed app's designated requirement."
  exit 1
fi

if [[ "$FIRST_REQUIREMENT" == cdhash* ]]; then
  print -u2 "FAIL: the designated requirement is still tied to an ad-hoc CDHash."
  exit 1
fi

if [[ "$FIRST_REQUIREMENT" != "$SECOND_REQUIREMENT" ]]; then
  print -u2 "FAIL: designated requirement changed between app payloads."
  print -u2 "First:  $FIRST_REQUIREMENT"
  print -u2 "Second: $SECOND_REQUIREMENT"
  exit 1
fi

if [[ -z "$FIRST_CDHASH" || -z "$SECOND_CDHASH" || "$FIRST_CDHASH" == "$SECOND_CDHASH" ]]; then
  print -u2 "FAIL: signing-check payloads did not produce different CDHashes."
  exit 1
fi

print "PASS: Chimlo's designated requirement stays stable across different builds."
print "Requirement: $FIRST_REQUIREMENT"
print "CDHash A: $FIRST_CDHASH"
print "CDHash B: $SECOND_CDHASH"
