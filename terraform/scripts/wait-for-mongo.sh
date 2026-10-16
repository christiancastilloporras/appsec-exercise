#!/bin/bash
set -e

echo 'Waiting for cloud-init to complete...'
cloud-init status --wait 2>/dev/null || echo 'cloud-init status not available, continuing'

# GitHub Actions runner is outside the Azure VNet; add its IP to the
# MongoDB NSG temporarily so we can reach port 27017 on the public IP.
RUNNER_IP=$(curl -s https://api.ipify.org)
az network nsg rule create --resource-group appsec-exercise-rg --nsg-name mongo-nsg --name mongo_runner_wait --priority 1055 --direction Inbound --access Allow --protocol Tcp --source-address-prefix $RUNNER_IP/32 --source-port-ranges '*' --destination-address-prefixes '*' --destination-port-ranges 27017 --description 'Temporary wait-for-ready access' 2>/dev/null || true

sleep 10

MONGO_IP=__MONGO_PUBLIC_IP__

for i in $(seq 1 60); do
  if bash -c "echo > /dev/tcp/$MONGO_IP/27017" 2>/dev/null; then
    echo "MongoDB is reachable on $MONGO_IP:27017"
    exit 0
  else
    echo "MongoDB not ready yet (attempt $i/60)..."
    sleep 10
  fi
done

echo 'MongoDB did not become reachable on port 27017 within 600s'
echo '=== mongod.out ==='
cat /home/__VM_ADMIN_USERNAME__/logs/mongod.out 2>/dev/null || true
echo '=== mongod.log ==='
cat /var/log/mongodb/mongod.log 2>/dev/null || true
echo '=== processes ==='
ps aux | grep mongod || true
exit 1
