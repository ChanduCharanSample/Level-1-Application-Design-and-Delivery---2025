#!/bin/bash
# cloudcupcake_vault.sh - Automates "Running Vault on Google Cloud" lab
# Author: CloudCupcake 🍰

echo "🚀 Starting Vault lab automation..."

# ================================
# Task 1: Install Vault & start dev server
# ================================
echo "📦 Installing Vault..."
wget https://releases.hashicorp.com/vault/1.8.0/vault_1.8.0_linux_amd64.zip
sudo apt-get update && sudo apt-get install unzip jq -y
unzip vault_1.8.0_linux_amd64.zip
sudo mv vault /usr/local/bin/
vault --version

echo "🔑 Starting Vault dev server in background..."
nohup vault server -dev -dev-root-token-id=root > vault.log 2>&1 &
sleep 5

export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN=root
echo "Vault server running at $VAULT_ADDR"

# ================================
# Task 2: Secrets - create, copy, upload
# ================================
echo "🗝 Creating secret at secret/hello..."
vault kv put secret/hello foo=world excited=yes
vault kv get -format=json secret/hello | jq -r '.data.data.foo' > secret_hello.txt
vault kv get -format=json secret/hello | jq -r '.data.data.excited' > secret_hello_excited.txt

echo "📂 Uploading secrets to Cloud Storage..."
gsutil cp secret_hello.txt gs://$DEVSHELL_PROJECT_ID
gsutil cp secret_hello_excited.txt gs://$DEVSHELL_PROJECT_ID

# ================================
# Task 3: KV secrets at kv/my-secret
# ================================
echo "🗝 Creating secret at kv/my-secret..."
vault secrets enable -path=kv kv
vault kv put kv/my-secret value="s3c(eT"
vault kv get -format=json kv/my-secret | jq -r '.data.value' > my_secret.txt
gsutil cp my_secret.txt gs://$DEVSHELL_PROJECT_ID

# ================================
# Task 4: Vault Transit - encryption/decryption
# ================================
echo "🔐 Enabling transit secrets engine..."
vault secrets enable transit
vault write -f transit/keys/my-key

PLAINTEXT="Learn Vault!"
PLAINTEXT_B64=$(echo -n "$PLAINTEXT" | base64)

echo "📝 Encrypting plaintext..."
CIPHERTEXT=$(vault write -field=ciphertext transit/encrypt/my-key plaintext="$PLAINTEXT_B64")
echo "Ciphertext: $CIPHERTEXT"

echo "🔓 Decrypting ciphertext..."
DECRYPTED_B64=$(vault write -field=plaintext transit/decrypt/my-key ciphertext="$CIPHERTEXT")
echo "$DECRYPTED_B64" | base64 --decode > decrypted_string.txt
cat decrypted_string.txt

echo "📂 Uploading decrypted string to Cloud Storage..."
gsutil cp decrypted_string.txt gs://$DEVSHELL_PROJECT_ID

echo "✅ Lab automation completed!"
echo "🎉 Subscribe to CloudCupcake 🍰"
