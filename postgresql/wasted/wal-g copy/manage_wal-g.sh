#!/bin/bash

# WAL-G管理脚本
# 用于管理PostgreSQL WAL-G备份

set -e

source .env # Source environment variables from .env file

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 帮助信息
show_help() {
    echo "WAL-G 管理脚本"
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "命令:"
    echo "  status          - 查看WAL-G和备份状态"
    echo "  backup          - 手动创建全量备份"
    echo "  list            - 列出所有备份"
    echo "  logs            - 查看备份日志"
    echo "  config          - 查看WAL-G配置"
    echo "  test            - 测试WAL-G连接"
    echo "  restore [name]  - 恢复指定备份"
    echo "  delete [name]   - 删除指定备份"
    echo "  cleanup         - 清理旧备份(保留最近5个)"
    echo "  cron            - 查看cron任务状态"
    echo "  help            - 显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 status"
    echo "  $0 backup"
    echo "  $0 restore base_20231201T120000Z"
    echo "  $0 delete base_20231201T120000Z"
}

# 检查容器是否运行
check_container() {
    if ! docker ps | grep -q $CONTAINER_NAME; then
        echo -e "${RED}❌ 容器 $CONTAINER_NAME 没有运行${NC}"
        exit 1
    fi
}

# 检查WAL-G是否安装
check_walg() {
    if ! docker exec $CONTAINER_NAME which wal-g > /dev/null 2>&1; then
        echo -e "${RED}❌ WAL-G 没有安装，请先运行 install_wal-g.sh${NC}"
        exit 1
    fi
}

# 查看状态
show_status() {
    echo -e "${BLUE}📊 WAL-G 状态检查${NC}"
    echo "=========================="
    
    echo -e "\n${YELLOW}🐳 容器状态:${NC}"
    docker ps --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    echo -e "\n${YELLOW}🔧 WAL-G 版本:${NC}"
    docker exec $CONTAINER_NAME bash -c "source /etc/wal-g.d/env/vars && wal-g --version" 2>/dev/null || echo "WAL-G 未安装或配置错误"
    
    echo -e "\n${YELLOW}💾 PostgreSQL 配置:${NC}"
    docker exec $CONTAINER_NAME bash -c "
        export PGPASSWORD=\$POSTGRESQL_PASSWORD
        psql -U postgres -h localhost -p 5432 -d postgres -c \"
        SELECT name, setting FROM pg_settings 
        WHERE name IN ('archive_mode', 'archive_command', 'wal_level') 
        ORDER BY name;\""
    
    echo -e "\n${YELLOW}📁 备份存储:${NC}"
    echo "使用 Cloudflare R2 (S3兼容存储)"
    docker exec $CONTAINER_NAME bash -c "source /etc/wal-g.d/env/vars && echo \"S3 Prefix: \$WALG_S3_PREFIX\"" 2>/dev/null || echo "WAL-G配置未找到"
    
    echo -e "\n${YELLOW}📝 最近备份日志:${NC}"
    docker exec $CONTAINER_NAME tail -n 5 /var/log/wal-g-backup.log 2>/dev/null || echo "日志文件不存在"
    
    echo -e "\n${YELLOW}⏰ Cron 任务:${NC}"
    docker exec $CONTAINER_NAME crontab -u postgres -l 2>/dev/null || echo "没有设置cron任务"
}

# 手动备份
manual_backup() {
    echo -e "${BLUE}🔄 开始手动备份...${NC}"
    
    docker exec $CONTAINER_NAME bash -c "
        source /etc/wal-g.d/env/vars
        echo \"$(date): 手动备份开始...\" | tee -a /var/log/wal-g-backup.log
        wal-g backup-push \$PGDATA
        if [ \$? -eq 0 ]; then
            echo \"$(date): 手动备份完成\" | tee -a /var/log/wal-g-backup.log
        else
            echo \"$(date): 手动备份失败\" | tee -a /var/log/wal-g-backup.log
            exit 1
        fi
    "
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 备份完成${NC}"
    else
        echo -e "${RED}❌ 备份失败${NC}"
        exit 1
    fi
}

# 列出备份
list_backups() {
    echo -e "${BLUE}📋 备份列表${NC}"
    echo "=========================="
    
    docker exec $CONTAINER_NAME bash -c "
        source /etc/wal-g.d/env/vars
        wal-g backup-list
    "
}

# 查看日志
show_logs() {
    echo -e "${BLUE}📝 备份日志${NC}"
    echo "=========================="
    
    docker exec $CONTAINER_NAME tail -n 50 /var/log/wal-g-backup.log 2>/dev/null || echo "日志文件不存在"
}

# 查看配置
show_config() {
    echo -e "${BLUE}⚙️ WAL-G 配置${NC}"
    echo "=========================="
    
    echo -e "\n${YELLOW}环境变量:${NC}"
    docker exec $CONTAINER_NAME cat /etc/wal-g.d/env/vars
    
    echo -e "\n${YELLOW}PostgreSQL 归档配置:${NC}"
    docker exec $CONTAINER_NAME grep -A 10 "WAL-G Configuration" /opt/bitnami/postgresql/conf/postgresql.conf || echo "配置未找到"
}

# 测试连接
test_walg() {
    echo -e "${BLUE}🔍 测试WAL-G连接${NC}"
    echo "=========================="
    
    docker exec $CONTAINER_NAME bash -c "
        source /etc/wal-g.d/env/vars
        echo '测试WAL-G配置...'
        wal-g backup-list > /dev/null 2>&1
        if [ \$? -eq 0 ]; then
            echo '✅ WAL-G连接正常'
        else
            echo '❌ WAL-G连接失败'
            exit 1
        fi
    "
}

# 恢复备份
restore_backup() {
    local backup_name=$1
    
    if [ -z "$backup_name" ]; then
        echo -e "${RED}❌ 请指定要恢复的备份名称${NC}"
        echo "使用 '$0 list' 查看可用备份"
        exit 1
    fi
    
    echo -e "${YELLOW}⚠️  警告: 这将覆盖当前数据库！${NC}"
    read -p "确认继续吗? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo "操作已取消"
        exit 0
    fi
    
    echo -e "${BLUE}🔄 开始恢复备份 $backup_name...${NC}"
    
    docker exec $CONTAINER_NAME bash -c "
        source /etc/wal-g.d/env/vars
        su - postgres -c 'pg_ctl stop -D /bitnami/postgresql/data -m fast'
        rm -rf \$PGDATA/*
        wal-g backup-fetch \$PGDATA $backup_name
        chown -R postgres:postgres \$PGDATA
        su - postgres -c 'pg_ctl start -D /bitnami/postgresql/data'
    "
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 恢复完成${NC}"
    else
        echo -e "${RED}❌ 恢复失败${NC}"
        exit 1
    fi
}

# 删除备份
delete_backup() {
    local backup_name=$1
    
    if [ -z "$backup_name" ]; then
        echo -e "${RED}❌ 请指定要删除的备份名称${NC}"
        echo "使用 '$0 list' 查看可用备份"
        exit 1
    fi
    
    echo -e "${YELLOW}⚠️  警告: 这将永久删除备份 $backup_name${NC}"
    read -p "确认删除吗? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo "操作已取消"
        exit 0
    fi
    
    echo -e "${BLUE}🗑️  删除备份 $backup_name...${NC}"
    
    docker exec $CONTAINER_NAME bash -c "
        source /etc/wal-g.d/env/vars
        wal-g delete before $backup_name
    "
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 删除完成${NC}"
    else
        echo -e "${RED}❌ 删除失败${NC}"
        exit 1
    fi
}

# 清理旧备份
cleanup_backups() {
    echo -e "${BLUE}🧹 清理旧备份 (保留最近5个)...${NC}"
    
    docker exec $CONTAINER_NAME bash -c "
        source /etc/wal-g.d/env/vars
        wal-g delete retain 5
    "
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 清理完成${NC}"
    else
        echo -e "${RED}❌ 清理失败${NC}"
        exit 1
    fi
}

# 查看cron状态
show_cron() {
    echo -e "${BLUE}⏰ Cron 状态${NC}"
    echo "=========================="
    
    echo -e "\n${YELLOW}Cron 服务状态:${NC}"
    docker exec $CONTAINER_NAME service cron status
    
    echo -e "\n${YELLOW}Postgres用户的cron任务:${NC}"
    docker exec $CONTAINER_NAME crontab -u postgres -l 2>/dev/null || echo "没有设置cron任务"
    
    echo -e "\n${YELLOW}Cron 日志:${NC}"
    docker exec $CONTAINER_NAME tail -n 10 /var/log/cron.log 2>/dev/null || echo "cron日志不存在"
}

# 主程序
main() {
    case "${1:-help}" in
        "status")
            check_container
            check_walg
            show_status
            ;;
        "backup")
            check_container
            check_walg
            manual_backup
            ;;
        "list")
            check_container
            check_walg
            list_backups
            ;;
        "logs")
            check_container
            show_logs
            ;;
        "config")
            check_container
            check_walg
            show_config
            ;;
        "test")
            check_container
            check_walg
            test_walg
            ;;
        "restore")
            check_container
            check_walg
            restore_backup "$2"
            ;;
        "delete")
            check_container
            check_walg
            delete_backup "$2"
            ;;
        "cleanup")
            check_container
            check_walg
            cleanup_backups
            ;;
        "cron")
            check_container
            show_cron
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

main "$@" 