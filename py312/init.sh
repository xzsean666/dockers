#!/bin/bash

# Create directories
mkdir -p app/crontab
mkdir -p app/logs

# Create startup script
cat > app/startup.sh << 'EOF'
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
EOF
chmod +x app/startup.sh

# Create crontab scripts
CRONTAB_SCRIPTS=(
    "mins1.sh"
    "mins5.sh"
    "mins15.sh"
    "mins30.sh"
    "hour1.sh"
    "hour6.sh"
    "hour12.sh"
    "day.sh"
)

for script in "${CRONTAB_SCRIPTS[@]}"; do
    cat > "app/crontab/$script" << 'EOF'
#!/bin/bash
# Crontab script: $script
# Add your commands here
EOF
    chmod +x "app/crontab/$script"
done

# Create the script content
cat > app/init-crontab.sh << 'EOF'
#!/bin/bash
(crontab -l 2>/dev/null; echo "*/1 * * * * /app/crontab/mins1.sh >> /app/logs/cron_jobs.log 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "*/5 * * * * /app/crontab/mins5.sh >> /app/logs/cron_jobs.log 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "*/15 * * * * /app/crontab/mins15.sh >> /app/logs/cron_jobs.log 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "*/30 * * * * /app/crontab/mins30.sh >> /app/logs/cron_jobs.log 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "0 * * * * /app/crontab/hour1.sh >> /app/logs/cron_jobs.log 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "0 */6 * * * /app/crontab/hour6.sh >> /app/logs/cron_jobs.log 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "0 */12 * * * /app/crontab/hour12.sh >> /app/logs/cron_jobs.log 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "0 0 * * * /app/crontab/day.sh >> /app/logs/cron_jobs.log 2>&1") | crontab -
EOF

# Make the script executable
chmod +x app/init-crontab.sh

echo "Directory structure and files created successfully!"
echo "Crontab entries have been added successfully!" 