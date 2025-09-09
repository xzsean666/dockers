FROM bitnami/postgresql:16

# Install required packages
USER root

RUN mkdir -p /var/lib/apt/lists/partial && \
    apt-get update && \
    apt-get install -y wget ca-certificates

# Set environment variables
ENV http_proxy=http://127.0.0.1:7898
ENV https_proxy=http://127.0.0.1:7897

# Download and install WAL-G with checksum verification
RUN WALG_VERSION=v3.0.7 && \
    WALG_BINARY=wal-g-pg-ubuntu-22.04-amd64 && \
    WALG_URL=https://github.com/wal-g/wal-g/releases/download/${WALG_VERSION}/${WALG_BINARY} && \
    WALG_CHECKSUM_URL=https://github.com/wal-g/wal-g/releases/download/${WALG_VERSION}/${WALG_BINARY}.sha256 && \
    cd /tmp && \
    wget ${WALG_URL} -O ${WALG_BINARY} && \
    wget ${WALG_CHECKSUM_URL} -O ${WALG_BINARY}.sha256 && \
    sha256sum -c ${WALG_BINARY}.sha256 && \
    mv ${WALG_BINARY} /usr/local/bin/wal-g && \
    chmod +x /usr/local/bin/wal-g && \
    rm -f /tmp/wal-g* && \
    wal-g --version

# Create directory for WAL-G configuration
RUN mkdir -p /etc/wal-g

# Copy WAL-G configuration
COPY wal-g.conf /etc/wal-g/

# Set environment variables
ENV WALG_CONFIG_FILE=/etc/wal-g/wal-g.conf
ENV WALG_COMPRESSION_METHOD=lz4
ENV WALG_DISK_RATE_LIMIT=10485760
ENV WALG_NETWORK_RATE_LIMIT=10485760 