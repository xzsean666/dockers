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
            echo \"   S3_PREFIX: \$WALG_S3_PREFIX\"
            echo \"   ENDPOINT: \$AWS_ENDPOINT_URL\"
            echo \"   REGION: \$AWS_REGION\"
            echo \"   FORCE_PATH_STYLE: \$AWS_S3_FORCE_PATH_STYLE\"
            
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
    echo -e "${BLUE}🧪 测试R2连接${NC}"
    
    if ! check_container; then
        return 1
    fi
    
    docker exec $CONTAINER_NAME bash -c "
        if [ -f /etc/wal-g.d/env/vars ]; then
            source /etc/wal-g.d/env/vars
            
            echo '🔗 测试基本网络连接...'
            if curl -I --connect-timeout 10 --max-time 30 \"\$AWS_ENDPOINT_URL\" 2>/dev/null | head -1 | grep -q \"HTTP\"; then
                echo '✅ 网络连接正常'
            else
                echo '⚠️  网络连接可能有问题（但R2可能不响应HEAD请求）'
            fi
            
            echo ''
            echo '🔗 测试WAL-G连接...'
            if timeout 60 wal-g backup-list 2>/dev/null; then
                echo '✅ WAL-G连接成功'
                return 0
            else
                echo '❌ WAL-G连接失败'
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
            
            if wal-g backup-push \$PGDATA; then
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

# 诊断R2配置
diagnose_r2() {
    echo -e "${BLUE}🔧 R2配置诊断${NC}"
    
    echo "1. 检查环境变量配置:"
    echo "   WALG_S3_PREFIX: $WALG_S3_PREFIX"
    echo "   AWS_ENDPOINT_URL: $AWS_ENDPOINT_URL"
    echo "   AWS_REGION: $AWS_REGION"
    echo "   AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:0:10}..."
    echo "   AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY:0:10}..."
    
    echo ""
    echo "2. 检查bucket名称:"
    bucket_name=$(echo $WALG_S3_PREFIX | sed 's|s3://||')
    echo "   Bucket: $bucket_name"
    
    if ! check_container; then
        return 1
    fi
    
    echo ""
    echo "3. 容器内部配置检查:"
    docker exec $CONTAINER_NAME bash -c "
        if [ -f /etc/wal-g.d/env/vars ]; then
            echo '✅ 配置文件存在'
            echo '配置文件内容:'
            cat /etc/wal-g.d/env/vars | grep -E '^export (WALG_|AWS_)' | head -10
        else
            echo '❌ 配置文件不存在'
        fi
    "
    
    echo ""
    echo -e "${YELLOW}📝 故障排除建议:${NC}"
    echo "   1. 确保R2 bucket '$bucket_name' 已创建"
    echo "   2. 检查R2 API token权限是否正确"
    echo "   3. 验证网络连接是否可达R2端点"
    echo "   4. 如果是首次使用，尝试手动创建备份测试连接"
}

# 重新配置WAL-G
reconfigure() {
    echo -e "${BLUE}⚙️ 重新配置WAL-G${NC}"
    
    if ! check_container; then
        return 1
    fi
    
    echo "正在重新生成配置文件..."
    docker exec $CONTAINER_NAME bash -c "
        # 重新创建配置文件
        mkdir -p /etc/wal-g.d/env
        cat > /etc/wal-g.d/env/vars << 'EOF'
# PostgreSQL 连接配置
export PGDATA=/bitnami/postgresql/data
export PGUSER=postgres
export PGPASSWORD=$POSTGRESQL_PASSWORD
export PGPORT=5432
export PGHOST=localhost

# WAL-G S3 配置 - 使用Cloudflare R2
export WALG_S3_PREFIX=$WALG_S3_PREFIX
export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
export AWS_REGION=$AWS_REGION
export AWS_ENDPOINT_URL=$AWS_ENDPOINT_URL
export AWS_S3_FORCE_PATH_STYLE=${AWS_S3_FORCE_PATH_STYLE:-true}

# R2特定配置
export WALG_S3_CA_CERT_FILE=
export WALG_S3_ENDPOINT_SOURCE=$AWS_ENDPOINT_URL
export WALG_S3_ENDPOINT_PORT=443
export WALG_S3_USE_SSL=true

# WAL-G 性能配置
export WALG_UPLOAD_CONCURRENCY=${WALG_UPLOAD_CONCURRENCY:-4}
export WALG_DOWNLOAD_CONCURRENCY=${WALG_DOWNLOAD_CONCURRENCY:-4}
export WALG_DISK_RATE_LIMIT=${WALG_DISK_RATE_LIMIT:-10485760}
export WALG_NETWORK_RATE_LIMIT=${WALG_NETWORK_RATE_LIMIT:-10485760}

# 启用详细日志用于调试
export WALG_LOG_LEVEL=DEVEL

# 设置压缩算法
export WALG_COMPRESSION_METHOD=lz4
EOF
        
        # 设置权限
        chmod 600 /etc/wal-g.d/env/vars
        chown postgres:postgres /etc/wal-g.d/env/vars
        
        echo '✅ 配置文件已重新生成'
    " \
    -e "POSTGRESQL_PASSWORD=$POSTGRESQL_PASSWORD" \
    -e "WALG_S3_PREFIX=$WALG_S3_PREFIX" \
    -e "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" \
    -e "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" \
    -e "AWS_REGION=$AWS_REGION" \
    -e "AWS_ENDPOINT_URL=$AWS_ENDPOINT_URL" \
    -e "AWS_S3_FORCE_PATH_STYLE=${AWS_S3_FORCE_PATH_STYLE:-true}" \
    -e "WALG_UPLOAD_CONCURRENCY=${WALG_UPLOAD_CONCURRENCY:-4}" \
    -e "WALG_DOWNLOAD_CONCURRENCY=${WALG_DOWNLOAD_CONCURRENCY:-4}" \
    -e "WALG_DISK_RATE_LIMIT=${WALG_DISK_RATE_LIMIT:-10485760}" \
    -e "WALG_NETWORK_RATE_LIMIT=${WALG_NETWORK_RATE_LIMIT:-10485760}"
}

# 显示帮助信息
show_help() {
    echo -e "${BLUE}📖 WAL-G管理脚本帮助${NC}"
    echo ""
    echo "使用方法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  status      显示WAL-G状态"
    echo "  test        测试R2连接"
    echo "  list        显示备份列表"
    echo "  backup      创建手动备份"
    echo "  logs        显示备份日志"
    echo "  diagnose    诊断R2配置"
    echo "  reconfig    重新配置WAL-G"
    echo "  help        显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 status     # 检查WAL-G状态"
    echo "  $0 test       # 测试R2连接"
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
    "diagnose")
        diagnose_r2
        ;;
    "reconfig")
        reconfigure
        ;;
    "help"|*)
        show_help
        ;;
esac 