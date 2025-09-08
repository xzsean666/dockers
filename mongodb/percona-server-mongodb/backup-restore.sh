#!/bin/bash

# 加载环境变量
source .env

# 容器名称
PBM_CONTAINER="${CONTAINER_NAME}-pbm"

# 显示存储配置信息
show_storage_info() {
    echo "=== 存储配置信息 ==="
    echo "存储类型: S3 兼容"
    echo "存储桶: ${S3_BUCKET}"
    echo "区域: ${AWS_DEFAULT_REGION}"
    if [ -n "${S3_ENDPOINT_URL}" ]; then
        echo "自定义端点: ${S3_ENDPOINT_URL}"
        # 识别存储服务类型
        if [[ "${S3_ENDPOINT_URL}" == *"r2.cloudflarestorage.com"* ]]; then
            echo "存储服务: Cloudflare R2"
        elif [[ "${S3_ENDPOINT_URL}" == *"backblazeb2.com"* ]]; then
            echo "存储服务: Backblaze B2"
        elif [[ "${S3_ENDPOINT_URL}" == *"aliyuncs.com"* ]]; then
            echo "存储服务: 阿里云 OSS"
        elif [[ "${S3_ENDPOINT_URL}" == *"myqcloud.com"* ]]; then
            echo "存储服务: 腾讯云 COS"
        else
            echo "存储服务: 自定义 S3 兼容服务"
        fi
    else
        echo "存储服务: AWS S3"
    fi
    echo "前缀路径: ${S3_PREFIX:-无}"
    echo "===================="
}

# 显示数据库连接信息
show_connection_info() {
    echo "=== 数据库连接信息 ==="
    echo "容器名称: ${CONTAINER_NAME}"
    echo "数据库端口: ${PORT}"
    echo "管理员用户: ${MONGO_ROOT_USERNAME}"
    echo ""
    echo "🔗 连接字符串："
    echo ""
    
    # 本地连接（通过 Docker）
    echo "📍 本地连接（Docker 内部）："
    echo "mongodb://${MONGO_ROOT_USERNAME}:${MONGO_ROOT_PASSWORD}@${CONTAINER_NAME}:27017/admin?authSource=admin"
    echo ""
    
    # 本地主机连接
    echo "📍 本地主机连接："
    echo "mongodb://${MONGO_ROOT_USERNAME}:${MONGO_ROOT_PASSWORD}@localhost:${PORT}/admin?authSource=admin"
    echo ""
    
    # 远程连接模板
    echo "📍 远程连接模板："
    echo "mongodb://${MONGO_ROOT_USERNAME}:${MONGO_ROOT_PASSWORD}@YOUR_HOST_IP:${PORT}/admin?authSource=admin"
    echo ""
    
    # MongoDB Compass 连接字符串
    echo "📍 MongoDB Compass 连接："
    echo "mongodb://${MONGO_ROOT_USERNAME}:${MONGO_ROOT_PASSWORD}@localhost:${PORT}/?authSource=admin&readPreference=primary&ssl=false"
    echo ""
    
    # Node.js 连接示例
    echo "📍 Node.js 连接示例："
    echo "const uri = 'mongodb://${MONGO_ROOT_USERNAME}:${MONGO_ROOT_PASSWORD}@localhost:${PORT}/mydb?authSource=admin';"
    echo ""
    
    # Python 连接示例
    echo "📍 Python 连接示例："
    echo "client = pymongo.MongoClient('mongodb://${MONGO_ROOT_USERNAME}:${MONGO_ROOT_PASSWORD}@localhost:${PORT}/?authSource=admin')"
    echo ""
    
    echo "🔧 命令行连接："
    echo "mongosh \"mongodb://${MONGO_ROOT_USERNAME}:${MONGO_ROOT_PASSWORD}@localhost:${PORT}/admin\""
    echo ""
    echo "或直接使用 Docker："
    echo "docker exec -it ${CONTAINER_NAME} mongosh -u ${MONGO_ROOT_USERNAME} -p ${MONGO_ROOT_PASSWORD} --authenticationDatabase admin"
    echo "===================="
}

# 显示连接信息
show_connection_info() {
    echo "=== 系统信息 ==="
    echo "MongoDB: ${CONTAINER_NAME} (端口 ${PORT})"
    echo "备份工具: ${PBM_CONTAINER}"
    echo "用户: ${MONGO_ROOT_USERNAME}"
    echo ""
    echo "🔗 连接字符串："
    echo "mongodb://${MONGO_ROOT_USERNAME}:${MONGO_ROOT_PASSWORD}@localhost:${PORT}/admin?authSource=admin"
    echo ""
    echo "🔧 快速连接："
    echo "docker exec -it ${CONTAINER_NAME} mongosh -u ${MONGO_ROOT_USERNAME} -p"
    echo "===================="
}

# 连接数据库
connect_db() {
    echo "🔗 连接到 MongoDB..."
    docker exec -it ${CONTAINER_NAME} mongosh -u ${MONGO_ROOT_USERNAME} -p ${MONGO_ROOT_PASSWORD} --authenticationDatabase admin
}

# 逻辑备份
backup() {
    echo "开始逻辑备份..."
    docker exec $PBM_CONTAINER pbm backup --type=logical
    [ $? -eq 0 ] && echo "✅ 备份完成！" || echo "❌ 备份失败！"
}

# 增量备份
backup_physical() {
    echo "开始增量备份..."
    docker exec $PBM_CONTAINER pbm backup --type=physical
    [ $? -eq 0 ] && echo "✅ 备份完成！" || echo "❌ 备份失败！"
}

# 列出备份
list_backups() {
    echo "📋 备份列表："
    docker exec $PBM_CONTAINER pbm list
}

# 恢复备份
restore() {
    [ -z "$1" ] && echo "用法: $0 restore <backup-id>" && exit 1
    echo "🔄 恢复备份 $1..."
    docker exec $PBM_CONTAINER pbm restore $1
    [ $? -eq 0 ] && echo "✅ 恢复完成！" || echo "❌ 恢复失败！"
}

# 时间点恢复
pitr_restore() {
    [ -z "$1" ] && echo "用法: $0 pitr '2024-01-15T10:00:00'" && exit 1
    echo "⏰ 恢复到时间点 $1..."
    docker exec $PBM_CONTAINER pbm restore --time="$1"
    [ $? -eq 0 ] && echo "✅ 时间点恢复完成！" || echo "❌ 恢复失败！"
}

# 主菜单
case "$1" in
    backup|backup-logical)
        backup
        ;;
    backup-physical|backup-inc)
        backup_physical
        ;;
    list)
        list_backups
        ;;
    restore)
        restore "$2"
        ;;
    pitr)
        pitr_restore "$2"
        ;;
    info|config)
        show_storage_info
        ;;
    connect|conn)
        connect_db
        ;;
    connection|uri)
        show_connection_info
        ;;
    *)
        echo "🗄️  Percona MongoDB + S3 备份工具"
        echo ""
        echo "📦 备份：$0 backup | backup-physical"
        echo "📋 管理：$0 list | restore <id> | pitr <time>"  
        echo "🔗 连接：$0 connect | connection"
        echo "⚙️  信息：$0 info"
        echo ""
        echo "容器：MongoDB(${CONTAINER_NAME}) + PBM(${PBM_CONTAINER})"
        ;;
esac
