#!/bin/bash
set -euo pipefail

# Cleanup any previous Vault process or token
unset VAULT_TOKEN
pkill vault || true

# Install Vault if it's missing
if ! command -v vault &>/dev/null; then
  echo "Installing Vault..."
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
  sudo apt-add-repository \
    "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
  sudo apt-get update
  sudo apt-get install -y vault
fi

# Start Vault in dev mode with known root token
nohup vault server -dev -dev-root-token-id="root-token" &>/tmp/vault.log &
sleep 3
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root-token'

vault status

# == Task 4: Create demo-policy ==
cat > demo-policy.hcl <<'EOF'
path "sys/mounts" {
  capabilities = ["read"]
}

path "sys/policies/acl" {
  capabilities = ["read", "list"]
}
EOF
vault policy write demo-policy demo-policy.hcl

# == Task 5: Create example-policy ==
cat > example-policy.hcl <<'EOF'
# List, create, update, and delete key/value secrets
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Manage secrets engines
path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# List existing secrets engines.
path "sys/mounts" {
  capabilities = ["read"]
}

# List auth methods
path "sys/auth" {
  capabilities = ["read"]
}
EOF
vault policy write example-policy example-policy.hcl

# == Task 6: Enable auth and create example-user ==
vault auth disable userpass || true
vault auth enable userpass
vault write auth/userpass/users/example-user password="password!" policies="default, demo-policy"

# == Task 7: Policies for Secrets ==
# Admin
cat > admin.hcl <<'EOF'
# Read system health check
path "sys/health" {
  capabilities = ["read", "sudo"]
}

# List existing policies
path "sys/policies/acl" {
  capabilities = ["list"]
}

# Create and manage ACL policies
path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Manage auth methods
path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Create/update/delete auth methods
path "sys/auth/*" {
  capabilities = ["create", "update", "delete", "sudo"]
}

# List auth methods
path "sys/auth" {
  capabilities = ["read"]
}

# Key/value secrets management
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Secrets engines management
path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# List secrets engines
path "sys/mounts" {
  capabilities = ["read"]
}
EOF
vault policy write admin admin.hcl

# Appdev
cat > appdev.hcl <<'EOF'
# List, create, update, and delete key/value secrets
path "secret/+/appdev/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Manage secrets engines
path "sys/mounts/*" {
  capabilities = ["create", "read", "update"]
}

# List secrets engines
path "sys/mounts" {
  capabilities = ["read"]
}
EOF
vault policy write appdev appdev.hcl

# Security
cat > security.hcl <<'EOF'
# List existing policies
path "sys/policies/acl" {
  capabilities = ["list"]
}

# Create and manage ACL policies
path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Manage secrets engines
path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# List secrets engines
path "sys/mounts" {
  capabilities = ["read"]
}

# Key/value secrets management
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Deny access to secret/admin path
path "secret/data/admin" {
  capabilities = ["deny"]
}
path "secret/data/admin/*" {
  capabilities = ["deny"]
}

# Deny listing of secret/admin metadata
path "secret/metadata/admin" {
  capabilities = ["deny"]
}
path "secret/metadata/admin/*" {
  capabilities = ["deny"]
}
EOF
vault policy write security security.hcl

# == Create users and secrets ==
vault write auth/userpass/users/app-dev password="appdev123" policies="appdev"
vault write auth/userpass/users/security password="security123" policies="security"
vault write auth/userpass/users/admin password="admin123" policies="admin"

vault kv put secret/security/first username=password
vault kv put secret/appdev/first username=password
vault kv put secret/admin/first admin=password

# == Verification ==
echo "Verifying app-dev:"
vault login -method=userpass username="app-dev" password="appdev123"
vault kv get secret/appdev/first >/dev/null
vault kv get secret/security/first 2>/dev/null && echo "Error: app-dev should be denied secret/security"
vault login root-token

echo "Verifying security:"
vault login -method=userpass username="security" password="security123"
vault kv get secret/security/first >/dev/null
vault kv get secret/admin/first 2>/dev/null && echo "Error: security should be denied secret/admin"
vault login root-token

echo "Verifying admin:"
vault login -method=userpass username="admin" password="admin123"
vault kv get secret/admin/first >/dev/null

echo -e "\n All lab checkpoints should now be complete — click 'Check my progress'"
