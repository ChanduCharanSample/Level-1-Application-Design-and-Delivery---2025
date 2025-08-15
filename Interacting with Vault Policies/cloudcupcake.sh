#!/bin/bash
set -e

echo -e "\n=== Installing Vault ==="
sudo apt update -y && sudo apt install -y curl gnupg lsb-release
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update -y && sudo apt-get install -y vault

echo -e "\n=== Starting Vault Dev Server ==="
pkill vault || true
nohup vault server -dev > vault.log 2>&1 &
sleep 3

export VAULT_ADDR='http://127.0.0.1:8200'
ROOT_TOKEN=$(grep 'Root Token:' vault.log | awk '{print $3}')
echo "Root token: $ROOT_TOKEN"

vault login "$ROOT_TOKEN"

echo -e "\n=== Enabling Userpass Auth ==="
vault auth enable userpass || true

echo -e "\n=== Creating Users ==="
vault write auth/userpass/users/admin password="admin123" policies="admin"
vault write auth/userpass/users/app-dev password="appdev123" policies="appdev"
vault write auth/userpass/users/security password="security123" policies="security"
vault write auth/userpass/users/demo-user password="demo123" policies="demo-policy"

echo -e "\n=== Writing Policies ==="

tee admin-policy.hcl <<EOF
path "secret/*" { capabilities = ["create","read","update","delete","list","sudo"] }
EOF

tee appdev-policy.hcl <<EOF
path "secret/appdev/*" { capabilities = ["create","read","update","delete","list"] }
EOF

tee security-policy.hcl <<EOF
path "secret/*" { capabilities = ["read","list"] }
path "secret/admin/*" { capabilities = ["deny"] }
EOF

tee demo-policy.hcl <<EOF
path "secret/*" { capabilities = ["read","list"] }
EOF

tee example-policy.hcl <<EOF
path "secret/example/*" { capabilities = ["create","read","list"] }
EOF

echo -e "\n=== Applying Policies ==="
vault policy write admin admin-policy.hcl
vault policy write appdev appdev-policy.hcl
vault policy write security security-policy.hcl
vault policy write demo-policy demo-policy.hcl
vault policy write example-policy example-policy.hcl

echo -e "\n=== Creating Secrets ==="
vault kv put secret/security/first username=password
vault kv put secret/security/second username=password
vault kv put secret/appdev/first username=password
vault kv put secret/appdev/beta-app/second username=password
vault kv put secret/admin/first admin=password
vault kv put secret/admin/supersecret/second admin=password
vault kv put secret/example/test key=value

echo -e "\n=== Managing Example Policy via CLI ==="
echo "- Reading example-policy"
vault policy read example-policy

echo "- Updating example-policy to allow update"
tee example-policy.hcl <<EOF
path "secret/example/*" { capabilities = ["create","read","update","list"] }
EOF
vault policy write example-policy example-policy.hcl

echo "- Deleting example-policy"
vault policy delete example-policy

echo "- Recreating example-policy"
vault policy write example-policy example-policy.hcl

echo -e "\n=== Testing Policies ==="

# Test demo-user (should only read/list)
echo "- Logging in as demo-user"
DEMO_TOKEN=$(vault login -method=userpass username=demo-user password=demo123 -format=json | jq -r '.auth.client_token')
VAULT_TOKEN=$DEMO_TOKEN vault kv get secret/example/test || echo "Denied as expected"
VAULT_TOKEN=$DEMO_TOKEN vault kv put secret/example/test key=new || echo "Denied as expected"

# Test app-dev user (should create in appdev path)
echo "- Logging in as app-dev"
APPDEV_TOKEN=$(vault login -method=userpass username=app-dev password=appdev123 -format=json | jq -r '.auth.client_token')
VAULT_TOKEN=$APPDEV_TOKEN vault kv put secret/appdev/newapp key=value
VAULT_TOKEN=$APPDEV_TOKEN vault kv get secret/appdev/newapp

echo -e "\n=== Vault Setup Completed Successfully ==="
