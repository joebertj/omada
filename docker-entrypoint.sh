#!/usr/bin/env bash
set -Eeuo pipefail

OMADA_DEB=/opt/omada/omada.deb
LOG_DIR=/opt/tplink/EAPController/logs

# Install Omada if not yet installed
if ! dpkg -s omadac >/dev/null 2>&1; then
  echo "[entrypoint] Installing Omada from $OMADA_DEB ..."
  dpkg -i "$OMADA_DEB" || { apt-get update && apt-get -y -f install && dpkg -i "$OMADA_DEB"; }
fi

# Optionally disable capability step (quiet log in containers)
if [[ "${OMADA_DISABLE_CAPS:-1}" = "1" ]] && [[ -f /opt/tplink/EAPController/bin/control.sh ]]; then
  sed -i -E 's/(^.*set_caps.*$)/# \1  # disabled in container/g' /opt/tplink/EAPController/bin/control.sh || true
fi

# Restart controller (postinst may auto-start)
tpeap stop >/dev/null 2>&1 || true
sleep 1
tpeap start

# Keep container up by following logs; do NOT create any data dirs/files
mkdir -p "$LOG_DIR" || true
: > "$LOG_DIR/server.log" 2>/dev/null || true
: > "$LOG_DIR/startup.log" 2>/dev/null || true
: > "$LOG_DIR/mongod.log" 2>/dev/null || true

echo "[entrypoint] Omada started. Following logs..."
exec tail -F "$LOG_DIR/server.log" "$LOG_DIR/startup.log" "$LOG_DIR/mongod.log"

