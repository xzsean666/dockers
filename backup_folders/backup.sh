#!/bin/bash
# ==============================================================================
# Folder Backup Script - Docker Edition
# Supports: Local backup, S3, Backblaze B2, Cloudflare R2
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Configuration from Environment Variables
# ==============================================================================
SOURCES_DIR="${BACKUP_SOURCES_DIR:-/sources}"
LOCAL_BACKUP_DIR="${BACKUP_LOCAL_DIR:-}"
MAX_BACKUPS="${MAX_BACKUPS:-7}"
CLOUD_MAX_BACKUPS="${CLOUD_MAX_BACKUPS:-${MAX_BACKUPS}}"
COMPRESSION_LEVEL="${COMPRESSION_LEVEL:-3}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
DRY_RUN="${DRY_RUN:-0}"
BACKUP_PREFIX="${BACKUP_PREFIX:-}"

# S3 config
S3_ENDPOINT="${S3_ENDPOINT:-}"
S3_BUCKET="${S3_BUCKET:-}"
S3_ACCESS_KEY="${S3_ACCESS_KEY:-}"
S3_SECRET_KEY="${S3_SECRET_KEY:-}"
S3_REGION="${S3_REGION:-us-east-1}"
S3_PATH="${S3_PATH:-}"
S3_FORCE_PATH_STYLE="${S3_FORCE_PATH_STYLE:-false}"

# Backblaze B2 config
B2_ACCOUNT_ID="${B2_ACCOUNT_ID:-}"
B2_APP_KEY="${B2_APP_KEY:-}"
B2_BUCKET="${B2_BUCKET:-}"
B2_PATH="${B2_PATH:-}"

# Cloudflare R2 config
R2_ENDPOINT="${R2_ENDPOINT:-}"
R2_ACCESS_KEY="${R2_ACCESS_KEY:-}"
R2_SECRET_KEY="${R2_SECRET_KEY:-}"
R2_BUCKET="${R2_BUCKET:-}"
R2_PATH="${R2_PATH:-}"

# Exclude patterns (comma-separated)
EXCLUDE_PATTERNS="${EXCLUDE_PATTERNS:-}"

RCLONE_BIN="rclone"
TMP_DIR="/tmp/backup_staging"

# ==============================================================================
# Helper Functions
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

    local safe_message
    safe_message=$(echo "$message" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    local text="$icon *Backup $status* - Host: $(hostname)\n$safe_message"

    if [ "$DRY_RUN" = "1" ]; then
        log "[dry-run] Slack: $text"
        return 0
    fi

    curl -s -X POST -H 'Content-type: application/json' \
        --data "{\"text\": \"$text\"}" "$SLACK_WEBHOOK_URL" >/dev/null 2>&1 || true
}

# ==============================================================================
# Cloud Upload Functions
# ==============================================================================

has_s3_config() {
    [ -n "$S3_BUCKET" ] && [ -n "$S3_ACCESS_KEY" ] && [ -n "$S3_SECRET_KEY" ]
}

has_b2_config() {
    [ -n "$B2_ACCOUNT_ID" ] && [ -n "$B2_APP_KEY" ] && [ -n "$B2_BUCKET" ]
}

has_r2_config() {
    [ -n "$R2_BUCKET" ] && [ -n "$R2_ACCESS_KEY" ] && [ -n "$R2_SECRET_KEY" ]
}

has_any_cloud() {
    has_s3_config || has_b2_config || has_r2_config
}

upload_to_s3() {
    local file="$1"
    local filename
    filename=$(basename "$file")

    local s3_path="${S3_PATH:-backups}"
    local dest=":s3,provider=AWS,access_key_id=${S3_ACCESS_KEY},secret_access_key=${S3_SECRET_KEY}"
    [ -n "$S3_ENDPOINT" ] && dest+=",endpoint=${S3_ENDPOINT}"
    [ -n "$S3_REGION" ] && dest+=",region=${S3_REGION}"
    if [ "$S3_FORCE_PATH_STYLE" = "true" ] || [ "$S3_FORCE_PATH_STYLE" = "1" ]; then
        dest+=",force_path_style=true"
    fi
    dest+=":${S3_BUCKET}/${s3_path#/}"

    log "Uploading to S3: ${S3_BUCKET}/${s3_path}/${filename}"
    if [ "$DRY_RUN" = "1" ]; then
        log "[dry-run] Would upload $file to S3"
    else
        "$RCLONE_BIN" copy "$file" "$dest" --progress
    fi
}

upload_to_b2() {
    local file="$1"
    local filename
    filename=$(basename "$file")

    local b2_path="${B2_PATH:-backups}"
    local dest=":b2,account=${B2_ACCOUNT_ID},key=${B2_APP_KEY}:${B2_BUCKET}/${b2_path#/}"

    log "Uploading to B2: ${B2_BUCKET}/${b2_path}/${filename}"
    if [ "$DRY_RUN" = "1" ]; then
        log "[dry-run] Would upload $file to B2"
    else
        "$RCLONE_BIN" copy "$file" "$dest" --progress
    fi
}

upload_to_r2() {
    local file="$1"
    local filename
    filename=$(basename "$file")

    local r2_path="${R2_PATH:-backups}"
    local r2_endpoint="${R2_ENDPOINT}"
    local dest=":s3,provider=Cloudflare,access_key_id=${R2_ACCESS_KEY},secret_access_key=${R2_SECRET_KEY}"
    [ -n "$r2_endpoint" ] && dest+=",endpoint=${r2_endpoint}"
    dest+=",force_path_style=true"
    dest+=":${R2_BUCKET}/${r2_path#/}"

    log "Uploading to R2: ${R2_BUCKET}/${r2_path}/${filename}"
    if [ "$DRY_RUN" = "1" ]; then
        log "[dry-run] Would upload $file to R2"
    else
        "$RCLONE_BIN" copy "$file" "$dest" --progress
    fi
}

upload_to_all_clouds() {
    local file="$1"

    if has_s3_config; then
        upload_to_s3 "$file" || log "WARNING: S3 upload failed"
    fi
    if has_b2_config; then
        upload_to_b2 "$file" || log "WARNING: B2 upload failed"
    fi
    if has_r2_config; then
        upload_to_r2 "$file" || log "WARNING: R2 upload failed"
    fi
}

# ==============================================================================
# Cloud Cleanup Functions
# ==============================================================================

cleanup_cloud_s3() {
    local s3_path="${S3_PATH:-backups}"
    local dest=":s3,provider=AWS,access_key_id=${S3_ACCESS_KEY},secret_access_key=${S3_SECRET_KEY}"
    [ -n "$S3_ENDPOINT" ] && dest+=",endpoint=${S3_ENDPOINT}"
    [ -n "$S3_REGION" ] && dest+=",region=${S3_REGION}"
    if [ "$S3_FORCE_PATH_STYLE" = "true" ] || [ "$S3_FORCE_PATH_STYLE" = "1" ]; then
        dest+=",force_path_style=true"
    fi
    dest+=":${S3_BUCKET}/${s3_path#/}"
    cleanup_cloud_remote "S3" "$dest"
}

cleanup_cloud_b2() {
    local b2_path="${B2_PATH:-backups}"
    local dest=":b2,account=${B2_ACCOUNT_ID},key=${B2_APP_KEY}:${B2_BUCKET}/${b2_path#/}"
    cleanup_cloud_remote "B2" "$dest"
}

cleanup_cloud_r2() {
    local r2_path="${R2_PATH:-backups}"
    local dest=":s3,provider=Cloudflare,access_key_id=${R2_ACCESS_KEY},secret_access_key=${R2_SECRET_KEY}"
    [ -n "$R2_ENDPOINT" ] && dest+=",endpoint=${R2_ENDPOINT}"
    dest+=",force_path_style=true"
    dest+=":${R2_BUCKET}/${r2_path#/}"
    cleanup_cloud_remote "R2" "$dest"
}

cleanup_cloud_remote() {
    local provider="$1"
    local dest="$2"

    log "Checking cloud backup rotation on $provider (limit: $CLOUD_MAX_BACKUPS)..."

    if [ "$DRY_RUN" = "1" ]; then
        log "[dry-run] Would cleanup old backups on $provider"
        return 0
    fi

    # List files sorted by time (oldest first), get only .tar.zst files
    local file_list
    file_list=$("$RCLONE_BIN" lsf "$dest" --files-only 2>/dev/null | grep '\.tar\.zst$' | sort) || true

    if [ -z "$file_list" ]; then
        log "No backup files found on $provider"
        return 0
    fi

    local file_count
    file_count=$(echo "$file_list" | wc -l)

    if [ "$file_count" -gt "$CLOUD_MAX_BACKUPS" ]; then
        local remove_count=$((file_count - CLOUD_MAX_BACKUPS))
        log "Found $file_count backups on $provider. Removing oldest $remove_count..."

        echo "$file_list" | head -n "$remove_count" | while IFS= read -r old_file; do
            log "Deleting from $provider: $old_file"
            "$RCLONE_BIN" deletefile "$dest/$old_file" || log "WARNING: Failed to delete $old_file from $provider"
        done
    else
        log "$provider backup count ($file_count) within limit ($CLOUD_MAX_BACKUPS)"
    fi
}

cleanup_all_clouds() {
    if has_s3_config; then
        cleanup_cloud_s3 || log "WARNING: S3 cleanup failed"
    fi
    if has_b2_config; then
        cleanup_cloud_b2 || log "WARNING: B2 cleanup failed"
    fi
    if has_r2_config; then
        cleanup_cloud_r2 || log "WARNING: R2 cleanup failed"
    fi
}

# ==============================================================================
# Local Backup Cleanup
# ==============================================================================

cleanup_local_backups() {
    local backup_dir="$1"

    if [ ! -d "$backup_dir" ]; then
        return 0
    fi

    log "Checking local backup rotation in $backup_dir (limit: $MAX_BACKUPS)..."

    if [ "$DRY_RUN" = "1" ]; then
        log "[dry-run] Would cleanup old local backups > $MAX_BACKUPS"
        return 0
    fi

    local -a existing_backups
    mapfile -t existing_backups < <(ls -1tr "$backup_dir"/*.tar.zst 2>/dev/null)
    local backup_count=${#existing_backups[@]}

    if [ "$backup_count" -gt "$MAX_BACKUPS" ]; then
        local remove_count=$((backup_count - MAX_BACKUPS))
        log "Found $backup_count local backups. Removing oldest $remove_count..."

        for ((i = 0; i < remove_count; i++)); do
            log "Removing: ${existing_backups[$i]}"
            rm -f "${existing_backups[$i]}"
        done
    else
        log "Local backup count ($backup_count) within limit ($MAX_BACKUPS)"
    fi
}

# ==============================================================================
# Main Backup Logic
# ==============================================================================

backup_directory() {
    local source_dir="$1"
    local source_name
    source_name=$(basename "$source_dir")

    if [ -n "$BACKUP_PREFIX" ]; then
        source_name="${BACKUP_PREFIX}_${source_name}"
    fi

    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_filename="${source_name}_${timestamp}.tar.zst"

    # Build exclude params
    local -a exclude_params=()
    if [ -n "$EXCLUDE_PATTERNS" ]; then
        IFS=',' read -ra patterns <<< "$EXCLUDE_PATTERNS"
        for pattern in "${patterns[@]}"; do
            pattern=$(echo "$pattern" | xargs) # trim whitespace
            exclude_params+=(--exclude="$pattern")
        done
    fi

    log "================================================================"
    log "Backing up: $source_dir"
    log "Archive:    $backup_filename"
    log "================================================================"

    # Create archive in temp directory
    mkdir -p "$TMP_DIR"
    local tmp_file="${TMP_DIR}/${backup_filename}"

    if [ "$DRY_RUN" = "1" ]; then
        log "[dry-run] Would compress $source_dir -> $backup_filename"
    else
        tar "${exclude_params[@]}" -I "zstd -${COMPRESSION_LEVEL} -T0" \
            -cf "$tmp_file" -C "$(dirname "$source_dir")" "$( basename "$source_dir")"

        local file_size
        file_size=$(du -h "$tmp_file" | cut -f1)
        log "Archive created: $backup_filename ($file_size)"
    fi

    # Save to local backup directory if configured
    if [ -n "$LOCAL_BACKUP_DIR" ]; then
        local local_dest_dir="${LOCAL_BACKUP_DIR}/${source_name}_backup"
        mkdir -p "$local_dest_dir"

        if [ "$DRY_RUN" = "1" ]; then
            log "[dry-run] Would copy to local: $local_dest_dir/$backup_filename"
        else
            cp "$tmp_file" "$local_dest_dir/"
            log "Saved locally: $local_dest_dir/$backup_filename"
            cleanup_local_backups "$local_dest_dir"
        fi
    else
        log "No local backup directory configured, skipping local save"
    fi

    # Upload to cloud if configured
    if has_any_cloud; then
        if [ "$DRY_RUN" = "1" ]; then
            log "[dry-run] Would upload to cloud"
            upload_to_all_clouds "$tmp_file"
        else
            upload_to_all_clouds "$tmp_file"
        fi
    else
        log "No cloud storage configured, skipping cloud upload"
    fi

    # Cleanup temp file
    if [ "$DRY_RUN" = "0" ] && [ -f "$tmp_file" ]; then
        rm -f "$tmp_file"
    fi

    log "Backup completed for: $source_dir"
    return 0
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    log "================================================================"
    log "Folder Backup - Starting"
    log "================================================================"

    # Validate: need at least one destination
    if [ -z "$LOCAL_BACKUP_DIR" ] && ! has_any_cloud; then
        fail "No backup destination configured! Set BACKUP_LOCAL_DIR and/or cloud storage credentials (S3/B2/R2)"
    fi

    # Check local backup dir
    if [ -n "$LOCAL_BACKUP_DIR" ]; then
        if [ ! -d "$LOCAL_BACKUP_DIR" ]; then
            log "Creating local backup directory: $LOCAL_BACKUP_DIR"
            mkdir -p "$LOCAL_BACKUP_DIR"
        fi
        log "Local backup: $LOCAL_BACKUP_DIR"
    fi

    # Log cloud targets
    has_s3_config && log "Cloud target: S3 (${S3_BUCKET})"
    has_b2_config && log "Cloud target: B2 (${B2_BUCKET})"
    has_r2_config && log "Cloud target: R2 (${R2_BUCKET})"

    # Find source directories
    if [ ! -d "$SOURCES_DIR" ]; then
        fail "Sources directory $SOURCES_DIR does not exist"
    fi

    local -a source_dirs=()
    for dir in "$SOURCES_DIR"/*/; do
        if [ -d "$dir" ]; then
            source_dirs+=("${dir%/}")
        fi
    done

    if [ ${#source_dirs[@]} -eq 0 ]; then
        fail "No directories found in $SOURCES_DIR to backup"
    fi

    log "Found ${#source_dirs[@]} directories to backup"

    local success_count=0
    local fail_count=0
    local -a results=()

    for source_dir in "${source_dirs[@]}"; do
        local name
        name=$(basename "$source_dir")
        if backup_directory "$source_dir"; then
            success_count=$((success_count + 1))
            results+=("✅ $name")
        else
            fail_count=$((fail_count + 1))
            results+=("❌ $name")
        fi
    done

    # Cloud rotation cleanup
    if has_any_cloud; then
        log "================================================================"
        log "Cloud backup rotation cleanup"
        log "================================================================"
        cleanup_all_clouds
    fi

    # Cleanup temp dir
    rm -rf "$TMP_DIR"

    # Summary
    log "================================================================"
    log "Backup Summary"
    log "================================================================"
    log "Total: ${#source_dirs[@]} | Success: $success_count | Failed: $fail_count"
    for r in "${results[@]}"; do
        log "  $r"
    done

    # Slack notification
    local summary="Backup Summary:\nTotal: ${#source_dirs[@]} | Success: $success_count | Failed: $fail_count"
    for r in "${results[@]}"; do
        summary+="\n  $r"
    done

    if [ "$fail_count" -gt 0 ]; then
        send_slack "FAILURE" "$summary"
        exit 1
    else
        send_slack "SUCCESS" "$summary"
    fi

    log "All done."
}

main "$@"
