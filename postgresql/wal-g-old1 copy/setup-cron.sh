#!/bin/bash

# PostgreSQL WAL-G 宿主机定时备份设置脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查.env文件
if [ ! -f .env ]; then
    log_error ".env文件不存在，请先创建配置文件"
    exit 1
fi

# 加载环境变量
source .env

# 获取当前目录的绝对路径
CURRENT_DIR=$(pwd)
SCRIPT_PATH="$CURRENT_DIR/scripts/manage.sh"
LOG_PATH="$CURRENT_DIR/logs"

# 创建日志目录
mkdir -p "$LOG_PATH"

# 默认备份计划（每天凌晨2点）
BACKUP_SCHEDULE=${BACKUP_SCHEDULE:-"0 2 * * *"}

log_info "设置PostgreSQL定时备份..."
log_info "备份计划: $BACKUP_SCHEDULE"
log_info "脚本路径: $SCRIPT_PATH"
log_info "日志路径: $LOG_PATH"

# 创建定时任务
CRON_JOB="$BACKUP_SCHEDULE cd $CURRENT_DIR && $SCRIPT_PATH --scheduled-backup >> $LOG_PATH/backup.log 2>&1"

# 检查是否已经存在相同的定时任务
if crontab -l 2>/dev/null | grep -F "$SCRIPT_PATH --scheduled-backup" > /dev/null; then
    log_warn "定时备份任务已存在，正在更新..."
    # 移除旧的任务
    crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH --scheduled-backup" | crontab -
fi

# 添加新的定时任务
(crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

if [ $? -eq 0 ]; then
    log_info "定时备份任务设置成功！"
    log_info ""
    log_info "当前的crontab设置:"
    crontab -l | grep "$SCRIPT_PATH --scheduled-backup"
    log_info ""
    log_info "备份日志将保存到: $LOG_PATH/backup.log"
    log_info ""
    log_info "管理命令:"
    log_info "  查看定时任务: crontab -l"
    log_info "  删除定时任务: crontab -e (手动删除相关行)"
    log_info "  查看备份日志: tail -f $LOG_PATH/backup.log"
    log_info "  手动执行备份: $SCRIPT_PATH --scheduled-backup"
else
    log_error "设置定时任务失败！"
    exit 1
fi 