FROM alpine:3.21

RUN apk add --no-cache \
    bash \
    tar \
    zstd \
    rclone \
    curl \
    tzdata

COPY backup.sh /usr/local/bin/backup.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/backup.sh /usr/local/bin/entrypoint.sh

RUN mkdir -p /sources /backups /var/log

VOLUME ["/sources", "/backups"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
