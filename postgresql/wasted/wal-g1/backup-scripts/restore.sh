#!/bin/bash

# WAL-G Restore Script
# Use this script to restore from a backup

set -e

BACKUP_NAME=${1:-"LATEST"}

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting restore process..."
log "Target backup: $BACKUP_NAME"

if [ "$BACKUP_NAME" == "LATEST" ]; then
    log "Restoring from latest backup..."
    wal-g backup-fetch $PGDATA LATEST
else
    log "Restoring from specific backup: $BACKUP_NAME"
    wal-g backup-fetch $PGDATA $BACKUP_NAME
fi

if [ $? -eq 0 ]; then
    log "Restore completed successfully"
    log "Remember to:"
    log "1. Check PostgreSQL configuration"
    log "2. Start PostgreSQL service"
    log "3. Verify data integrity"
else
    log "Restore failed!"
    exit 1
fi
