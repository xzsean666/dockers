#!/bin/bash

# Manual WAL-G Backup Script
# Use this script to manually trigger a backup

set -e

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting manual backup..."

# Wait for PostgreSQL to be ready
until pg_isready -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER; do
    log "Waiting for PostgreSQL to be ready..."
    sleep 5
done

# Perform backup
log "Executing backup command..."
wal-g backup-push $PGDATA

if [ $? -eq 0 ]; then
    log "Manual backup completed successfully"
    
    # List current backups
    log "Current backups:"
    wal-g backup-list
else
    log "Manual backup failed!"
    exit 1
fi
