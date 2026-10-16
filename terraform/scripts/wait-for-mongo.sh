#!/bin/bash
# Don't use set -e: we want to retry, not exit on first failure

MONGO_IP=__MONGO_PUBLIC_IP__
CLOUD_USER=__VM_ADMIN_USERNAME__

echo "=== Waiting for cloud-init to complete ==="
# Wait for cloud-init to finish with proper diagnostics
# Don't swallow errors - capture them so we can debug cloud-init failures
CLOUD_INIT_READY=false
for i in $(seq 1 30); do
  if command -v cloud-init >/dev/null 2>&1; then
    CI_STATUS=$(cloud-init status --wait 2>&1)
    CI_EXIT=$?
    echo "cloud-init status (attempt $i/30): exit=$CI_EXIT"
    if [ $CI_EXIT -eq 0 ]; then
      CLOUD_INIT_READY=true
      echo "cloud-init completed successfully"
      break
    else
      echo "--- cloud-init status output ---"
      echo "$CI_STATUS"
      echo "--- end cloud-init output ---"
      echo "cloud-init not ready yet (attempt $i/30), retrying in 10s..."
      sleep 10
    fi
  else
    echo "cloud-init not installed (attempt $i/30), checking if SSH is ready instead..."
    sleep 10
    # If cloud-init isn't available, check if the system is responsive
    if [ -f /var/log/cloud-init-output.log ]; then
      echo "--- cloud-init-output.log (last 20 lines) ---"
      tail -20 /var/log/cloud-init-output.log 2>/dev/null || true
      echo "--- end cloud-init-output.log ---"
    fi
    CLOUD_INIT_READY=true
    break
  fi
done

if [ "$CLOUD_INIT_READY" != "true" ]; then
  echo "ERROR: cloud-init did not complete within 300s"
  echo "=== cloud-init-output.log ==="
  cat /var/log/cloud-init-output.log 2>/dev/null || true
  echo "=== cloud-init.log (last 50 lines) ==="
  tail -50 /var/log/cloud-init.log 2>/dev/null || true
  exit 1
fi

echo "=== cloud-init ready, waiting for MongoDB to start ==="
# Give MongoDB a moment to start after cloud-init completes
sleep 15

# Only 2 attempts: fail fast, let Terraform retry the whole null_resource
for i in $(seq 1 2); do
  if bash -c "echo > /dev/tcp/$MONGO_IP/27017" 2>/dev/null; then
    echo "MongoDB is reachable on $MONGO_IP:27017"
    exit 0
  else
    echo "MongoDB not ready yet (attempt $i/2)..."
    echo "  Checking mongod process..."
    ps aux | grep mongod | grep -v grep || echo "  mongod process not found"
    echo "  Checking mongod.out..."
    cat /home/$CLOUD_USER/logs/mongod.out 2>/dev/null || echo "  mongod.out not found"
    echo "  Checking port 27017 locally..."
    ss -tlnp 2>/dev/null | grep 27017 || echo "  port 27017 not listening"
    sleep 10
  fi
done

echo "MongoDB did not become reachable on port 27017 after 2 attempts"
echo "=== mongod.out ==="
cat /home/$CLOUD_USER/logs/mongod.out 2>/dev/null || true
echo "=== mongod.log ==="
cat /var/log/mongodb/mongod.log 2>/dev/null || true
echo "=== processes ==="
ps aux | grep mongod || true
echo "=== cloud-init-output.log (last 50 lines) ==="
tail -50 /var/log/cloud-init-output.log 2>/dev/null || true
echo "=== cloud-init.log (last 50 lines) ==="
tail -50 /var/log/cloud-init.log 2>/dev/null || true
exit 1