#!/bin/bash
# cloudcupcake.sh - Automates "Managing Vault Tokens" Lab
# Author: CloudCupcake 🍰

echo "🚀 Starting Vault in dev mode..."
vault server -dev -dev-root-token-id="root" > /tmp/vault.log 2>&1 &
sleep 5

# Set Vault environment variables
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN="root"
echo "✅ Vault running at $VAULT_ADDR with token $VAULT_TOKEN"

echo "🔑 Checking Vault status..."
vault status

# Create a new token with 1h TTL
echo "🔧 Creating a token with 1h TTL..."
TOKEN1=$(vault token create -format=json -ttl=1h | jq -r '.auth.client_token')
echo "📌 New token: $TOKEN1"

# Lookup token details
echo "🔍 Looking up token details..."
vault token lookup $TOKEN1

# Renew the token
echo "🔄 Renewing token..."
vault token renew $TOKEN1

# Revoke the token
echo "⛔ Revoking token..."
vault token revoke $TOKEN1

# Create a new secret at kv/my-secret
echo "📝 Creating secret at kv/my-secret..."
vault secrets enable -path=kv kv || true
vault kv put kv/my-secret my-value="cloudcupcake-secret"

# Read the secret value
echo "📂 Reading secret value..."
vault kv get -format=json kv/my-secret | jq -r '.data.data["my-value"]' > secret.txt
cat secret.txt

# Detect GCP bucket name
echo "📡 Detecting bucket name..."
BUCKET_NAME=$(gsutil ls | head -n1 | sed 's/gs:\/\///; s/\///')
echo "✅ Bucket: $BUCKET_NAME"

# Upload secret to bucket
echo "☁️ Uploading secret.txt to bucket..."
gsutil cp secret.txt gs://$BUCKET_NAME/secret.txt

echo "🎉 Lab automation complete! Now check progress in Skills Boost."
