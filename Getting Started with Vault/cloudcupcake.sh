#!/bin/bash
# cloudcupcake_vault.sh - Automates "Running Vault on Google Cloud" lab
# Author: CloudCupcake 🍰

echo "🚀 Starting Vault lab automation..."

# ================================
# Task 1: Install Vault & start dev server
# ================================
echo "📦 Installing Vault..."
wget https://releases.hashicorp.com/vault/1.8.0/vault_1.8.0_linux_amd64.zip
sudo apt-get install unzip -y
unzip vault_1.8.0_linux_amd64.zip
sudo mv vault /usr/local/bin/
vault --version

echo "🔑 Starting Vault dev server in background..."
nohup vault server -dev -dev-root-token-id=root > vault.log 2>&1 &
sleep 3

export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN=root
echo "Vault server running at $VAULT_ADDR"

# ================================
# Task 2: Secrets - create, read, delete
# ================================
echo "🗝 Writing first secret..."
vault kv put secret/cloudcupcake secret1="HelloVault"

echo "📖 Reading secret..."
vault kv get secret/cloudcupcake

echo "❌ Deleting secret..."
vault kv delete secret/cloudcupcake

# ================================
# Task 3: Secrets Versioning
# ================================
echo "📌 Writing versioned secrets..."
vault kv put secret/versiontest value="v1"
vault kv put secret/versiontest value="v2"
vault kv get -version=1 secret/versiontest
vault kv get -version=2 secret/versiontest

# ================================
# Task 4: Enable another secrets engine
# ================================
echo "⚙️ Enabling KV v2 secrets engine at path 'kv2'..."
vault secrets enable -path=kv2 kv-v2
vault kv put kv2/test secret2="CloudCupcakeRocks"
vault kv get kv2/test

# ================================
# Task 5: Enable Userpass authentication
# ================================
echo "👤 Enabling userpass authentication..."
vault auth enable userpass
vault write auth/userpass/users/testuser password="pass123" policies=default

# ================================
# Task 6: Token authentication
# ================================
echo "🔑 Creating token..."
vault token create -format=json | jq -r ".auth.client_token" > token.txt
TOKEN=$(cat token.txt)
echo "Generated token: $TOKEN"

echo "📂 Saving token to bucket for lab progress..."
gsutil cp token.txt gs://$DEVSHELL_PROJECT_ID-bucket/token.txt

echo "✅ Lab automation completed!"
echo "🎉 Subscribe to CloudCupcake 🍰"
