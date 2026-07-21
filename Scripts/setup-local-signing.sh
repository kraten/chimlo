#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/signing-common.sh"

IDENTITY="$CHIMLO_LOCAL_SIGNING_IDENTITY_DEFAULT"
ROOT_IDENTITY="Chimlo Local Signing Root"
KEYCHAIN_PATH="$CHIMLO_LOCAL_SIGNING_KEYCHAIN_DEFAULT"
TRUST_KEYCHAIN="${CHIMLO_LOCAL_SIGNING_TRUST_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
PASSWORD_FILE="$CHIMLO_LOCAL_SIGNING_PASSWORD_FILE_DEFAULT"
PASSWORD_DIR="${PASSWORD_FILE:h}"
OPENSSL_BIN="${CHIMLO_OPENSSL_BIN:-$(command -v openssl)}"

if [[ -z "$OPENSSL_BIN" ]]; then
  print -u2 "OpenSSL is required to create Chimlo's local signing identity."
  exit 1
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/chimlo-local-signing.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

repair_trust_and_validate() {
  typeset keychain_password="$1"
  typeset certificate_path="$TEMP_DIR/identity.pem"
  typeset keychain_list
  typeset -a keychains

  /usr/bin/security unlock-keychain -p "$keychain_password" "$KEYCHAIN_PATH"
  /usr/bin/security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$keychain_password" \
    "$KEYCHAIN_PATH" >/dev/null

  keychain_list="$(/usr/bin/security list-keychains -d user \
    | /usr/bin/sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//')"
  keychains=("${(@f)keychain_list}")
  if (( ${keychains[(Ie)$KEYCHAIN_PATH]} == 0 )); then
    /usr/bin/security list-keychains -d user -s "${keychains[@]}" "$KEYCHAIN_PATH"
  fi

  if /usr/bin/security find-identity -v -p codesigning "$KEYCHAIN_PATH" \
    | /usr/bin/grep -Fq "\"$IDENTITY\""; then
    return 0
  fi

  if ! /usr/bin/security find-certificate -c "$ROOT_IDENTITY" -p "$KEYCHAIN_PATH" > "$certificate_path"; then
    return 1
  fi

  /usr/bin/security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$TRUST_KEYCHAIN" \
    "$certificate_path"

  /usr/bin/security find-identity -v -p codesigning "$KEYCHAIN_PATH" \
    | /usr/bin/grep -Fq "\"$IDENTITY\""
}

if [[ -f "$KEYCHAIN_PATH" || -f "$PASSWORD_FILE" ]]; then
  if [[ ! -f "$KEYCHAIN_PATH" || ! -f "$PASSWORD_FILE" ]]; then
    print -u2 "Chimlo found an incomplete signing setup."
    print -u2 "Expected both:"
    print -u2 "  $KEYCHAIN_PATH"
    print -u2 "  $PASSWORD_FILE"
    print -u2 "No existing keychain or password file was changed."
    exit 1
  fi

  EXISTING_PASSWORD="$(<"$PASSWORD_FILE")"
  if repair_trust_and_validate "$EXISTING_PASSWORD"; then
    print "Chimlo's local signing identity is ready."
    print "$KEYCHAIN_PATH"
    exit 0
  fi

  print -u2 "The existing Chimlo signing keychain could not be repaired."
  print -u2 "No existing keychain or password file was removed."
  exit 1
fi

umask 077
KEYCHAIN_PASSWORD="$($OPENSSL_BIN rand -hex 32)"

/usr/bin/security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
/usr/bin/security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
/usr/bin/security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

mkdir -p "$PASSWORD_DIR"
print -rn -- "$KEYCHAIN_PASSWORD" > "$PASSWORD_FILE"
chmod 600 "$PASSWORD_FILE"

ROOT_CERTIFICATE_PATH="$TEMP_DIR/root.pem"
ROOT_PRIVATE_KEY_PATH="$TEMP_DIR/root-key.pem"
CERTIFICATE_PATH="$TEMP_DIR/identity.pem"
CERTIFICATE_REQUEST_PATH="$TEMP_DIR/identity.csr"
CERTIFICATE_EXTENSIONS_PATH="$TEMP_DIR/identity-extensions.cnf"
PRIVATE_KEY_PATH="$TEMP_DIR/identity-key.pem"
PKCS12_PATH="$TEMP_DIR/identity.p12"
typeset -a PKCS12_COMPATIBILITY_ARGS

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
  -days 3650 \
  -subj "/CN=$ROOT_IDENTITY/O=Chimlo/OU=Local Code Signing" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -addext "subjectKeyIdentifier=hash" \
  -keyout "$ROOT_PRIVATE_KEY_PATH" \
  -out "$ROOT_CERTIFICATE_PATH"

"$OPENSSL_BIN" req \
  -new \
  -newkey rsa:3072 \
  -nodes \
  -sha256 \
  -subj "/CN=$IDENTITY/O=Chimlo/OU=Local Code Signing" \
  -keyout "$PRIVATE_KEY_PATH" \
  -out "$CERTIFICATE_REQUEST_PATH"

printf '%s\n' \
  '[chimlo_code_signing]' \
  'basicConstraints=critical,CA:FALSE' \
  'keyUsage=critical,digitalSignature' \
  'extendedKeyUsage=critical,codeSigning' \
  'subjectKeyIdentifier=hash' \
  'authorityKeyIdentifier=keyid,issuer' \
  > "$CERTIFICATE_EXTENSIONS_PATH"

"$OPENSSL_BIN" x509 \
  -req \
  -in "$CERTIFICATE_REQUEST_PATH" \
  -CA "$ROOT_CERTIFICATE_PATH" \
  -CAkey "$ROOT_PRIVATE_KEY_PATH" \
  -set_serial "0x$($OPENSSL_BIN rand -hex 16)" \
  -days 3650 \
  -sha256 \
  -extfile "$CERTIFICATE_EXTENSIONS_PATH" \
  -extensions chimlo_code_signing \
  -out "$CERTIFICATE_PATH"

"$OPENSSL_BIN" pkcs12 \
  -export \
  "${PKCS12_COMPATIBILITY_ARGS[@]}" \
  -name "$IDENTITY" \
  -inkey "$PRIVATE_KEY_PATH" \
  -in "$CERTIFICATE_PATH" \
  -certfile "$ROOT_CERTIFICATE_PATH" \
  -passout "pass:$KEYCHAIN_PASSWORD" \
  -out "$PKCS12_PATH"

/usr/bin/security import "$PKCS12_PATH" \
  -k "$KEYCHAIN_PATH" \
  -f pkcs12 \
  -P "$KEYCHAIN_PASSWORD" \
  -x \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null

if ! repair_trust_and_validate "$KEYCHAIN_PASSWORD"; then
  print -u2 "The identity was created, but macOS did not trust it for code signing."
  print -u2 "Run this command again to retry the trust step."
  exit 1
fi

print "Created Chimlo's dedicated local signing identity."
print "$KEYCHAIN_PATH"
