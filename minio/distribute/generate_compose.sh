#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Load environment variables
set -a
source .env
set +a

# Check if required environment variables are set
: "${CLUSTER_NODES:?Need to set CLUSTER_NODES in .env}"
: "${NODE_NAME:?Need to set NODE_NAME in .env}"
: "${LOCAL_DISK_PATH:?Need to set LOCAL_DISK_PATH in .env}"
: "${CONSOLE_PORT:?Need to set CONSOLE_PORT in .env}"
: "${API_PORT:?Need to set API_PORT in .env}"
: "${MINIO_ROOT_USER:?Need to set MINIO_ROOT_USER in .env}"
: "${MINIO_ROOT_PASSWORD:?Need to set MINIO_ROOT_PASSWORD in .env}"

# Split CLUSTER_NODES string into an array
IFS=',' read -ra NODES <<< "$CLUSTER_NODES"

# Generate MinIO server command
MINIO_COMMAND="server"
for ip in "${NODES[@]}"; do
    MINIO_COMMAND+=" http://$ip/data"
done
MINIO_COMMAND+=" --console-address :$CONSOLE_PORT"

# Create docker-compose.yml file
cat > docker-compose.yml <<EOF
version: "3.8"

services:
  minio:
    image: minio/minio:latest
    container_name: minio
    restart: always
    hostname: \${NODE_NAME}
    user: root
    volumes:
      - $LOCAL_DISK_PATH:/data
    ports:
      - "$API_PORT:9000"
      - "$CONSOLE_PORT:9001"
    environment:
      MINIO_ROOT_USER: \${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: \${MINIO_ROOT_PASSWORD}
    command: $MINIO_COMMAND
EOF

echo "✅ docker-compose.yml has been successfully generated!"
