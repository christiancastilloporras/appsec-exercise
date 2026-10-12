#!/bin/bash
# MongoDB backup script - backs up to Azure Blob Storage
# This runs daily via GitHub Actions cron
#
# IMPORTANT: Since the GitHub Actions Runner is outside the Azure VNET,
# it connects via the MongoDB VM's PUBLIC IP. The MongoDB NSG restricts
# port 27017 to the AKS subnet only. This script temporarily adds the
# Runner's IP to the NSG rule, performs the backup, and removes the rule.
#
# Authentication: MongoDB uses auth (admin:****) with authSource=admin

set -e

# --- Input variables (passed from GitHub Actions workflow) ---
MONGO_IP=${MONGO_IP:-"localhost"}
MONGO_ADMIN_PASSWORD=${MONGO_ADMIN_PASSWORD:-""}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT:-""}
STORAGE_KEY=${STORAGE_KEY:-""}
CONTAINER_NAME=${CONTAINER_NAME:-"mongo-backups"}
RESOURCE_GROUP=${RESOURCE_GROUP:-"appsec-exercise-rg"}
NSG_NAME=${NSG_NAME:-"mongo-nsg"}
RUNNER_IP=${RUNNER_IP:-"$(curl -s https://api.ipify.org)"}

# Validate required inputs
if [ -z "$MONGO_IP" ] || [ -z "$MONGO_ADMIN_PASSWORD" ] || [ -z "$STORAGE_ACCOUNT" ] || [ -z "$STORAGE_KEY" ]; then
  echo "ERROR: Required environment variables missing"
  echo "Required: MONGO_IP, MONGO_ADMIN_PASSWORD, STORAGE_ACCOUNT, STORAGE_KEY"
  exit 1
fi

# NSG rule name must be unique per IP to avoid conflicts
NSG_RULE_NAME="mongo_runner_$(echo "$RUNNER_IP" | tr '.' '_')"
NSG_RULE_PRIORITY=1055

echo "Starting MongoDB backup for $MONGO_IP"
echo "Runner IP: $RUNNER_IP"

# ============================================================
# Step 1: Add temporary NSG rule for Runner IP → MongoDB (27017)
# ============================================================
echo "Adding temporary NSG rule for Runner IP access..."
az network nsg rule create \
  --resource-group "$RESOURCE_GROUP" \
  --nsg-name "$NSG_NAME" \
  --name "$NSG_RULE_NAME" \
  --priority "$NSG_RULE_PRIORITY" \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefix "$RUNNER_IP/32" \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 27017 \
  --description "Temporary backup access for GitHub Runner ($RUNNER_IP)"

echo "NSG rule added. Waiting for propagation..."
sleep 15

# Cleanup function - always remove the NSG rule, even if backup fails
cleanup_nsg() {
  echo "Removing temporary NSG rule: $NSG_RULE_NAME"
  az network nsg rule delete \
    --resource-group "$RESOURCE_GROUP" \
    --nsg-name "$NSG_NAME" \
    --name "$NSG_RULE_NAME" 2>/dev/null || echo "NSG rule already removed"
}
trap cleanup_nsg EXIT

# ============================================================
# Step 2: Verify NSG rule propagation
# ============================================================
echo "Verifying NSG rule is active..."
for i in $(seq 1 10); do
  RULE_CHECK=$(az network nsg rule list \
    --resource-group "$RESOURCE_GROUP" \
    --nsg-name "$NSG_NAME" \
    --query "[?name=='$NSG_RULE_NAME']" -o tsv 2>/dev/null)
  if [ -n "$RULE_CHECK" ]; then
    echo "NSG rule confirmed active"
    break
  fi
  echo "Waiting for NSG rule... (attempt $i/10)"
  sleep 5
done

# ============================================================
# Step 3: Perform mongodump with authentication
# ============================================================
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/mongo_backup_${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"

echo "Running mongodump with authentication..."
mongodump \
  --host "$MONGO_IP" \
  --port 27017 \
  --username "admin" \
  --password "$MONGO_ADMIN_PASSWORD" \
  --authenticationDatabase "admin" \
  -o "$BACKUP_DIR"

echo "mongodump completed successfully"

# ============================================================
# Step 4: Compress and upload to Azure Blob Storage
# ============================================================
BACKUP_FILE="${BACKUP_DIR}.tar.gz"
tar -czf "$BACKUP_FILE" -C /tmp "$(basename "$BACKUP_DIR")"
echo "Backup compressed: $BACKUP_FILE"

echo "Uploading to Azure Blob Storage..."
az storage blob upload \
  --account-name "$STORAGE_ACCOUNT" \
  --account-key "$STORAGE_KEY" \
  --container-name "$CONTAINER_NAME" \
  --name "mongo_${TIMESTAMP}.tar.gz" \
  --file "$BACKUP_FILE" \
  --auth-mode key

echo "Backup uploaded successfully to: https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER_NAME}/mongo_${TIMESTAMP}.tar.gz"

# ============================================================
# Step 5: Cleanup local files (NSG rule removed by trap)
# ============================================================
rm -rf "$BACKUP_DIR" "$BACKUP_FILE"
echo "Backup complete! (NSG rule removed by cleanup trap)"
