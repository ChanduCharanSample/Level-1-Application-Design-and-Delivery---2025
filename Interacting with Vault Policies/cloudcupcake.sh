#!/bin/bash
set -e

# --- FIX for Qwiklabs ---
unset VAULT_TOKEN

# 1. Install Vault (if missing)
if ! command -v vault &>/dev/null; then
  echo "Installing Vault..."
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
  sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
  sudo apt-get update
  sudo apt-get install -y vault
fi

# 2. Kill any running Vault process
pkill vault || true

# 3. Start Vault dev server
nohup vault server -dev -dev-root-token-id="root-token" &>/tmp/vault.log &
sleep 2
export VAULT_ADDR='http://127.0.0.1:8200'
vault login root-token

# 4. Create demo-policy
echo '
path "sys/mounts" { capabilities = ["read"] }
path "sys/policies/acl" { capabilities = ["read", "list"] }
' > demo-policy.hcl
vault policy write demo-policy demo-policy.hcl

# 5. Create example-policy
echo '
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
' > example-policy.hcl
vault policy write example-policy example-policy.hcl

# 6. Setup users
vault auth enable userpass
vault write auth/userpass/users/example-user password="password!" policies="default,demo-policy"
vault write auth/userpass/users/admin password="admin123" policies="admin"
vault write auth/userpass/users/app-dev password="appdev123" policies="appdev"
vault write auth/userpass/users/security password="security123" policies="security"

# 7. Create admin policy
echo '
path "sys/health" { capabilities = ["read","sudo"] }
path "sys/policies/acl" { capabilities = ["list"] }
path "sys/policies/acl/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "auth/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/auth/*" { capabilities = ["create","update","delete","sudo"] }
path "sys/auth" { capabilities = ["read"] }
path "secret/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/mounts/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/mounts" { capabilities = ["read"] }
' > admin.hcl
vault policy write admin admin.hcl

# 8. Create appdev policy
echo '
path "secret/+/appdev/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/mounts/*" { capabilities = ["create","read","update"] }
path "sys/mounts" { capabilities = ["read"] }
' > appdev.hcl
vault policy write appdev appdev.hcl

# 9. Create security policy
echo '
path "sys/policies/acl" { capabilities = ["list"] }
path "sys/policies/acl/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/mounts/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "sys/mounts" { capabilities = ["read"] }
path "secret/*" { capabilities = ["create","read","update","delete","list","sudo"] }
path "secret/data/admin" { capabilities = ["deny"] }
path "secret/data/admin/*" { capabilities = ["deny"] }
path "secret/metadata/admin" { capabilities = ["deny"] }
path "secret/metadata/admin/*" { capabilities = ["deny"] }
' > security.hcl
vault policy write security security.hcl

# 10. Create sample secrets
vault kv put secret/security/first username=password
vault kv put secret/appdev/first username=password
vault kv put secret/admin/first admin=password

# 11. Test app-dev user
vault login -method=userpass username="app-dev" password="appdev123"
echo "app-dev access secret/appdev/first:"
vault kv get secret/appdev/first
echo "app-dev access secret/security/first (should fail):"
vault kv get secret/security/first || echo "denied as expected"

# 12. Test security user
vault login -method=userpass username="security" password="security123"
echo "security access secret/security/first:"
vault kv get secret/security/first
echo "security access secret/admin/first (should fail):"
vault kv get secret/admin/first || echo "denied as expected"

# 13. Test admin user
vault login -method=userpass username="admin" password="admin123"
echo "admin access secret/admin/first:"
vault kv get secret/admin/first

echo -e "\n✅ All policies setup and verified successfully!"
