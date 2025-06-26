-- 测试 Pgpool 读写分离
-- 创建测试表（写操作，应该路由到主库）
CREATE TABLE IF NOT EXISTS user_data (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW()
);

-- 插入测试数据（写操作，应该路由到主库）
INSERT INTO user_data (name, email) VALUES 
    ('Alice', 'alice@example.com'),
    ('Bob', 'bob@example.com'),
    ('Charlie', 'charlie@example.com');

-- 简单 SELECT（读操作，应该路由到从库）
SELECT * FROM user_data;

-- 带 WHERE 条件的 SELECT（读操作，应该路由到从库）
SELECT * FROM user_data WHERE id > 1;

-- 聚合查询（读操作，应该路由到从库）
SELECT COUNT(*) as total_users FROM user_data;

-- 更新操作（写操作，应该路由到主库）
UPDATE user_data SET email = 'alice.updated@example.com' WHERE name = 'Alice';

-- 再次查询验证（读操作，应该路由到从库）
SELECT * FROM user_data ORDER BY id;

-- 清理测试数据
-- DROP TABLE user_data; 