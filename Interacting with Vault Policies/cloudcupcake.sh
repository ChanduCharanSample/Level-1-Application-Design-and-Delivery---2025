#!/bin/bash
set -e

echo "===== Installing Vault ====="
sudo apt-get update -y
sudo apt-get install -y unzip curl jq

curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update -y
sudo apt-get install -y vault

echo "===== Starting Vault in dev mode ====="
pkill vault || true
vault server -dev -dev-root-token-id="root" > vault.log 2>&1 &
sleep 3

export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'
echo "VAULT_ADDR=$VAULT_ADDR"
echo "VAULT_TOKEN=$VAULT_TOKEN"

echo "===== Login to Vault ====="
vault login $VAULT_TOKEN

echo "===== Enabling userpass auth ====="
vault auth enable userpass || true

echo "===== Creating demo-policy ====="
cat > demo-policy.hcl <<EOF
path "secret/data/demo/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
vault policy write demo-policy demo-policy.hcl

echo "===== Creating example-policy ====="
cat > example-policy.hcl <<EOF
path "secret/data/example/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
vault policy write example-policy example-policy.hcl

echo "===== Managing example-policy ====="
echo "---- Reading example-policy ----"
vault policy read example-policy

echo "---- Updating example-policy ----"
cat > example-policy.hcl <<EOF
path "secret/data/example/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/data/extra/*" {
  capabilities = ["read", "list"]
}
EOF
vault policy write example-policy example-policy.hcl

echo "---- Deleting example-policy ----"
vault policy delete example-policy
echo "---- Recreating example-policy ----"
vault policy write example-policy example-policy.hcl

echo "===== Creating policies for secrets ====="
cat > admin-policy.hcl <<EOF
path "secret/data/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
vault policy write admin admin-policy.hcl

cat > appdev-policy.hcl <<EOF
path "secret/data/app/*" {
  capabilities = ["create", "read", "update", "list"]
}
EOF
vault policy write appdev appdev-policy.hcl

cat > security-policy.hcl <<EOF
path "secret/data/security/*" {
  capabilities = ["read", "list"]
}
EOF
vault policy write security security-policy.hcl

echo "===== Creating users ====="
vault write auth/userpass/users/alice password="alicepass" policies=admin
vault write auth/userpass/users/bob password="bobpass" policies=appdev
vault write auth/userpass/users/charlie password="charliepass" policies=security

echo "===== Writing secrets ====="
vault kv put secret/demo/secret1 value="demo_secret"
vault kv put secret/example/secret1 value="example_secret"
vault kv put secret/app/appsecret value="app_secret_value"
vault kv put secret/security/secsecret value="security_secret_value"

echo "===== Testing policies ====="
echo "---- Testing Alice (admin) ----"
VAULT_TOKEN=$(vault login -method=userpass username=alice password=alicepass -format=json | jq -r '.auth.client_token')
VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=$VAULT_TOKEN vault kv get secret/app/appsecret

echo "---- Testing Bob (appdev) ----"
VAULT_TOKEN=$(vault login -method=userpass username=bob password=bobpass -format=json | jq -r '.auth.client_token')
VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=$VAULT_TOKEN vault kv get secret/app/appsecret

echo "---- Testing Charlie (security) ----"
VAULT_TOKEN=$(vault login -method=userpass username=charlie password=charliepass -format=json | jq -r '.auth.client_token')
VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=$VAULT_TOKEN vault kv get secret/security/secsecret

echo "===== Lab automation complete ====="
echo "Vault is running in background. Run 'vault status' to check."
