# Omada 5.15.24.19 on Ubuntu 20.04 (focal, amd64)
# Root-start fix: run control.sh as root; jsvc drops to 'omada'

FROM ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive
ARG OMADA_DEB_URL="https://static.tp-link.com/upload/software/2025/202508/20250802/omada_v5.15.24.19_linux_x64_20250724152622.deb"
ENV TZ=UTC LANG=C.UTF-8

# Base tools + jsvc + utils
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg tzdata dumb-init procps net-tools iputils-ping \
      xz-utils adduser passwd libcap2 jsvc && \
    rm -rf /var/lib/apt/lists/*

# Java 17 (fallback to 11 if 17 not available)
RUN apt-get update && \
    (apt-get install -y --no-install-recommends openjdk-17-jre-headless || \
     apt-get install -y --no-install-recommends openjdk-11-jre-headless) && \
    rm -rf /var/lib/apt/lists/*

# MongoDB 4.4 repo (amd64) + server (Omada launches mongod itself on 127.0.0.1:27217)
RUN mkdir -p /usr/share/keyrings && \
    curl -fsSL https://pgp.mongodb.com/server-4.4.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-4.4.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/mongodb-4.4.gpg] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/4.4 multiverse" \
      > /etc/apt/sources.list.d/mongodb-org-4.4.list && \
    apt-get update && apt-get install -y --no-install-recommends mongodb-org-server && \
    rm -rf /var/lib/apt/lists/*

# Omada user & dirs
RUN adduser --system --no-create-home --group omada || true && \
    mkdir -p /opt/tplink/EAPController/data /opt/tplink/EAPController/logs /opt/tplink/EAPController/work

WORKDIR /tmp

# Extract Omada payload (skip dpkg maintainer scripts)
RUN curl -fL "$OMADA_DEB_URL" -o omada.deb && \
    dpkg-deb -x omada.deb / && rm -f omada.deb && \
    ln -sf /usr/bin/mongod /opt/tplink/EAPController/bin/mongod && \
    chown -R omada:omada /opt/tplink/EAPController

# Entrypoint: run control.sh as ROOT (required), jsvc drops to 'omada'; tail logs; graceful stop
COPY --chmod=755 <<'SCRIPT' /usr/local/bin/omada-entrypoint.sh
#!/usr/bin/env bash
set -euo pipefail

OMADA_DIR="/opt/tplink/EAPController"
CTRL="${OMADA_DIR}/bin/control.sh"
LOG="${OMADA_DIR}/logs/server.log"

mkdir -p "${OMADA_DIR}/logs" "${OMADA_DIR}/work" "${OMADA_DIR}/data"
chown -R omada:omada "${OMADA_DIR}" || true
touch "${LOG}"

stop_omada() {
  echo "[entrypoint] Stopping Omada Controller..."
  "${CTRL}" stop || true
  pkill -P $$ tail || true
  exit 0
}
trap stop_omada SIGTERM SIGINT

echo "[entrypoint] Starting Omada Controller (root -> jsvc drops to 'omada')..."
"${CTRL}" start

sleep 2
echo "[entrypoint] Tailing logs: ${LOG}"
tail -F "${LOG}" & 
wait $!
SCRIPT

VOLUME ["/opt/tplink/EAPController/data", "/opt/tplink/EAPController/logs"]

# Required ports
EXPOSE 8043 8088 27002 29811 29812 29813
EXPOSE 27001/udp 29810/udp

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["/usr/local/bin/omada-entrypoint.sh"]

