#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
TAG="${1:-}"
ARTIFACT_ROOT="${CHIMLO_RELEASE_ARTIFACT_ROOT:-$PROJECT_DIR/dist/releases}"
CHANGELOG_PATH="$PROJECT_DIR/CHANGELOG.md"

if [[ ! "$TAG" =~ '^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$' ]]; then
  print -u2 "Usage: $0 <tag-vX.Y.Z>"
  exit 64
fi

cd "$PROJECT_DIR"

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  print -u2 "Refusing to publish from a dirty worktree."
  exit 1
fi

TAG_COMMIT="$(git rev-list -n 1 "$TAG" 2>/dev/null || true)"
HEAD_COMMIT="$(git rev-parse HEAD)"
if [[ -z "$TAG_COMMIT" || "$TAG_COMMIT" != "$HEAD_COMMIT" ]]; then
  print -u2 "The release tag must point at the checked-out commit: $TAG"
  exit 1
fi

ARTIFACT_DIR="$ARTIFACT_ROOT/$TAG"
DMG_PATH="$ARTIFACT_DIR/Chimlo-$TAG.dmg"
APPCAST_PATH="$ARTIFACT_DIR/appcast.xml"
MANIFEST_PATH="$ARTIFACT_DIR/RELEASE-MANIFEST.txt"
CHECKSUM_PATH="$ARTIFACT_DIR/SHA256SUMS.txt"

for artifact in "$DMG_PATH" "$APPCAST_PATH" "$MANIFEST_PATH" "$CHECKSUM_PATH"; do
  if [[ ! -f "$artifact" ]]; then
    print -u2 "Missing release artifact: $artifact"
    exit 1
  fi
done

if [[ ! -f "$CHANGELOG_PATH" ]]; then
  print -u2 "Missing changelog: $CHANGELOG_PATH"
  exit 1
fi

RELEASE_VERSION="${TAG#v}"
RELEASE_NOTES_PATH="$(/usr/bin/mktemp -t chimlo-release-notes)"
cleanup_release_notes() {
  rm -f "$RELEASE_NOTES_PATH"
}
trap cleanup_release_notes EXIT

/usr/bin/awk -v heading="## [$RELEASE_VERSION]" '
  index($0, heading) == 1 { in_release = 1; next }
  in_release && /^## \[/ { exit }
  in_release && /^\[[^]]+\]: / { exit }
  in_release { print }
' "$CHANGELOG_PATH" > "$RELEASE_NOTES_PATH"

if ! /usr/bin/grep -q '[^[:space:]]' "$RELEASE_NOTES_PATH"; then
  print -u2 "CHANGELOG.md has no release notes for $RELEASE_VERSION."
  exit 1
fi

(
  cd "$ARTIFACT_DIR"
  /usr/bin/shasum -a 256 -c "${CHECKSUM_PATH:t}"
)

gh auth status
if gh release view "$TAG" >/dev/null 2>&1; then
  print -u2 "A GitHub release already exists for $TAG. Nothing was uploaded."
  exit 1
fi

gh release create "$TAG" \
  "$DMG_PATH" \
  "$APPCAST_PATH" \
  "$MANIFEST_PATH" \
  "$CHECKSUM_PATH" \
  --draft \
  --verify-tag \
  --notes-file "$RELEASE_NOTES_PATH" \
  --title "Chimlo $RELEASE_VERSION"

print "Uploaded the exact locally signed files to a draft GitHub release."
print "Review the draft before publishing it."
