#!/bin/bash

# WAL-G Backup Daemon Script
# This script runs as the main process in the WAL-G container

set -e

echo "Starting WAL-G backup daemon..."
echo "Timestamp: $(date)"

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a /backup/logs/backup.log
}

# Function to perform full backup
perform_full_backup() {
    log "Starting full backup..."
    
    # Wait for PostgreSQL to be ready
    until pg_isready -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER; do
        log "Waiting for PostgreSQL to be ready..."
        sleep 5
    done
    
    # Perform backup
    wal-g backup-push $PGDATA
    
    if [ $? -eq 0 ]; then
        log "Full backup completed successfully"
        echo "$(date)" > /backup/logs/last-backup.txt
    else
        log "Full backup failed!"
        exit 1
    fi
}

# Function to cleanup old backups
cleanup_backups() {
    log "Cleaning up old backups..."
    
    # Keep last 7 full backups
    wal-g delete retain FULL 7
    
    if [ $? -eq 0 ]; then
        log "Backup cleanup completed successfully"
    else
        log "Backup cleanup failed!"
    fi
}

# Create logs directory if it doesn't exist
mkdir -p /backup/logs

# Check if it's time for a backup (run once every 6 hours by default)
BACKUP_INTERVAL=${BACKUP_INTERVAL:-21600}  # 6 hours in seconds

log "WAL-G backup daemon started"
log "Backup interval: ${BACKUP_INTERVAL} seconds"

# Main loop
while true; do
    log "Checking if backup is needed..."
    
    # Check if this is the first backup or enough time has passed
    if [ ! -f /backup/logs/last-backup.txt ]; then
        log "No previous backup found, performing initial backup"
        perform_full_backup
        cleanup_backups
    else
        last_backup=$(cat /backup/logs/last-backup.txt)
        current_time=$(date +%s)
        last_backup_time=$(date -d "$last_backup" +%s 2>/dev/null || echo 0)
        time_diff=$((current_time - last_backup_time))
        
        if [ $time_diff -ge $BACKUP_INTERVAL ]; then
            log "Time for scheduled backup (${time_diff}s since last backup)"
            perform_full_backup
            cleanup_backups
        else
            remaining=$((BACKUP_INTERVAL - time_diff))
            log "Next backup in ${remaining} seconds"
        fi
    fi
    
    # Sleep for 5 minutes before next check
    sleep 300
done
