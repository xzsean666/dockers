#!/bin/bash

# PostgreSQL容器内执行的备份脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

# 数据目录
PG_DATA_DIR="/bitnami/postgresql/data"

# wal-g路径
WALG_PATH="/usr/local/bin-ext/wal-g"

# 检查wal-g是否可用
if [ ! -f "$WALG_PATH" ]; then
    log_error "wal-g未找到: $WALG_PATH"
    exit 1
fi

# 执行备份
log_info "开始执行完整备份..."
log_info "数据目录: $PG_DATA_DIR"
log_info "使用wal-g: $WALG_PATH"

start_time=$(date '+%Y-%m-%d %H:%M:%S')
log_info "备份开始时间: $start_time"

if "$WALG_PATH" backup-push "$PG_DATA_DIR"; then
    end_time=$(date '+%Y-%m-%d %H:%M:%S')
    log_info "备份完成时间: $end_time"
    log_info "备份成功完成"
    exit 0
else
    log_error "备份失败"
    exit 1
fi 