# Omada Controller 5.15.24.19 with MongoDB 4.4.29 on Ubuntu 24.04 (noble)
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Core utilities
RUN apt-get update && apt-get install -y \
    dumb-init curl gnupg ca-certificates gdebi-core openjdk-17-jre-headless && \
    rm -rf /var/lib/apt/lists/*

# --- Install pinned legacy deps from local .debs ---
# jsvc (Commons Daemon 1.0.15)
COPY libcommons-daemon-java_1.0.15-11build1_all.deb /tmp/libcommons-daemon-java.deb
RUN gdebi -n /tmp/libcommons-daemon-java.deb && rm -f /tmp/libcommons-daemon-java.deb

# libssl1.1 (needed for MongoDB 4.4.29)
COPY libssl1.1_1.1.0g-2ubuntu4_amd64.deb /tmp/libssl1.1.deb
RUN gdebi -n /tmp/libssl1.1.deb && rm -f /tmp/libssl1.1.deb && \
    apt-mark hold libssl1.1

# --- MongoDB 4.4.29 (focal build) ---
RUN curl -fsSL https://pgp.mongodb.com/server-4.4.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-4.4.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/mongodb-4.4.gpg] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/4.4 multiverse" \
      > /etc/apt/sources.list.d/mongodb-org-4.4.list && \
    apt-get update && \
    apt-get install -y mongodb-org=4.4.29 mongodb-org-server=4.4.29 \
                       mongodb-org-shell=4.4.29 mongodb-org-mongos=4.4.29 \
                       mongodb-org-tools=4.4.29 && \
    rm -rf /var/lib/apt/lists/*

# --- Omada Controller ---
COPY omada_v5.15.24.19_linux_x64_20250724152622.deb /tmp/omada.deb
RUN apt-get update && apt-get install -y /tmp/omada.deb && \
    rm -f /tmp/omada.deb && rm -rf /var/lib/apt/lists/*

# Keep a skeleton for seeding fresh volumes
RUN cp -a /opt/tplink/EAPController /opt/tplink/EAPController.dist

# Create omada user/group (match host IDs: uid=110, gid=113)
RUN groupadd -g 113 omada && \
    useradd -u 110 -g 113 -d /opt/tplink/EAPController/data -s /usr/sbin/nologin omada || true

# Add entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/bin/dumb-init","--","/usr/local/bin/entrypoint.sh"]

# Expose Omada + Mongo ports
EXPOSE 8043 8088 8843 27017 29810/udp 29811/udp 29812/udp 29813/udp

