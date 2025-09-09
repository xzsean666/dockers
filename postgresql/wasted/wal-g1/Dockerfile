# WAL-G Dockerfile for PostgreSQL backup to S3
FROM golang:1.21-alpine AS builder

# Set proxy environment variables for build stage
ARG HTTP_PROXY=http://astrid:4CBa737x10IgZU676z@31.58.137.32:13128
ARG HTTPS_PROXY=http://astrid:4CBa737x10IgZU676z@31.58.137.32:13128
ARG NO_PROXY=localhost,127.0.0.1

ENV HTTP_PROXY=$HTTP_PROXY
ENV HTTPS_PROXY=$HTTPS_PROXY
ENV NO_PROXY=$NO_PROXY

# Install build dependencies
RUN apk add --no-cache \
    git \
    cmake \
    gcc \
    musl-dev \
    libc-dev \
    brotli-dev \
    lzo-dev \
    libsodium-dev

# Set working directory
WORKDIR /go/src/github.com/wal-g/wal-g

# Clone WAL-G repository
RUN git clone https://github.com/wal-g/wal-g.git .

# Set build flags for compression libraries
ENV USE_BROTLI=1
ENV USE_LIBSODIUM=1
ENV USE_LZO=1

# Install dependencies and build
RUN make deps && make pg_build

# Final stage - create minimal runtime image
FROM alpine:3.18

# Set proxy ARGs for final stage
ARG HTTP_PROXY=http://astrid:4CBa737x10IgZU676z@31.58.137.32:13128
ARG HTTPS_PROXY=http://astrid:4CBa737x10IgZU676z@31.58.137.32:13128
ARG NO_PROXY=localhost,127.0.0.1

# Install runtime dependencies with temporary proxy settings
RUN HTTP_PROXY=$HTTP_PROXY \
    HTTPS_PROXY=$HTTPS_PROXY \
    NO_PROXY=$NO_PROXY \
    apk add --no-cache \
    postgresql-client \
    ca-certificates \
    bash \
    curl \
    tzdata \
    brotli \
    lzo \
    libsodium

# Create wal-g user
RUN adduser -D -s /bin/bash walg

# Copy wal-g binary from builder
COPY --from=builder /go/src/github.com/wal-g/wal-g/main/pg/wal-g /usr/local/bin/wal-g

# Make sure binary is executable
RUN chmod +x /usr/local/bin/wal-g

# Create directories for backups and scripts
RUN mkdir -p /backup/scripts /backup/logs && \
    chown -R walg:walg /backup

# Copy backup scripts
COPY backup-scripts/ /backup/scripts/
RUN chmod +x /backup/scripts/*.sh

# Switch to walg user
USER walg
WORKDIR /backup

# Default command
CMD ["/backup/scripts/backup-daemon.sh"]
