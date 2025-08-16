
#!/bin/bash
# cloudcupcake.sh - Vault Dev Mode Automation
# Author: CloudCupcake 🍰

# Kill any existing Vault dev server
pkill -f "vault server -dev" 2>/dev/null

echo "🚀 Starting Vault in dev mode..."
# Start Vault dev server in background and capture logs
vault server -dev > vault.log 2>&1 &
sleep 3

# Extract Root Token from logs
ROOT_TOKEN=$(grep "Root Token:" vault.log | awk '{print $3}')

# Set environment variables
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="$ROOT_TOKEN"

# Save to bashrc for persistence
echo "export VAULT_ADDR=http://127.0.0.1:8200" >> ~/.bashrc
echo "export VAULT_TOKEN=$ROOT_TOKEN" >> ~/.bashrc

# Test Vault connection
echo "🔑 Root Token: $ROOT_TOKEN"
vault status
