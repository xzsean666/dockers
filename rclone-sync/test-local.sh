#!/usr/bin/env bash
set -euo pipefail

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

mkdir -p "$ROOT/source/photos" "$ROOT/source/documents" "$ROOT/target"
mkdir -p "$ROOT/source/photos/sub"
printf 'photo\n' > "$ROOT/source/photos/a.txt"
printf 'skip\n' > "$ROOT/source/photos/skip.tmp"
printf 'nested skip\n' > "$ROOT/source/photos/sub/nested.tmp"
printf 'doc\n' > "$ROOT/source/documents/readme.md"
printf 'old\n' > "$ROOT/source/documents/old.txt"
touch -d '2020-01-01 00:00:00' "$ROOT/source/documents/old.txt"

RCLONE_SYNC_SOURCE_ROOT="$ROOT/source" \
RCLONE_SYNC_TARGET_ROOT="$ROOT/target/prefix" \
RCLONE_SYNC_DIRECTORIES="photos,documents" \
RCLONE_SYNC_MODE=copy \
RCLONE_SYNC_DRY_RUN=false \
RCLONE_SYNC_EXCLUDE_EXTENSIONS=".tmp" \
RCLONE_SYNC_LOGS_DIR="$ROOT/logs" \
RCLONE_SYNC_STATE_DIR="$ROOT/state" \
RCLONE_SYNC_RCLONE_CONFIG="" \
TZ=UTC \
python3 "$(dirname "$0")/runner.py"

test -f "$ROOT/target/prefix/photos/a.txt"
test ! -f "$ROOT/target/prefix/photos/skip.tmp"
test ! -f "$ROOT/target/prefix/photos/sub/nested.tmp"
test -f "$ROOT/target/prefix/documents/readme.md"

RCLONE_SYNC_SOURCE_ROOT="$ROOT/source" \
RCLONE_SYNC_TARGET_ROOT="$ROOT/target/old-only" \
RCLONE_SYNC_DIRECTORIES="documents" \
RCLONE_SYNC_MODE=copy \
RCLONE_SYNC_DRY_RUN=false \
RCLONE_SYNC_OLDER_THAN="1d" \
RCLONE_SYNC_LOGS_DIR="$ROOT/logs" \
RCLONE_SYNC_STATE_DIR="$ROOT/state" \
RCLONE_SYNC_RCLONE_CONFIG="" \
TZ=UTC \
python3 "$(dirname "$0")/runner.py"

test -f "$ROOT/target/old-only/documents/old.txt"
test ! -f "$ROOT/target/old-only/documents/readme.md"

echo "local smoke test passed"
