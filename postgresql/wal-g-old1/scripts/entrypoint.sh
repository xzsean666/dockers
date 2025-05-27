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

# 等待PostgreSQL启动
wait_for_postgres() {
    log_info "等待PostgreSQL启动..."
    local count=0
    local max_attempts=30
    
    while [ $count -lt $max_attempts ]; do
        if pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" > /dev/null 2>&1; then
            log_info "PostgreSQL已就绪"
            return 0
        fi
        
        log_info "等待PostgreSQL启动... ($((count + 1))/$max_attempts)"
        sleep 5
        count=$((count + 1))
    done
    
    log_error "PostgreSQL启动超时"
    return 1
}

# 验证WAL-G配置
validate_walg_config() {
    log_info "验证WAL-G配置..."
    
    # 检查必需的环境变量
    if [ -z "$WALG_S3_PREFIX" ]; then
        log_error "WALG_S3_PREFIX未设置"
        return 1
    fi
    
    if [ -z "$AWS_ACCESS_KEY_ID" ]; then
        log_error "AWS_ACCESS_KEY_ID未设置"
        return 1
    fi
    
    if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        log_error "AWS_SECRET_ACCESS_KEY未设置"
        return 1
    fi
    
    # 测试WAL-G连接
    if wal-g st ls > /dev/null 2>&1; then
        log_info "WAL-G S3连接正常"
    else
        log_warn "WAL-G S3连接可能有问题，请检查配置"
    fi
    
    return 0
}

# 设置定时备份
setup_cron() {
    log_info "设置定时备份任务..."
    
    # 创建cron任务
    echo "# WAL-G Backup Schedule" > /etc/crontab
    echo "SHELL=/bin/bash" >> /etc/crontab
    echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" >> /etc/crontab
    echo "" >> /etc/crontab
    
    # 完整备份任务由宿主机的cron负责，这里不添加
    
    # 添加WAL归档处理任务 (每5分钟检查一次)
    echo "*/5 * * * * root /scripts/wal_archive.sh >> /var/log/cron/wal_archive.log 2>&1" >> /etc/crontab
    
    # 添加清理任务 (每周日凌晨3点)
    echo "0 3 * * 0 root /scripts/cleanup.sh >> /var/log/cron/cleanup.log 2>&1" >> /etc/crontab
    
    log_info "定时任务已设置"
}

# 启动服务
start_services() {
    log_info "启动cron服务..."
    cron
    
    log_info "WAL-G备份服务已启动"
    log_info "备份计划: ${BACKUP_SCHEDULE:-0 2 * * *}"
    log_info "保留天数: ${RETENTION_DAYS:-7}"
}

# 复制wal-g二进制文件到共享卷
setup_shared_binaries() {
    log_info "设置共享的wal-g二进制文件..."
    
    local shared_bin_dir="/usr/local/bin-shared"
    
    # 确保共享目录存在
    mkdir -p "$shared_bin_dir"
    
    # 复制wal-g二进制文件到共享卷
    if cp /usr/local/bin/wal-g "$shared_bin_dir/wal-g"; then
        chmod +x "$shared_bin_dir/wal-g"
        log_info "wal-g二进制文件已复制到共享卷"
    else
        log_error "复制wal-g二进制文件到共享卷失败"
        return 1
    fi
    
    return 0
}

# 主函数
main() {
    log_info "WAL-G备份容器启动中..."
    
    # 设置共享的wal-g二进制文件
    if ! setup_shared_binaries; then
        exit 1
    fi
    
    # 等待PostgreSQL
    if ! wait_for_postgres; then
        exit 1
    fi
    
    # 验证配置
    if ! validate_walg_config; then
        exit 1
    fi
    
    # 设置定时任务
    setup_cron
    
    # 启动服务
    start_services
    
    # 保持容器运行
    log_info "进入守护模式..."
    tail -f /var/log/cron/*.log 2>/dev/null || tail -f /dev/null
}

# 信号处理
cleanup() {
    log_info "接收到停止信号，正在关闭..."
    pkill cron
    exit 0
}

trap cleanup SIGTERM SIGINT

# 启动主函数
main "$@" 