#!/bin/bash

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
    exit 1
fi

# Load environment variables
source $CONFIG_FILE

print_info "开始测试 Odyssey 连接和读写分离..."

# Function to test database connection
test_connection() {
    local host=$1
    local port=$2
    local database=$3
    local username=$4
    local password=$5
    local description=$6
    
    print_info "测试 $description 连接..."
    
    PGPASSWORD=$password psql -h $host -p $port -d $database -U $username -c "SELECT 'Connection successful to $description' as result, current_timestamp;" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        print_success "$description 连接成功"
        return 0
    else
        print_error "$description 连接失败"
        return 1
    fi
}

# Function to test write operation
test_write() {
    local host=$1
    local port=$2
    local database=$3
    local username=$4
    local password=$5
    
    print_info "测试写操作..."
    
    PGPASSWORD=$password psql -h $host -p $port -d $database -U $username -c "
        CREATE TABLE IF NOT EXISTS odyssey_test (
            id SERIAL PRIMARY KEY,
            test_data TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        INSERT INTO odyssey_test (test_data) VALUES ('Write test at ' || CURRENT_TIMESTAMP);
        SELECT 'Write operation successful' as result;
    " 2>/dev/null
    
    if [ $? -eq 0 ]; then
        print_success "写操作测试成功"
        return 0
    else
        print_error "写操作测试失败"
        return 1
    fi
}

# Function to test read operation
test_read() {
    local host=$1
    local port=$2
    local database=$3
    local username=$4
    local password=$5
    
    print_info "测试读操作..."
    
    PGPASSWORD=$password psql -h $host -p $port -d $database -U $username -c "
        SELECT 'Read operation successful' as result, COUNT(*) as total_records 
        FROM odyssey_test;
    " 2>/dev/null
    
    if [ $? -eq 0 ]; then
        print_success "读操作测试成功"
        return 0
    else
        print_error "读操作测试失败"
        return 1
    fi
}

echo "========================================="
echo "Odyssey PostgreSQL 连接池测试"
echo "========================================="

# Test write connection (to master)
echo
print_info "1. 测试写操作连接 (Master)"
test_write "localhost" "$ODYSSEY_PORT" "write_$POSTGRES_MASTER_DB" "write_$POSTGRES_MASTER_USER" "$POSTGRES_MASTER_PASSWORD"

# Test read connection (to slave)
echo
print_info "2. 测试读操作连接 (Slave)"
# Wait a bit for replication
sleep 2
test_read "localhost" "$ODYSSEY_PORT" "read_$POSTGRES_SLAVE_DB" "read_$POSTGRES_SLAVE_USER" "$POSTGRES_SLAVE_PASSWORD"

# Test default connection
echo
print_info "3. 测试默认连接"
test_connection "localhost" "$ODYSSEY_PORT" "$POSTGRES_MASTER_DB" "$POSTGRES_MASTER_USER" "$POSTGRES_MASTER_PASSWORD" "Default"

echo
echo "========================================="
print_info "连接字符串示例:"
echo "  写操作: psql -h localhost -p $ODYSSEY_PORT -d write_$POSTGRES_MASTER_DB -U write_$POSTGRES_MASTER_USER"
echo "  读操作: psql -h localhost -p $ODYSSEY_PORT -d read_$POSTGRES_SLAVE_DB -U read_$POSTGRES_SLAVE_USER"
echo "  默认:   psql -h localhost -p $ODYSSEY_PORT -d $POSTGRES_MASTER_DB -U $POSTGRES_MASTER_USER"

echo
print_info "应用程序配置示例:"
echo "  写操作 URI: postgresql://write_$POSTGRES_MASTER_USER:$POSTGRES_MASTER_PASSWORD@localhost:$ODYSSEY_PORT/write_$POSTGRES_MASTER_DB"
echo "  读操作 URI: postgresql://read_$POSTGRES_SLAVE_USER:$POSTGRES_SLAVE_PASSWORD@localhost:$ODYSSEY_PORT/read_$POSTGRES_SLAVE_DB"

echo "=========================================" 