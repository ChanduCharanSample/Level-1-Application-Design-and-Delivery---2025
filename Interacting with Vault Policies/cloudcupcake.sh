#!/bin/bash
set -e

echo "=== Installing Vault ==="
sudo apt-get update -y
sudo apt-get install -y curl gnupg lsb-release
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update -y
sudo apt-get install -y vault

echo "=== Starting Vault Dev Server ==="
pkill vault || true
nohup vault server -dev > vault.log 2>&1 &
sleep 5

export VAULT_ADDR='http://127.0.0.1:8200'
ROOT_TOKEN=$(grep 'Root Token:' vault.log | awk '{print $3}')
export VAULT_TOKEN="$ROOT_TOKEN"
echo "Root token: $ROOT_TOKEN"

vault login "$ROOT_TOKEN"

echo "=== Enabling Userpass Auth ==="
vault auth enable userpass || true

echo "=== Creating Users ==="
vault write auth/userpass/users/admin password="admin123" policies="admin"
vault write auth/userpass/users/app-dev password="appdev123" policies="appdev"
vault write auth/userpass/users/security password="security123" policies="security"

echo "=== Writing Policies ==="

tee admin-policy.hcl <<EOF
path "secret/*" { capabilities = ["create","read","update","delete","list","sudo"] }
EOF

tee appdev-policy.hcl <<EOF
path "secret/data/appdev/*" { capabilities = ["create","read","update","delete","list"] }
EOF

tee security-policy.hcl <<EOF
path "secret/*" { capabilities = ["read","list"] }
path "secret/data/admin/*" { capabilities = ["deny"] }
EOF

tee demo-policy.hcl <<EOF
path "secret/data/demo/*" { capabilities = ["create","read","update","delete","list"] }
EOF

tee example-policy.hcl <<EOF
path "secret/data/example/*" { capabilities = ["create","read","update","delete","list"] }
EOF

vault policy write admin admin-policy.hcl
vault policy write appdev appdev-policy.hcl
vault policy write security security-policy.hcl
vault policy write demo-policy demo-policy.hcl
vault policy write example-policy example-policy.hcl

echo "=== Managing example-policy (Update / Read / Delete / Recreate) ==="
tee example-policy.hcl <<EOF
path "secret/data/example/*" { capabilities = ["create","read","update","delete","list"] }
path "sys/policies/acl" { capabilities = ["list"] }
EOF
vault policy write example-policy example-policy.hcl
vault policy read example-policy
vault policy delete example-policy
vault policy write example-policy example-policy.hcl

echo "=== Creating Secrets ==="
vault kv put secret/security/first username=password
vault kv put secret/security/second username=password
vault kv put secret/appdev/first username=password
vault kv put secret/appdev/beta-app/second username=password
vault kv put secret/admin/first admin=password
vault kv put secret/admin/supersecret/second admin=password
vault kv put secret/demo/first value=demo123
vault kv put secret/example/first value=example123

echo "=== Testing Policies ==="
echo "--- Admin should see all secrets ---"
vault login -method=userpass username=admin password=admin123
vault kv list secret/

echo "--- Appdev should access only appdev secrets ---"
vault login -method=userpass username=app-dev password=appdev123
vault kv get secret/appdev/first || echo "Access denied"

echo "--- Security should read but not admin secrets ---"
vault login -method=userpass username=security password=security123
vault kv get secret/security/first || echo "Access denied"
vault kv get secret/admin/first || echo "Access denied (expected)"

echo "=== All Tasks Completed ==="
