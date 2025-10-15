#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="omada"
BACKUP_DIR="/tmp/omada-backup-$(date +%Y%m%d-%H%M%S)"

echo "================================================"
echo "Omada Container → Native Migration Script"
echo "================================================"
echo ""
echo "Running migration on local host..."
echo ""

# Step 1: Stop container
echo "[1/6] Stopping Omada container..."
if sudo docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  echo "  → Stopping container: $CONTAINER_NAME"
  sudo docker stop "$CONTAINER_NAME"
elif sudo docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  echo "  → Container $CONTAINER_NAME already stopped"
else
  echo "  → Container $CONTAINER_NAME not found"
fi

echo ""

# Step 2: Backup Docker volume data
echo "[2/6] Backing up Docker volume data..."
mkdir -p "$BACKUP_DIR"

# Check if volumes exist
if sudo docker volume ls --format '{{.Name}}' | grep -q "omada-data"; then
  echo "  → Copying omada-data volume..."
  sudo docker run --rm -v omada-data:/source -v "$BACKUP_DIR":/backup ubuntu:24.04 \
    bash -c "cd /source && tar czf /backup/omada-data.tar.gz ."
  echo "  → Data backed up to $BACKUP_DIR/omada-data.tar.gz"
else
  echo "  → Warning: omada-data volume not found"
fi

if sudo docker volume ls --format '{{.Name}}' | grep -q "omada-logs"; then
  echo "  → Copying omada-logs volume..."
  sudo docker run --rm -v omada-logs:/source -v "$BACKUP_DIR":/backup ubuntu:24.04 \
    bash -c "cd /source && tar czf /backup/omada-logs.tar.gz ."
  echo "  → Logs backed up to $BACKUP_DIR/omada-logs.tar.gz"
else
  echo "  → Warning: omada-logs volume not found"
fi

echo ""

# Step 3: Install system dependencies
echo "[3/6] Installing system dependencies..."
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
echo ""

# Step 4: Install MongoDB 4.4.29
echo "[4/6] Installing MongoDB 4.4.29..."

# Check if MongoDB is already installed
if command -v mongod >/dev/null 2>&1; then
  MONGO_VERSION=$(mongod --version | grep "db version" | awk '{print $3}' || echo "unknown")
  echo "  → MongoDB already installed: $MONGO_VERSION"
  if [[ "$MONGO_VERSION" == "v4.4.29" ]]; then
    echo "  → Correct version, skipping installation"
  else
    echo "  → Different version found, continuing with installation..."
  fi
fi

if ! command -v mongod >/dev/null 2>&1 || [[ "$(mongod --version | grep 'db version' | awk '{print $3}')" != "v4.4.29" ]]; then
  echo "  → Setting up MongoDB 4.4 repository..."
  curl -fsSL https://pgp.mongodb.com/server-4.4.asc \
    | sudo gpg --no-tty --dearmor -o /usr/share/keyrings/mongodb-4.4.gpg

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
fi

echo ""

# Step 5: Install legacy dependencies
echo "[5/6] Installing legacy dependencies..."

# Find the omada directory (could be ~/omada or current directory)
OMADA_DIR="$HOME/omada"
if [[ ! -d "$OMADA_DIR" ]]; then
  OMADA_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

if [[ -f "$OMADA_DIR/libssl1.1_1.1.0g-2ubuntu4_amd64.deb" ]]; then
  echo "  → Installing libssl1.1..."
  sudo dpkg -i "$OMADA_DIR/libssl1.1_1.1.0g-2ubuntu4_amd64.deb" || {
    sudo apt-get update && sudo apt-get -y -f install
    sudo dpkg -i "$OMADA_DIR/libssl1.1_1.1.0g-2ubuntu4_amd64.deb"
  }
else
  echo "  ✗ Warning: libssl1.1 .deb not found in $OMADA_DIR"
fi

if [[ -f "$OMADA_DIR/libcommons-daemon-java_1.0.15-11build1_all.deb" ]]; then
  echo "  → Installing libcommons-daemon-java..."
  sudo dpkg -i "$OMADA_DIR/libcommons-daemon-java_1.0.15-11build1_all.deb" || {
    sudo apt-get -y -f install
    sudo dpkg -i "$OMADA_DIR/libcommons-daemon-java_1.0.15-11build1_all.deb"
  }
else
  echo "  ✗ Warning: libcommons-daemon-java .deb not found in $OMADA_DIR"
fi

echo "  → Legacy dependencies installed"
echo ""

# Step 6: Install Omada and restore data
echo "[6/6] Installing Omada and restoring data..."

# Find the Omada .deb file
OMADA_DEB=$(find "$OMADA_DIR" -name "omada_v*.deb" -o -name "omada*.deb" 2>/dev/null | head -1)

if [[ -z "$OMADA_DEB" ]]; then
  echo "  ✗ Error: Omada .deb file not found in $OMADA_DIR"
  echo "  Please ensure the .deb file is in the omada folder"
  exit 1
fi

echo "  → Found Omada package: $OMADA_DEB"

# Check if Omada is already installed
if dpkg -s omadac >/dev/null 2>&1; then
  echo "  → Omada already installed, stopping service..."
  sudo tpeap stop || true
  sleep 2
else
  echo "  → Installing Omada..."
  sudo dpkg -i "$OMADA_DEB" || {
    sudo apt-get update && sudo apt-get -y -f install
    sudo dpkg -i "$OMADA_DEB"
  }
  
  # Stop the auto-started service
  echo "  → Stopping auto-started service..."
  sudo tpeap stop || true
  sleep 2
fi

# Restore data from backup
if [[ -f "$BACKUP_DIR/omada-data.tar.gz" ]]; then
  echo "  → Restoring data..."
  sudo mkdir -p /opt/tplink/EAPController/data
  sudo tar xzf "$BACKUP_DIR/omada-data.tar.gz" -C /opt/tplink/EAPController/data/
  echo "  → Data restored successfully"
else
  echo "  ✗ Warning: Data backup file not found at $BACKUP_DIR/omada-data.tar.gz"
fi

if [[ -f "$BACKUP_DIR/omada-logs.tar.gz" ]]; then
  echo "  → Restoring logs..."
  sudo mkdir -p /opt/tplink/EAPController/logs
  sudo tar xzf "$BACKUP_DIR/omada-logs.tar.gz" -C /opt/tplink/EAPController/logs/
  echo "  → Logs restored successfully"
else
  echo "  ✗ Warning: Logs backup file not found at $BACKUP_DIR/omada-logs.tar.gz"
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
echo ""
echo "================================================"
echo "Migration Complete!"
echo "================================================"
echo ""
echo "Omada is now running natively on this host"
echo "Access it at: https://$(hostname -I | awk '{print $1}'):8043"
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
echo "Next steps:"
echo "  1. Verify Omada is accessible at the URL above"
echo "  2. Check that your data/configuration was restored"
echo "  3. If everything works, you can remove the old container:"
echo "     sudo docker rm $CONTAINER_NAME"
echo "  4. Optionally remove Docker volumes:"
echo "     sudo docker volume rm omada-data omada-logs"
echo ""
echo "================================================"

