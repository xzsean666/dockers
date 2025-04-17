FROM bitnami/postgresql:16

# Install required packages
RUN install_packages wget

# Download and install WAL-G
RUN wget https://github.com/wal-g/wal-g/releases/download/v2.0.1/wal-g-pg-ubuntu-latest-amd64 -O /usr/local/bin/wal-g \
    && chmod +x /usr/local/bin/wal-g

# Create directory for WAL-G configuration
RUN mkdir -p /etc/wal-g

# Copy WAL-G configuration
COPY wal-g.conf /etc/wal-g/

# Set environment variables
ENV WALG_CONFIG_FILE=/etc/wal-g/wal-g.conf
ENV WALG_COMPRESSION_METHOD=lz4
ENV WALG_DISK_RATE_LIMIT=10485760
ENV WALG_NETWORK_RATE_LIMIT=10485760 