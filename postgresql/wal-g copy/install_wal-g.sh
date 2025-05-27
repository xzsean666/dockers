#!/bin/bash

# WAL-G安装和配置脚本
# 用于在PostgreSQL容器中安装和配置WAL-G

set -e

source .env # Source environment variables from .env file

WAL_G_VERSION="3.0.7"

echo "🚀 开始安装和配置WAL-G..."

# 检查容器是否运行
if ! docker ps | grep -q $CONTAINER_NAME; then
    echo "❌ 容器 $CONTAINER_NAME 没有运行，请先启动容器"
    exit 1
fi

echo "📦 在容器中安装WAL-G..."

# 进入容器并安装WAL-G
docker exec -it $CONTAINER_NAME bash -c "
    # 更新包管理器
    apt-get update
    
    # 安装wget和ca-certificates
    apt-get install -y wget ca-certificates
    
    # 下载WAL-G
    wget -O /usr/local/bin/wal-g https://github.com/wal-g/wal-g/releases/download/v${WAL_G_VERSION}/wal-g-pg-ubuntu-20.04-amd64
    
    # 设置执行权限
    chmod +x /usr/local/bin/wal-g
    
    # 验证安装
    /usr/local/bin/wal-g --version
"

echo "⚙️ 配置WAL-G环境变量..."

# 创建WAL-G配置
docker exec -it $CONTAINER_NAME bash -c "
    # 创建WAL-G配置目录
    mkdir -p /etc/wal-g.d/env
    
    # 安装网络工具用于后续连接测试
    apt-get update -qq
    apt-get install -y -qq curl wget
    
    # 从宿主机环境变量写入WAL-G配置文件，直接使用实际值
    cat > /etc/wal-g.d/env/vars << EOF
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
export AWS_S3_FORCE_PATH_STYLE=$AWS_S3_FORCE_PATH_STYLE

# WAL-G 性能配置
export WALG_UPLOAD_CONCURRENCY=${WALG_UPLOAD_CONCURRENCY:-4}
export WALG_DOWNLOAD_CONCURRENCY=${WALG_DOWNLOAD_CONCURRENCY:-4}
export WALG_DISK_RATE_LIMIT=${WALG_DISK_RATE_LIMIT:-10485760}
export WALG_NETWORK_RATE_LIMIT=${WALG_NETWORK_RATE_LIMIT:-10485760}

# 启用详细日志用于调试
export WALG_LOG_LEVEL=DEVEL
EOF
    
    # 设置权限
    chmod 600 /etc/wal-g.d/env/vars
    chown postgres:postgres /etc/wal-g.d/env/vars
    
    # 验证配置是否正确写入
    echo '🔍 验证WAL-G配置:'
    source /etc/wal-g.d/env/vars
    echo \"  WALG_S3_PREFIX: \$WALG_S3_PREFIX\"
    echo \"  AWS_ENDPOINT_URL: \$AWS_ENDPOINT_URL\"
    echo \"  AWS_ACCESS_KEY_ID: \$AWS_ACCESS_KEY_ID\"
    
    # 测试网络连接
    echo '🌐 测试 R2 端点连接...'
    curl -I --connect-timeout 10 $AWS_ENDPOINT_URL || echo '⚠️  网络连接测试失败，请检查网络'
    
    echo '✅ WAL-G环境变量配置完成，使用S3存储到Cloudflare R2'
"

echo "📝 配置PostgreSQL启用WAL归档..."

# 配置PostgreSQL
docker exec -it $CONTAINER_NAME bash -c "
    # 创建WAL归档脚本
    cat > /usr/local/bin/wal-g-archive.sh << 'EOF'
#!/bin/bash
source /etc/wal-g.d/env/vars
wal-g wal-push \"\$1\"
EOF
    
    chmod +x /usr/local/bin/wal-g-archive.sh
    chown postgres:postgres /usr/local/bin/wal-g-archive.sh
    
    # 备份原始配置文件
    cp /opt/bitnami/postgresql/conf/postgresql.conf /opt/bitnami/postgresql/conf/postgresql.conf.backup
    
    # 添加WAL-G配置到postgresql.conf
    cat >> /opt/bitnami/postgresql/conf/postgresql.conf << 'EOF'

# WAL-G Configuration
# 启用WAL归档
archive_mode = on
# 设置归档命令使用WAL-G
archive_command = '/usr/local/bin/wal-g-archive.sh %p'
# 确保WAL级别为replica或logical
wal_level = replica
# 增加checkpoint频率以减少恢复时间
checkpoint_completion_target = 0.9
# 增加WAL文件大小以提高性能
max_wal_size = 2GB
min_wal_size = 512MB
# 设置归档超时
archive_timeout = 300
EOF
    
    echo '✅ PostgreSQL配置已更新'
"

echo "⏱️ 设置自动备份任务..."

# 创建备份脚本
docker exec -it $CONTAINER_NAME bash -c "
    cat > /usr/local/bin/wal-g-backup.sh << 'EOF'
#!/bin/bash
source /etc/wal-g.d/env/vars
echo \"\$(date): 开始WAL-G备份...\" >> /var/log/wal-g-backup.log
wal-g backup-push \$PGDATA >> /var/log/wal-g-backup.log 2>&1
if [ \$? -eq 0 ]; then
    echo \"\$(date): WAL-G备份完成\" >> /var/log/wal-g-backup.log
else
    echo \"\$(date): WAL-G备份失败\" >> /var/log/wal-g-backup.log
fi
EOF

    chmod +x /usr/local/bin/wal-g-backup.sh
    chown postgres:postgres /usr/local/bin/wal-g-backup.sh
    
    # 创建日志文件
    touch /var/log/wal-g-backup.log
    chown postgres:postgres /var/log/wal-g-backup.log
"

# 安装cron任务
docker exec -it $CONTAINER_NAME bash -c "
    # 安装cron
    apt-get install -y cron
    
    # 为postgres用户添加crontab
    echo '$BACKUP_SCHEDULE /usr/local/bin/wal-g-backup.sh' | crontab -u postgres -
    
    # 启动cron服务
    service cron start
    
    # 显示当前的crontab
    echo '当前的crontab任务:'
    crontab -u postgres -l
"

echo "🔄 重启PostgreSQL容器以应用archive_mode配置..."

# 重启整个容器 (archive_mode需要重启才能生效)
docker restart $CONTAINER_NAME

# 等待容器完全启动
echo "⏳ 等待容器启动..."
sleep 30

# 检查容器状态
echo "🔍 检查容器状态..."
docker ps --filter "name=$CONTAINER_NAME"

# 等待PostgreSQL服务就绪
echo "⏳ 等待PostgreSQL服务就绪..."
timeout=60
while [ $timeout -gt 0 ]; do
    if docker exec $CONTAINER_NAME pg_isready -h localhost -p 5432 -U postgres > /dev/null 2>&1; then
        echo "✅ PostgreSQL服务已就绪"
        break
    fi
    sleep 2
    timeout=$((timeout-2))
done

if [ $timeout -eq 0 ]; then
    echo "❌ PostgreSQL服务启动超时"
    exit 1
fi

# 验证配置
echo "🔍 验证PostgreSQL配置..."
docker exec $CONTAINER_NAME bash -c "
    export PGPASSWORD=\$POSTGRESQL_PASSWORD
    psql -U postgres -h localhost -p 5432 -d postgres -c \"
    SELECT name, setting FROM pg_settings 
    WHERE name IN ('archive_mode', 'archive_command', 'wal_level', 'archive_timeout') 
    ORDER BY name;\"
"

# 最终测试WAL-G连接
echo "🧪 测试WAL-G与R2的连接..."
docker exec $CONTAINER_NAME bash -c "
    source /etc/wal-g.d/env/vars
    echo '正在测试WAL-G连接到R2...'
    timeout 30 wal-g backup-list > /dev/null 2>&1
    if [ \$? -eq 0 ]; then
        echo '✅ WAL-G连接测试成功！'
    else
        echo '⚠️  WAL-G连接测试失败，请检查:'
        echo '   1. R2访问密钥是否正确'
        echo '   2. bucket是否存在'
        echo '   3. 网络连接是否正常'
        echo '   建议运行: ./manage_wal-g.sh test 进行详细诊断'
    fi
"

echo "✅ WAL-G安装和配置完成！"
echo ""
echo "📋 接下来你可以："
echo "   1. 运行 './manage_wal-g.sh status' 查看状态"
echo "   2. 运行 './manage_wal-g.sh backup' 手动创建备份"
echo "   3. 运行 './manage_wal-g.sh list' 查看备份列表"
echo ""
echo "🔧 配置信息："
echo "   - 备份存储: Cloudflare R2 (S3兼容)"
echo "   - S3 Bucket: pgbackup"
echo "   - 自动备份时间: $BACKUP_SCHEDULE"
echo "   - 日志文件: /var/log/wal-g-backup.log"
echo ""
echo "⚠️  重要提示："
echo "   - 备份数据将存储到Cloudflare R2，不是本地文件系统"
echo "   - 请确保R2 bucket 'pgbackup' 已创建"
echo "   - 首次备份可能需要较长时间" 