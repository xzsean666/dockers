#!/bin/bash

# 测试 Pgpool 读写分离功能
# 使用方法: ./test_read_write_split.sh <pgpool_host> <pgpool_port> <username> <password> <database>

PGPOOL_HOST=${1:-localhost}
PGPOOL_PORT=${2:-5432}
DB_USER=${3:-postgres}
DB_PASS=${4:-postgres}
DB_NAME=${5:-postgres}

echo "=== 测试 Pgpool 读写分离 ==="
echo "连接信息: $PGPOOL_HOST:$PGPOOL_PORT"
echo ""

# 设置 PGPASSWORD 环境变量
export PGPASSWORD=$DB_PASS

echo "1. 创建测试表（应该路由到主库）"
psql -h $PGPOOL_HOST -p $PGPOOL_PORT -U $DB_USER -d $DB_NAME -c "CREATE TABLE IF NOT EXISTS test_split (id SERIAL PRIMARY KEY, data TEXT, created_at TIMESTAMP DEFAULT NOW());"

echo ""
echo "2. 插入数据（应该路由到主库）"
psql -h $PGPOOL_HOST -p $PGPOOL_PORT -U $DB_USER -d $DB_NAME -c "INSERT INTO test_split (data) VALUES ('test data 1'), ('test data 2'), ('test data 3');"

echo ""
echo "3. 执行 SELECT 查询（应该路由到从库）"
echo "   简单 SELECT:"
psql -h $PGPOOL_HOST -p $PGPOOL_PORT -U $DB_USER -d $DB_NAME -c "SELECT * FROM test_split;"

echo ""
echo "   带聚合函数的 SELECT:"
psql -h $PGPOOL_HOST -p $PGPOOL_PORT -U $DB_USER -d $DB_NAME -c "SELECT COUNT(*) FROM test_split;"

echo ""
echo "   带 WHERE 条件的 SELECT:"
psql -h $PGPOOL_HOST -p $PGPOOL_PORT -U $DB_USER -d $DB_NAME -c "SELECT * FROM test_split WHERE id > 1;"

echo ""
echo "4. 更新数据（应该路由到主库）"
psql -h $PGPOOL_HOST -p $PGPOOL_PORT -U $DB_USER -d $DB_NAME -c "UPDATE test_split SET data = 'updated data' WHERE id = 1;"

echo ""
echo "5. 再次 SELECT（应该路由到从库）"
psql -h $PGPOOL_HOST -p $PGPOOL_PORT -U $DB_USER -d $DB_NAME -c "SELECT * FROM test_split ORDER BY id;"

echo ""
echo "6. 删除测试数据（应该路由到主库）"
psql -h $PGPOOL_HOST -p $PGPOOL_PORT -U $DB_USER -d $DB_NAME -c "DELETE FROM test_split WHERE id > 2;"

echo ""
echo "7. 最终 SELECT（应该路由到从库）"
psql -h $PGPOOL_HOST -p $PGPOOL_PORT -U $DB_USER -d $DB_NAME -c "SELECT * FROM test_split;"

echo ""
echo "8. 清理测试表"
psql -h $PGPOOL_HOST -p $PGPOOL_PORT -U $DB_USER -d $DB_NAME -c "DROP TABLE IF EXISTS test_split;"

echo ""
echo "=== 测试完成 ==="
echo "请检查 Pgpool 日志以确认查询路由："
echo "- 主库查询应显示: DB node id: 0"
echo "- 从库查询应显示: DB node id: 1" 