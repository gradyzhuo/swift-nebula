#!/usr/bin/env bash
# gen-test-certs.sh — generates self-signed certs for integration tests.
# FOR TESTING ONLY. Do not use in production.
set -euo pipefail

OUTPUT="$(cd "$(dirname "$0")/.." && pwd)/Tests/Fixtures"
mkdir -p "$OUTPUT"

echo "Generating test certificates in $OUTPUT ..."

# --- Trusted CA ---
openssl genrsa -out "$OUTPUT/ca.key" 2048 2>/dev/null
openssl req -new -x509 -days 3650 -key "$OUTPUT/ca.key"     -out "$OUTPUT/ca.crt"     -subj "/CN=Nebula Test CA/O=NebulaTest" 2>/dev/null

# --- Server identity ---
openssl genrsa -out "$OUTPUT/server.key" 2048 2>/dev/null
openssl req -new -key "$OUTPUT/server.key"     -out "$OUTPUT/server.csr" -subj "/CN=localhost/O=NebulaTest" 2>/dev/null
openssl x509 -req -days 3650     -in "$OUTPUT/server.csr"     -CA "$OUTPUT/ca.crt" -CAkey "$OUTPUT/ca.key" -CAcreateserial     -out "$OUTPUT/server.crt" 2>/dev/null

# --- Client identity (trusted) ---
openssl genrsa -out "$OUTPUT/client.key" 2048 2>/dev/null
openssl req -new -key "$OUTPUT/client.key"     -out "$OUTPUT/client.csr" -subj "/CN=nebula-client/O=NebulaTest" 2>/dev/null
openssl x509 -req -days 3650     -in "$OUTPUT/client.csr"     -CA "$OUTPUT/ca.crt" -CAkey "$OUTPUT/ca.key" -CAcreateserial     -out "$OUTPUT/client.crt" 2>/dev/null

# --- Rogue CA (not trusted by server) ---
openssl genrsa -out "$OUTPUT/rogue-ca.key" 2048 2>/dev/null
openssl req -new -x509 -days 3650 -key "$OUTPUT/rogue-ca.key"     -out "$OUTPUT/rogue-ca.crt"     -subj "/CN=Rogue CA/O=Rogue" 2>/dev/null

# --- Rogue client cert (signed by rogue CA) ---
openssl genrsa -out "$OUTPUT/rogue-client.key" 2048 2>/dev/null
openssl req -new -key "$OUTPUT/rogue-client.key"     -out "$OUTPUT/rogue-client.csr" -subj "/CN=rogue/O=Rogue" 2>/dev/null
openssl x509 -req -days 3650     -in "$OUTPUT/rogue-client.csr"     -CA "$OUTPUT/rogue-ca.crt" -CAkey "$OUTPUT/rogue-ca.key" -CAcreateserial     -out "$OUTPUT/rogue-client.crt" 2>/dev/null

# Clean up CSRs and serials
rm -f "$OUTPUT/"*.csr "$OUTPUT/"*.srl

echo "Done. Files written to $OUTPUT:"
ls "$OUTPUT"
