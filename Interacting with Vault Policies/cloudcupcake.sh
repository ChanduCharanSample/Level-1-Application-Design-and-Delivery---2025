#!/bin/bash
set -euo pipefail

# Ensure no interfering token or Vault process
unset VAULT_TOKEN
pkill vault || true

# 1. Install Vault if not present
if ! command -v vault &> /dev/null; then
  echo "Installing Vault..."
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
  sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
  sudo apt-get update
  sudo apt-get install -y vault
fi

# 2. Start Vault dev server with a fixed root token
nohup vault server -dev -dev-root-token-id="root-token" &>/tmp/vault.log &
sleep 3
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root-token'

# Verify it’s working
echo "Vault server status:"
vault status

# 3. Create demo-policy
cat > demo-policy.hcl <<'EOF'
path "sys/mounts" {
  capabilities = ["read"]
}
path "sys/policies/acl" {
  capabilities = ["read", "list"]
}
EOF
vault policy write demo-policy demo-policy.hcl

# 4. Create example-policy (CLI checkpoint)
cat > example-policy.hcl <<'EOF'
path "secret/*" {
  capabilities = ["create","read","update","delete","list","sudo"]
}
path "sys/mounts/*" {
  capabilities = ["create","read","update","delete","list","sudo"]
}
path "sys/mounts" {
  capabilities = ["read"]
}
path "sys/auth" {
  capabilities = ["read"]
}
EOF
vault policy write example-policy example-policy.hcl

# 5. Enable or reset userpass auth method
vault auth disable userpass || true
vault auth enable userpass

# 6. Create users with respective policies
vault write auth/userpass/users/example-user password="password!" policies="default,demo-policy"
vault write auth/userpass/users/admin password="admin123" policies="admin"
vault write auth/userpass/users/app-dev password="appdev123" policies="appdev"
vault write auth/userpass/users/security password="security123" policies="security"

# 7. Create admin policy
cat > admin.hcl <<'EOF'
path "sys/health" { capabilities = ["read","sudo"] }
path "sys/policies/acl" { capabilities = ["list"] }
path "sys/policies/acl/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "auth/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/auth/*" { capabilities = ["create","update","delete","sudo"] }
path "sys/auth" { capabilities = ["read"] }
path "secret/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/mounts/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/mounts" { capabilities = ["read"] }
EOF
vault policy write admin admin.hcl

# 8. Create appdev policy
cat > appdev.hcl <<'EOF'
path "secret/+/appdev/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/mounts/*" { capabilities = ["create","read","update"] }
path "sys/mounts" { capabilities = ["read"] }
EOF
vault policy write appdev appdev.hcl

# 9. Create security policy
cat > security.hcl <<'EOF'
path "sys/policies/acl" { capabilities = ["list"] }
path "sys/policies/acl/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/mounts/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/mounts" { capabilities = ["read"] }
path "secret/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "secret/data/admin" { capabilities = ["deny"] }
path "secret/data/admin/*" { capabilities = ["deny"] }
path "secret/metadata/admin" { capabilities = ["deny"] }
path "secret/metadata/admin/*" { capabilities = ["deny"] }
EOF
vault policy write security security.hcl

# 10. Create sample secrets
vault kv put secret/security/first username=password
vault kv put secret/appdev/first username=password
vault kv put secret/admin/first admin=password

# 11. Test app-dev user access
vault login -method=userpass username="app-dev" password="appdev123"
vault kv get secret/appdev/first > /dev/null
( vault kv get secret/security/first 2>&1 ) || echo "app-dev correctly denied secret/security"
vault login root-token

# 12. Test security user access
vault login -method=userpass username="security" password="security123"
vault kv get secret/security/first > /dev/null
( vault kv get secret/admin/first 2>&1 ) || echo "security correctly denied secret/admin"
vault login root-token

# 13. Test admin user access
vault login -method=userpass username="admin" password="admin123"
vault kv get secret/admin/first > /dev/null

echo -e "\nAll lab checkpoints should now be completed successfully!"
