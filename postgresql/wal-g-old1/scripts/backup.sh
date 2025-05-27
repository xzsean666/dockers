#!/bin/bash

# This script is intended to be run INSIDE the PostgreSQL container via docker exec

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

# 数据目录
PG_DATA_DIR="/bitnami/postgresql/data"

# 检查wal-g是否可用 (可选，依赖于如何在PG容器中提供wal-g)
check_walg_available() {
    if ! command -v wal-g &> /dev/null; then
        log_error "wal-g command not found inside PostgreSQL container."
        log_error "Please ensure wal-g is available in the PostgreSQL container's PATH."
        return 1
    fi
    return 0
}

# 执行备份
perform_backup() {
    log_info "开始执行完整备份..."
    
    # 记录备份开始时间
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    log_info "备份开始时间: $start_time"
    
    # 执行备份，指向PG数据目录
    # 这里的环境变量 (WALG_S3_PREFIX etc.) 需要通过 docker exec 传递进来
    if wal-g backup-push "$PG_DATA_DIR"; then
        local end_time=$(date '+%Y-%m-%d %H:%M:%S')
        log_info "备份完成时间: $end_time"
        log_info "备份成功完成"
        return 0
    else
        log_error "备份失败"
        return 1
    fi
}

# 主备份流程
main() {
    log_info "=== 开始执行PostgreSQL容器内的备份任务 ==="
    
    # 检查wal-g是否可用
    if ! check_walg_available; then
        exit 1
    fi
    
    # 执行备份
    if perform_backup; then
        log_info "=== 备份任务完成 ==="
        # send_notification "SUCCESS" "备份成功完成" # 通知应由宿主机脚本处理
    else
        log_error "=== 备份任务失败 ==="
        # send_notification "FAILED" "备份执行失败" # 通知应由宿主机脚本处理
        exit 1
    fi
}

# 错误处理
set -euo pipefail

# 执行主函数
main "$@" 