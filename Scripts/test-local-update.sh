#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
TEST_ROOT="$PROJECT_DIR/dist/update-test"
HOST_APP_PATH="$TEST_ROOT/host/Chimlo.app"
UPDATE_APP_PATH="$TEST_ROOT/update/Chimlo.app"
FEED_DIR="$TEST_ROOT/feed"
DMG_PATH="$FEED_DIR/Chimlo-99.0.0.dmg"
APPCAST_PATH="$FEED_DIR/appcast.xml"
SERVER_LOG_PATH="$TEST_ROOT/server.log"
PACKAGE_APP="$SCRIPT_DIR/package-app.sh"
PACKAGE_DMG="$SCRIPT_DIR/package-dmg.sh"
GENERATE_APPCAST="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
SIGN_UPDATE="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update"
SPARKLE_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-dev.chimlo.mac}"
PORT="${CHIMLO_UPDATE_TEST_PORT:-55116}"
HOST_VERSION="98.0.0"
HOST_BUILD="9800"
UPDATE_VERSION="99.0.0"
UPDATE_BUILD="9900"
MODE="${1:-}"
TEST_BUNDLE_IDENTIFIER="dev.chimlo.mac.update-test"

if [[ -n "$MODE" && "$MODE" != "--prepare-only" ]]; then
  print -u2 "Usage: $0 [--prepare-only]"
  exit 64
fi

if [[ ! "$PORT" =~ '^[0-9]+$' ]] || (( PORT < 1024 || PORT > 65535 )); then
  print -u2 "CHIMLO_UPDATE_TEST_PORT must be between 1024 and 65535."
  exit 64
fi

if [[ "$TEST_ROOT" != "$PROJECT_DIR/dist/update-test" ]]; then
  print -u2 "Refusing to replace an unexpected test directory: $TEST_ROOT"
  exit 1
fi

if [[ ! -x "$GENERATE_APPCAST" || ! -x "$SIGN_UPDATE" ]]; then
  print -u2 "Sparkle's update tools are unavailable."
  print -u2 "Run 'swift package resolve' first."
  exit 1
fi

PYTHON_BIN=""
if [[ "$MODE" != "--prepare-only" ]]; then
  PYTHON_BIN="${CHIMLO_PYTHON_BIN:-$(command -v python3 || true)}"
  if [[ -z "$PYTHON_BIN" ]]; then
    print -u2 "Python 3 is required to serve the local test feed."
    exit 1
  fi

  if /usr/bin/nc -z 127.0.0.1 "$PORT" >/dev/null 2>&1; then
    print -u2 "Port $PORT is already in use."
    print -u2 "Choose another port with CHIMLO_UPDATE_TEST_PORT=<port>."
    exit 1
  fi
fi

FEED_BASE_URL="http://localhost:$PORT"
FEED_URL="$FEED_BASE_URL/appcast.xml"
TEST_PROCESS_PATTERN='dist/update-test/(host|update)/Chimlo\.app/Contents/MacOS/Chimlo'

if /usr/bin/pgrep -f "$TEST_PROCESS_PATTERN" >/dev/null 2>&1; then
  print -u2 "Chimlo Update Test is still running."
  print -u2 "Quit it before starting a fresh local update test."
  exit 1
fi

rm -rf "$TEST_ROOT"
mkdir -p "${HOST_APP_PATH:h}" "${UPDATE_APP_PATH:h}" "$FEED_DIR"

print "Building the signed update candidate ($UPDATE_VERSION)..."
CHIMLO_VERSION="$UPDATE_VERSION" \
CHIMLO_BUILD_NUMBER="$UPDATE_BUILD" \
CHIMLO_PACKAGE_VARIANT=update-test \
CHIMLO_PACKAGE_OUTPUT_PATH="$UPDATE_APP_PATH" \
CHIMLO_UPDATE_FEED_URL="$FEED_URL" \
  "$PACKAGE_APP"

print "Packaging the local update disk image..."
CHIMLO_PACKAGE_APP_PATH="$UPDATE_APP_PATH" \
  "$PACKAGE_DMG" "$DMG_PATH"

print "Generating the signed local appcast..."
"$GENERATE_APPCAST" \
  --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix "$FEED_BASE_URL/" \
  --link "https://github.com/kraten/chimlo" \
  --maximum-versions 1 \
  --maximum-deltas 0 \
  -o "$APPCAST_PATH" \
  "$FEED_DIR"

if [[ ! -f "$APPCAST_PATH" ]]; then
  print -u2 "Sparkle did not generate the local appcast."
  exit 1
fi

/usr/bin/xmllint --noout "$APPCAST_PATH"
"$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" --verify "$APPCAST_PATH"

ACTUAL_URL="$(/usr/bin/xmllint --xpath \
  'string(//*[local-name()="enclosure"]/@url)' "$APPCAST_PATH")"
ARCHIVE_SIGNATURE="$(/usr/bin/xmllint --xpath \
  'string(//*[local-name()="enclosure"]/@*[local-name()="edSignature"])' \
  "$APPCAST_PATH")"
APPCAST_LENGTH="$(/usr/bin/xmllint --xpath \
  'string(//*[local-name()="enclosure"]/@length)' "$APPCAST_PATH")"
ACTUAL_LENGTH="$(/usr/bin/stat -f '%z' "$DMG_PATH")"
APPCAST_BUILD="$(/usr/bin/xmllint --xpath \
  'string(//*[local-name()="item"]/*[local-name()="version"])' \
  "$APPCAST_PATH")"

if [[ "$ACTUAL_URL" != "$FEED_BASE_URL/${DMG_PATH:t}" ]]; then
  print -u2 "The local appcast points at an unexpected download URL: $ACTUAL_URL"
  exit 1
fi

if [[ -z "$ARCHIVE_SIGNATURE" \
   || "$APPCAST_LENGTH" != "$ACTUAL_LENGTH" \
   || "$APPCAST_BUILD" != "$UPDATE_BUILD" ]]; then
  print -u2 "The local appcast metadata is incomplete or stale."
  exit 1
fi

"$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" \
  --verify "$DMG_PATH" "$ARCHIVE_SIGNATURE"

print "Building the older signed host ($HOST_VERSION)..."
CHIMLO_VERSION="$HOST_VERSION" \
CHIMLO_BUILD_NUMBER="$HOST_BUILD" \
CHIMLO_PACKAGE_VARIANT=update-test \
CHIMLO_PACKAGE_OUTPUT_PATH="$HOST_APP_PATH" \
CHIMLO_UPDATE_FEED_URL="$FEED_URL" \
  "$PACKAGE_APP"

verify_test_app() {
  typeset app_path="$1"
  typeset expected_version="$2"
  typeset info_plist="$app_path/Contents/Info.plist"

  /usr/bin/codesign --verify --deep --strict "$app_path"

  typeset bundle_identifier
  typeset app_version
  typeset feed_url
  typeset update_test_mode
  typeset automatic_checks
  bundle_identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw "$info_plist")"
  app_version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$info_plist")"
  feed_url="$(/usr/bin/plutil -extract SUFeedURL raw "$info_plist")"
  update_test_mode="$(/usr/bin/plutil -extract ChimloUpdateTestMode raw "$info_plist")"
  automatic_checks="$(/usr/bin/plutil -extract SUEnableAutomaticChecks raw "$info_plist")"

  if [[ "$bundle_identifier" != "$TEST_BUNDLE_IDENTIFIER" \
     || "$app_version" != "$expected_version" \
     || "$feed_url" != "$FEED_URL" \
     || "$update_test_mode" != "true" \
     || "$automatic_checks" != "false" ]]; then
    print -u2 "The local update test app has unexpected bundle metadata: $app_path"
    exit 1
  fi
}

verify_test_app "$HOST_APP_PATH" "$HOST_VERSION"
verify_test_app "$UPDATE_APP_PATH" "$UPDATE_VERSION"

HOST_REQUIREMENT="$(/usr/bin/codesign -d -r- "$HOST_APP_PATH" 2>&1 \
  | /usr/bin/sed -n 's/^designated => //p')"
UPDATE_REQUIREMENT="$(/usr/bin/codesign -d -r- "$UPDATE_APP_PATH" 2>&1 \
  | /usr/bin/sed -n 's/^designated => //p')"

if [[ -z "$HOST_REQUIREMENT" || "$HOST_REQUIREMENT" != "$UPDATE_REQUIREMENT" ]]; then
  print -u2 "The two local test apps do not share a designated requirement."
  exit 1
fi

rm -rf "$UPDATE_APP_PATH"
rmdir "${UPDATE_APP_PATH:h}"

print "PASS: local update artifacts are signed, isolated, and internally consistent."
print "Host:    $HOST_APP_PATH"
print "Update:  $DMG_PATH"
print "Appcast: $APPCAST_PATH"
print "Bundle:  $TEST_BUNDLE_IDENTIFIER"

if [[ "$MODE" == "--prepare-only" ]]; then
  exit 0
fi

SERVER_PID=0
cleanup_server() {
  if (( SERVER_PID > 0 )) && /bin/kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    /bin/kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup_server EXIT INT TERM

"$PYTHON_BIN" -m http.server "$PORT" \
  --bind 127.0.0.1 \
  --directory "$FEED_DIR" \
  >"$SERVER_LOG_PATH" 2>&1 &
SERVER_PID=$!

SERVER_READY=0
for _ in {1..50}; do
  if /usr/bin/curl --silent --fail "$FEED_URL" >/dev/null 2>&1; then
    SERVER_READY=1
    break
  fi
  /bin/sleep 0.1
done

if (( ! SERVER_READY )); then
  print -u2 "The local update server did not start."
  print -u2 "See: $SERVER_LOG_PATH"
  exit 1
fi

/usr/bin/defaults delete "$TEST_BUNDLE_IDENTIFIER" >/dev/null 2>&1 || true
/usr/bin/open -n "$HOST_APP_PATH"

print
print "Local update test is running. Nothing has been uploaded."
print "1. In About > Updates, click 'Check for Updates'."
print "2. Click 'Update to latest version'."
print "3. After Chimlo relaunches, confirm it shows Version $UPDATE_VERSION."
print
print "Keep this command running while the update downloads."
print "Press Control-C after the test to stop the local server."
print "Server log: $SERVER_LOG_PATH"

wait "$SERVER_PID"
