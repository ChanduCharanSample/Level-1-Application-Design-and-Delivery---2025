#!/bin/bash
set -e

# 1. Log in as root
vault login <your-root-token>

# 2. Create a token with dev-readonly and logs policies
vault token create -policy=dev-readonly -policy=logs

# 3. Create users with policies
vault write auth/userpass/users/admin \
    password="admin123" \
    policies="admin"

vault write auth/userpass/users/app-dev \
    password="appdev123" \
    policies="appdev"

vault write auth/userpass/users/security \
    password="security123" \
    policies="security"

# 4. Create policies
vault policy write admin - <<EOF
path "sys/health" { capabilities = ["read", "sudo"] }
path "sys/policies/acl" { capabilities = ["list"] }
path "sys/policies/acl/*" { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }
path "auth/*" { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }
path "sys/auth/*" { capabilities = ["create", "update", "delete", "sudo"] }
path "sys/auth" { capabilities = ["read"] }
path "secret/*" { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }
path "sys/mounts/*" { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }
path "sys/mounts" { capabilities = ["read"] }
EOF

vault policy write appdev - <<EOF
path "secret/+/appdev/*" { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }
path "sys/mounts/*" { capabilities = ["create", "read", "update"] }
path "sys/mounts" { capabilities = ["read"] }
EOF

vault policy write security - <<EOF
path "sys/policies/acl" { capabilities = ["list"] }
path "sys/policies/acl/*" { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }
path "sys/mounts/*" { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }
path "sys/mounts" { capabilities = ["read"] }
path "secret/*" { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }
path "secret/data/admin" { capabilities = ["deny"] }
path "secret/data/admin/*" { capabilities = ["deny"] }
path "secret/metadata/admin" { capabilities = ["deny"] }
path "secret/metadata/admin/*" { capabilities = ["deny"] }
EOF

# 5. Create secrets
vault kv put secret/security/first username=password
vault kv put secret/security/second username=password

vault kv put secret/appdev/first username=password
vault kv put secret/appdev/beta-app/second username=password

vault kv put secret/admin/first admin=password
vault kv put secret/admin/supersecret/second admin=password

# 6. Test app-dev policy
vault login -method="userpass" username="app-dev" password="appdev123"
vault kv get secret/appdev/first
vault kv get secret/appdev/beta-app/second
vault kv put secret/appdev/appcreds credentials=creds123
vault kv destroy -versions=1 secret/appdev/appcreds || true
vault kv get secret/security/first || true
vault kv list secret/ || true

# 7. Test security policy
vault login -method="userpass" username="security" password="security123"
vault kv get secret/security/first
vault kv get secret/security/second
vault kv put secret/security/supersecure/bigsecret secret=idk
vault kv destroy -versions=1 secret/security/supersecure/bigsecret
vault kv get secret/appdev/first
vault kv list secret/
vault secrets enable -path=supersecret kv
vault kv get secret/admin/first || true
vault kv list secret/admin || true

# 8. Test admin policy
vault login -method="userpass" username="admin" password="admin123"
vault kv get secret/admin/first
vault kv get secret/security/first
vault kv put secret/webserver/credentials web=awesome
vault kv destroy -versions=1 secret/webserver/credentials
vault kv get secret/appdev/first
vault kv list secret/appdev/
vault policy list

# 9. Save policies list to GCS
vault policy list > policies-update.txt
gsutil cp policies-update.txt gs://$PROJECT_ID

# 10. Enable GCP auth
vault auth enable gcp

# 11. List enabled auth methods
vault auth list
