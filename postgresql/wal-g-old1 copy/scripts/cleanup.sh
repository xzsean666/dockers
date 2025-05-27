#!/bin/bash

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

# 检查PostgreSQL连接
check_postgres_connection() {
    if ! pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" > /dev/null 2>&1; then
        log_error "无法连接到PostgreSQL"
        return 1
    fi
    return 0
}

# 列出当前备份
list_current_backups() {
    log_info "当前备份列表:"
    wal-g backup-list || log_error "获取备份列表失败"
}

# 清理过期备份
cleanup_old_backups() {
    local retention_days=${RETENTION_DAYS:-7}
    
    log_info "开始清理超过 $retention_days 天的备份..."
    
    # 获取备份列表并计算要保留的数量
    local backup_count=$(wal-g backup-list 2>/dev/null | grep -E '^[0-9]' | wc -l)
    
    if [ $backup_count -eq 0 ]; then
        log_warn "没有找到任何备份"
        return 0
    fi
    
    log_info "找到 $backup_count 个备份"
    
    # 保留至少3个备份，即使超过了保留天数
    local min_retain=3
    local retain_count=$((backup_count > min_retain ? min_retain : backup_count))
    
    # 使用时间戳来删除过期备份
    local cutoff_date=$(date -d "$retention_days days ago" '+%Y-%m-%dT%H:%M:%S')
    log_info "清理截止时间: $cutoff_date"
    
    # 删除过期的完整备份，但保留最少数量
    if wal-g delete retain FULL $retain_count; then
        log_info "清理完成，保留了最近的 $retain_count 个完整备份"
    else
        log_error "清理备份失败"
        return 1
    fi
    
    # 清理WAL文件
    if wal-g delete garbage; then
        log_info "WAL垃圾文件清理完成"
    else
        log_warn "WAL垃圾文件清理失败"
    fi
}

# 发送清理报告
send_cleanup_report() {
    local status=$1
    local message=$2
    
    # 获取清理后的备份统计
    local backup_count=$(wal-g backup-list 2>/dev/null | grep -E '^[0-9]' | wc -l)
    local detailed_message="$message. 当前保留 $backup_count 个备份"
    
    # 发送通知
    if [ -n "$WEBHOOK_URL" ]; then
        curl -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"PostgreSQL Backup Cleanup $status: $detailed_message\"}" \
            > /dev/null 2>&1
    fi
}

# 健康检查
health_check() {
    log_info "执行备份健康检查..."
    
    # 检查最新备份的时间
    local latest_backup=$(wal-g backup-list 2>/dev/null | grep -E '^[0-9]' | tail -1 | awk '{print $1}')
    
    if [ -n "$latest_backup" ]; then
        log_info "最新备份: $latest_backup"
        
        # 检查备份是否太旧 (超过2天)
        local backup_timestamp=$(echo "$latest_backup" | sed 's/T/ /')
        local backup_epoch=$(date -d "$backup_timestamp" +%s 2>/dev/null || echo 0)
        local current_epoch=$(date +%s)
        local age_hours=$(((current_epoch - backup_epoch) / 3600))
        
        if [ $age_hours -gt 48 ]; then
            log_warn "警告: 最新备份已经超过48小时 (${age_hours}小时前)"
            send_cleanup_report "WARNING" "最新备份已经超过48小时"
        else
            log_info "最新备份时间正常 (${age_hours}小时前)"
        fi
    else
        log_error "没有找到任何备份！"
        send_cleanup_report "ERROR" "没有找到任何备份"
        return 1
    fi
}

# 主函数
main() {
    log_info "=== 开始备份清理任务 ==="
    
    # 检查PostgreSQL连接
    if ! check_postgres_connection; then
        log_error "PostgreSQL连接检查失败"
        send_cleanup_report "FAILED" "PostgreSQL连接失败"
        exit 1
    fi
    
    # 列出当前备份
    list_current_backups
    
    # 执行清理
    if cleanup_old_backups; then
        log_info "备份清理成功"
        
        # 执行健康检查
        if health_check; then
            log_info "=== 备份清理任务完成 ==="
            send_cleanup_report "SUCCESS" "备份清理成功完成"
        else
            log_warn "=== 备份清理完成，但健康检查发现问题 ==="
            send_cleanup_report "WARNING" "备份清理完成，但发现健康问题"
        fi
    else
        log_error "=== 备份清理失败 ==="
        send_cleanup_report "FAILED" "备份清理执行失败"
        exit 1
    fi
    
    # 显示清理后的备份列表
    log_info "清理后的备份列表:"
    list_current_backups
}

# 错误处理
set -euo pipefail

# 执行主函数
main "$@" 