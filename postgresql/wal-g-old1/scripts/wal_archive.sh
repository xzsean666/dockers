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

# WAL归档目录
WAL_ARCHIVE_DIR="/shared/wal-archive"

# 处理WAL文件归档
process_wal_files() {
    local file_count=0
    local success_count=0
    local error_count=0
    
    # 检查归档目录是否存在
    if [ ! -d "$WAL_ARCHIVE_DIR" ]; then
        log_warn "WAL归档目录不存在: $WAL_ARCHIVE_DIR"
        return 0
    fi
    
    # 处理所有WAL文件
    for wal_file in "$WAL_ARCHIVE_DIR"/*; do
        # 跳过如果没有文件
        [ ! -f "$wal_file" ] && continue
        
        local filename=$(basename "$wal_file")
        
        # 跳过非WAL文件
        if [[ ! "$filename" =~ ^[0-9A-F]{24}$ ]] && [[ ! "$filename" =~ \.backup$ ]]; then
            continue
        fi
        
        file_count=$((file_count + 1))
        
        # 使用wal-g推送WAL文件
        if wal-g wal-push "$wal_file"; then
            # 成功后删除本地文件
            rm -f "$wal_file"
            success_count=$((success_count + 1))
            log_info "WAL文件已归档: $filename"
        else
            error_count=$((error_count + 1))
            log_error "WAL文件归档失败: $filename"
        fi
    done
    
    # 输出统计信息
    if [ $file_count -gt 0 ]; then
        log_info "WAL归档统计: 总计=$file_count, 成功=$success_count, 失败=$error_count"
    fi
}

# 清理旧的WAL文件 (超过1小时的)
cleanup_old_wal_files() {
    if [ -d "$WAL_ARCHIVE_DIR" ]; then
        local old_files=$(find "$WAL_ARCHIVE_DIR" -type f -mmin +60 2>/dev/null | wc -l)
        if [ $old_files -gt 0 ]; then
            log_warn "发现 $old_files 个超过1小时的WAL文件"
            find "$WAL_ARCHIVE_DIR" -type f -mmin +60 -delete 2>/dev/null
            log_info "已清理超过1小时的WAL文件"
        fi
    fi
}

# 监控归档目录大小
monitor_archive_size() {
    if [ -d "$WAL_ARCHIVE_DIR" ]; then
        local size=$(du -sh "$WAL_ARCHIVE_DIR" 2>/dev/null | cut -f1)
        local file_count=$(find "$WAL_ARCHIVE_DIR" -type f 2>/dev/null | wc -l)
        
        if [ $file_count -gt 100 ]; then
            log_warn "WAL归档目录文件数量过多: $file_count 个文件 ($size)"
        fi
    fi
}

# 主函数
main() {
    # 静默模式，只在有文件处理或出错时输出
    local quiet_mode=true
    
    # 检查PostgreSQL连接
    if ! pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" > /dev/null 2>&1; then
        if [ "$quiet_mode" = false ]; then
            log_warn "PostgreSQL连接检查失败，跳过WAL归档"
        fi
        return 0
    fi
    
    # 处理WAL文件
    process_wal_files
    
    # 清理旧文件
    cleanup_old_wal_files
    
    # 监控归档大小
    monitor_archive_size
}

# 错误处理
set -euo pipefail

# 执行主函数
main "$@" 