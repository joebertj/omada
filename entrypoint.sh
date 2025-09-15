#!/usr/bin/env bash
set -euo pipefail
BASE=/opt/tplink/EAPController
DIST=/opt/tplink/EAPController.dist

# Seed empty mounted dirs if needed
for d in data logs work; do
  mkdir -p "$BASE/$d"
  if [ -z "$(ls -A "$BASE/$d" 2>/dev/null || true)" ] && [ -d "$DIST/$d" ]; then
    cp -a "$DIST/$d/." "$BASE/$d/" || true
  fi
done

# Ownership
chown -R omada:omada "$BASE" 2>/dev/null || true

# Complete dpkg if pending
apt-get -y -f install >/dev/null 2>&1 || true
dpkg --configure -a >/dev/null 2>&1 || true

exec /usr/bin/tpeap start

