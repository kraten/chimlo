#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
source "$SCRIPT_DIR/signing-common.sh"

IDENTITY="${CHIMLO_RELEASE_SIGNING_IDENTITY:-$CHIMLO_RELEASE_SIGNING_IDENTITY_DEFAULT}"
KEYCHAIN_PATH="${CHIMLO_RELEASE_SIGNING_KEYCHAIN:-$CHIMLO_RELEASE_SIGNING_KEYCHAIN_DEFAULT}"
PASSWORD_FILE="${CHIMLO_RELEASE_SIGNING_PASSWORD_FILE:-$CHIMLO_RELEASE_SIGNING_PASSWORD_FILE_DEFAULT}"
PASSWORD_DIR="${PASSWORD_FILE:h}"
TRUST_KEYCHAIN="${CHIMLO_RELEASE_SIGNING_TRUST_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
PUBLIC_CERTIFICATE_PATH="${CHIMLO_RELEASE_PUBLIC_CERTIFICATE_PATH:-$PROJECT_DIR/Packaging/Signing/ChimloRelease.cer}"
P12_PASSWORD_KEYCHAIN="${CHIMLO_RELEASE_P12_PASSWORD_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
P12_PASSWORD_SERVICE="${CHIMLO_RELEASE_P12_PASSWORD_SERVICE:-dev.chimlo.release-signing-backup}"
P12_PASSWORD_ACCOUNT="${CHIMLO_RELEASE_P12_PASSWORD_ACCOUNT:-$(/usr/bin/id -un)}"
BACKUP_PATH="${1:-}"
OPENSSL_BIN="${CHIMLO_OPENSSL_BIN:-$(command -v openssl)}"

if [[ -z "$BACKUP_PATH" || ! -f "$BACKUP_PATH" ]]; then
  print -u2 "Usage: $0 <Chimlo-Release.p12>"
  exit 64
fi

if [[ -z "$OPENSSL_BIN" ]]; then
  print -u2 "OpenSSL is required to restore Chimlo's release signing identity."
  exit 1
fi

if [[ -e "$KEYCHAIN_PATH" || -e "$PASSWORD_FILE" ]]; then
  print -u2 "Refusing to overwrite an existing release keychain or password file."
  print -u2 "$KEYCHAIN_PATH"
  print -u2 "$PASSWORD_FILE"
  exit 1
fi

if [[ -f "$BACKUP_PATH.sha256" ]]; then
  EXPECTED_SHA256="$(/usr/bin/awk 'NR == 1 { print $1 }' "$BACKUP_PATH.sha256")"
  ACTUAL_SHA256="$(/usr/bin/shasum -a 256 "$BACKUP_PATH" | /usr/bin/awk '{ print $1 }')"
  if [[ -z "$EXPECTED_SHA256" || "$EXPECTED_SHA256" != "$ACTUAL_SHA256" ]]; then
    print -u2 "The .p12 backup does not match its SHA-256 checksum."
    exit 1
  fi
fi

if [[ "${CHIMLO_USE_STORED_RELEASE_P12_PASSWORD:-0}" == "1" ]]; then
  P12_PASSWORD="$(/usr/bin/security find-generic-password \
    -w \
    -a "$P12_PASSWORD_ACCOUNT" \
    -s "$P12_PASSWORD_SERVICE" \
    "$P12_PASSWORD_KEYCHAIN")"
elif [[ -n "${CHIMLO_RELEASE_P12_PASSWORD:-}" ]]; then
  P12_PASSWORD="$CHIMLO_RELEASE_P12_PASSWORD"
else
  read -r -s "P12_PASSWORD?Password for the encrypted .p12 backup: "
  print
fi

umask 077
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/chimlo-release-restore.XXXXXX")"
PUBLIC_CERTIFICATE_PREEXISTED=0
[[ -f "$PUBLIC_CERTIFICATE_PATH" ]] && PUBLIC_CERTIFICATE_PREEXISTED=1
RESTORE_COMPLETE=0
TRUST_ADDED=0

cleanup_restore() {
  typeset exit_code=$?
  trap - EXIT
  if (( ! RESTORE_COMPLETE )); then
    if (( TRUST_ADDED )); then
      /usr/bin/security remove-trusted-cert "$CERTIFICATE_PATH" >/dev/null 2>&1 || true
    fi
    if [[ -e "$KEYCHAIN_PATH" ]]; then
      /usr/bin/security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
    fi
    rm -f "$PASSWORD_FILE"
    if (( ! PUBLIC_CERTIFICATE_PREEXISTED )); then
      rm -f "$PUBLIC_CERTIFICATE_PATH"
    fi
  fi
  rm -rf "$TEMP_DIR"
  exit "$exit_code"
}
trap cleanup_restore EXIT

P12_PASSWORD_FILE="$TEMP_DIR/p12-password"
CERTIFICATE_PATH="$TEMP_DIR/release-certificate.pem"
CERTIFICATE_DER_PATH="$TEMP_DIR/release-certificate.cer"
KEYCHAIN_PASSWORD="$($OPENSSL_BIN rand -hex 32)"
typeset -a PKCS12_COMPATIBILITY_ARGS

print -rn -- "$P12_PASSWORD" > "$P12_PASSWORD_FILE"

if "$OPENSSL_BIN" pkcs12 -help 2>&1 | /usr/bin/grep -Fq -- '-legacy'; then
  PKCS12_COMPATIBILITY_ARGS=(-legacy)
else
  PKCS12_COMPATIBILITY_ARGS=()
fi

"$OPENSSL_BIN" pkcs12 \
  "${PKCS12_COMPATIBILITY_ARGS[@]}" \
  -in "$BACKUP_PATH" \
  -passin "file:$P12_PASSWORD_FILE" \
  -clcerts \
  -nokeys \
  -out "$CERTIFICATE_PATH"

"$OPENSSL_BIN" x509 \
  -in "$CERTIFICATE_PATH" \
  -outform DER \
  -out "$CERTIFICATE_DER_PATH"

if [[ -f "$PUBLIC_CERTIFICATE_PATH" ]] \
  && ! /usr/bin/cmp -s "$PUBLIC_CERTIFICATE_PATH" "$CERTIFICATE_DER_PATH"; then
  print -u2 "The backup certificate does not match Chimlo's committed public certificate."
  print -u2 "$PUBLIC_CERTIFICATE_PATH"
  exit 1
fi

/usr/bin/security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
/usr/bin/security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
/usr/bin/security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

mkdir -p "$PASSWORD_DIR"
print -rn -- "$KEYCHAIN_PASSWORD" > "$PASSWORD_FILE"
chmod 600 "$PASSWORD_FILE"

/usr/bin/security import "$BACKUP_PATH" \
  -k "$KEYCHAIN_PATH" \
  -f pkcs12 \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null

/usr/bin/security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN_PATH" >/dev/null

KEYCHAIN_LIST="$(/usr/bin/security list-keychains -d user \
  | /usr/bin/sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//')"
typeset -a KEYCHAINS
KEYCHAINS=("${(@f)KEYCHAIN_LIST}")
if (( ${KEYCHAINS[(Ie)$KEYCHAIN_PATH]} == 0 )); then
  /usr/bin/security list-keychains -d user -s "${KEYCHAINS[@]}" "$KEYCHAIN_PATH"
fi

/usr/bin/security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$TRUST_KEYCHAIN" \
  "$CERTIFICATE_PATH"
TRUST_ADDED=1

if ! /usr/bin/security find-identity -v -p codesigning "$KEYCHAIN_PATH" \
  | /usr/bin/grep -Fq "\"$IDENTITY\""; then
  print -u2 "The restored identity is not valid for code signing."
  exit 1
fi

if [[ ! -f "$PUBLIC_CERTIFICATE_PATH" ]]; then
  mkdir -p "${PUBLIC_CERTIFICATE_PATH:h}"
  cp "$CERTIFICATE_DER_PATH" "$PUBLIC_CERTIFICATE_PATH"
  chmod 644 "$PUBLIC_CERTIFICATE_PATH"
fi

unset P12_PASSWORD

CERTIFICATE_SHA256="$(/usr/bin/shasum -a 256 "$CERTIFICATE_DER_PATH" | /usr/bin/awk '{ print $1 }')"
RESTORE_COMPLETE=1
print "Restored the Chimlo Release signing identity."
print "Identity: $IDENTITY"
print "Keychain: $KEYCHAIN_PATH"
print "Certificate SHA-256: $CERTIFICATE_SHA256"
