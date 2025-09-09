#!/bin/bash

# Configuration
DB_CONTAINER="psqlm"  # Your PostgreSQL container name
DB_USER="sean"       # Your PostgreSQL user
DB_NAME="MyDB"       # Your database name
DB_PASSWORD="psqlm"  # Your PostgreSQL password (WARNING: Hardcoding passwords is not secure)

OPERATION="" # backup or restore
BACKUP_FILE="" # backup file path

# Function to display usage
usage() {
    echo "Usage: $0 [--backup | --restore] --path <backup_file_path>"
    echo "  --backup: Perform a database backup."
    echo "  --restore: Perform a database restore."
    echo "  --path <backup_file_path>: Specify the path for the backup file (output for backup, input for restore)."
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"

    case ${key} in
        --backup)
        OPERATION="backup"
        shift # past argument
        ;;
        --restore)
        OPERATION="restore"
        shift # past argument
        ;;
        --path)
        BACKUP_FILE="$2"
        shift # past argument
        shift # past value
        ;;
        *)
        echo "Unknown option: $1"
        usage
        ;;
    esac
done

# Validate arguments
if [ -z "${OPERATION}" ] || [ -z "${BACKUP_FILE}" ]; then
    echo "Error: You must specify an operation (--backup or --restore) and a backup file path (--path)."
    usage
fi

# Ensure the backup directory exists for backup operation
if [ "${OPERATION}" == "backup" ]; then
    BACKUP_DIR=$(dirname "${BACKUP_FILE}")
    mkdir -p "${BACKUP_DIR}"
fi

# Perform the selected operation
case "${OPERATION}" in
    backup)
        echo "Starting backup of database ${DB_NAME} from container ${DB_CONTAINER} to ${BACKUP_FILE}..."
        sudo docker exec -e PGPASSWORD="${DB_PASSWORD}" ${DB_CONTAINER} pg_dump -U ${DB_USER} -Fc ${DB_NAME} > ${BACKUP_FILE}
        if [ $? -eq 0 ]; then
            echo "Backup successful! File saved to ${BACKUP_FILE}"
        else
            echo "Backup failed!"
            exit 1
        fi
        ;;
    restore)
        echo "Starting restore of database ${DB_NAME} from ${BACKUP_FILE} to container ${DB_CONTAINER}..."
        # Ensure the backup file exists for restore operation
        if [ ! -f "${BACKUP_FILE}" ]; then
            echo "Error: Backup file not found at ${BACKUP_FILE}"
            exit 1
        fi
        sudo docker exec -i -e PGPASSWORD="${DB_PASSWORD}" ${DB_CONTAINER} pg_restore -U ${DB_USER} -d ${DB_NAME} < ${BACKUP_FILE}
        if [ $? -eq 0 ]; then
            echo "Restore successful!"
        else
            echo "Restore failed!"
            exit 1
        fi
        ;;
esac

# Example restore command (commented out)
# echo "Example restore command:"
# echo "sudo docker exec -i -e PGPASSWORD=\"${DB_PASSWORD}\" ${DB_CONTAINER} pg_restore -U ${DB_USER} -d ${DB_NAME} < ${BACKUP_FILE}"
