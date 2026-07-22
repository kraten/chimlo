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
CERTIFICATE_DAYS="${CHIMLO_RELEASE_CERTIFICATE_DAYS:-7300}"
P12_PASSWORD_KEYCHAIN="${CHIMLO_RELEASE_P12_PASSWORD_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
P12_PASSWORD_SERVICE="${CHIMLO_RELEASE_P12_PASSWORD_SERVICE:-dev.chimlo.release-signing-backup}"
P12_PASSWORD_ACCOUNT="${CHIMLO_RELEASE_P12_PASSWORD_ACCOUNT:-$(/usr/bin/id -un)}"
BACKUP_ONE="${1:-}"
BACKUP_TWO="${2:-}"
OPENSSL_BIN="${CHIMLO_OPENSSL_BIN:-$(command -v openssl)}"

if [[ -z "$BACKUP_ONE" || -z "$BACKUP_TWO" ]]; then
  print -u2 "Usage: $0 <first-backup.p12> <second-backup.p12>"
  print -u2 "Both destinations must be absolute paths on separate backup devices."
  exit 64
fi

if [[ -z "$OPENSSL_BIN" ]]; then
  print -u2 "OpenSSL is required to create Chimlo's release signing identity."
  exit 1
fi

if [[ "$BACKUP_ONE" != /* || "$BACKUP_TWO" != /* ]]; then
  print -u2 "Both backup destinations must be absolute paths."
  exit 1
fi

if [[ "${BACKUP_ONE:e:l}" != "p12" || "${BACKUP_TWO:e:l}" != "p12" ]]; then
  print -u2 "Both backup destinations must end in .p12."
  exit 1
fi

if [[ "$BACKUP_ONE" == "$BACKUP_TWO" ]]; then
  print -u2 "The two backup destinations must be different."
  exit 1
fi

for backup_path in "$BACKUP_ONE" "$BACKUP_TWO"; do
  if [[ -e "$backup_path" || -e "$backup_path.sha256" ]]; then
    print -u2 "Refusing to overwrite an existing backup or checksum: $backup_path"
    exit 1
  fi
  if [[ ! -d "${backup_path:h}" || ! -w "${backup_path:h}" ]]; then
    print -u2 "Backup directory is missing or not writable: ${backup_path:h}"
    exit 1
  fi
done

FIRST_DEVICE="$(/usr/bin/stat -f '%d' "${BACKUP_ONE:h}")"
SECOND_DEVICE="$(/usr/bin/stat -f '%d' "${BACKUP_TWO:h}")"
if [[ "$FIRST_DEVICE" == "$SECOND_DEVICE" ]]; then
  if [[ "${CHIMLO_STAGE_SECOND_BACKUP_FOR_CLOUD:-0}" == "1" ]]; then
    print -u2 "Warning: the second encrypted backup is temporarily staged on the same disk."
    print -u2 "Upload it to separate cloud storage, verify it, then delete the staged copy."
  elif [[ "${CHIMLO_ALLOW_SAME_BACKUP_DEVICE:-0}" != "1" ]]; then
    print -u2 "Both backup paths are on the same filesystem."
    print -u2 "Use separate devices, or explicitly stage the second encrypted copy for cloud upload."
    exit 1
  fi
fi

if [[ -e "$KEYCHAIN_PATH" || -e "$PASSWORD_FILE" ]]; then
  print -u2 "A Chimlo Release signing setup already exists. Nothing was changed."
  print -u2 "$KEYCHAIN_PATH"
  print -u2 "$PASSWORD_FILE"
  exit 1
fi

if [[ -e "$PUBLIC_CERTIFICATE_PATH" ]]; then
  print -u2 "Refusing to replace the committed public release certificate:"
  print -u2 "$PUBLIC_CERTIFICATE_PATH"
  exit 1
fi

P12_PASSWORD_WAS_GENERATED=0
if [[ "${CHIMLO_GENERATE_RELEASE_P12_PASSWORD:-0}" == "1" ]]; then
  if /usr/bin/security find-generic-password \
    -a "$P12_PASSWORD_ACCOUNT" \
    -s "$P12_PASSWORD_SERVICE" \
    "$P12_PASSWORD_KEYCHAIN" >/dev/null 2>&1; then
    print -u2 "Refusing to replace an existing release-backup password in Keychain."
    print -u2 "Service: $P12_PASSWORD_SERVICE"
    exit 1
  fi
  P12_PASSWORD="$($OPENSSL_BIN rand -base64 36 | /usr/bin/tr -d '\n')"
  P12_PASSWORD_WAS_GENERATED=1
elif [[ -n "${CHIMLO_RELEASE_P12_PASSWORD:-}" ]]; then
  P12_PASSWORD="$CHIMLO_RELEASE_P12_PASSWORD"
else
  read -r -s "P12_PASSWORD?Choose a password for both encrypted .p12 backups: "
  print
  read -r -s "P12_PASSWORD_CONFIRM?Repeat the .p12 backup password: "
  print
  if [[ "$P12_PASSWORD" != "$P12_PASSWORD_CONFIRM" ]]; then
    print -u2 "The backup passwords do not match."
    exit 1
  fi
fi

if (( ${#P12_PASSWORD} < 16 )); then
  print -u2 "The .p12 backup password must contain at least 16 characters."
  exit 1
fi

umask 077
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/chimlo-release-signing.XXXXXX")"
SETUP_COMPLETE=0
TRUST_ADDED=0
GENERATED_PASSWORD_STORED=0

cleanup_setup() {
  typeset exit_code=$?
  trap - EXIT
  if (( ! SETUP_COMPLETE )); then
    if (( TRUST_ADDED )); then
      /usr/bin/security remove-trusted-cert "$CERTIFICATE_PATH" >/dev/null 2>&1 || true
    fi
    if (( GENERATED_PASSWORD_STORED )); then
      /usr/bin/security delete-generic-password \
        -a "$P12_PASSWORD_ACCOUNT" \
        -s "$P12_PASSWORD_SERVICE" \
        "$P12_PASSWORD_KEYCHAIN" >/dev/null 2>&1 || true
    fi
    if [[ -e "$KEYCHAIN_PATH" ]]; then
      /usr/bin/security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
    fi
    rm -f "$PASSWORD_FILE" "$PUBLIC_CERTIFICATE_PATH"
  fi
  rm -rf "$TEMP_DIR"
  exit "$exit_code"
}
trap cleanup_setup EXIT

PRIVATE_KEY_PATH="$TEMP_DIR/release-key.pem"
CERTIFICATE_PATH="$TEMP_DIR/release-certificate.pem"
PKCS12_PATH="$TEMP_DIR/Chimlo-Release.p12"
P12_PASSWORD_FILE="$TEMP_DIR/p12-password"
KEYCHAIN_PASSWORD="$($OPENSSL_BIN rand -hex 32)"
typeset -a PKCS12_COMPATIBILITY_ARGS

print -rn -- "$P12_PASSWORD" > "$P12_PASSWORD_FILE"

if "$OPENSSL_BIN" pkcs12 -help 2>&1 | /usr/bin/grep -Fq -- '-legacy'; then
  PKCS12_COMPATIBILITY_ARGS=(-legacy)
else
  PKCS12_COMPATIBILITY_ARGS=()
fi

"$OPENSSL_BIN" req \
  -new \
  -newkey rsa:3072 \
  -nodes \
  -x509 \
  -sha256 \
  -days "$CERTIFICATE_DAYS" \
  -subj "/CN=$IDENTITY/O=Chimlo/OU=Release Code Signing" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
  -addext "keyUsage=critical,digitalSignature,keyCertSign,cRLSign" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "subjectKeyIdentifier=hash" \
  -keyout "$PRIVATE_KEY_PATH" \
  -out "$CERTIFICATE_PATH"

"$OPENSSL_BIN" pkcs12 \
  -export \
  "${PKCS12_COMPATIBILITY_ARGS[@]}" \
  -name "$IDENTITY" \
  -inkey "$PRIVATE_KEY_PATH" \
  -in "$CERTIFICATE_PATH" \
  -passout "file:$P12_PASSWORD_FILE" \
  -out "$PKCS12_PATH"

"$OPENSSL_BIN" pkcs12 \
  "${PKCS12_COMPATIBILITY_ARGS[@]}" \
  -in "$PKCS12_PATH" \
  -passin "file:$P12_PASSWORD_FILE" \
  -noout

P12_SHA256="$(/usr/bin/shasum -a 256 "$PKCS12_PATH" | /usr/bin/awk '{print $1}')"
for backup_path in "$BACKUP_ONE" "$BACKUP_TWO"; do
  /usr/bin/ditto "$PKCS12_PATH" "$backup_path"
  chmod 600 "$backup_path" 2>/dev/null || true
  print -r -- "$P12_SHA256  ${backup_path:t}" > "$backup_path.sha256"
  BACKUP_SHA256="$(/usr/bin/shasum -a 256 "$backup_path" | /usr/bin/awk '{print $1}')"
  if [[ "$BACKUP_SHA256" != "$P12_SHA256" ]]; then
    print -u2 "Backup verification failed: $backup_path"
    exit 1
  fi
done

/usr/bin/security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
/usr/bin/security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
/usr/bin/security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

mkdir -p "$PASSWORD_DIR"
print -rn -- "$KEYCHAIN_PASSWORD" > "$PASSWORD_FILE"
chmod 600 "$PASSWORD_FILE"

/usr/bin/security import "$PKCS12_PATH" \
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
  print -u2 "The Chimlo Release identity was created but is not valid for code signing."
  exit 1
fi

if (( P12_PASSWORD_WAS_GENERATED )); then
  /usr/bin/security add-generic-password \
    -U \
    -a "$P12_PASSWORD_ACCOUNT" \
    -s "$P12_PASSWORD_SERVICE" \
    -w "$P12_PASSWORD" \
    "$P12_PASSWORD_KEYCHAIN" >/dev/null
  GENERATED_PASSWORD_STORED=1
fi

mkdir -p "${PUBLIC_CERTIFICATE_PATH:h}"
"$OPENSSL_BIN" x509 \
  -in "$CERTIFICATE_PATH" \
  -outform DER \
  -out "$PUBLIC_CERTIFICATE_PATH"
chmod 644 "$PUBLIC_CERTIFICATE_PATH"

CERTIFICATE_SHA256="$($OPENSSL_BIN x509 -in "$CERTIFICATE_PATH" -noout -fingerprint -sha256 \
  | /usr/bin/sed 's/^sha256 Fingerprint=//; s/://g')"
CERTIFICATE_EXPIRY="$($OPENSSL_BIN x509 -in "$CERTIFICATE_PATH" -noout -enddate \
  | /usr/bin/sed 's/^notAfter=//')"

unset P12_PASSWORD
unset P12_PASSWORD_CONFIRM 2>/dev/null || true

SETUP_COMPLETE=1

print "Created the exportable Chimlo Release signing identity."
print "Identity: $IDENTITY"
print "Keychain: $KEYCHAIN_PATH"
print "Public certificate: $PUBLIC_CERTIFICATE_PATH"
print "Certificate SHA-256: $CERTIFICATE_SHA256"
print "Certificate expires: $CERTIFICATE_EXPIRY"
print "Verified backup: $BACKUP_ONE"
print "Verified backup: $BACKUP_TWO"
if (( P12_PASSWORD_WAS_GENERATED )); then
  print "Backup password saved in Keychain service: $P12_PASSWORD_SERVICE"
  print "Copy that password to a separate password manager before relying on the offline backups."
fi
