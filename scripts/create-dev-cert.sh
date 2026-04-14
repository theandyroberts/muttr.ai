#!/bin/bash
# Creates a self-signed code signing certificate for Muttr development.
# This keeps the signature stable across rebuilds so macOS permissions persist.
# Run once: ./scripts/create-dev-cert.sh

CERT_NAME="Muttr Development"

# Check if it already exists
if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "Certificate '$CERT_NAME' already exists."
    exit 0
fi

# Create self-signed certificate
cat > /tmp/muttr-cert.conf <<EOF
[ req ]
default_bits       = 2048
distinguished_name = req_dn
prompt             = no
[ req_dn ]
CN = $CERT_NAME
[ codesign ]
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
EOF

# Generate key and certificate
openssl req -x509 -newkey rsa:2048 -keyout /tmp/muttr-key.pem -out /tmp/muttr-cert.pem \
    -days 3650 -nodes -config /tmp/muttr-cert.conf -extensions codesign 2>/dev/null

# Import into keychain and trust for code signing
security import /tmp/muttr-cert.pem -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign 2>/dev/null
security import /tmp/muttr-key.pem -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign 2>/dev/null

# Clean up
rm -f /tmp/muttr-cert.pem /tmp/muttr-key.pem /tmp/muttr-cert.conf

echo ""
echo "Certificate '$CERT_NAME' created."
echo ""
echo "IMPORTANT: Open Keychain Access, find '$CERT_NAME', double-click it,"
echo "expand 'Trust', and set 'Code Signing' to 'Always Trust'."
echo ""
echo "Then verify with: security find-identity -v -p codesigning"
