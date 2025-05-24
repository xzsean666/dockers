FROM bitnami/postgresql:16

# Install required packages
RUN install_packages wget ca-certificates

# Download and install WAL-G with checksum verification
RUN WALG_VERSION=v2.0.1 && \
    WALG_BINARY=wal-g-pg-ubuntu-latest-amd64 && \
    WALG_URL=https://github.com/wal-g/wal-g/releases/download/${WALG_VERSION}/${WALG_BINARY} && \
    WALG_CHECKSUM_URL=https://github.com/wal-g/wal-g/releases/download/${WALG_VERSION}/${WALG_BINARY}.sha256 && \
    cd /tmp && \
    wget ${WALG_URL} -O wal-g && \
    wget ${WALG_CHECKSUM_URL} -O wal-g.sha256 && \
    sha256sum -c wal-g.sha256 && \
    mv wal-g /usr/local/bin/wal-g && \
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