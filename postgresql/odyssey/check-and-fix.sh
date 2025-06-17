#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
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

print_check() {
    echo -e "${CYAN}[CHECK]${NC} $1"
}

print_fix() {
    echo -e "${MAGENTA}[FIX]${NC} $1"
}

# Configuration
CONFIG_FILE="example.odyssey.env"
ODYSSEY_CONF_TEMPLATE="odyssey.conf.template"
DOCKER_COMPOSE_FILE="docker-compose.yml"
DEPLOY_SCRIPT="deploy-odyssey.sh"
TEST_SCRIPT="test-connection.sh"
ODYSSEY_DIR="odyssey-src"

echo "========================================================"
echo "Odyssey PostgreSQL 读写分离配置全面检测"
echo "========================================================"

# Global check results
ERRORS=0
WARNINGS=0
ISSUES=()

# Function to add issue
add_issue() {
    local type=$1
    local message=$2
    ISSUES+=("[$type] $message")
    if [ "$type" = "ERROR" ]; then
        ((ERRORS++))
    elif [ "$type" = "WARNING" ]; then
        ((WARNINGS++))
    fi
}

# Check 1: Prerequisites
print_check "检查系统prerequisites..."

if ! command -v docker &> /dev/null; then
    add_issue "ERROR" "Docker 未安装"
else
    print_success "Docker 已安装: $(docker --version)"
fi

if ! command -v docker-compose &> /dev/null; then
    add_issue "ERROR" "Docker Compose 未安装"
else
    print_success "Docker Compose 已安装: $(docker-compose --version)"
fi

if ! command -v git &> /dev/null; then
    add_issue "ERROR" "Git 未安装"
else
    print_success "Git 已安装: $(git --version)"
fi

if ! command -v envsubst &> /dev/null; then
    add_issue "ERROR" "envsubst 未安装 (需要 gettext 包)"
else
    print_success "envsubst 已安装"
fi

if ! command -v psql &> /dev/null; then
    add_issue "WARNING" "PostgreSQL 客户端未安装，无法进行连接测试"
else
    print_success "PostgreSQL 客户端已安装: $(psql --version)"
fi

if ! command -v nc &> /dev/null; then
    add_issue "WARNING" "netcat 未安装，健康检查可能失败"
else
    print_success "netcat 已安装"
fi

# Check 2: Required files
print_check "检查必要文件..."

if [ ! -f "$CONFIG_FILE" ]; then
    add_issue "ERROR" "配置文件 $CONFIG_FILE 不存在"
else
    print_success "配置文件 $CONFIG_FILE 存在"
fi

if [ ! -f "$ODYSSEY_CONF_TEMPLATE" ]; then
    add_issue "ERROR" "配置模板 $ODYSSEY_CONF_TEMPLATE 不存在"
else
    print_success "配置模板 $ODYSSEY_CONF_TEMPLATE 存在"
fi

if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
    add_issue "ERROR" "Docker Compose 文件 $DOCKER_COMPOSE_FILE 不存在"
else
    print_success "Docker Compose 文件 $DOCKER_COMPOSE_FILE 存在"
fi

if [ ! -f "$DEPLOY_SCRIPT" ]; then
    add_issue "WARNING" "部署脚本 $DEPLOY_SCRIPT 不存在"
else
    print_success "部署脚本 $DEPLOY_SCRIPT 存在"
    if [ ! -x "$DEPLOY_SCRIPT" ]; then
        add_issue "WARNING" "部署脚本 $DEPLOY_SCRIPT 不可执行"
    fi
fi

if [ ! -f "$TEST_SCRIPT" ]; then
    add_issue "WARNING" "测试脚本 $TEST_SCRIPT 不存在"
else
    print_success "测试脚本 $TEST_SCRIPT 存在"
    if [ ! -x "$TEST_SCRIPT" ]; then
        add_issue "WARNING" "测试脚本 $TEST_SCRIPT 不可执行"
    fi
fi

# Check 3: Configuration validation
if [ -f "$CONFIG_FILE" ]; then
    print_check "验证配置文件内容..."
    
    source "$CONFIG_FILE"
    
    # Check required variables
    required_vars=(
        "ODYSSEY_CONTAINER_NAME"
        "ODYSSEY_PORT"
        "POSTGRES_MASTER_HOST"
        "POSTGRES_MASTER_PORT"
        "POSTGRES_MASTER_DB"
        "POSTGRES_MASTER_USER"
        "POSTGRES_MASTER_PASSWORD"
        "POSTGRES_SLAVE_HOST"
        "POSTGRES_SLAVE_PORT"
        "POSTGRES_SLAVE_DB"
        "POSTGRES_SLAVE_USER"
        "POSTGRES_SLAVE_PASSWORD"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            add_issue "ERROR" "必需的配置变量 $var 未设置或为空"
        else
            # Check for placeholder values
            case "${!var}" in
                *"IP地址"*|*"主机名"*|*"主数据库"*|*"从数据库"*)
                    add_issue "ERROR" "配置变量 $var 仍然是占位符值: ${!var}"
                    ;;
                *)
                    print_success "配置变量 $var 已设置: ${!var}"
                    ;;
            esac
        fi
    done
    
    # Check if master and slave are different
    if [ "$POSTGRES_MASTER_HOST" = "$POSTGRES_SLAVE_HOST" ] && [ "$POSTGRES_MASTER_PORT" = "$POSTGRES_SLAVE_PORT" ]; then
        add_issue "WARNING" "主从数据库使用相同的主机和端口，这不是真正的读写分离"
    fi
    
    # Validate port numbers
    if ! [[ "$ODYSSEY_PORT" =~ ^[0-9]+$ ]] || [ "$ODYSSEY_PORT" -lt 1024 ] || [ "$ODYSSEY_PORT" -gt 65535 ]; then
        add_issue "ERROR" "Odyssey 端口号无效: $ODYSSEY_PORT"
    fi
    
    if ! [[ "$POSTGRES_MASTER_PORT" =~ ^[0-9]+$ ]] || [ "$POSTGRES_MASTER_PORT" -lt 1 ] || [ "$POSTGRES_MASTER_PORT" -gt 65535 ]; then
        add_issue "ERROR" "主数据库端口号无效: $POSTGRES_MASTER_PORT"
    fi
    
    if ! [[ "$POSTGRES_SLAVE_PORT" =~ ^[0-9]+$ ]] || [ "$POSTGRES_SLAVE_PORT" -lt 1 ] || [ "$POSTGRES_SLAVE_PORT" -gt 65535 ]; then
        add_issue "ERROR" "从数据库端口号无效: $POSTGRES_SLAVE_PORT"
    fi
fi

# Check 4: Docker network
print_check "检查 Docker 网络..."

if docker network ls | grep -q "postgres-network"; then
    print_success "Docker 网络 postgres-network 已存在"
else
    add_issue "WARNING" "Docker 网络 postgres-network 不存在，将会自动创建"
fi

# Check 5: Odyssey source code
print_check "检查 Odyssey 源代码..."

if [ ! -d "$ODYSSEY_DIR" ]; then
    add_issue "WARNING" "Odyssey 源代码目录 $ODYSSEY_DIR 不存在，部署时会自动克隆"
else
    print_success "Odyssey 源代码目录 $ODYSSEY_DIR 存在"
    
    if [ -d "$ODYSSEY_DIR/.git" ]; then
        print_success "Odyssey 是 Git 仓库，可以更新"
    else
        add_issue "WARNING" "Odyssey 目录存在但不是 Git 仓库"
    fi
    
    # Check for Dockerfile
    if [ ! -f "$ODYSSEY_DIR/docker/Dockerfile" ]; then
        add_issue "ERROR" "Odyssey Dockerfile 不存在: $ODYSSEY_DIR/docker/Dockerfile"
    else
        print_success "Odyssey Dockerfile 存在"
    fi
fi

# Check 6: Generated files
print_check "检查生成的文件..."

if [ -f "odyssey.conf" ]; then
    print_success "Odyssey 配置文件 odyssey.conf 已生成"
else
    add_issue "INFO" "Odyssey 配置文件 odyssey.conf 未生成，部署时会自动生成"
fi

# Check directories
if [ ! -d "logs" ]; then
    add_issue "INFO" "日志目录 logs 不存在，部署时会自动创建"
else
    print_success "日志目录 logs 存在"
fi

if [ ! -d "data" ]; then
    add_issue "INFO" "数据目录 data 不存在，部署时会自动创建"
else
    print_success "数据目录 data 存在"
fi

# Check 7: Running containers
print_check "检查运行的容器..."

if docker ps | grep -q "$ODYSSEY_CONTAINER_NAME"; then
    print_success "Odyssey 容器正在运行"
elif docker ps -a | grep -q "$ODYSSEY_CONTAINER_NAME"; then
    add_issue "WARNING" "Odyssey 容器存在但未运行"
else
    add_issue "INFO" "Odyssey 容器不存在，需要首次部署"
fi

# Summary and recommendations
echo
echo "========================================================"
echo "检测结果总结"
echo "========================================================"

echo "发现的问题:"
echo "  错误: $ERRORS"
echo "  警告: $WARNINGS"
echo "  信息: $((${#ISSUES[@]} - ERRORS - WARNINGS))"

echo
if [ ${#ISSUES[@]} -gt 0 ]; then
    echo "详细问题列表:"
    for issue in "${ISSUES[@]}"; do
        echo "  $issue"
    done
fi

echo
echo "========================================================"
echo "修复建议"
echo "========================================================"

if [ $ERRORS -gt 0 ]; then
    print_error "发现 $ERRORS 个错误，必须修复后才能部署"
    echo
    echo "主要修复步骤:"
    
    # Install missing tools
    if ! command -v docker &> /dev/null; then
        print_fix "安装 Docker:"
        echo "  curl -fsSL https://get.docker.com -o get-docker.sh"
        echo "  sudo sh get-docker.sh"
        echo "  sudo usermod -aG docker \$USER"
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        print_fix "安装 Docker Compose:"
        echo "  sudo curl -L \"https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose"
        echo "  sudo chmod +x /usr/local/bin/docker-compose"
    fi
    
    if ! command -v envsubst &> /dev/null; then
        print_fix "安装 envsubst (gettext):"
        echo "  # Ubuntu/Debian:"
        echo "  sudo apt-get update && sudo apt-get install -y gettext-base"
        echo "  # CentOS/RHEL:"
        echo "  sudo yum install -y gettext"
    fi
    
    # Configuration fixes
    if [ -f "$CONFIG_FILE" ] && grep -q "主数据库\|从数据库\|IP地址\|主机名" "$CONFIG_FILE"; then
        print_fix "修复配置文件 $CONFIG_FILE:"
        echo "  编辑 $CONFIG_FILE 文件，替换占位符为实际值:"
        echo "  POSTGRES_MASTER_HOST=实际的主数据库IP地址"
        echo "  POSTGRES_SLAVE_HOST=实际的从数据库IP地址"
        echo "  确保所有密码和用户名都是正确的"
    fi
    
else
    print_success "没有发现阻塞性错误！"
fi

if [ $WARNINGS -gt 0 ]; then
    echo
    print_warning "发现 $WARNINGS 个警告，建议修复以获得最佳体验"
    
    # Network creation
    if ! docker network ls | grep -q "postgres-network"; then
        print_fix "创建 Docker 网络:"
        echo "  docker network create postgres-network"
    fi
    
    # Permission fixes
    if [ -f "$DEPLOY_SCRIPT" ] && [ ! -x "$DEPLOY_SCRIPT" ]; then
        print_fix "修复脚本权限:"
        echo "  chmod +x $DEPLOY_SCRIPT"
    fi
    
    if [ -f "$TEST_SCRIPT" ] && [ ! -x "$TEST_SCRIPT" ]; then
        print_fix "修复测试脚本权限:"
        echo "  chmod +x $TEST_SCRIPT"
    fi
fi

echo
echo "========================================================"
echo "下一步操作"
echo "========================================================"

if [ $ERRORS -eq 0 ]; then
    print_success "系统准备就绪！可以开始部署："
    echo
    echo "1. 如果配置文件需要修改："
    echo "   nano $CONFIG_FILE"
    echo
    echo "2. 运行部署脚本："
    echo "   ./deploy-odyssey.sh"
    echo
    echo "3. 测试连接："
    echo "   ./test-connection.sh"
    echo
    echo "4. 查看运行状态："
    echo "   docker-compose ps"
    echo "   docker-compose logs -f odyssey"
else
    print_error "请先修复上述错误，然后重新运行此检测脚本"
fi

echo
echo "========================================================"
echo "读写分离使用说明"
echo "========================================================"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE" 2>/dev/null || true
    
    echo "配置完成后，您可以通过以下方式使用读写分离："
    echo
    echo "写操作 (路由到主数据库):"
    echo "  psql -h localhost -p ${ODYSSEY_PORT:-6432} -d write_${POSTGRES_MASTER_DB:-MyDB} -U write_${POSTGRES_MASTER_USER:-sean}"
    echo
    echo "读操作 (路由到从数据库):"
    echo "  psql -h localhost -p ${ODYSSEY_PORT:-6432} -d read_${POSTGRES_SLAVE_DB:-MyDB} -U read_${POSTGRES_SLAVE_USER:-sean}"
    echo
    echo "应用程序连接字符串示例:"
    echo "  写: postgresql://write_${POSTGRES_MASTER_USER:-sean}:PASSWORD@localhost:${ODYSSEY_PORT:-6432}/write_${POSTGRES_MASTER_DB:-MyDB}"
    echo "  读: postgresql://read_${POSTGRES_SLAVE_USER:-sean}:PASSWORD@localhost:${ODYSSEY_PORT:-6432}/read_${POSTGRES_SLAVE_DB:-MyDB}"
fi

echo
print_success "检测完成！" 