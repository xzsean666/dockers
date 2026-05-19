ARG RCLONE_IMAGE=rclone/rclone:latest
FROM ${RCLONE_IMAGE}

RUN apk add --no-cache \
    bash \
    python3 \
    py3-yaml \
    tzdata

COPY runner.py /usr/local/bin/rclone-sync-runner
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/rclone-sync-runner /usr/local/bin/entrypoint.sh \
    && mkdir -p /config/rclone /filters /data /logs /state /tmp

ENV RCLONE_CONFIG=/config/rclone/rclone.conf

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
