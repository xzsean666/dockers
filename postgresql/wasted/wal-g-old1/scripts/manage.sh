#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

log_title() {
    echo -e "${BLUE}[TITLE]${NC} $1"
}

# 检查容器是否运行
check_container_running() {
    local container_name="$1"
    if ! docker ps --filter "name=$container_name" --filter "status=running" | grep -q "$container_name"; then
        return 1
    fi
    return 0
}

# 显示菜单
show_menu() {
    echo -e "\n${BLUE}================================${NC}"
    echo -e "${BLUE}    PostgreSQL WAL-G 备份管理    ${NC}"
    echo -e "${BLUE}================================${NC}"
    echo "1. 查看所有备份"
    echo "2. 创建完整备份"
    echo "3. 恢复到最新备份"
    echo "4. 恢复到指定时间点"
    echo "5. 删除过期备份"
    echo "6. 检查服务状态"
    echo "7. 查看备份日志"
    echo "8. 手动清理WAL文件"
    echo "9. 备份统计信息"
    echo "0. 退出"
    echo -e "${BLUE}================================${NC}"
    echo -n "请选择操作 [0-9]: "
}

# 查看所有备份
list_backups() {
    log_title "查看所有备份"
    
    # 在wal-g容器中执行
    if docker exec "${CONTAINER_NAME}-wal-g" wal-g backup-list; then
        log_info "备份列表获取成功"
    else
        log_error "获取备份列表失败"
    fi
}

# 创建完整备份
create_backup() {
    log_title "创建完整备份"
    
    local pg_container_name="${CONTAINER_NAME}"
    local walg_container_name="${CONTAINER_NAME}-wal-g"
    
    # 检查容器是否运行
    if ! check_container_running "$pg_container_name"; then
        log_error "PostgreSQL容器 ($pg_container_name) 未运行"
        return 1
    fi
    
    if ! check_container_running "$walg_container_name"; then
        log_error "WAL-G容器 ($walg_container_name) 未运行"
        return 1
    fi
    
    log_info "在 PostgreSQL 容器中执行备份..."
    
    # 直接在PostgreSQL容器中执行备份脚本（无需复制文件）
    if docker exec "$pg_container_name" /bin/bash /shared/scripts/pg-backup.sh; then
        log_info "完整备份成功完成！"
        return 0
    else
        log_error "完整备份失败！"
        return 1
    fi
}

# 恢复到最新备份
restore_latest() {
    log_title "恢复到最新备份"
    log_warn "此操作将停止数据库并覆盖当前数据！"
    
    # 二次确认
    read -p "请输入 'YES' 确认继续: " confirm
    if [ "$confirm" != "YES" ]; then
        log_info "操作已取消"
        return 0
    fi

    log_info "停止PostgreSQL容器..."
    docker-compose stop postgresql
    
    log_info "执行恢复..."
    # 使用 docker-compose run --rm 执行恢复命令，确保正确挂载卷和环境变量
    if docker-compose run --rm -e "WALG_S3_PREFIX=${WALG_S3_PREFIX}" \
                           -e "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}" \
                           -e "AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}" \
                           -e "AWS_REGION=${AWS_REGION}" \
                           ${AWS_ENDPOINT_URL:+-e "AWS_ENDPOINT_URL=${AWS_ENDPOINT_URL}"} \
                           ${AWS_S3_FORCE_PATH_STYLE:+-e "AWS_S3_FORCE_PATH_STYLE=${AWS_S3_FORCE_PATH_STYLE}"} \
                           wal-g bash -c "
        # 清理现有数据目录
        if [ -d /bitnami/postgresql/data ]; then
            echo \"清理现有数据目录...\"
            rm -rf /bitnami/postgresql/data/*
        fi
        
        echo \"执行 wal-g backup-fetch...\"
        wal-g backup-fetch /bitnami/postgresql/data LATEST
        echo \"Backup restored successfully\"
    "; then
        log_info "启动PostgreSQL容器..."
        docker-compose start postgresql
        log_info "恢复完成！"
    else
        log_error "恢复失败！正在重启PostgreSQL容器..."
        docker-compose start postgresql
        return 1
    fi
}

# 恢复到指定时间点
restore_to_time() {
    log_title "恢复到指定时间点"
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

    log_info "停止PostgreSQL容器..."
    docker-compose stop postgresql
    
    log_info "执行时间点恢复..."
    # 使用 docker-compose run --rm 执行恢复命令，确保正确挂载卷和环境变量
    if docker-compose run --rm -e "WALG_S3_PREFIX=${WALG_S3_PREFIX}" \
                           -e "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}" \
                           -e "AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}" \
                           -e "AWS_REGION=${AWS_REGION}" \
                           ${AWS_ENDPOINT_URL:+-e "AWS_ENDPOINT_URL=${AWS_ENDPOINT_URL}"} \
                           ${AWS_S3_FORCE_PATH_STYLE:+-e "AWS_S3_FORCE_PATH_STYLE=${AWS_S3_FORCE_PATH_STYLE}"} \
                           wal-g bash -c "
        # 清理现有数据目录
        if [ -d /bitnami/postgresql/data ]; then
            echo \"清理现有数据目录...\"
            rm -rf /bitnami/postgresql/data/*
        fi
        
        echo \"执行 wal-g backup-fetch...\"
        wal-g backup-fetch /bitnami/postgresql/data LATEST
        
        echo \"配置 recovery.conf...\"
        # 创建 recovery.conf 配置时间点恢复
        echo \"restore_command = 'wal-g wal-fetch %f %p'\" > /bitnami/postgresql/data/recovery.conf
        echo \"recovery_target_time = '$target_time'\" >> /bitnami/postgresql/data/recovery.conf
        echo \"recovery_target_action = 'promote'\" >> /bitnami/postgresql/data/recovery.conf
        echo \"Point-in-time recovery configured\"
    "; then
        log_info "启动PostgreSQL容器..."
        docker-compose start postgresql
        log_info "时间点恢复完成！"
    else
        log_error "时间点恢复失败！"
        docker-compose start postgresql
        return 1
    fi
}

# 删除过期备份
delete_old_backups() {
    log_title "删除过期备份"
    
    if ! check_container_running "${CONTAINER_NAME}-wal-g"; then
        log_error "wal-g容器未运行"
        return 1
    fi
    
    echo -e "${YELLOW}请输入要保留的备份数量${NC}"
    read -p "保留数量: " retain_count
    
    # 验证输入
    if ! [[ "$retain_count" =~ ^[0-9]+$ ]] || [ "$retain_count" -le 0 ]; then
        log_error "无效的数量"
        return 1
    fi
    
    log_warn "即将删除除最近 $retain_count 个备份外的所有备份"
    read -p "请输入 'YES' 确认: " confirm
    if [ "$confirm" != "YES" ]; then
        log_info "操作已取消"
        return 0
    fi

    if docker exec "${CONTAINER_NAME}-wal-g" wal-g delete retain FULL "$retain_count"; then
        log_info "删除完成！"
    else
        log_error "删除失败！"
        return 1
    fi
}

# 检查服务状态
check_status() {
    log_title "检查服务状态"
    
    echo "=== PostgreSQL容器状态 ==="
    if check_container_running "$CONTAINER_NAME"; then
        log_info "PostgreSQL容器正在运行"
        
        # 检查PostgreSQL服务状态
        if docker exec "$CONTAINER_NAME" pg_isready -U postgres; then
            log_info "PostgreSQL服务正常"
        else
            log_warn "PostgreSQL服务异常"
        fi
    else
        log_warn "PostgreSQL容器未运行"
    fi
    
    echo -e "\n=== WAL-G容器状态 ==="
    if check_container_running "${CONTAINER_NAME}-wal-g"; then
        log_info "WAL-G容器正在运行"
        
        # 检查WAL-G版本
        docker exec "${CONTAINER_NAME}-wal-g" wal-g --version
        
        # 检查cron状态
        if docker exec "${CONTAINER_NAME}-wal-g" pgrep cron > /dev/null; then
            log_info "定时任务服务正常"
        else
            log_warn "定时任务服务异常"
        fi
    else
        log_warn "WAL-G容器未运行"
    fi
}

# 查看备份日志
view_logs() {
    log_title "查看备份日志"
    
    if ! check_container_running "${CONTAINER_NAME}-wal-g"; then
        log_error "wal-g容器未运行"
        return 1
    fi
    
    echo "1. 查看备份日志"
    echo "2. 查看WAL归档日志"
    echo "3. 查看清理日志"
    echo "4. 查看容器日志"
    read -p "请选择 [1-4]: " log_choice
    
    case $log_choice in
        1)
            docker exec "${CONTAINER_NAME}-wal-g" tail -n 50 /var/log/cron/backup.log 2>/dev/null || log_warn "备份日志文件不存在"
            ;;
        2)
            docker exec "${CONTAINER_NAME}-wal-g" tail -n 50 /var/log/cron/wal_archive.log 2>/dev/null || log_warn "WAL归档日志文件不存在"
            ;;
        3)
            docker exec "${CONTAINER_NAME}-wal-g" tail -n 50 /var/log/cron/cleanup.log 2>/dev/null || log_warn "清理日志文件不存在"
            ;;
        4)
            docker logs --tail 50 "${CONTAINER_NAME}-wal-g"
            ;;
        *)
            log_error "无效选择"
            ;;
    esac
}

# 手动清理WAL文件
manual_wal_cleanup() {
    log_title "手动清理WAL文件"
    
    if ! check_container_running "${CONTAINER_NAME}-wal-g"; then
        log_error "wal-g容器未运行"
        return 1
    fi
    
    log_info "执行WAL文件清理..."
    if docker exec "${CONTAINER_NAME}-wal-g" /scripts/wal_archive.sh; then
        log_info "WAL文件清理完成"
    else
        log_error "WAL文件清理失败"
    fi
}

# 备份统计信息
backup_statistics() {
    log_title "备份统计信息"
    
    if ! check_container_running "${CONTAINER_NAME}-wal-g"; then
        log_error "wal-g容器未运行"
        return 1
    fi
    
    echo "=== 备份统计 ==="
    local backup_count=$(docker exec "${CONTAINER_NAME}-wal-g" wal-g backup-list 2>/dev/null | grep -E '^[0-9]' | wc -l)
    echo "总备份数量: $backup_count"
    
    if [ $backup_count -gt 0 ]; then
        local latest_backup=$(docker exec "${CONTAINER_NAME}-wal-g" wal-g backup-list 2>/dev/null | grep -E '^[0-9]' | tail -1 | awk '{print $1}')
        echo "最新备份: $latest_backup"
        
        local oldest_backup=$(docker exec "${CONTAINER_NAME}-wal-g" wal-g backup-list 2>/dev/null | grep -E '^[0-9]' | head -1 | awk '{print $1}')
        echo "最旧备份: $oldest_backup"
    fi
    
    echo -e "\n=== WAL归档统计 ==="
    local wal_count=$(docker exec "${CONTAINER_NAME}-wal-g" find /shared/wal-archive -type f 2>/dev/null | wc -l)
    echo "待归档WAL文件数量: $wal_count"
    
    if [ $wal_count -gt 0 ]; then
        local wal_size=$(docker exec "${CONTAINER_NAME}-wal-g" du -sh /shared/wal-archive 2>/dev/null | cut -f1)
        echo "待归档WAL文件大小: $wal_size"
    fi
}

# 主循环
main() {
    # 检查.env文件
    if [ ! -f .env ]; then
        log_error ".env文件不存在，请先创建配置文件"
        exit 1
    fi
    
    # 加载环境变量
    source .env
    
    # 检查必要的环境变量
    if [ -z "${CONTAINER_NAME:-}" ]; then
        log_error "CONTAINER_NAME环境变量未设置"
        exit 1
    fi
    
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
            7) view_logs ;;
            8) manual_wal_cleanup ;;
            9) backup_statistics ;;
            0) echo "退出程序"; exit 0 ;;
            *) log_error "无效选择，请重试" ;;
        esac
        
        echo
        read -p "按Enter键继续..."
    done
}

# 用于定时任务的静默备份函数
scheduled_backup() {
    # 检查.env文件
    if [ ! -f .env ]; then
        echo "ERROR: .env文件不存在，请先创建配置文件" >&2
        exit 1
    fi
    
    # 加载环境变量
    source .env
    
    # 检查必要的环境变量
    if [ -z "${CONTAINER_NAME:-}" ]; then
        echo "ERROR: CONTAINER_NAME环境变量未设置" >&2
        exit 1
    fi
    
    # 添加时间戳
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') 开始定时备份任务 ==="
    
    # 执行备份
    if create_backup; then
        echo "=== $(date '+%Y-%m-%d %H:%M:%S') 定时备份任务完成 ==="
        exit 0
    else
        echo "=== $(date '+%Y-%m-%d %H:%M:%S') 定时备份任务失败 ===" >&2
        exit 1
    fi
}

# 检查是否是定时备份调用
if [ "$1" = "--scheduled-backup" ]; then
    scheduled_backup
    exit $?
fi

# 运行主函数
main "$@" 