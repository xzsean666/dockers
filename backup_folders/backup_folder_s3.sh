#!/bin/bash

# ==============================================================================
# Folder Backup Script with ZSTD Compression and S3/Rclone Upload
# ==============================================================================

set -euo pipefail

# Default Configuration
SOURCE_DIR=""
BACKUP_ROOT_DIR=""
MAX_BACKUPS=7
EXCLUDE_PARAMS=()
COMPRESSION_LEVEL=3
SLACK_WEBHOOK_URL=""

# S3/Rclone Defaults
RCLONE_BIN="rclone"
RCLONE_GLOBAL_FLAGS=()
RCLONE_CONFIG_FILE=""
UPLOAD_TARGETS=()
LATEST_BACKUP_FILE=""
DRY_RUN=0

# ==============================================================================
# Helper Functions from pgbackup-docker-s3.sh
# ==============================================================================

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
    log "ERROR: $*"
    send_slack "FAILURE" "Error: $*"
    exit 1
}

send_slack() {
    local status="$1"
    local message="$2"

    if [ -z "${SLACK_WEBHOOK_URL:-}" ]; then
        return 0
    fi

    local icon="✅"
    if [ "$status" != "SUCCESS" ]; then
        icon="❌"
    fi

    # Escape double quotes and newlines for JSON
    local safe_message
    safe_message=$(echo "$message" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

    local text="$icon *Backup $status* - Host: $(hostname)\n$safe_message"

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] Slack: $text"
        return 0
    fi

    if command -v curl &> /dev/null; then
        curl -s -X POST -H 'Content-type: application/json' --data "{\"text\": \"$text\"}" "$SLACK_WEBHOOK_URL" >/dev/null || true
    else
        echo "Warning: curl is not installed. Cannot send Slack notification."
    fi
}

bool_val() {
    local val="${1:-}"
    shopt -s nocasematch
    if [[ "$val" =~ ^(1|true|yes|y|on)$ ]]; then
        echo 1
    else
        echo 0
    fi
    shopt -u nocasematch
}

sanitize_key() {
    local raw=$1
    local upper
    upper=$(echo "$raw" | tr '[:lower:]' '[:upper:]')
    if [[ ! "$upper" =~ ^[A-Z0-9_]+$ ]]; then
        fail "Invalid name '$raw' in UPLOAD_TARGETS (use letters/numbers/underscores)"
    fi
    echo "$upper"
}

job_var() {
    local key=$1
    local suffix=$2
    local var="${key}_${suffix}"
    printf '%s' "${!var-}"
}

require_job_var() {
    local key=$1
    local suffix=$2
    local val
    val=$(job_var "$key" "$suffix")
    [ -n "$val" ] || fail "Target $key missing required field ${key}_${suffix}"
    printf '%s' "$val"
}

build_s3_destination() {
    local key=$1
    local provider endpoint_raw endpoint bucket path region ak sk token force_path_style storage_class acl
    provider=$(job_var "$key" "S3_PROVIDER")
    provider=${provider:-S3}
    endpoint_raw=$(job_var "$key" "S3_ENDPOINT")
    endpoint="$endpoint_raw"
    if [[ "$endpoint" =~ ^https?:// ]]; then
        endpoint="${endpoint#http://}"
        endpoint="${endpoint#https://}"
    fi
    bucket=$(require_job_var "$key" "S3_BUCKET")
    path=$(job_var "$key" "S3_PATH")
    if [ -z "$path" ]; then
        # Default path to source folder name + _backup
        path="$(basename "$SOURCE_DIR")_backup"
    fi
    region=$(job_var "$key" "S3_REGION")
    ak=$(require_job_var "$key" "S3_ACCESS_KEY")
    sk=$(require_job_var "$key" "S3_SECRET_KEY")
    token=$(job_var "$key" "S3_SESSION_TOKEN")
    force_path_style=$(job_var "$key" "S3_FORCE_PATH_STYLE")
    storage_class=$(job_var "$key" "S3_STORAGE_CLASS")
    acl=$(job_var "$key" "S3_ACL")

    if [ -z "$force_path_style" ]; then
        case "$(echo "$provider" | tr '[:upper:]' '[:lower:]')" in
            cloudflare|backblaze) force_path_style=true ;;
        esac
    fi

    local dest=":s3,provider=${provider},access_key_id=${ak},secret_access_key=${sk}"
    [ -n "$endpoint" ] && dest+=",endpoint=${endpoint}"
    [ -n "$region" ] && dest+=",region=${region}"
    if [ -n "$force_path_style" ] && [ "$(bool_val "$force_path_style")" -eq 1 ]; then
        dest+=",force_path_style=true"
    fi
    [ -n "$storage_class" ] && dest+=",storage_class=${storage_class}"
    [ -n "$acl" ] && dest+=",acl=${acl}"
    [ -n "$token" ] && dest+=",session_token=${token}"

    dest+=":${bucket}"
    if [ -n "$path" ]; then
        dest+="/${path#/}"
    fi
    echo "$dest"
}

build_ssh_destination() {
    local key=$1
    local host path user port key_file
    host=$(require_job_var "$key" "SSH_HOST")
    path=$(require_job_var "$key" "SSH_PATH")
    user=$(job_var "$key" "SSH_USER")
    port=$(job_var "$key" "SSH_PORT")
    key_file=$(job_var "$key" "SSH_KEY_FILE")

    local dest=":sftp,host=${host}"
    [ -n "$user" ] && dest+=",user=${user}"
    [ -n "$port" ] && dest+=",port=${port}"
    [ -n "$key_file" ] && dest+=",key_file=${key_file}"
    dest+=":${path}"
    echo "$dest"
}

build_remote_destination() {
    local key=$1
    local dest
    dest=$(job_var "$key" "DESTINATION")
    [ -n "$dest" ] || dest=$(job_var "$key" "REMOTE")
    [ -n "$dest" ] || fail "Target $key missing DESTINATION/REMOTE for REMOTE type"
    echo "$dest"
}

compute_destination() {
    local key=$1
    local type
    type=$(job_var "$key" "TYPE")
    type=${type:-S3}
    type=$(echo "$type" | tr '[:lower:]' '[:upper:]')
    case "$type" in
        S3) build_s3_destination "$key" ;;
        SSH|SFTP) build_ssh_destination "$key" ;;
        REMOTE) build_remote_destination "$key" ;;
        *)
            fail "Target $key has unsupported TYPE '$type' (expected SSH/S3/REMOTE)"
            ;;
    esac
}

upload_target() {
    local key=$1
    local mode dest extra_flags
    dest=$(compute_destination "$key")
    mode=$(job_var "$key" "MODE")
    mode=${mode:-copy} # Default to copy for single file backups in this script context usually, but sync is better for mirrors
    
    # Logic note: In pgbackup, 'sync' for folder mirror, 'copy' for single file. 
    # Here we are backing up a tar file. 'copy' is appropriate for uploading the tarball. 
    # If the user wants to sync the backup directory, they might use 'sync'.
    # For simplicity, if mode is sync, we sync the BACKUP_DIR. If copy, we copy the LATEST_BACKUP_FILE.
    
    mode=$(echo "$mode" | tr '[:upper:]' '[:lower:]')
    extra_flags=$(job_var "$key" "RCLONE_FLAGS")

    local subcommand source_path
    if [ "$mode" = "sync" ]; then
        subcommand="sync"
        source_path="$BACKUP_DIR"
    else
        subcommand="copy"
        source_path="$LATEST_BACKUP_FILE"
        [ -n "$source_path" ] || fail "LATEST_BACKUP_FILE not set; ensure backup step ran"
    fi

    local dest_masked
    dest_masked=$(echo "$dest" | sed -E 's/(access_key_id=)[^,]+/\1***/g; s/(secret_access_key=)[^,]+/\1***/g; s/(session_token=)[^,]+/\1***/g')
    log "Upload target $key -> $dest_masked ($subcommand)"

    local cmd=("$RCLONE_BIN" "$subcommand" "$source_path" "$dest")
    
    # Add sane defaults for S3 uploads if copy
    if [ "$subcommand" = "copy" ] || [ "$subcommand" = "move" ]; then
         cmd+=(--progress) 
    fi

    if [ -n "$RCLONE_CONFIG_FILE" ]; then
        cmd+=(--config "$RCLONE_CONFIG_FILE")
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        cmd+=(--dry-run)
    fi
    if [ ${#RCLONE_GLOBAL_FLAGS[@]} -gt 0 ]; then
        cmd+=("${RCLONE_GLOBAL_FLAGS[@]}")
    fi
    if [ -n "$extra_flags" ]; then
        # shellcheck disable=SC2206
        local job_flags=($extra_flags)
        cmd+=("${job_flags[@]}")
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] Would run: ${cmd[*]}"
    else
        "${cmd[@]}"
    fi
}

upload_all_targets() {
    if [ ${#UPLOAD_TARGETS[@]} -eq 0 ]; then
        log "No UPLOAD_TARGETS configured; skipping upload."
        return
    fi
    command -v "$RCLONE_BIN" >/dev/null 2>&1 || fail "rclone not found: $RCLONE_BIN"

    local key_raw key
    for key_raw in "${UPLOAD_TARGETS[@]}"; do
        key=$(sanitize_key "$key_raw")
        upload_target "$key"
    done
}

# ==============================================================================
# Main Script Logic
# ==============================================================================

usage() {
    echo "Usage: $0 --config <path_to_config_file> [--dry-run]"
    echo ""
    echo "Arguments:"
    echo "  --config    Path to the configuration file (required)"
    echo "  --dry-run   Simulate actions without performing them"
    echo ""
    exit 1
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --config) SOURCE_CONFIG="$2"; shift ;;
        --dry-run) DRY_RUN=1 ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

# Validate config file
if [ -z "${SOURCE_CONFIG:-}" ]; then
    echo "Error: Configuration file not specified."
    usage
fi

if [ ! -f "$SOURCE_CONFIG" ]; then
    echo "Error: Configuration file '$SOURCE_CONFIG' not found."
    exit 1
fi

# Load configuration
echo "Loading configuration from: $SOURCE_CONFIG"
source "$SOURCE_CONFIG"

# Validate required variables
if [ -z "$SOURCE_DIR" ]; then
    echo "Error: SOURCE_DIR is not set in the configuration file."
    exit 1
fi

if [ -z "$BACKUP_ROOT_DIR" ]; then
    echo "Error: BACKUP_ROOT_DIR is not set in the configuration file."
    exit 1
fi

# Check if zstd is installed
if ! command -v zstd &> /dev/null; then
    echo "Error: zstd is not installed. Please install it first."
    exit 1
fi

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory '$SOURCE_DIR' does not exist."
    exit 1
fi

# Setup backup paths
SOURCE_BASENAME=$(basename "$SOURCE_DIR")
BACKUP_DIR="${BACKUP_ROOT_DIR}/${SOURCE_BASENAME}_backup"

if [ ! -d "$BACKUP_DIR" ]; then
    echo "Creating backup directory: $BACKUP_DIR"
    if [ "$DRY_RUN" -eq 0 ]; then
        mkdir -p "$BACKUP_DIR"
    fi
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILENAME="${SOURCE_BASENAME}_${TIMESTAMP}.tar.zst"
BACKUP_FILEPATH="${BACKUP_DIR}/${BACKUP_FILENAME}"
LATEST_BACKUP_FILE="$BACKUP_FILEPATH"

echo "----------------------------------------------------------------"
echo "Starting backup..."
echo "Source:      $SOURCE_DIR"
echo "Destination: $BACKUP_FILEPATH"
echo "----------------------------------------------------------------"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] Would compress $SOURCE_DIR to $BACKUP_FILEPATH"
else
    tar "${EXCLUDE_PARAMS[@]}" -I "zstd -${COMPRESSION_LEVEL} -T0" -cf "$BACKUP_FILEPATH" -C "$(dirname "$SOURCE_DIR")" "$SOURCE_BASENAME"
    
    if [ $? -eq 0 ]; then
        echo "✅ Backup completed successfully."
        FILE_SIZE=$(du -h "$BACKUP_FILEPATH" | cut -f1)
        echo "Backup Size: $FILE_SIZE"
        
        # We delay the success slack message until after uploads, or send one here?
        # The upload_all_targets sends logs. Let's send a preliminary success or just wait.
        # backup_folder.sh sends it here.
        # pgbackup calls send_slack at the END of main.
        # Let's clean up local backups first.
    else
        echo "❌ Backup failed!"
        send_slack "FAILURE" "Backup Failed: $SOURCE_BASENAME"
        exit 1
    fi
fi

# Cleanup old backups
echo "----------------------------------------------------------------"
echo "Checking for old backups (Limit: $MAX_BACKUPS)..."

if [ "$DRY_RUN" -eq 0 ]; then
    EXISTING_BACKUPS=($(ls -1tr "$BACKUP_DIR"/*.tar.zst 2>/dev/null))
    BACKUP_COUNT=${#EXISTING_BACKUPS[@]}

    if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then
        REMOVE_COUNT=$((BACKUP_COUNT - MAX_BACKUPS))
        echo "Found $BACKUP_COUNT backups. Removing oldest $REMOVE_COUNT..."
        
        for ((i=0; i<REMOVE_COUNT; i++)); do
            FILE_TO_REMOVE="${EXISTING_BACKUPS[$i]}"
            echo "Removing: $FILE_TO_REMOVE"
            rm -f "$FILE_TO_REMOVE"
        done
        echo "Cleanup complete."
    else
        echo "Backup count ($BACKUP_COUNT) is within limit ($MAX_BACKUPS). No cleanup needed."
    fi
else
    echo "[dry-run] Would cleanup old backups > $MAX_BACKUPS"
fi

# Upload to S3/Cloud
echo "----------------------------------------------------------------"
echo "Starting Uploads..."
upload_all_targets

echo "----------------------------------------------------------------"
echo "All tasks done."

if [ "$DRY_RUN" -eq 0 ] && [ -f "$BACKUP_FILEPATH" ]; then
    FILE_SIZE=$(du -h "$BACKUP_FILEPATH" | cut -f1)
    send_slack "SUCCESS" "Backup & Upload Completed: $SOURCE_BASENAME\nFile: $BACKUP_FILENAME\nSize: $FILE_SIZE"
fi
