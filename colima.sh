#!/usr/bin/env bash
# colima.sh — clean reset + Colima (x86_64 VM) + Buildx builder (macOS)
# Usage: chmod +x colima.sh && ./colima.sh
# Env overrides: CPU=4 MEMORY=8 DISK=40 ARCH=x86_64 BUILDER_NAME=colima-builder

set -euo pipefail

# ---------- Config ----------
CPU="${CPU:-4}"
MEMORY="${MEMORY:-8}"      # GB
DISK="${DISK:-40}"         # GB
ARCH="${ARCH:-x86_64}"     # x86_64 recommended for MongoDB 4.4
BUILDER_NAME="${BUILDER_NAME:-colima-builder}"

log()  { printf "\033[1;32m==> %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33mWARN: %s\033[0m\n" "$*"; }
die()  { printf "\033[1;31mERR : %s\033[0m\n" "$*"; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "This script is for macOS."

# ---------- Homebrew & tools ----------
if ! command -v brew >/dev/null 2>&1; then
  die "Homebrew not found. Install from https://brew.sh then re-run."
fi

log "Installing/upgrading prerequisites (docker, compose, buildx, colima, qemu, lima guest agents)…"
brew update >/dev/null
brew install docker docker-compose docker-buildx colima qemu lima-additional-guestagents >/dev/null || true
brew upgrade docker docker-compose docker-buildx colima qemu lima-additional-guestagents >/dev/null || true

# Apple Silicon: install Rosetta (no-op on Intel)
if [[ "$(uname -m)" == "arm64" ]]; then
  log "Ensuring Rosetta is installed (required for x86_64 VM & emulation)…"
  sudo /usr/sbin/softwareupdate --install-rosetta --agree-to-license || true
fi

# Make sure buildx plugin is discoverable by Docker CLI
if ! docker buildx version >/dev/null 2>&1; then
  log "Linking docker-buildx CLI plugin…"
  mkdir -p "$HOME/.docker/cli-plugins"
  ln -sf "$(brew --prefix)/opt/docker-buildx/bin/docker-buildx" \
         "$HOME/.docker/cli-plugins/docker-buildx"
  chmod +x "$HOME/.docker/cli-plugins/docker-buildx"
fi

# ---------- Clean broken docker/contexts ----------
log "Cleaning Docker contexts…"
docker context use default >/dev/null 2>&1 || true
docker context rm colima   >/dev/null 2>&1 || true

# ---------- Reset Colima VM ----------
log "Resetting Colima VM (stop & delete)…"
colima stop   >/dev/null 2>&1 || true
colima delete -f >/dev/null 2>&1 || true
if command -v limactl >/dev/null 2>&1; then
  limactl stop colima   >/dev/null 2>&1 || true
  limactl delete -f colima >/dev/null 2>&1 || true
fi

FLAGS=(--arch "${ARCH}" --network-address --cpu "${CPU}" --memory "${MEMORY}" --disk "${DISK}" --runtime docker)

start_vz() {
  # vZ is fastest on Apple Silicon; enable Rosetta for amd64 images
  colima start "${FLAGS[@]}" --vm-type vz --vz-rosetta
}
start_qemu() {
  colima start "${FLAGS[@]}" --vm-type qemu
}

# ---------- Start Colima fresh ----------
log "Starting Colima (arch=${ARCH}, cpu=${CPU}, mem=${MEMORY}G, disk=${DISK}G)…"
START_OK=0
if [[ "$(uname -m)" == "arm64" ]]; then
  # Try vZ first on Apple Silicon; fall back to QEMU
  if start_vz 2>/dev/null; then
    START_OK=1
  else
    warn "vZ not available or failed; falling back to QEMU…"
    if start_qemu 2>/dev/null; then
      START_OK=1
    fi
  fi
else
  # Intel Macs: default hypervisor is fine
  if colima start "${FLAGS[@]}" 2>/dev/null; then
    START_OK=1
  fi
fi

if [[ $START_OK -ne 1 ]]; then
  # Recover from “host agent is running but driver is not” / “cannot restart, VM not previously started”
  warn "Colima start failed; attempting deep clean and QEMU fallback…"
  colima stop   >/dev/null 2>&1 || true
  colima delete -f >/dev/null 2>&1 || true
  rm -rf "$HOME/.colima/_lima/colima" 2>/dev/null || true
  start_qemu
fi

# ---------- Point Docker to Colima ----------
log "Selecting Docker context: colima"
docker context use colima >/dev/null

# ---------- Buildx builder ----------
if docker buildx inspect "${BUILDER_NAME}" >/dev/null 2>&1; then
  log "Using existing Buildx builder: ${BUILDER_NAME}"
  docker buildx use "${BUILDER_NAME}"
else
  log "Creating Buildx builder: ${BUILDER_NAME}"
  docker buildx create --name "${BUILDER_NAME}" --driver docker-container --use
fi
docker buildx inspect --bootstrap >/dev/null

# ---------- Summary ----------
echo
log "Colima + Buildx ready"
docker info 2>/dev/null | awk '/Architecture|Default Address Pools/ {print}'
echo "Context       : $(docker context show)"
echo "Builder       : ${BUILDER_NAME}"
echo
echo "Example amd64 build (loads image locally):"
echo "  docker buildx build --builder ${BUILDER_NAME} --platform=linux/amd64 --output=type=docker -t your/image:tag ."

