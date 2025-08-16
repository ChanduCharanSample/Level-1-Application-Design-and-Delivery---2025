#!/bin/bash
set -e

echo "=== Task 1: Install Vault ==="
# Add HashiCorp repo and install Vault
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update -y
sudo apt-get install vault -y

echo "=== Verify Vault installation ==="
vault -version

# Create Vault config
cat > config.hcl <<'EOF'
storage "raft" {
  path    = "./vault/data"
  node_id = "node1"
}

listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = true
}

api_addr = "http://127.0.0.1:8200"
cluster_addr = "https://127.0.0.1:8201"
ui = true

disable_mlock = true
EOF

mkdir -p ./vault/data

echo "=== Start Vault server in background ==="
vault server -config=config.hcl > vault.log 2>&1 &
sleep 5

export VAULT_ADDR='http://127.0.0.1:8200'

echo "=== Initialize Vault ==="
vault operator init -key-shares=5 -key-threshold=3 > init-keys.txt
cat init-keys.txt

UNSEAL_KEY1=$(grep 'Unseal Key 1:' init-keys.txt | awk '{print $4}')
UNSEAL_KEY2=$(grep 'Unseal Key 2:' init-keys.txt | awk '{print $4}')
UNSEAL_KEY3=$(grep 'Unseal Key 3:' init-keys.txt | awk '{print $4}')
ROOT_TOKEN=$(grep 'Initial Root Token:' init-keys.txt | awk '{print $4}')

echo "=== Unsealing Vault ==="
vault operator unseal $UNSEAL_KEY1
vault operator unseal $UNSEAL_KEY2
vault operator unseal $UNSEAL_KEY3

echo "=== Login as Root ==="
vault login $ROOT_TOKEN

echo "=== Task 2: Enable Google Cloud secrets engine ==="
vault secrets enable gcp

echo "=== Task 3: Configure Default Credentials ==="
# NOTE: Replace FILE.json with your uploaded service account JSON
CREDS=$(ls ~ | grep json | head -n 1)
echo "Using credentials file: $CREDS"

vault write gcp/config \
  credentials=@"$CREDS" \
  ttl=3600 \
  max_ttl=86400

echo "=== Task 4: Create bindings.hcl ==="
PROJECT_ID=$(gcloud config get-value project)

cat > bindings.hcl <<EOF
resource "buckets/${PROJECT_ID}" {
  roles = [
    "roles/storage.objectAdmin",
    "roles/storage.legacyBucketReader",
  ]
}
EOF

echo "=== Configure Roleset for Access Tokens ==="
vault write gcp/roleset/my-token-roleset \
  project="$PROJECT_ID" \
  secret_type="access_token" \
  token_scopes="https://www.googleapis.com/auth/cloud-platform" \
  bindings=@bindings.hcl

echo "=== Generate OAuth2 Access Token ==="
vault read gcp/roleset/my-token-roleset/token > token.txt
TOKEN=$(grep 'token ' token.txt | awk '{print $2}')
echo "Generated Token: $TOKEN"

echo "=== Test API Call with Token ==="
curl -s \
  "https://storage.googleapis.com/storage/v1/b/${PROJECT_ID}" \
  --header "Authorization: Bearer ${TOKEN}" \
  --header "Accept: application/json" | jq .

echo "=== Download sample.txt ==="
curl -s -X GET \
  -H "Authorization: Bearer ${TOKEN}" \
  -o "sample.txt" \
  "https://storage.googleapis.com/storage/v1/b/${PROJECT_ID}/o/sample.txt?alt=media"

cat sample.txt || true

echo "=== Configure Roleset for Service Account Keys ==="
vault write gcp/roleset/my-key-roleset \
  project="$PROJECT_ID" \
  secret_type="service_account_key" \
  bindings=@bindings.hcl

vault read gcp/roleset/my-key-roleset/key

echo "=== Configure Static Accounts ==="
SA_EMAIL=$(gcloud iam service-accounts list --format="value(email)" | head -n 1)

vault write gcp/static-account/my-token-account \
  service_account_email="$SA_EMAIL" \
  secret_type="access_token" \
  token_scopes="https://www.googleapis.com/auth/cloud-platform" \
  bindings=@bindings.hcl

vault write gcp/static-account/my-key-account \
  service_account_email="$SA_EMAIL" \
  secret_type="service_account_key" \
  bindings=@bindings.hcl

echo "=== Lab automation completed successfully 🚀 ==="
