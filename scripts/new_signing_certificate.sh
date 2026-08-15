#!/usr/bin/env bash
# Give CI a distribution certificate of its own, in two passes.
#
#   scripts/new_signing_certificate.sh              generate the private key + request
#   scripts/new_signing_certificate.sh <certificate>   turn the signed result into secrets
#
# The private key is created here and never leaves this machine: the repository
# is public, so a key that reached a workflow log would be readable by anyone.
# Only the request travels, and it carries nothing but the public half.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNING_DIR="$ROOT_DIR/build/signing"
KEY_PATH="$SIGNING_DIR/distribution.key"
CSR_PATH="$SIGNING_DIR/distribution.csr"
P12_PATH="$SIGNING_DIR/distribution.p12"

if ! command -v gh > /dev/null 2>&1; then
  echo "This needs the gh CLI: brew install gh"
  exit 1
fi

# Pass one: make the key pair, hand back a request for CI to sign.
if [[ $# -eq 0 ]]; then
  if [[ -f "$KEY_PATH" ]]; then
    echo "A private key already exists at $KEY_PATH"
    echo
    echo "Delete it only if you are starting over — a certificate signed against"
    echo "it is useless without it, and Apple counts that dead certificate"
    echo "against the account limit until it expires."
    exit 1
  fi

  mkdir -p "$SIGNING_DIR"
  # /usr/bin/openssl throughout, never whatever `openssl` resolves to. Homebrew
  # OpenSSL 3 protects a .p12 with an algorithm `security import` cannot verify,
  # and it fails on the runner as "MAC verification failed (wrong password?)",
  # which sends you hunting for a password problem that does not exist.
  /usr/bin/openssl req -new -newkey rsa:2048 -nodes \
    -keyout "$KEY_PATH" \
    -out "$CSR_PATH" \
    -subj "/CN=IronLog CI/O=IronLog/C=US" \
    2> /dev/null
  chmod 600 "$KEY_PATH"

  echo "Private key written to $KEY_PATH — it stays here, do not send it anywhere."
  echo
  echo "Now have CI sign the request:"
  echo
  echo "  gh workflow run signing-certificate.yml -f action=create \\"
  echo "    -f csr=$(base64 < "$CSR_PATH" | tr -d '\n')"
  echo
  echo "Then open the run, copy the line between the COPY markers, and pass it back:"
  echo
  echo "  scripts/new_signing_certificate.sh <certificate>"
  exit 0
fi

# Pass two: pair the signed certificate with the key that was kept back.
if [[ ! -f "$KEY_PATH" ]]; then
  echo "No private key at $KEY_PATH"
  echo "Run this with no arguments first — a certificate cannot sign without it."
  exit 1
fi

certificate="$1"
if [[ -f "$certificate" ]]; then
  certificate="$(cat "$certificate")"
fi

printf '%s' "$certificate" | tr -d '\n' | base64 --decode > "$SIGNING_DIR/distribution.cer" || {
  echo "That did not decode. Pass the base64 line from the workflow log, or a file holding it."
  exit 1
}

# Apple returns DER; the bundler wants PEM.
/usr/bin/openssl x509 -inform DER -in "$SIGNING_DIR/distribution.cer" -out "$SIGNING_DIR/distribution.pem"
echo "Certificate:"
/usr/bin/openssl x509 -in "$SIGNING_DIR/distribution.pem" -noout -subject -enddate | sed 's/^/  /'

# Verify the two halves actually belong together before shipping them, since a
# mismatch shows up much later as an opaque codesign failure on the runner.
key_modulus="$(/usr/bin/openssl rsa -in "$KEY_PATH" -noout -modulus 2> /dev/null)"
certificate_modulus="$(/usr/bin/openssl x509 -in "$SIGNING_DIR/distribution.pem" -noout -modulus)"
if [[ "$key_modulus" != "$certificate_modulus" ]]; then
  echo
  echo "This certificate was not signed against $KEY_PATH — they do not match."
  echo "It probably came from an older request. Start over with no arguments."
  exit 1
fi

password="$(uuidgen)"
/usr/bin/openssl pkcs12 -export \
  -inkey "$KEY_PATH" \
  -in "$SIGNING_DIR/distribution.pem" \
  -name "IronLog CI distribution" \
  -out "$P12_PATH" \
  -passout pass:"$password"
chmod 600 "$P12_PATH"

base64 < "$P12_PATH" | tr -d '\n' | gh secret set SIGNING_CERTIFICATE_P12
printf '%s' "$password" | gh secret set SIGNING_CERTIFICATE_PASSWORD

echo
echo "Set SIGNING_CERTIFICATE_P12 and SIGNING_CERTIFICATE_PASSWORD."
echo "Keep $P12_PATH — replacing this certificate later needs it, and build/ is"
echo "not tracked by git."
