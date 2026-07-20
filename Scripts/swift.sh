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
