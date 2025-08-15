#!/bin/bash
set -e

# Stop Vault if running
pkill vault || true

# Unset existing Vault token to avoid conflicts
unset VAULT_TOKEN

# Download policies
curl -O https://raw.githubusercontent.com/ChanduCharanSample/Level-1-Application-Design-and-Delivery---2025/main/Interacting%20with%20Vault%20policies/cloudcupcake.sh

# Start Vault in dev mode
vault server -dev -dev-root-token-id=root > /tmp/vault.log 2>&1 &
sleep 5

# Export Vault address and root token
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'

# Verify Vault is running
vault status

# Enable secrets engine
vault secrets enable -path=secret kv

# Upload policies
vault policy write example-policy - <<EOF
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF

# Make sure userpass is clean before enabling
vault auth disable userpass || true
vault auth enable userpass

# Create a test user
vault write auth/userpass/users/admin \
    password="password" \
    policies="example-policy"

echo "✅ All policies setup and userpass auth enabled successfully!"
