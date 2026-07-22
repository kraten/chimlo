#!/bin/zsh

# Shared local-signing configuration for Chimlo's packaging scripts.
# This file is sourced by scripts that already enable `set -euo pipefail`.

CHIMLO_LOCAL_SIGNING_IDENTITY_DEFAULT="Chimlo Local Development"
CHIMLO_LOCAL_SIGNING_KEYCHAIN_DEFAULT="$HOME/Library/Keychains/ChimloLocalSigning.keychain-db"
CHIMLO_LOCAL_SIGNING_PASSWORD_FILE_DEFAULT="$HOME/Library/Application Support/Chimlo/Signing/keychain-password"
CHIMLO_RELEASE_SIGNING_IDENTITY_DEFAULT="Chimlo Release"
CHIMLO_RELEASE_SIGNING_KEYCHAIN_DEFAULT="$HOME/Library/Keychains/ChimloReleaseSigning.keychain-db"
CHIMLO_RELEASE_SIGNING_PASSWORD_FILE_DEFAULT="$HOME/Library/Application Support/Chimlo/Release Signing/keychain-password"

chimlo_configure_signing() {
  typeset requested_identity="${CHIMLO_CODE_SIGN_IDENTITY:-}"
  typeset requested_keychain="${CHIMLO_CODE_SIGN_KEYCHAIN:-}"
  typeset password_file="${CHIMLO_CODE_SIGN_PASSWORD_FILE:-$CHIMLO_LOCAL_SIGNING_PASSWORD_FILE_DEFAULT}"

  CHIMLO_SIGNING_MODE="adhoc"
  CHIMLO_ACTIVE_SIGNING_IDENTITY="-"
  CHIMLO_ACTIVE_SIGNING_KEYCHAIN=""

  if [[ "$requested_identity" == "-" ]]; then
    # Explicitly opt into ad-hoc signing without falling back to the local keychain.
    :
  elif [[ -n "$requested_identity" ]]; then
    CHIMLO_SIGNING_MODE="identity"
    CHIMLO_ACTIVE_SIGNING_IDENTITY="$requested_identity"
    CHIMLO_ACTIVE_SIGNING_KEYCHAIN="$requested_keychain"
  elif [[ -f "$CHIMLO_LOCAL_SIGNING_KEYCHAIN_DEFAULT" && -f "$password_file" ]]; then
    CHIMLO_SIGNING_MODE="local"
    CHIMLO_ACTIVE_SIGNING_IDENTITY="$CHIMLO_LOCAL_SIGNING_IDENTITY_DEFAULT"
    CHIMLO_ACTIVE_SIGNING_KEYCHAIN="$CHIMLO_LOCAL_SIGNING_KEYCHAIN_DEFAULT"
  fi

  if [[ "$CHIMLO_SIGNING_MODE" != "adhoc" && -n "$CHIMLO_ACTIVE_SIGNING_KEYCHAIN" ]]; then
    if [[ ! -f "$password_file" ]]; then
      print -u2 "Chimlo cannot unlock the requested signing keychain."
      print -u2 "Missing password file: $password_file"
      return 1
    fi

    typeset keychain_password
    keychain_password="$(<"$password_file")"
    /usr/bin/security unlock-keychain -p "$keychain_password" "$CHIMLO_ACTIVE_SIGNING_KEYCHAIN"
    /usr/bin/security set-key-partition-list \
      -S apple-tool:,apple:,codesign: \
      -s \
      -k "$keychain_password" \
      "$CHIMLO_ACTIVE_SIGNING_KEYCHAIN" >/dev/null

    if ! /usr/bin/security find-identity -v -p codesigning "$CHIMLO_ACTIVE_SIGNING_KEYCHAIN" \
      | /usr/bin/grep -Fq "\"$CHIMLO_ACTIVE_SIGNING_IDENTITY\""; then
      print -u2 "Chimlo's requested signing identity is unavailable or untrusted."
      print -u2 "Identity: $CHIMLO_ACTIVE_SIGNING_IDENTITY"
      print -u2 "Keychain: $CHIMLO_ACTIVE_SIGNING_KEYCHAIN"
      return 1
    fi
  fi

  typeset -ga CHIMLO_CODESIGN_ARGS
  CHIMLO_CODESIGN_ARGS=(--force --sign "$CHIMLO_ACTIVE_SIGNING_IDENTITY")

  if [[ "$CHIMLO_SIGNING_MODE" != "adhoc" ]]; then
    if [[ "$CHIMLO_ACTIVE_SIGNING_IDENTITY" == Developer\ ID\ Application:* ]]; then
      CHIMLO_CODESIGN_ARGS+=(--timestamp --options runtime)
    else
      CHIMLO_CODESIGN_ARGS+=(--timestamp=none)
    fi
  fi

  if [[ -n "$CHIMLO_ACTIVE_SIGNING_KEYCHAIN" ]]; then
    CHIMLO_CODESIGN_ARGS+=(--keychain "$CHIMLO_ACTIVE_SIGNING_KEYCHAIN")
  fi
}

chimlo_codesign_path() {
  /usr/bin/codesign "${CHIMLO_CODESIGN_ARGS[@]}" "$1"
}

chimlo_codesign_path_preserving_entitlements() {
  /usr/bin/codesign \
    "${CHIMLO_CODESIGN_ARGS[@]}" \
    --preserve-metadata=entitlements \
    "$1"
}

chimlo_sign_app_bundle() {
  typeset app_path="$1"
  typeset helper_path="$app_path/Contents/Helpers/chimlo"
  typeset mediaremote_framework_path="$app_path/Contents/Resources/MediaRemoteAdapter/MediaRemoteAdapter.framework"
  typeset sparkle_framework_path="$app_path/Contents/Frameworks/Sparkle.framework"

  if [[ -d "$sparkle_framework_path" ]]; then
    typeset sparkle_version_path="$sparkle_framework_path/Versions/B"
    chimlo_codesign_path "$sparkle_version_path/XPCServices/Installer.xpc"
    chimlo_codesign_path_preserving_entitlements "$sparkle_version_path/XPCServices/Downloader.xpc"
    chimlo_codesign_path "$sparkle_version_path/Autoupdate"
    chimlo_codesign_path "$sparkle_version_path/Updater.app"
    chimlo_codesign_path "$sparkle_framework_path"
  fi

  if [[ -d "$mediaremote_framework_path" ]]; then
    chimlo_codesign_path "$mediaremote_framework_path"
  fi

  if [[ -f "$helper_path" ]]; then
    chimlo_codesign_path "$helper_path"
  fi

  chimlo_codesign_path "$app_path"
  /usr/bin/codesign --verify --deep --strict "$app_path"
}
