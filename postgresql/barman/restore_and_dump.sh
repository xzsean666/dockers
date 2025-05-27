#!/bin/bash

# Script to restore a Barman backup to a temporary PG instance and create a pg_dump

# --- Configuration ---
BARMAN_CONTAINER="barman" # Name of your Barman service in docker-compose.yml
SERVER_NAME="${CONTAINER_NAME}" # Name of the PG server in Barman (from .env, matches PG container name)
# Ensure CONTAINER_NAME is sourced, e.g., from your .env file
if [ -f .env ]; then
    export $(cat .env | grep -v '#' | awk '/=/ {print $1}')
fi

TEMP_VOLUME_NAME="${SERVER_NAME}_restore_temp_data" # Name for the temporary Docker volume
TEMP_PG_CONTAINER_NAME="${SERVER_NAME}_restore_temp_pg" # Name for the temporary PG container

# IMPORTANT: Replace 'latest' with the actual backup ID you want to restore
# You can find backup IDs by running: docker-compose exec ${BARMAN_CONTAINER} barman list-backups ${SERVER_NAME}
BACKUP_ID="latest"

# Output file name for the pg_dump
OUTPUT_DUMP_FILE="${SERVER_NAME}_restored_${BACKUP_ID}_dump.sql"

# --- Check if Barman container is running ---
echo "Checking if Barman container '${BARMAN_CONTAINER}' is running..."
docker-compose ps -q ${BARMAN_CONTAINER} > /dev/null
if [ $? -ne 0 ]; then
    echo "Error: Barman container '${BARMAN_CONTAINER}' is not running. Please start it using 'docker-compose up -d ${BARMAN_CONTAINER}'"
    exit 1
fi
echo "Barman container is running."

# --- Clean up previous temporary resources if they exist ---
echo "Cleaning up any previous temporary resources..."
docker stop ${TEMP_PG_CONTAINER_NAME} 2>/dev/null
docker rm ${TEMP_PG_CONTAINER_NAME} 2>/dev/null
docker volume rm ${TEMP_VOLUME_NAME} 2>/dev/null
echo "Cleanup complete."

# --- Create temporary volume ---
echo "Creating temporary volume '${TEMP_VOLUME_NAME}'..."
docker volume create ${TEMP_VOLUME_NAME}
if [ $? -ne 0 ]; then
    echo "Error creating volume."
    exit 1
fi
echo "Temporary volume created."

# --- Restore backup using Barman container ---
echo "Restoring backup '${BACKUP_ID}' from server '${SERVER_NAME}' to volume '${TEMP_VOLUME_NAME}'..."
# The /bitnami/postgresql is the default data directory for Bitnami PostgreSQL image
docker-compose exec ${BARMAN_CONTAINER} barman recover ${SERVER_NAME} ${BACKUP_ID} "/${TEMP_VOLUME_NAME}" --remote-ssh-command "docker run --rm -v ${TEMP_VOLUME_NAME}:/${TEMP_VOLUME_NAME} bitnami/postgresql:16 ls /${TEMP_VOLUME_NAME}" # This remote-ssh-command is a workaround to make barman see the remote volume, might need adjustment based on barman version/setup. A more robust way might involve mounting the volume to barman directly or using a dedicated restore container. Let's use a simpler direct volume mount approach for recover.

# Revised recover command using direct volume mount on barman container execution
# Stop barman temporarily to allow volume mount (might not be needed depending on docker version)
# docker-compose stop ${BARMAN_CONTAINER} # Potentially stop if needed for volume mount

# To allow barman container to write to the temp volume, we need to mount the temp volume
# when executing the barman recover command. This is tricky with docker-compose exec.
# A better approach is to run a *new* temporary Barman container just for the restore.

echo "Starting temporary Barman container for restore..."
RESTORE_BARMAN_CONTAINER="temp_barman_restore_${RANDOM}"
docker run --name ${RESTORE_BARMAN_CONTAINER} --network $(docker-compose config --services ${BARMAN_CONTAINER} | xargs docker inspect --format '{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}') \
    -v ${TEMP_VOLUME_NAME}:/recovery_target \
    -v ${PWD}/barman_conf:/etc/barman \
    -v ${PWD}/barman_data:/barman_data \
    --env-file .env \
    ghcr.io/bitnami/barman:2 barman recover ${SERVER_NAME} ${BACKUP_ID} /recovery_target

if [ $? -ne 0 ]; then
    echo "Error during Barman restore. Please check the logs."
    docker rm ${RESTORE_BARMAN_CONTAINER} 2>/dev/null
    docker volume rm ${TEMP_VOLUME_NAME} 2>/dev/null
    exit 1
fi
echo "Barman restore completed."

# Remove temporary Barman container
docker rm ${RESTORE_BARMAN_CONTAINER} 2>/dev/null

# --- Prepare restored data for startup (create standby.signal) ---
# This step needs to be done on the restored data volume.
# We can use a temporary container to access the volume and create the file.
echo "Creating standby.signal in restored data directory..."
TEMP_ACCESS_CONTAINER="temp_volume_access_${RANDOM}"
docker run --name ${TEMP_ACCESS_CONTAINER} -v ${TEMP_VOLUME_NAME}:/data alpine:latest touch /data/standby.signal
if [ $? -ne 0 ]; then
    echo "Error creating standby.signal."
    docker rm ${TEMP_ACCESS_CONTAINER} 2>/dev/null
    docker volume rm ${TEMP_VOLUME_NAME} 2>/dev/null
    exit 1
fi
docker rm ${TEMP_ACCESS_CONTAINER} 2>/dev/null

# --- Start temporary PostgreSQL container with the restored data ---
echo "Starting temporary PostgreSQL container '${TEMP_PG_CONTAINER_NAME}'..."
# We need to source .env again to ensure PG environment variables are available
if [ -f .env ]; then
    export $(cat .env | grep -v '#' | awk '/=/ {print $1}')
fi

docker run -d --name ${TEMP_PG_CONTAINER_NAME} \
    -v ${TEMP_VOLUME_NAME}:/bitnami/postgresql \
    -e POSTGRESQL_REPLICATION_MODE=replica \
    -e POSTGRESQL_REPLICATION_USER=${POSTGRESQL_REPLICATION_USER} \
    -e POSTGRESQL_REPLICATION_PASSWORD=${POSTGRESQL_REPLICATION_PASSWORD} \
    -e POSTGRESQL_USERNAME=${POSTGRESQL_USERNAME} \
    -e POSTGRESQL_PASSWORD=${POSTGRESQL_PASSWORD} \
    -e POSTGRESQL_DATABASE=${POSTGRESQL_DATABASE} \
    -e BITNAMI_DEBUG=true \
    bitnami/postgresql:16

if [ $? -ne 0 ]; then
    echo "Error starting temporary PostgreSQL container."
    docker volume rm ${TEMP_VOLUME_NAME} 2>/dev/null
    exit 1
fi
echo "Temporary PostgreSQL container started. Waiting for it to become ready..."

# --- Wait for PostgreSQL to become ready ---
# Simple check: wait until the container logs indicate it's ready or a specific message appears
# You might need a more robust health check depending on your exact PG startup
sleep 20 # Give it some time to start
READY=false
for i in {1..20}; do # Check up to 20 times (100 seconds total)
    if docker logs ${TEMP_PG_CONTAINER_NAME} 2>&1 | grep -q "database system is ready to accept connections"; then
        READY=true
        break
    fi
    echo "Waiting for temporary PG container to be ready (attempt ${i}/20)..."
    sleep 5
done

if [ "$READY" = false ]; then
    echo "Error: Temporary PostgreSQL container did not become ready."
    docker stop ${TEMP_PG_CONTAINER_NAME} 2>/dev/null
    docker rm ${TEMP_PG_CONTAINER_NAME} 2>/dev/null
    docker volume rm ${TEMP_VOLUME_NAME} 2>/dev/null
    exit 1
fi
echo "Temporary PostgreSQL container is ready."

# --- Run pg_dump from the temporary container ---
echo "Running pg_dump from temporary container '${TEMP_PG_CONTAINER_NAME}'..."
# Need to ensure PG password env var is available for pg_dump inside the container
docker exec -e PGPASSWORD=${POSTGRESQL_PASSWORD} ${TEMP_PG_CONTAINER_NAME} \
    pg_dump -U ${POSTGRESQL_USERNAME} -d ${POSTGRESQL_DATABASE} > ${OUTPUT_DUMP_FILE}

if [ $? -ne 0 ]; then
    echo "Error during pg_dump. Check container logs for details: docker logs ${TEMP_PG_CONTAINER_NAME}"
    docker stop ${TEMP_PG_CONTAINER_NAME} 2>/dev/null
    docker rm ${TEMP_PG_CONTAINER_NAME} 2>/dev/null
    docker volume rm ${TEMP_VOLUME_NAME} 2>/dev/null
    exit 1
fi
echo "pg_dump completed. Output saved to ./${OUTPUT_DUMP_FILE}"

# --- Clean up temporary resources ---
echo "Cleaning up temporary PostgreSQL container and volume..."
docker stop ${TEMP_PG_CONTAINER_NAME}
docker rm ${TEMP_PG_CONTAINER_NAME}
docker volume rm ${TEMP_VOLUME_NAME}
echo "Cleanup complete."

echo "Process finished."