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
echo ""

# Web UI ports
echo "→ Allowing port 8043/tcp (HTTPS Web UI)"
sudo ufw allow 8043/tcp comment 'Omada HTTPS Web UI'

echo "→ Allowing port 8088/tcp (HTTP Web UI)"
sudo ufw allow 8088/tcp comment 'Omada HTTP Web UI'

# Discovery and management ports
echo "→ Allowing port 27001/udp (Discovery)"
sudo ufw allow 27001/udp comment 'Omada Discovery'

echo "→ Allowing port 27002/tcp (Manager)"
sudo ufw allow 27002/tcp comment 'Omada Manager'

# EAP management ports
echo "→ Allowing port 29810/udp (EAP Discovery)"
sudo ufw allow 29810/udp comment 'Omada EAP Discovery'

echo "→ Allowing port 29811/tcp (EAP Management)"
sudo ufw allow 29811/tcp comment 'Omada EAP Management'

echo "→ Allowing port 29812/tcp (EAP Adoption)"
sudo ufw allow 29812/tcp comment 'Omada EAP Adoption'

echo "→ Allowing port 29813/tcp (EAP Upgrade)"
sudo ufw allow 29813/tcp comment 'Omada EAP Upgrade'

echo "→ Allowing port 29814/tcp (EAP Statistics)"
sudo ufw allow 29814/tcp comment 'Omada EAP Statistics'

echo "→ Allowing port 29815/tcp (EAP RTT)"
sudo ufw allow 29815/tcp comment 'Omada EAP RTT'

echo "→ Allowing port 29816/tcp (EAP Log)"
sudo ufw allow 29816/tcp comment 'Omada EAP Log'

echo ""
echo "Firewall rules applied. Current status:"
echo ""
sudo ufw status numbered

echo ""
echo "================================================"
echo "Firewall configuration complete!"
echo "================================================"

