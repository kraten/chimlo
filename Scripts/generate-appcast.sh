#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
ARCHIVE_PATH="${1:-}"
OUTPUT_PATH="${2:-$PROJECT_DIR/dist/appcast.xml}"
GENERATE_APPCAST="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
RELEASE_TAG="${CHIMLO_RELEASE_TAG:-}"

if [[ -z "$ARCHIVE_PATH" || ! -f "$ARCHIVE_PATH" ]]; then
  print -u2 "Usage: $0 <release.dmg> [output-appcast.xml]"
  exit 1
fi

if [[ -z "$RELEASE_TAG" ]]; then
  print -u2 "CHIMLO_RELEASE_TAG is required to generate release download URLs."
  exit 1
fi

if [[ ! -x "$GENERATE_APPCAST" ]]; then
  print -u2 "Sparkle's generate_appcast tool is unavailable. Run 'swift package resolve' first."
  exit 1
fi

if [[ "$OUTPUT_PATH" != /* ]]; then
  OUTPUT_PATH="$PROJECT_DIR/$OUTPUT_PATH"
fi

STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/chimlo-appcast.XXXXXX")"

cleanup_staging() {
  rm -rf "$STAGING_ROOT"
}
trap cleanup_staging EXIT

/usr/bin/ditto "$ARCHIVE_PATH" "$STAGING_ROOT/${ARCHIVE_PATH:t}"

typeset -a appcast_args
appcast_args=(
  --download-url-prefix "https://github.com/kraten/chimlo/releases/download/$RELEASE_TAG/"
  --link "https://github.com/kraten/chimlo"
  --maximum-versions 1
  --maximum-deltas 0
  -o "$STAGING_ROOT/appcast.xml"
  "$STAGING_ROOT"
)

"$GENERATE_APPCAST" \
  --account "${SPARKLE_KEY_ACCOUNT:-dev.chimlo.mac}" \
  "${appcast_args[@]}"

if [[ ! -f "$STAGING_ROOT/appcast.xml" ]]; then
  print -u2 "Sparkle did not generate appcast.xml."
  exit 1
fi

mkdir -p "${OUTPUT_PATH:h}"
cp "$STAGING_ROOT/appcast.xml" "$OUTPUT_PATH"

echo "$OUTPUT_PATH"
