#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 错误处理
set -euo pipefail

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "命令 '$1' 未找到，请先安装"
        exit 1
    fi
}

# 检查Docker和docker-compose
check_dependencies() {
    check_command "docker"
    check_command "docker-compose"
}

# 获取容器名称
get_container_name() {
    local container_name=$(grep -A 1 "container_name:" docker-compose.yml 2>/dev/null | grep -v "container_name:" | tr -d '[:space:]' || echo "")
    echo "${container_name:-postgresql-master}"
}

# 检查容器是否运行
check_container_running() {
    if ! docker ps --filter "name=$CONTAINER_NAME" --filter "status=running" | grep -q "$CONTAINER_NAME"; then
        log_error "容器 $CONTAINER_NAME 未运行"
        return 1
    fi
    return 0
}

# 设置容器名称变量
CONTAINER_NAME=$(get_container_name)

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then 
    log_error "请使用sudo运行此脚本"
    exit 1
fi

# 检查依赖
check_dependencies

# 显示菜单
show_menu() {
    echo -e "\n${GREEN}PostgreSQL 备份恢复工具${NC}"
    echo "1. 查看所有备份"
    echo "2. 创建完整备份"
    echo "3. 恢复到最新备份"
    echo "4. 恢复到指定时间点"
    echo "5. 删除过期备份"
    echo "6. 检查容器状态"
    echo "7. 退出"
    echo -n "请选择操作 [1-7]: "
}

# 查看所有备份
list_backups() {
    log_info "正在列出所有备份..."
    if check_container_running; then
        if docker exec "$CONTAINER_NAME" wal-g backup-list; then
            log_info "备份列表获取成功"
        else
            log_error "获取备份列表失败"
        fi
    fi
}

# 创建完整备份
create_backup() {
    log_info "正在创建完整备份..."
    
    if ! check_container_running; then
        return 1
    fi
    
    # 检查WAL-G配置
    if ! docker exec "$CONTAINER_NAME" wal-g --help > /dev/null 2>&1; then
        log_error "WAL-G未正确安装或配置"
        return 1
    fi
    
    # 执行备份
    log_info "开始执行备份，这可能需要一些时间..."
    if docker exec "$CONTAINER_NAME" wal-g backup-push /bitnami/postgresql/data; then
        log_info "备份创建成功！"
        # 显示备份信息
        log_info "最新备份列表："
        docker exec "$CONTAINER_NAME" wal-g backup-list | tail -5
    else
        log_error "备份创建失败！请检查："
        log_error "1. S3凭证配置是否正确"
        log_error "2. 网络连接是否正常"
        log_error "3. WAL-G配置是否正确"
        return 1
    fi
}

# 恢复到最新备份
restore_latest() {
    log_warn "正在恢复到最新备份..."
    log_warn "此操作将停止数据库并覆盖当前数据！"
    
    # 二次确认
    read -p "请输入 'YES' 确认继续: " confirm
    if [ "$confirm" != "YES" ]; then
        log_info "操作已取消"
        return 0
    fi

    log_info "停止容器..."
    if ! docker-compose stop "$CONTAINER_NAME"; then
        log_error "停止容器失败"
        return 1
    fi

    log_info "执行恢复..."
    if docker-compose run --rm "$CONTAINER_NAME" bash -c "
        set -e
        echo 'Fetching latest backup...'
        wal-g backup-fetch /bitnami/postgresql/data LATEST
        echo 'Backup restored successfully'
    "; then
        log_info "启动容器..."
        docker-compose start "$CONTAINER_NAME"
        log_info "恢复完成！"
    else
        log_error "恢复失败！正在重启容器..."
        docker-compose start "$CONTAINER_NAME"
        return 1
    fi
}

# 恢复到指定时间点
restore_to_time() {
    log_warn "恢复到指定时间点"
    echo -e "${YELLOW}请输入要恢复的时间点 (格式: YYYY-MM-DD HH:MM:SS UTC)${NC}"
    read -p "时间点: " target_time
    
    # 验证时间格式
    if ! date -d "$target_time" &>/dev/null; then
        log_error "无效的时间格式"
        return 1
    fi
    
    log_warn "此操作将停止数据库并覆盖当前数据！"
    read -p "请输入 'YES' 确认继续: " confirm
    if [ "$confirm" != "YES" ]; then
        log_info "操作已取消"
        return 0
    fi

    log_info "停止容器..."
    docker-compose stop "$CONTAINER_NAME"
    
    log_info "清理数据目录..."
    docker-compose run --rm "$CONTAINER_NAME" rm -rf /bitnami/postgresql/data/*
    
    log_info "执行时间点恢复..."
    if docker-compose run --rm "$CONTAINER_NAME" bash -c "
        set -e
        wal-g backup-fetch /bitnami/postgresql/data LATEST
        echo \"restore_command = 'wal-g wal-fetch %f %p'\" > /bitnami/postgresql/data/recovery.conf
        echo \"recovery_target_time = '$target_time'\" >> /bitnami/postgresql/data/recovery.conf
        echo \"recovery_target_action = 'promote'\" >> /bitnami/postgresql/data/recovery.conf
        echo \"Point-in-time recovery configured\"
    "; then
        log_info "启动容器..."
        docker-compose start "$CONTAINER_NAME"
        log_info "时间点恢复完成！"
    else
        log_error "时间点恢复失败！"
        docker-compose start "$CONTAINER_NAME"
        return 1
    fi
}

# 删除过期备份
delete_old_backups() {
    log_warn "删除过期备份"
    echo -e "${YELLOW}请输入要保留的备份数量${NC}"
    read -p "保留数量: " retain_count
    
    # 验证输入
    if ! [[ "$retain_count" =~ ^[0-9]+$ ]] || [ "$retain_count" -le 0 ]; then
        log_error "无效的数量"
        return 1
    fi
    
    if ! check_container_running; then
        return 1
    fi
    
    log_warn "即将删除除最近 $retain_count 个备份外的所有备份"
    read -p "请输入 'YES' 确认: " confirm
    if [ "$confirm" != "YES" ]; then
        log_info "操作已取消"
        return 0
    fi

    if docker exec "$CONTAINER_NAME" wal-g delete retain FULL "$retain_count"; then
        log_info "删除完成！"
    else
        log_error "删除失败！"
        return 1
    fi
}

# 检查容器状态
check_status() {
    log_info "检查容器状态..."
    echo "容器名称: $CONTAINER_NAME"
    
    if check_container_running; then
        log_info "容器正在运行"
        
        # 检查PostgreSQL状态
        if docker exec "$CONTAINER_NAME" pg_isready -U postgres; then
            log_info "PostgreSQL服务正常"
        else
            log_warn "PostgreSQL服务异常"
        fi
        
        # 检查WAL-G
        if docker exec "$CONTAINER_NAME" wal-g --version; then
            log_info "WAL-G已安装"
        else
            log_warn "WAL-G未正确安装"
        fi
    else
        log_warn "容器未运行"
    fi
}

# 主循环
while true; do
    show_menu
    read choice
    case $choice in
        1) list_backups ;;
        2) create_backup ;;
        3) restore_latest ;;
        4) restore_to_time ;;
        5) delete_old_backups ;;
        6) check_status ;;
        7) echo "退出程序"; exit 0 ;;
        *) log_error "无效选择，请重试" ;;
    esac
    
    echo
    read -p "按Enter键继续..."
done 