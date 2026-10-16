#!/bin/bash
set -eux

# Wait for network to be ready
sleep 10

# Install dependencies
apt-get update -y || true
apt-get install -y curl procps iproute2 || true

# Download MongoDB 7.0.14 (ubuntu2204 build for Ubuntu 22.04 Jammy)
MONGO_TARBALL="mongodb-linux-x86_64-ubuntu2204-7.0.14.tgz"
curl -fsSL "https://fastdl.mongodb.org/linux/${MONGO_TARBALL}" -o /tmp/mongodb.tgz --retry 3 --retry-delay 5

# Extract MongoDB
mkdir -p /tmp/mongodb-extract
tar -xzf /tmp/mongodb.tgz -C /tmp/mongodb-extract

# Copy binaries to /usr/local/bin
MONGO_DIR=$(ls -d /tmp/mongodb-extract/mongodb-linux-x86_64-ubuntu2204-7.0.14)
cp -r "${MONGO_DIR}/bin/"* /usr/local/bin/

# Create MongoDB directories
mkdir -p /data/db /var/log/mongodb

# Set ownership to the cloud user
CLOUD_USER=$(whoami)
chown -R $CLOUD_USER:$CLOUD_USER /data/db /var/log/mongodb 2>/dev/null || true

# Create logs directory for our output
mkdir -p /home/$CLOUD_USER/logs

# ============================================================
# Step 1: Start MongoDB WITHOUT auth to create admin user
# ============================================================
echo "Starting MongoDB without authentication to create admin user..."

nohup mongod \
  --bind_ip 0.0.0.0 \
  --dbpath /data/db \
  --logpath /var/log/mongodb/mongod.log \
  --fork \
  --pidfilepath /var/run/mongod.pid \
  > /home/$CLOUD_USER/logs/mongod.out 2>&1 &

# Wait for mongod to fully start and bind
echo "Waiting for MongoDB to start (initial, without auth) ..."
for i in $(seq 1 30); do
  if ss -tlnp 2>/dev/null | grep -q :27017 || netstat -tlnp 2>/dev/null | grep -q :27017; then
    echo "MongoDB is listening on port 27017"
    sleep 3
    break
  fi
  echo "Attempt $i/30 - checking port 27017..."
  sleep 2
done

if ! ss -tlnp 2>/dev/null | grep -q :27017 && ! netstat -tlnp 2>/dev/null | grep -q :27017; then
  echo "MongoDB failed to start within 60s"
  cat /home/$CLOUD_USER/logs/mongod.out 2>/dev/null || true
  cat /var/log/mongodb/mongod.log 2>/dev/null || true
  exit 1
fi

# ============================================================
# Create admin user using MongoDB localhost exception
# ============================================================
# MongoDB 7.0 ships mongosh instead of the legacy mongo shell.
# Create a symlink so mongosh is also available as 'mongo' for compatibility.
if command -v mongosh >/dev/null 2>&1; then
  ln -sf "$(which mongosh)" /usr/local/bin/mongo 2>/dev/null || true
fi

echo "Creating admin user..."
mongosh admin <<EOF
db.createUser({
  user: "admin",
  pwd: "${mongo_admin_password}",
  roles: [{ role: "root", db: "admin" }]
})
EOF
echo "Admin user created successfully"

# ============================================================
# Step 2: Stop mongod and restart WITH --auth
# ============================================================
echo "Stopping MongoDB to restart with authentication enabled..."
pkill -f mongod || true
sleep 5

# Ensure port is fully released
for i in $(seq 1 10); do
  if ! ss -tlnp 2>/dev/null | grep -q :27017 && ! netstat -tlnp 2>/dev/null | grep -q :27017; then
    break
  fi
  echo "Waiting for port 27017 to be released (attempt $i)..."
  sleep 2
done

echo "Starting MongoDB with authentication enabled (--auth)..."
nohup mongod \
  --auth \
  --bind_ip 0.0.0.0 \
  --dbpath /data/db \
  --logpath /var/log/mongodb/mongod.log \
  --fork \
  --pidfilepath /var/run/mongod.pid \
  > /home/$CLOUD_USER/logs/mongod.out 2>&1 &

# Wait for mongod to fully start with auth
echo "Waiting for MongoDB to start with auth..."
for i in $(seq 1 30); do
  if ss -tlnp 2>/dev/null | grep -q :27017 || netstat -tlnp 2>/dev/null | grep -q :27017; then
    echo "MongoDB is now listening on port 27017 with authentication enabled"
    exit 0
  fi
  echo "Attempt $i/30 - checking port 27017 with auth..."
  sleep 2
done

echo "MongoDB failed to start with auth within 60s"
echo "=== mongod.out ==="
cat /home/$CLOUD_USER/logs/mongod.out 2>/dev/null || true
echo "=== mongod.log ==="
cat /var/log/mongodb/mongod.log 2>/dev/null || true
echo "=== processes ==="
ps aux | grep mongod || true
exit 1