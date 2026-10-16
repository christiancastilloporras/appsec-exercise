#!/bin/bash
set -e

echo 'Waiting for cloud-init to complete...'
cloud-init status --wait 2>/dev/null || echo 'cloud-init status not available, continuing'

# Runner IP NSG rule is now managed by Terraform (mongo_nsg.Mongo-Runner-Temp)
# via the runner_ip variable passed from the GitHub Actions workflow.
# No az CLI needed on the VM - the rule is pre-created before provisioning.

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
