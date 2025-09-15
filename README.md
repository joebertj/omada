# Omada Controller (Docker)

Containerized **TP-Link Omada SDN Controller v5.15.24.19** on Ubuntu 20.04 (amd64).  
Image runs `control.sh` as root (drops to `omada` via `jsvc`), uses **OpenJDK 11 (JDK)** and **MongoDB 4.4**.  
Data/logs persist in Docker volumes.

---

## Files
- **Dockerfile** – builds the image (focal/amd64).
- **build.sh** – builds with Buildx and loads the image locally.
- **run.sh** – runs the container (auto stop+rm if the name already exists).
- **colima.sh** – one-shot setup for **Colima** (with amd64 VM) + **Buildx** on macOS.

---

## Quickstart (macOS with Colima)

```bash
# 0) One time: prepare Colima + Buildx (amd64 VM)
chmod +x colima.sh && ./colima.sh

# 1) Build the image
chmod +x build.sh && ./build.sh

# 2) Run the controller
chmod +x run.sh && ./run.sh
# or bind to VPN iface/IP only:
#   BIND_IF=utun6 ./run.sh
#   BIND_IP=10.8.0.5 ./run.sh

## Pre steps
# 1) Download osc if not yet available
wget https://static.tp-link.com/upload/software/2025/202508/20250802/omada_v5.15.24.19_linux_x64_20250724152622.deb
