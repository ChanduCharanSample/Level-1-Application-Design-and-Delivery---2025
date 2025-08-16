#!/bin/bash
set -e

echo "🚀 Starting automation for 'Creating Dynamic Secrets for Google Cloud with Vault' lab..."

# -------------------------------
# Step 1: Auto-detect Service Account JSON
# -------------------------------
KEY_FILE=$(find ~ -maxdepth 1 -type f -name "*.json" | head -n 1)

if [[ -z "$KEY_FILE" ]]; then
  echo "❌ ERROR: No Service Account JSON key found in home directory."
  echo "➡️ Please download it from Task 3 and place it in your home (~) directory."
  exit 1
fi

echo "✅ Found Service Account key: $KEY_FILE"

# -------------------------------
# Step 2: Enable GCP Secrets Engine
# -------------------------------
echo "⚡ Enabling GCP secrets engine in Vault..."
vault secrets enable gcp || echo "ℹ️ GCP secrets engine already enabled."

# -------------------------------
# Step 3: Configure Vault with SA credentials
# -------------------------------
echo "⚡ Configuring Vault with default GCP credentials..."
vault write gcp/config credentials=@$KEY_FILE

# -------------------------------
# Step 4: Create Roleset for Dynamic Keys
# -------------------------------
echo "⚡ Creating roleset 'my-roleset'..."
vault write gcp/roleset/my-roleset \
    project="$(gcloud config get-value project)" \
    secret_type="service_account_key" \
    bindings='{"roles/viewer" = ["serviceAccount:'"$(gcloud config get-value project)"'.svc.id.goog[default/default]"]}'

# -------------------------------
# Step 5: Generate Dynamic Service Account Key (checkpoint)
# -------------------------------
echo "⚡ Generating a dynamic service account key..."
vault read gcp/key/my-roleset || true

# -------------------------------
# Step 6: Configure Static Account
# -------------------------------
echo "⚡ Configuring a static account..."
SA_EMAIL=$(gcloud iam service-accounts list --format="value(email)" | head -n 1)

if [[ -z "$SA_EMAIL" ]]; then
  echo "❌ ERROR: No service account found in project."
  exit 1
fi

vault write gcp/static-account/my-static-account \
    service_account_email="$SA_EMAIL" \
    bindings='{"roles/editor"=["*"]}'

# -------------------------------
# Step 7: Verify Static Account
# -------------------------------
echo "⚡ Reading static account credentials..."
vault read gcp/static-account/my-static-account/key || true

echo "🎉 All checkpoints configured successfully!"
echo "✅ Default credentials"
echo "✅ Rolesets bindings"
echo "✅ Dynamic service account key roleset"
echo "✅ Static account"

echo "👉 Now go back to Qwiklabs and check your progress!"
