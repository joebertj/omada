#!/usr/bin/env bash
set -euo pipefail

NAME=${NAME:-omada}
IMAGE=${IMAGE:-omada:5.15.24.19}
PLATFORM=${PLATFORM:-linux/amd64}

# Optional: bind to a specific IP (e.g., VPN iface utun6)
BIND_IP=${BIND_IP:-}
BIND_IF=${BIND_IF:-}

if [[ -n "$BIND_IF" && -z "$BIND_IP" ]]; then
  # macOS: get IPv4 of interface (e.g., utun6)
  BIND_IP=$(ifconfig "$BIND_IF" 2>/dev/null | awk '/inet /{print $2; exit}') || true
fi

port() {
  local p="$1"
  if [[ -n "$BIND_IP" ]]; then echo "-p ${BIND_IP}:${p}:${p}"; else echo "-p ${p}:${p}"; fi
}
port_udp() {
  local p="$1"
  if [[ -n "$BIND_IP" ]]; then echo "-p ${BIND_IP}:${p}:${p}/udp"; else echo "-p ${p}:${p}/udp"; fi
}

# Stop & remove existing container (if any)
if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  echo "Stopping existing container: $NAME"
  docker stop "$NAME" >/dev/null || true
  echo "Removing existing container: $NAME"
  docker rm "$NAME" >/dev/null || true
fi

# Ensure volumes exist
docker volume create omada-data >/dev/null || true
docker volume create omada-logs >/dev/null || true

# Run
exec docker run -d --name "$NAME" --platform="$PLATFORM" \
  --cap-add=SETPCAP \
  --cap-add=NET_BIND_SERVICE \
  --cap-add=SETFCAP \
  --privileged \
  $(port 8043) \
  $(port 8088) \
  $(port_udp 27001) \
  $(port 27002) \
  $(port_udp 29810) \
  $(port 29811) \
  $(port 29812) \
  $(port 29813) \
  -v omada-data:/opt/tplink/EAPController/data \
  -v omada-logs:/opt/tplink/EAPController/logs \
  --restart unless-stopped \
  "$IMAGE"
