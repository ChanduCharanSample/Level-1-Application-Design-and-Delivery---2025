#!/bin/bash
set -e

echo "🚀 Starting Vault GCP Secrets Engine Lab Automation..."

# 1️⃣ Detect Project ID
PROJECT_ID=$(gcloud config get-value project)
echo "📌 Project ID: $PROJECT_ID"

# 2️⃣ Detect Service Account JSON key automatically (Task 3)
KEY_FILE=$(ls *.json 2>/dev/null | head -n 1)
if [[ -z "$KEY_FILE" ]]; then
  echo "❌ No service account JSON key file found. Please upload your JSON key first."
  exit 1
fi
echo "🔑 Using Service Account Key: $KEY_FILE"

# 3️⃣ Enable GCP secrets engine
vault secrets enable gcp || echo "✅ GCP secrets engine already enabled"

# 4️⃣ Create default credentials (Checkpoint 1)
vault write gcp/config credentials=@"$KEY_FILE" ttl=3600 max_ttl=86400
echo "✅ Default credentials configured (Checkpoint 1 passed)"

# 5️⃣ Create Vault bindings file dynamically (Checkpoint 2)
BINDINGS_FILE="bindings.hcl"
cat > $BINDINGS_FILE <<EOF
resource "//cloudresourcemanager.googleapis.com/projects/$PROJECT_ID" {
  roles = [
    "roles/storage.objectAdmin",
    "roles/storage.legacyBucketReader"
  ]
}
EOF
echo "✅ Roleset bindings file created (Checkpoint 2 passed)"

# 6️⃣ Configure a roleset that generates service account keys (Checkpoint 3)
vault write gcp/roleset/my-key-roleset \
  project="$PROJECT_ID" \
  secret_type="service_account_key" \
  bindings=@"$BINDINGS_FILE"
vault read gcp/roleset/my-key-roleset/key > roleset_key.json
echo "✅ Roleset key generated (Checkpoint 3 passed)"

# 7️⃣ Configure static accounts (Checkpoint 4)
SA_EMAIL=$(jq -r .client_email "$KEY_FILE")
vault write gcp/static-account/my-key-account \
  service_account_email="$SA_EMAIL" \
  secret_type="service_account_key" \
  bindings=@"$BINDINGS_FILE"
vault read gcp/static-account/my-key-account > static_account.json
echo "✅ Static account configured (Checkpoint 4 passed)"

# 8️⃣ Finished
echo "🎉 All tasks and checkpoints completed successfully!"
echo "📂 Generated files: roleset_key.json, static_account.json"
