#!/bin/bash

# Database connectivity test script
# 用于测试主从数据库的直接连接，确保配置正确

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

# Configuration file
CONFIG_FILE="example.odyssey.env"

# Check if configuration file exists
if [ ! -f "$CONFIG_FILE" ]; then
    print_error "配置文件 $CONFIG_FILE 不存在！"
    print_info "请先创建配置文件，可以参考 config-example.env"
    exit 1
fi

# Check if psql is available
if ! command -v psql &> /dev/null; then
    print_error "PostgreSQL 客户端 (psql) 未安装！"
    print_info "Ubuntu/Debian: sudo apt-get install -y postgresql-client"
    print_info "CentOS/RHEL: sudo yum install -y postgresql"
    exit 1
fi

# Load environment variables
source $CONFIG_FILE

echo "========================================================"
echo "PostgreSQL 主从数据库连接测试"
echo "========================================================"

# Function to test database connection
test_database_connection() {
    local host=$1
    local port=$2
    local database=$3
    local username=$4
    local password=$5
    local description=$6
    local role=$7
    
    print_info "测试 $description 连接..."
    echo "  主机: $host:$port"
    echo "  数据库: $database"
    echo "  用户: $username"
    
    # Test basic connection
    if PGPASSWORD=$password psql -h $host -p $port -d $database -U $username -c "SELECT 'Connection successful' as result, current_timestamp, version();" 2>/dev/null; then
        print_success "$description 连接成功"
        
        # Test if it's a master (can write)
        if [ "$role" = "master" ]; then
            print_info "测试主数据库写权限..."
            if PGPASSWORD=$password psql -h $host -p $port -d $database -U $username -c "
                CREATE TABLE IF NOT EXISTS odyssey_connectivity_test (
                    id SERIAL PRIMARY KEY,
                    test_type TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
                INSERT INTO odyssey_connectivity_test (test_type) VALUES ('master_write_test');
                SELECT 'Master write test successful' as result;
            " 2>/dev/null; then
                print_success "$description 写权限测试成功"
            else
                print_error "$description 写权限测试失败"
                return 1
            fi
        fi
        
        # Test if it's a slave (should be able to read)
        if [ "$role" = "slave" ]; then
            print_info "测试从数据库读权限..."
            if PGPASSWORD=$password psql -h $host -p $port -d $database -U $username -c "
                SELECT 'Slave read test successful' as result, 
                       COUNT(*) as total_test_records 
                FROM information_schema.tables 
                WHERE table_schema = 'public';
            " 2>/dev/null; then
                print_success "$description 读权限测试成功"
                
                # Check if test table exists (might indicate replication is working)
                if PGPASSWORD=$password psql -h $host -p $port -d $database -U $username -c "
                    SELECT COUNT(*) as replicated_records 
                    FROM odyssey_connectivity_test 
                    WHERE test_type = 'master_write_test';
                " 2>/dev/null | grep -q "1"; then
                    print_success "检测到主库写入的数据已复制到从库"
                else
                    print_warning "未检测到主库的测试数据，可能复制延迟或复制未配置"
                fi
            else
                print_error "$description 读权限测试失败"
                return 1
            fi
        fi
        
        return 0
    else
        print_error "$description 连接失败"
        print_info "请检查："
        echo "  1. 数据库服务器是否运行"
        echo "  2. 网络连接是否正常"
        echo "  3. 防火墙设置"
        echo "  4. 用户名和密码是否正确"
        echo "  5. 数据库是否存在"
        return 1
    fi
}

# Function to test network connectivity
test_network_connectivity() {
    local host=$1
    local port=$2
    local description=$3
    
    print_info "测试 $description 网络连接 ($host:$port)..."
    
    if command -v nc &> /dev/null; then
        if nc -z -w5 "$host" "$port" 2>/dev/null; then
            print_success "$description 网络连接正常"
            return 0
        else
            print_error "$description 网络连接失败"
            return 1
        fi
    elif command -v telnet &> /dev/null; then
        if timeout 5 telnet "$host" "$port" &>/dev/null; then
            print_success "$description 网络连接正常"
            return 0
        else
            print_error "$description 网络连接失败"
            return 1
        fi
    else
        print_warning "nc 和 telnet 都未安装，跳过网络连接测试"
        return 0
    fi
}

# Track test results
MASTER_CONNECTION_OK=false
SLAVE_CONNECTION_OK=false
NETWORK_ISSUES=false

echo
print_info "步骤 1: 网络连接测试"
echo "----------------------------------------"

# Test master network connectivity
if test_network_connectivity "$POSTGRES_MASTER_HOST" "$POSTGRES_MASTER_PORT" "主数据库"; then
    MASTER_NETWORK_OK=true
else
    MASTER_NETWORK_OK=false
    NETWORK_ISSUES=true
fi

# Test slave network connectivity
if test_network_connectivity "$POSTGRES_SLAVE_HOST" "$POSTGRES_SLAVE_PORT" "从数据库"; then
    SLAVE_NETWORK_OK=true
else
    SLAVE_NETWORK_OK=false
    NETWORK_ISSUES=true
fi

echo
print_info "步骤 2: 数据库连接测试"
echo "----------------------------------------"

# Test master database connection
if [ "$MASTER_NETWORK_OK" = true ]; then
    if test_database_connection "$POSTGRES_MASTER_HOST" "$POSTGRES_MASTER_PORT" "$POSTGRES_MASTER_DB" "$POSTGRES_MASTER_USER" "$POSTGRES_MASTER_PASSWORD" "主数据库 (Master)" "master"; then
        MASTER_CONNECTION_OK=true
    fi
else
    print_warning "跳过主数据库连接测试 (网络不通)"
fi

echo

# Test slave database connection
if [ "$SLAVE_NETWORK_OK" = true ]; then
    if test_database_connection "$POSTGRES_SLAVE_HOST" "$POSTGRES_SLAVE_PORT" "$POSTGRES_SLAVE_DB" "$POSTGRES_SLAVE_USER" "$POSTGRES_SLAVE_PASSWORD" "从数据库 (Slave)" "slave"; then
        SLAVE_CONNECTION_OK=true
    fi
else
    print_warning "跳过从数据库连接测试 (网络不通)"
fi

echo
print_info "步骤 3: 主从配置验证"
echo "----------------------------------------"

# Check if master and slave are different
if [ "$POSTGRES_MASTER_HOST" = "$POSTGRES_SLAVE_HOST" ] && [ "$POSTGRES_MASTER_PORT" = "$POSTGRES_SLAVE_PORT" ]; then
    print_warning "主从数据库使用相同的主机和端口"
    print_info "这通常表示："
    echo "  1. 使用的是单机测试环境"
    echo "  2. 或者还未配置真正的主从复制"
    echo "  3. 读写分离仍然有效，但没有高可用性"
else
    print_success "主从数据库使用不同的主机/端口，配置正确"
fi

# Summary
echo
echo "========================================================"
echo "测试结果总结"
echo "========================================================"

if [ "$MASTER_CONNECTION_OK" = true ] && [ "$SLAVE_CONNECTION_OK" = true ]; then
    print_success "✅ 所有数据库连接测试通过！"
    echo
    print_info "下一步操作："
    echo "  1. 运行配置检测: chmod +x check-and-fix.sh && ./check-and-fix.sh"
    echo "  2. 部署 Odyssey: ./deploy-odyssey.sh"
    echo "  3. 测试读写分离: ./test-connection.sh"
    
elif [ "$MASTER_CONNECTION_OK" = true ] && [ "$SLAVE_CONNECTION_OK" = false ]; then
    print_warning "⚠️  主数据库连接正常，从数据库连接失败"
    echo
    print_info "可能的解决方案："
    echo "  1. 检查从数据库服务器状态"
    echo "  2. 验证从数据库配置"
    echo "  3. 临时可以将从库配置设为与主库相同进行测试"
    
elif [ "$MASTER_CONNECTION_OK" = false ] && [ "$SLAVE_CONNECTION_OK" = true ]; then
    print_error "❌ 主数据库连接失败，从数据库连接正常"
    echo
    print_info "这是不正常的配置，请检查主数据库"
    
else
    print_error "❌ 主从数据库连接都失败"
    echo
    print_info "请检查："
    echo "  1. 数据库服务器是否运行"
    echo "  2. 网络连接和防火墙设置"
    echo "  3. 配置文件中的连接信息"
fi

if [ "$NETWORK_ISSUES" = true ]; then
    echo
    print_warning "网络连接问题排查："
    echo "  1. ping $POSTGRES_MASTER_HOST"
    echo "  2. ping $POSTGRES_SLAVE_HOST"
    echo "  3. telnet $POSTGRES_MASTER_HOST $POSTGRES_MASTER_PORT"
    echo "  4. telnet $POSTGRES_SLAVE_HOST $POSTGRES_SLAVE_PORT"
    echo "  5. 检查防火墙: sudo ufw status (Ubuntu) 或 sudo firewall-cmd --list-all (CentOS)"
fi

echo
print_info "配置文件位置: $CONFIG_FILE"
print_info "如需修改配置: nano $CONFIG_FILE" 