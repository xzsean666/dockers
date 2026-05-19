#!/bin/sh
set -eu

RUNNER="/usr/local/bin/rclone-sync-runner"
SCHEDULE="${RCLONE_SYNC_SCHEDULE:-${CRON_SCHEDULE:-}}"
RUN_ON_STARTUP="${RCLONE_SYNC_RUN_ON_STARTUP:-true}"
TZ="${TZ:-UTC}"

if [ "$#" -gt 0 ]; then
    case "$1" in
        run|run-once)
            exec "$RUNNER"
            ;;
        version|--version)
            exec "$RUNNER" --version
            ;;
        *)
            exec "$@"
            ;;
    esac
fi

echo "================================================================"
echo "rclone-sync starting"
echo "================================================================"
echo "Timezone:       $TZ"
echo "Schedule:       ${SCHEDULE:-run-once}"
echo "Run on startup: $RUN_ON_STARTUP"
echo "Config:         ${RCLONE_SYNC_CONFIG:-/config/jobs.yaml}"
echo "================================================================"

"$RUNNER" --notify-startup || true

if [ "$RUN_ON_STARTUP" = "true" ] || [ "$RUN_ON_STARTUP" = "1" ] || [ "$RUN_ON_STARTUP" = "yes" ]; then
    "$RUNNER"
fi

if [ -z "$SCHEDULE" ]; then
    echo "No schedule configured; exiting after startup run."
    exit 0
fi

umask 077
python3 - <<'PY' > /etc/rclone-sync.env
import os
import shlex

for key, value in sorted(os.environ.items()):
    if key in {"PWD", "OLDPWD", "SHLVL", "_"}:
        continue
    allowed = (
        key == "TZ"
        or key == "PATH"
        or key == "RCLONE_CONFIG"
        or key.startswith("RCLONE_SYNC_")
        or key.startswith("RCLONE_CONFIG_")
        or key in {"http_proxy", "https_proxy", "all_proxy", "no_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY"}
    )
    if not allowed:
        continue
    print(f"export {key}={shlex.quote(value)}")
PY
chmod 600 /etc/rclone-sync.env

cat > /usr/local/bin/rclone-sync-cron.sh <<'EOF'
#!/bin/sh
set -eu
. /etc/rclone-sync.env
exec /usr/local/bin/rclone-sync-runner
EOF
chmod +x /usr/local/bin/rclone-sync-cron.sh

echo "$SCHEDULE /usr/local/bin/rclone-sync-cron.sh" > /etc/crontabs/root
echo "Cron scheduled. Waiting for next run..."
exec crond -f -l 2
