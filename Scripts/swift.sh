#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
MODULE_CACHE="${TMPDIR:-/tmp}/chimlo-clang-module-cache"
SWIFTPM_CACHE="${TMPDIR:-/tmp}/chimlo-swiftpm-cache"

mkdir -p "$MODULE_CACHE" "$SWIFTPM_CACHE"
cd "$PROJECT_DIR"

COMMAND="${1:-}"
if [[ -z "$COMMAND" ]]; then
  echo "usage: swift.sh <build|test|run> [arguments...]" >&2
  exit 64
fi
shift

SWIFT_ARGS=("$@")

# Some Command Line Tools installations ship Swift Testing beside the
# toolchain without adding that directory to SwiftPM's test search paths.
# Supplying the installed framework explicitly keeps `make test` working with
# both Command Line Tools and full Xcode, without vendoring another test copy.
if [[ "$COMMAND" == "test" ]]; then
  ACTIVE_DEVELOPER_DIR="$(/usr/bin/xcode-select -p)"
  TESTING_FRAMEWORKS_DIR="$ACTIVE_DEVELOPER_DIR/Library/Developer/Frameworks"
  if [[ -d "$TESTING_FRAMEWORKS_DIR/Testing.framework" ]]; then
    SWIFT_ARGS+=(
      -Xswiftc -F
      -Xswiftc "$TESTING_FRAMEWORKS_DIR"
      -Xlinker -F
      -Xlinker "$TESTING_FRAMEWORKS_DIR"
      -Xlinker -rpath
      -Xlinker "$TESTING_FRAMEWORKS_DIR"
    )
  fi
fi

if [[ -n "${CHIMLO_SDK_PATH:-}" ]]; then
  SDKROOT="$CHIMLO_SDK_PATH" \
    CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    SWIFTPM_MODULECACHE_OVERRIDE="$SWIFTPM_CACHE" \
    swift "$COMMAND" --disable-sandbox "${SWIFT_ARGS[@]}" --sdk "$CHIMLO_SDK_PATH"
else
  CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    SWIFTPM_MODULECACHE_OVERRIDE="$SWIFTPM_CACHE" \
    swift "$COMMAND" --disable-sandbox "${SWIFT_ARGS[@]}"
fi
