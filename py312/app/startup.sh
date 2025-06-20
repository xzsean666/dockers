#!/bin/bash
# Startup script for the application

LOCK_FILE="/tmp/startup.lock"
LOG_FILE="/var/log/startup.log"
CRON_LOG_FILE="/app/logs/cron_jobs.log"

# Ensure the cron log file exists
touch "$CRON_LOG_FILE"

# Check if already running
if [ -f "$LOCK_FILE" ]; then
    echo "$(date): Startup script is already running or was interrupted. Lock file exists: $LOCK_FILE" >> $LOG_FILE
    exit 1
fi

# Create lock file
echo $$ > "$LOCK_FILE"

# Cleanup function
cleanup() {
    rm -f "$LOCK_FILE"
    echo "$(date): Startup script cleanup completed" >> $LOG_FILE
}

# Set trap to cleanup on exit
trap cleanup EXIT

echo "$(date): Starting application initialization..." >> $LOG_FILE

# Add your startup commands here
# Example:
# echo "$(date): Initializing application..." >> $LOG_FILE

echo "$(date): Application initialization completed" >> $LOG_FILE
