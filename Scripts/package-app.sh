#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="$PROJECT_DIR/dist/Chimlo.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
HELPERS_DIR="$CONTENTS_DIR/Helpers"

cd "$PROJECT_DIR"
./Scripts/swift.sh build -c release --product ChimloApp
./Scripts/swift.sh build -c release --product chimlo

if [[ -n "${CHIMLO_SDK_PATH:-}" ]]; then
  BIN_DIR="$(SDKROOT="$CHIMLO_SDK_PATH" CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/chimlo-clang-module-cache" SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/chimlo-swiftpm-cache" swift build --disable-sandbox -c release --show-bin-path --sdk "$CHIMLO_SDK_PATH")"
else
  BIN_DIR="$(swift build --disable-sandbox -c release --show-bin-path)"
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$HELPERS_DIR"
cp "$PROJECT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$BIN_DIR/ChimloApp" "$MACOS_DIR/Chimlo"
cp "$BIN_DIR/chimlo" "$HELPERS_DIR/chimlo"

chmod 755 "$MACOS_DIR/Chimlo" "$HELPERS_DIR/chimlo"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$HELPERS_DIR/chimlo"
  codesign --force --sign - "$APP_DIR"
  codesign --verify --deep --strict "$APP_DIR"
fi

echo "$APP_DIR"
