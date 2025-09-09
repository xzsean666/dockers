#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
ODYSSEY_REPO="https://github.com/yandex/odyssey.git"
ODYSSEY_DIR="odyssey-src"
CONFIG_FILE="example.odyssey.env"
ODYSSEY_CONF="odyssey.conf"

print_info "开始部署 Odyssey PostgreSQL 连接池..."

# Check if docker and docker-compose are installed
if ! command -v docker &> /dev/null; then
    print_error "Docker 未安装，请先安装 Docker"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    print_error "Docker Compose 未安装，请先安装 Docker Compose"
    exit 1
fi

# Step 1: Clone Odyssey repository
print_info "第 1 步: 克隆 Odyssey 源代码..."
if [ -d "$ODYSSEY_DIR" ]; then
    print_warning "目录 $ODYSSEY_DIR 已存在，正在更新..."
    cd $ODYSSEY_DIR
    git pull origin master
    cd ..
else
    git clone $ODYSSEY_REPO $ODYSSEY_DIR
fi
print_success "Odyssey 源代码准备完成"

# Step 2: Check configuration file
print_info "第 2 步: 检查配置文件..."
if [ ! -f "$CONFIG_FILE" ]; then
    print_error "配置文件 $CONFIG_FILE 不存在！"
    print_info "请编辑 $CONFIG_FILE 文件，配置你的数据库信息"
    exit 1
fi

# Load environment variables
source $CONFIG_FILE

# Step 3: Generate Odyssey configuration
print_info "第 3 步: 生成 Odyssey 配置文件..."
if [ ! -f "odyssey.conf.template" ]; then
    print_error "模板文件 odyssey.conf.template 不存在！"
    exit 1
fi

# Replace environment variables in the template
envsubst < odyssey.conf.template > $ODYSSEY_CONF
print_success "配置文件 $ODYSSEY_CONF 生成完成"

# Step 4: Create necessary directories
print_info "第 4 步: 创建必要的目录..."
mkdir -p logs
mkdir -p data
print_success "目录创建完成"

# Step 5: Validate configuration
print_info "第 5 步: 验证配置..."
print_info "Master 数据库: ${POSTGRES_MASTER_HOST}:${POSTGRES_MASTER_PORT}"
print_info "Slave 数据库: ${POSTGRES_SLAVE_HOST}:${POSTGRES_SLAVE_PORT}"
print_info "Odyssey 端口: ${ODYSSEY_PORT}"

# Step 6: Build and start services
print_info "第 6 步: 构建和启动 Odyssey 服务..."
docker-compose down 2>/dev/null || true
docker-compose build --no-cache
docker-compose up -d

# Step 7: Wait for service to be ready
print_info "第 7 步: 等待服务启动..."
sleep 10

# Check if Odyssey is running
if docker-compose ps | grep -q "Up"; then
    print_success "Odyssey 服务启动成功！"
    echo
    print_info "连接信息:"
    echo "  主机: localhost"
    echo "  端口: ${ODYSSEY_PORT}"
    echo "  写操作数据库: write_${POSTGRES_MASTER_DB}"
    echo "  读操作数据库: read_${POSTGRES_SLAVE_DB}"
    echo "  用户名: 根据配置文件"
    echo
    print_info "使用示例:"
    echo "  写操作: psql -h localhost -p ${ODYSSEY_PORT} -d write_${POSTGRES_MASTER_DB} -U write_${POSTGRES_MASTER_USER}"
    echo "  读操作: psql -h localhost -p ${ODYSSEY_PORT} -d read_${POSTGRES_SLAVE_DB} -U read_${POSTGRES_SLAVE_USER}"
    echo
    print_info "查看日志: docker-compose logs -f odyssey"
    print_info "停止服务: docker-compose down"
else
    print_error "Odyssey 服务启动失败！"
    print_info "查看日志: docker-compose logs odyssey"
    exit 1
fi

print_success "Odyssey 部署完成！" 