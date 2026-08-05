#!/bin/bash
# MongoDB backup script - backs up to Azure Blob Storage
# This runs daily via GitHub Actions cron

set -e

MONGO_IP=${MONGO_IP:-"localhost"}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT:-""}
STORAGE_KEY=${STORAGE_KEY:-""}
CONTAINER_NAME=${CONTAINER_NAME:-"mongo-backups"}

echo "Starting MongoDB backup for $MONGO_IP"

# Create backup directory with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/mongo_backup_${TIMESTAMP}"
mkdir -p $BACKUP_DIR

# Perform mongodump
echo "Running mongodump..."
mongodump --host $MONGO_IP --port 27017 -o $BACKUP_DIR

# Compress the backup
BACKUP_FILE="${BACKUP_DIR}.tar.gz"
tar -czf $BACKUP_FILE -C /tmp $(basename $BACKUP_DIR)

echo "Backup created: $BACKUP_FILE"

# Upload to Azure Blob Storage using Azure CLI
echo "Uploading to Azure Blob Storage..."
az storage blob upload \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY \
  --container-name $CONTAINER_NAME \
  --name "mongo_${TIMESTAMP}.tar.gz" \
  --file $BACKUP_FILE \
  --auth-mode key

echo "Backup uploaded successfully to: https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER_NAME}/mongo_${TIMESTAMP}.tar.gz"

# Cleanup
rm -rf $BACKUP_DIR $BACKUP_FILE
echo "Backup complete!"