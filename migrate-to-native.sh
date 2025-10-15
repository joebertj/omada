#!/usr/bin/env bash
set -euo pipefail

# Configuration
REMOTE_HOST="10.27.79.7"
SSH_KEY="$HOME/.ssh/klti"
CONTAINER_NAME="omada"
BACKUP_DIR="/tmp/omada-backup-$(date +%Y%m%d-%H%M%S)"

echo "================================================"
echo "Omada Container → Native Migration Script"
echo "================================================"
echo ""

# Step 1: Connect to remote and stop container
echo "[1/6] Connecting to $REMOTE_HOST and stopping Omada container..."
ssh -i "$SSH_KEY" "$REMOTE_HOST" << 'REMOTE_SCRIPT'
set -euo pipefail

CONTAINER_NAME=omada

# Check if container exists and is running
if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  echo "  → Stopping container: $CONTAINER_NAME"
  docker stop "$CONTAINER_NAME"
elif docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  echo "  → Container $CONTAINER_NAME already stopped"
else
  echo "  → Container $CONTAINER_NAME not found"
fi
REMOTE_SCRIPT

echo ""

# Step 2: Backup Docker volume data
echo "[2/6] Backing up Docker volume data..."
ssh -i "$SSH_KEY" "$REMOTE_HOST" << REMOTE_SCRIPT
set -euo pipefail

BACKUP_DIR="$BACKUP_DIR"
mkdir -p "\$BACKUP_DIR"

# Check if volumes exist
if docker volume ls --format '{{.Name}}' | grep -q "omada-data"; then
  echo "  → Copying omada-data volume..."
  docker run --rm -v omada-data:/source -v "\$BACKUP_DIR":/backup ubuntu:24.04 \
    bash -c "cd /source && tar czf /backup/omada-data.tar.gz ."
  echo "  → Data backed up to \$BACKUP_DIR/omada-data.tar.gz"
else
  echo "  → Warning: omada-data volume not found"
fi

if docker volume ls --format '{{.Name}}' | grep -q "omada-logs"; then
  echo "  → Copying omada-logs volume..."
  docker run --rm -v omada-logs:/source -v "\$BACKUP_DIR":/backup ubuntu:24.04 \
    bash -c "cd /source && tar czf /backup/omada-logs.tar.gz ."
  echo "  → Logs backed up to \$BACKUP_DIR/omada-logs.tar.gz"
else
  echo "  → Warning: omada-logs volume not found"
fi

echo "\$BACKUP_DIR"
REMOTE_SCRIPT

echo ""

# Step 3: Install system dependencies
echo "[3/6] Installing system dependencies on remote host..."
ssh -i "$SSH_KEY" "$REMOTE_HOST" << 'REMOTE_SCRIPT'
set -euo pipefail

echo "  → Updating package lists..."
sudo apt-get update -qq

echo "  → Installing base dependencies..."
sudo apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  gnupg \
  tzdata \
  openjdk-17-jre-headless \
  jsvc \
  procps \
  net-tools \
  psmisc \
  libcap2 \
  libcap2-bin

echo "  → Dependencies installed"
REMOTE_SCRIPT

echo ""

# Step 4: Install MongoDB 4.4.29
echo "[4/6] Installing MongoDB 4.4.29..."
ssh -i "$SSH_KEY" "$REMOTE_HOST" << 'REMOTE_SCRIPT'
set -euo pipefail

# Check if MongoDB is already installed
if command -v mongod >/dev/null 2>&1; then
  MONGO_VERSION=$(mongod --version | grep "db version" | awk '{print $3}' || echo "unknown")
  echo "  → MongoDB already installed: $MONGO_VERSION"
  if [[ "$MONGO_VERSION" == "v4.4.29" ]]; then
    echo "  → Correct version, skipping installation"
    exit 0
  fi
fi

echo "  → Setting up MongoDB 4.4 repository..."
curl -fsSL https://pgp.mongodb.com/server-4.4.asc \
  | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-4.4.gpg

echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-4.4.gpg ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/4.4 multiverse" \
  | sudo tee /etc/apt/sources.list.d/mongodb-org-4.4.list

echo "  → Installing MongoDB 4.4.29..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
  mongodb-org=4.4.29 \
  mongodb-org-server=4.4.29 \
  mongodb-org-shell=4.4.29 \
  mongodb-org-mongos=4.4.29 \
  mongodb-org-tools=4.4.29

# Prevent MongoDB from auto-updating
echo "mongodb-org hold" | sudo dpkg --set-selections
echo "mongodb-org-server hold" | sudo dpkg --set-selections
echo "mongodb-org-shell hold" | sudo dpkg --set-selections
echo "mongodb-org-mongos hold" | sudo dpkg --set-selections
echo "mongodb-org-tools hold" | sudo dpkg --set-selections

echo "  → MongoDB 4.4.29 installed"
REMOTE_SCRIPT

echo ""

# Step 5: Upload and install dependencies
echo "[5/6] Uploading legacy dependencies..."
scp -i "$SSH_KEY" \
  "/home/joebert/omada/libssl1.1_1.1.0g-2ubuntu4_amd64.deb" \
  "/home/joebert/omada/libcommons-daemon-java_1.0.15-11build1_all.deb" \
  "$REMOTE_HOST:/tmp/"

ssh -i "$SSH_KEY" "$REMOTE_HOST" << 'REMOTE_SCRIPT'
set -euo pipefail

echo "  → Installing libssl1.1..."
sudo dpkg -i /tmp/libssl1.1_1.1.0g-2ubuntu4_amd64.deb || {
  sudo apt-get update && sudo apt-get -y -f install
  sudo dpkg -i /tmp/libssl1.1_1.1.0g-2ubuntu4_amd64.deb
}

echo "  → Installing libcommons-daemon-java..."
sudo dpkg -i /tmp/libcommons-daemon-java_1.0.15-11build1_all.deb || {
  sudo apt-get -y -f install
  sudo dpkg -i /tmp/libcommons-daemon-java_1.0.15-11build1_all.deb
}

rm -f /tmp/libssl1.1_1.1.0g-2ubuntu4_amd64.deb /tmp/libcommons-daemon-java_1.0.15-11build1_all.deb
echo "  → Legacy dependencies installed"
REMOTE_SCRIPT

echo ""

# Step 6: Install Omada and restore data
echo "[6/6] Installing Omada and restoring data..."
ssh -i "$SSH_KEY" "$REMOTE_HOST" << REMOTE_SCRIPT
set -euo pipefail

# Find the Omada .deb file in the omada folder
OMADA_DEB=\$(find ~/omada -name "omada_v*.deb" -o -name "omada*.deb" 2>/dev/null | head -1)

if [[ -z "\$OMADA_DEB" ]]; then
  echo "  ✗ Error: Omada .deb file not found in ~/omada/"
  echo "  Please ensure the .deb file is in the omada folder"
  exit 1
fi

echo "  → Found Omada package: \$OMADA_DEB"

# Check if Omada is already installed
if dpkg -s omadac >/dev/null 2>&1; then
  echo "  → Omada already installed, stopping service..."
  sudo tpeap stop || true
  sleep 2
else
  echo "  → Installing Omada..."
  sudo dpkg -i "\$OMADA_DEB" || {
    sudo apt-get update && sudo apt-get -y -f install
    sudo dpkg -i "\$OMADA_DEB"
  }
  
  # Stop the auto-started service
  echo "  → Stopping auto-started service..."
  sudo tpeap stop || true
  sleep 2
fi

# Restore data from backup
BACKUP_DIR=\$(ls -dt /tmp/omada-backup-* 2>/dev/null | head -1)

if [[ -z "\$BACKUP_DIR" ]]; then
  echo "  ✗ Warning: No backup directory found"
else
  echo "  → Found backup: \$BACKUP_DIR"
  
  if [[ -f "\$BACKUP_DIR/omada-data.tar.gz" ]]; then
    echo "  → Restoring data..."
    sudo mkdir -p /opt/tplink/EAPController/data
    sudo tar xzf "\$BACKUP_DIR/omada-data.tar.gz" -C /opt/tplink/EAPController/data/
    echo "  → Data restored successfully"
  else
    echo "  ✗ Warning: Data backup file not found"
  fi
  
  if [[ -f "\$BACKUP_DIR/omada-logs.tar.gz" ]]; then
    echo "  → Restoring logs..."
    sudo mkdir -p /opt/tplink/EAPController/logs
    sudo tar xzf "\$BACKUP_DIR/omada-logs.tar.gz" -C /opt/tplink/EAPController/logs/
    echo "  → Logs restored successfully"
  else
    echo "  ✗ Warning: Logs backup file not found"
  fi
fi

# Set correct ownership
echo "  → Setting file permissions..."
sudo chown -R omada:omada /opt/tplink/EAPController/data /opt/tplink/EAPController/logs 2>/dev/null || true

# Start Omada
echo "  → Starting Omada service..."
sudo tpeap start

# Check status
sleep 3
echo ""
echo "  → Checking service status..."
sudo tpeap status || true

echo ""
echo "  ✓ Migration complete!"
REMOTE_SCRIPT

echo ""
echo "================================================"
echo "Migration Complete!"
echo "================================================"
echo ""
echo "Omada is now running natively on $REMOTE_HOST"
echo "Access it at: https://$REMOTE_HOST:8043"
echo ""
echo "Next steps:"
echo "  1. Verify Omada is accessible at the URL above"
echo "  2. Check that your data/configuration was restored"
echo "  3. If everything works, you can remove the old container:"
echo "     ssh -i $SSH_KEY $REMOTE_HOST 'docker rm $CONTAINER_NAME'"
echo "  4. Optionally remove Docker volumes:"
echo "     ssh -i $SSH_KEY $REMOTE_HOST 'docker volume rm omada-data omada-logs'"
echo ""
echo "================================================"

