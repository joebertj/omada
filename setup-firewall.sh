#!/usr/bin/env bash
set -euo pipefail

echo "================================================"
echo "Omada UFW Firewall Configuration"
echo "================================================"
echo ""

# Enable UFW if not already enabled
if ! sudo ufw status | grep -q "Status: active"; then
  echo "Enabling UFW..."
  sudo ufw --force enable
fi

echo "Configuring firewall rules for Omada Controller..."
echo "Restricting access to 10.27.79.0/24 subnet only"
echo ""

# Subnet restriction
SUBNET="10.27.79.0/24"

# Web UI ports
echo "→ Allowing port 8043/tcp (HTTPS Web UI) from $SUBNET"
sudo ufw allow from "$SUBNET" to any port 8043 proto tcp comment 'Omada HTTPS Web UI'

echo "→ Allowing port 8088/tcp (HTTP Web UI) from $SUBNET"
sudo ufw allow from "$SUBNET" to any port 8088 proto tcp comment 'Omada HTTP Web UI'

# Discovery and management ports
echo "→ Allowing port 27001/udp (Discovery) from $SUBNET"
sudo ufw allow from "$SUBNET" to any port 27001 proto udp comment 'Omada Discovery'

echo "→ Allowing port 27002/tcp (Manager) from $SUBNET"
sudo ufw allow from "$SUBNET" to any port 27002 proto tcp comment 'Omada Manager'

# EAP management ports
echo "→ Allowing port 29810/udp (EAP Discovery) from $SUBNET"
sudo ufw allow from "$SUBNET" to any port 29810 proto udp comment 'Omada EAP Discovery'

echo "→ Allowing port 29811/tcp (EAP Management) from $SUBNET"
sudo ufw allow from "$SUBNET" to any port 29811 proto tcp comment 'Omada EAP Management'

echo "→ Allowing port 29812/tcp (EAP Adoption) from $SUBNET"
sudo ufw allow from "$SUBNET" to any port 29812 proto tcp comment 'Omada EAP Adoption'

echo "→ Allowing port 29813/tcp (EAP Upgrade) from $SUBNET"
sudo ufw allow from "$SUBNET" to any port 29813 proto tcp comment 'Omada EAP Upgrade'

echo "→ Allowing port 29814/tcp (EAP Statistics) from $SUBNET"
sudo ufw allow from "$SUBNET" to any port 29814 proto tcp comment 'Omada EAP Statistics'

echo "→ Allowing port 29815/tcp (EAP RTT) from $SUBNET"
sudo ufw allow from "$SUBNET" to any port 29815 proto tcp comment 'Omada EAP RTT'

echo "→ Allowing port 29816/tcp (EAP Log) from $SUBNET"
sudo ufw allow from "$SUBNET" to any port 29816 proto tcp comment 'Omada EAP Log'

echo ""
echo "Firewall rules applied. Current status:"
echo ""
sudo ufw status numbered

echo ""
echo "================================================"
echo "Firewall configuration complete!"
echo "================================================"

