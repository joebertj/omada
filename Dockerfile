FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive TZ=UTC
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Base tools + Java + jsvc + dumb-init (no Omada yet)
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg tzdata \
      openjdk-17-jre-headless \
      jsvc \
      dumb-init \
      procps net-tools psmisc \
      libcap2 libcap2-bin \
  && rm -rf /var/lib/apt/lists/*

# Exact local prereqs: legacy OpenSSL 1.1 and commons-daemon Java JAR
COPY libssl1.1_1.1.0g-2ubuntu4_amd64.deb /tmp/libssl1.1.deb
COPY libcommons-daemon-java_1.0.15-11build1_all.deb /tmp/libcommons-daemon-java.deb

RUN dpkg -i /tmp/libssl1.1.deb || (apt-get update && apt-get -y -f install && dpkg -i /tmp/libssl1.1.deb) \
 && dpkg -i /tmp/libcommons-daemon-java.deb || (apt-get -y -f install && dpkg -i /tmp/libcommons-daemon-java.deb) \
 && rm -f /tmp/libssl1.1.deb /tmp/libcommons-daemon-java.deb \
 && rm -rf /var/lib/apt/lists/*

# MongoDB 4.4.29 (focal channel; built with OpenSSL 1.1.0g)
RUN curl -fsSL https://pgp.mongodb.com/server-4.4.asc \
      | gpg --dearmor -o /usr/share/keyrings/mongodb-4.4.gpg \
 && echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-4.4.gpg ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/4.4 multiverse" \
      > /etc/apt/sources.list.d/mongodb-org-4.4.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      mongodb-org=4.4.29 mongodb-org-server=4.4.29 mongodb-org-shell=4.4.29 mongodb-org-mongos=4.4.29 mongodb-org-tools=4.4.29 \
 && rm -rf /var/lib/apt/lists/*

# Copy Omada .deb but DO NOT install at build time
COPY omada_v5.15.24.19_linux_x64_20250724152622.deb /opt/omada/omada.deb

# Tiny entrypoint: install Omada, then start it
COPY docker-entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Optional: silence capability warning (safe when using ports 8088/8043)
ENV OMADA_DISABLE_CAPS=1

EXPOSE 8088 8043
ENTRYPOINT ["/usr/bin/dumb-init", "--", "/usr/local/bin/entrypoint.sh"]

