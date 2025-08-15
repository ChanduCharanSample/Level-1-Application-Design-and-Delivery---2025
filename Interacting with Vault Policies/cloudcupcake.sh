#!/bin/bash
set -e

echo "=== Installing Vault ==="
sudo apt update && sudo apt install -y curl gnupg lsb-release
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install -y vault

echo "=== Starting Vault Dev Server ==="
pkill vault || true
nohup vault server -dev > vault.log 2>&1 &
sleep 3

export VAULT_ADDR='http://127.0.0.1:8200'
ROOT_TOKEN=$(grep 'Root Token:' vault.log | awk '{print $3}')
echo "Root token: $ROOT_TOKEN"

vault login "$ROOT_TOKEN"

echo "=== Enabling Userpass Auth ==="
vault auth enable userpass || true

echo "=== Creating Users ==="
vault write auth/userpass/users/admin password="admin123" policies="admin"
vault write auth/userpass/users/app-dev password="appdev123" policies="appdev"
vault write auth/userpass/users/security password="security123" policies="security"

echo "=== Writing Policies ==="

# Admin policy
tee admin-policy.hcl <<EOF
path "secret/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/policies/acl/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/mounts/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/mounts" { capabilities = ["read"] }
path "sys/auth/*" { capabilities = ["create","read","update","delete","list","sudo"] }
EOF

# App Dev policy
tee appdev-policy.hcl <<EOF
path "secret/+/appdev/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/mounts/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/mounts" { capabilities = ["read"] }
EOF

# Security policy
tee security-policy.hcl <<EOF
path "secret/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/policies/acl/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/mounts/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/mounts" { capabilities = ["read"] }
path "secret/admin/*" { capabilities = ["deny"] }
EOF

# Demo policy (read-only access)
tee demo-policy.hcl <<EOF
path "secret/*" { capabilities = ["read","list"] }
EOF

# Example policy (create/read/list)
tee example-policy.hcl <<EOF
path "secret/example/*" { capabilities = ["create","read","list"] }
EOF

echo "=== Applying Policies ==="
vault policy write admin admin-policy.hcl
vault policy write appdev appdev-policy.hcl
vault policy write security security-policy.hcl
vault policy write demo-policy demo-policy.hcl
vault policy write example-policy example-policy.hcl

echo "=== Creating Secrets ==="
vault kv put secret/security/first username=password
vault kv put secret/security/second username=password
vault kv put secret/appdev/first username=password
vault kv put secret/appdev/beta-app/second username=password
vault kv put secret/admin/first admin=password
vault kv put secret/admin/supersecret/second admin=password
vault kv put secret/example/test key=value

echo "=== Managing Example Policy via CLI ==="
# Read example-policy
vault policy read example-policy

# Update example-policy to allow 'update'
tee example-policy.hcl <<EOF
path "secret/example/*" { capabilities = ["create","read","update","list"] }
EOF
vault policy write example-policy example-policy.hcl

# Delete example-policy
vault policy delete example-policy
# Recreate it
vault policy write example-policy example-policy.hcl

echo "=== Testing Demo Policy ==="
vault write auth/userpass/users/demo-user password="demo123" policies="demo-policy"
vault login -method=userpass username=demo-user password=demo123 || true

echo "Vault setup completed with demo-policy and example-policy."
