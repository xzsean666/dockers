#!/bin/bash
set -euo pipefail

CRON_SCHEDULE="${CRON_SCHEDULE:-0 2 * * *}"
RUN_ON_STARTUP="${RUN_ON_STARTUP:-false}"
TZ="${TZ:-UTC}"

echo "================================================================"
echo "Folder Backup Container Starting"
echo "================================================================"
echo "Timezone:     $TZ"
echo "Schedule:     $CRON_SCHEDULE"
echo "Run on start: $RUN_ON_STARTUP"
echo "================================================================"

# Export all env vars so cron job can access them
printenv | grep -vE '^(HOME|USER|LOGNAME|PATH|SHELL|TERM|SHLVL|PWD|_|HOSTNAME|OLDPWD)=' > /etc/environment.backup 2>/dev/null || true

# Create cron wrapper script
cat > /usr/local/bin/backup-cron.sh << 'WRAPPER'
#!/bin/bash
set -a
source /etc/environment.backup
set +a
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
/usr/local/bin/backup.sh >> /var/log/backup.log 2>&1
WRAPPER
chmod +x /usr/local/bin/backup-cron.sh

# Setup cron job
echo "$CRON_SCHEDULE /usr/local/bin/backup-cron.sh" > /etc/crontabs/root

# Run on startup if configured
if [ "$RUN_ON_STARTUP" = "true" ] || [ "$RUN_ON_STARTUP" = "1" ]; then
    echo "Running initial backup..."
    /usr/local/bin/backup.sh
fi

echo "Cron scheduled. Waiting for next run..."

# Start crond in foreground
exec crond -f -l 2
