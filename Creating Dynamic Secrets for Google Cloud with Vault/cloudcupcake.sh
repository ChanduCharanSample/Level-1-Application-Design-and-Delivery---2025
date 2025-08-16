#!/bin/bash
set -e

echo "🚀 Starting Vault GCP Secrets Engine Lab Automation..."

# Detect project ID
PROJECT_ID=$(gcloud config get-value project)
echo "📌 Project ID: $PROJECT_ID"

# Find the Service Account JSON file automatically (Task 3 key file)
KEY_FILE=$(ls *.json 2>/dev/null | head -n 1)
if [[ -z "$KEY_FILE" ]]; then
  echo "❌ No service account JSON key file found in current directory."
  echo "👉 Please upload it with:  Upload File (JSON) → Cloud Shell home directory"
  exit 1
fi
echo "🔑 Using Service Account Key: $KEY_FILE"

# 1. Enable GCP secrets engine
vault secrets enable gcp || echo "✅ GCP secrets engine already enabled"

# 2. Configure default credentials
vault write gcp/config credentials=@"$KEY_FILE"
echo "✅ Default credentials configured (Checkpoint 1 passed)"

# 3. Create a roleset with IAM bindings
vault write gcp/roleset/my-roleset \
  project="$PROJECT_ID" \
  secret_type="service_account_key" \
  bindings=-<<EOF
resource "//cloudresourcemanager.googleapis.com/projects/$PROJECT_ID" {
  roles = ["roles/viewer"]
}
EOF
echo "✅ Roleset with bindings configured (Checkpoint 2 passed)"

# 4. Generate a key from the roleset
vault read gcp/key/my-roleset > roleset_key.json
echo "✅ Roleset key generated (Checkpoint 3 passed)"

# 5. Create a static account using the uploaded service account
SA_EMAIL=$(jq -r .client_email "$KEY_FILE")
vault write gcp/static-account/my-static-account \
  service_account_email="$SA_EMAIL" \
  secret_type="access_token"
vault read gcp/static-account/my-static-account > static_account.json
echo "✅ Static account configured (Checkpoint 4 passed)"

echo "🎉 All lab checkpoints completed successfully!"
echo "📂 Generated files: roleset_key.json, static_account.json"
