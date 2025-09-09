#!/bin/bash

# WAL-G PostgreSQL 设置脚本
# 用于初始化配置和检查环境

set -e

echo "🚀 WAL-G PostgreSQL 备份系统设置"
echo "=================================="

# 检查是否存在 .env 文件
if [ ! -f ".env" ]; then
    echo "📝 创建 .env 配置文件..."
    cp examples.env .env
    echo "✅ .env 文件已创建，请编辑其中的配置"
    echo ""
    echo "⚠️  重要：请确保以下配置正确："
    echo "   1. AWS_ACCESS_KEY_ID - 你的 Cloudflare R2 访问密钥"
    echo "   2. AWS_SECRET_ACCESS_KEY - 你的 Cloudflare R2 秘密密钥"
    echo "   3. AWS_ENDPOINT_URL - 你的 R2 端点URL"
    echo "   4. WALG_S3_PREFIX - S3 bucket 路径"
    echo ""
    echo "📋 编辑配置文件："
    echo "   nano .env"
    echo ""
    exit 1
fi

# 检查必要的环境变量
echo "🔍 检查配置..."

source .env

# 必需的变量列表
required_vars=(
    "WALG_S3_PREFIX"
    "AWS_ACCESS_KEY_ID" 
    "AWS_SECRET_ACCESS_KEY"
    "AWS_ENDPOINT_URL"
    "POSTGRESQL_PASSWORD"
)

missing_vars=()

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        missing_vars+=("$var")
    fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
    echo "❌ 以下环境变量未配置："
    for var in "${missing_vars[@]}"; do
        echo "   - $var"
    done
    echo ""
    echo "请编辑 .env 文件配置这些变量"
    exit 1
fi

echo "✅ 基本配置检查通过"

# 检查 Docker 是否运行
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker 没有运行，请先启动 Docker"
    exit 1
fi

echo "✅ Docker 运行正常"

# 检查是否存在同名容器
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "⚠️  发现已存在的容器: $CONTAINER_NAME"
    read -p "是否删除现有容器重新开始? (y/N): " choice
    if [[ $choice =~ ^[Yy]$ ]]; then
        docker rm -f $CONTAINER_NAME
        echo "✅ 已删除现有容器"
    else
        echo "保持现有容器"
    fi
fi

# 检查 R2 bucket 访问
echo "🔗 测试 Cloudflare R2 连接..."

# 使用 AWS CLI 测试连接 (如果可用)
if command -v aws &> /dev/null; then
    if AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
       AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
       aws s3 ls $WALG_S3_PREFIX --endpoint-url=$AWS_ENDPOINT_URL > /dev/null 2>&1; then
        echo "✅ R2 连接测试成功"
    else
        echo "⚠️  R2 连接测试失败，请检查:"
        echo "   1. 访问密钥是否正确"
        echo "   2. bucket 是否已创建"
        echo "   3. 端点URL是否正确"
        echo ""
        echo "   你可以继续安装，但备份可能会失败"
    fi
else
    echo "⚠️  未安装 AWS CLI，无法测试 R2 连接"
    echo "   建议安装 aws-cli 进行连接测试"
fi

echo ""
echo "🎯 设置完成！接下来的步骤："
echo "1. 启动 PostgreSQL 容器:"
echo "   docker-compose up -d"
echo ""
echo "2. 安装和配置 WAL-G:"
echo "   ./install_wal-g.sh"
echo ""
echo "3. 管理备份:"
echo "   ./manage_wal-g.sh status"
echo "   ./manage_wal-g.sh backup"
echo ""
echo "�� 详细说明请查看 README.md" 