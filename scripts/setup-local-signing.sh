#!/bin/zsh
set -euo pipefail

IDENTITY_NAME="Telepathy Local Development"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
AVAILABLE_IDENTITIES="$(security find-identity -v -p codesigning "$LOGIN_KEYCHAIN" || true)"

if grep -Fq "\"$IDENTITY_NAME\"" <<< "$AVAILABLE_IDENTITIES"
then
  echo "$IDENTITY_NAME is already available."
  exit 0
fi

TEMPORARY_DIRECTORY="$(mktemp -d /tmp/telepathy-signing.XXXXXX)"
TEMPORARY_PASSWORD="$(openssl rand -hex 32)"
CERTIFICATE="$TEMPORARY_DIRECTORY/certificate.pem"
PRIVATE_KEY="$TEMPORARY_DIRECTORY/private-key.pem"
IDENTITY="$TEMPORARY_DIRECTORY/identity.p12"

cleanup() {
  rm -R -- "$TEMPORARY_DIRECTORY"
}
trap cleanup EXIT

openssl req \
  -new \
  -newkey rsa:2048 \
  -x509 \
  -sha256 \
  -days 3650 \
  -nodes \
  -subj "/CN=$IDENTITY_NAME/O=Telepathy Development/C=US" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,digitalSignature,keyCertSign" \
  -addext "extendedKeyUsage=codeSigning" \
  -keyout "$PRIVATE_KEY" \
  -out "$CERTIFICATE" \
  >/dev/null 2>&1

openssl pkcs12 \
  -export \
  -inkey "$PRIVATE_KEY" \
  -in "$CERTIFICATE" \
  -out "$IDENTITY" \
  -passout "pass:$TEMPORARY_PASSWORD"

security import "$IDENTITY" \
  -k "$LOGIN_KEYCHAIN" \
  -f pkcs12 \
  -P "$TEMPORARY_PASSWORD" \
  -T /usr/bin/codesign \
  >/dev/null
security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$LOGIN_KEYCHAIN" \
  "$CERTIFICATE"

AVAILABLE_IDENTITIES="$(security find-identity -v -p codesigning "$LOGIN_KEYCHAIN" || true)"
if ! grep -Fq "\"$IDENTITY_NAME\"" <<< "$AVAILABLE_IDENTITIES"
then
  echo "The signing identity was imported but is not available to codesign." >&2
  exit 1
fi

echo "Created $IDENTITY_NAME in the login Keychain."
echo "Future Telepathy installations will reuse this identity automatically."
