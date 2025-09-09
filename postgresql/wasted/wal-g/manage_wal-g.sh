#!/bin/bash

# WAL-G管理脚本
# 用于管理和调试WAL-G连接问题

set -e

# 检查.env文件是否存在
if [ ! -f .env ]; then
    echo "❌ .env文件不存在，请从examples.env复制并配置"
    exit 1
fi

source .env

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查容器是否运行
check_container() {
    if ! docker ps | grep -q $CONTAINER_NAME; then
        echo -e "${RED}❌ 容器 $CONTAINER_NAME 没有运行${NC}"
        return 1
    fi
    return 0
}

# 显示WAL-G状态
show_status() {
    echo -e "${BLUE}🔍 WAL-G状态检查${NC}"
    
    if ! check_container; then
        return 1
    fi
    
    docker exec $CONTAINER_NAME bash -c "
        if [ -f /etc/wal-g.d/env/vars ]; then
            echo '✅ WAL-G配置文件存在'
            source /etc/wal-g.d/env/vars
            
            echo '📋 当前配置:'
            echo \"   FILE_PREFIX: \$WALG_FILE_PREFIX\"
            
            # 检查WAL-G是否安装
            if which wal-g &>/dev/null; then
                echo '✅ WAL-G已安装'
                wal-g --version
            else
                echo '❌ WAL-G未安装'
                return 1
            fi
        else
            echo '❌ WAL-G配置文件不存在'
            return 1
        fi
    "
}

# 测试R2连接
test_connection() {
    echo -e "${BLUE}🧪 测试本地文件系统连接${NC}"
    
    if ! check_container; then
        return 1
    fi
    
    docker exec $CONTAINER_NAME bash -c "
        if [ -f /etc/wal-g.d/env/vars ]; then
            source /etc/wal-g.d/env/vars
            
            echo '🔗 测试WAL-G本地存储访问...'
            if timeout 60 wal-g backup-list 2>/dev/null; then
                echo '✅ WAL-G本地存储访问成功'
                return 0
            else
                echo '❌ WAL-G本地存储访问失败'
                echo ''
                echo '🔍 详细错误信息:'
                timeout 30 wal-g backup-list 2>&1 || true
                return 1
            fi
        else
            echo '❌ WAL-G配置文件不存在，请先运行安装脚本'
            return 1
        fi
    "
}

# 显示备份列表
list_backups() {
    echo -e "${BLUE}📊 显示备份列表${NC}"
    
    if ! check_container; then
        return 1
    fi
    
    docker exec $CONTAINER_NAME bash -c "
        if [ -f /etc/wal-g.d/env/vars ]; then
            source /etc/wal-g.d/env/vars
            echo '正在获取备份列表...'
            wal-g backup-list || echo '❌ 获取备份列表失败'
        else
            echo '❌ WAL-G配置文件不存在'
            return 1
        fi
    "
}

# 手动创建备份
create_backup() {
    echo -e "${BLUE}💾 创建手动备份${NC}"
    
    if ! check_container; then
        return 1
    fi
    
    docker exec $CONTAINER_NAME bash -c "
        if [ -f /etc/wal-g.d/env/vars ]; then
            source /etc/wal-g.d/env/vars
            echo '开始创建备份...'
            echo '注意：首次备份可能需要较长时间'
            
            if wal-g backup-push $PGDATA; then
                echo '✅ 备份创建成功'
                echo ''
                echo '📊 更新后的备份列表:'
                wal-g backup-list
            else
                echo '❌ 备份创建失败'
                return 1
            fi
        else
            echo '❌ WAL-G配置文件不存在'
            return 1
        fi
    "
}

# 查看日志
show_logs() {
    echo -e "${BLUE}📄 显示WAL-G日志${NC}"
    
    if ! check_container; then
        return 1
    fi
    
    docker exec $CONTAINER_NAME bash -c "
        if [ -f /var/log/wal-g-backup.log ]; then
            echo '最近的备份日志:'
            tail -20 /var/log/wal-g-backup.log
        else
            echo '❌ 备份日志文件不存在'
        fi
    "
}

# 显示帮助信息
show_help() {
    echo -e "${BLUE}📖 WAL-G管理脚本帮助${NC}"
    echo ""
    echo "使用方法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  status      显示WAL-G状态"
    echo "  test        测试本地文件系统连接"
    echo "  list        显示备份列表"
    echo "  backup      创建手动备份"
    echo "  logs        显示备份日志"
    echo "  reconfig    重新配置WAL-G"
    echo "  help        显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 status     # 检查WAL-G状态"
    echo "  $0 test       # 测试本地文件系统连接"
    echo "  $0 backup     # 创建备份"
}

# 主程序
case "${1:-help}" in
    "status")
        show_status
        ;;
    "test")
        test_connection
        ;;
    "list")
        list_backups
        ;;
    "backup")
        create_backup
        ;;
    "logs")
        show_logs
        ;;
    "reconfig")
        reconfigure
        ;;
    "help"|*)
        show_help
        ;;
esac 