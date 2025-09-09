# Pgpool-II 读写分离配置

这个配置使用 Bitnami 的 Pgpool-II 镜像实现 PostgreSQL 的严格读写分离。

## 📋 功能特性

- ✅ **严格读写分离**: 写操作只路由到主库，读操作只路由到从库
- ✅ **健康检查**: 自动监控数据库状态
- ✅ **连接池**: 优化数据库连接管理
- ✅ **环境变量配置**: 便于管理和部署
- ✅ **详细日志**: 记录连接和查询信息

## 🚀 快速开始

### 1. 复制环境变量配置文件

```bash
cp .example.env .env
```

### 2. 修改配置

编辑 `.env` 文件，配置您的数据库信息：

```bash
# 必须修改的配置
POSTGRES_PRIMARY_HOST=your-primary-host
POSTGRES_REPLICA_HOST=your-replica-host
POSTGRES_PASSWORD=your_postgres_password
```

### 3. 启动服务

```bash
docker-compose up -d
```

### 4. 验证服务

```bash
# 查看服务状态
docker-compose ps

# 查看日志
docker-compose logs -f pgpool

# 测试连接
psql -h localhost -p 5432 -U postgres
```

## ⚙️ 主要配置说明

### 数据库配置

- `POSTGRES_PRIMARY_HOST`: 主数据库地址
- `POSTGRES_REPLICA_HOST`: 从数据库地址
- `POSTGRES_PASSWORD`: 数据库密码

### Pgpool 配置

- `PGPOOL_PORT`: Pgpool 服务端口 (默认: 5432)
- `PGPOOL_ADMIN_USERNAME`: Pgpool 管理员用户名
- `PGPOOL_ADMIN_PASSWORD`: Pgpool 管理员密码

### 性能配置

- `PGPOOL_MAX_POOL`: 最大连接池数
- `PGPOOL_NUM_INIT_CHILDREN`: 初始子进程数
- `PGPOOL_CHILD_MAX_CONNECTIONS`: 子进程最大连接数

## 🔍 读写分离规则

### 写操作 → 主库

- `INSERT`, `UPDATE`, `DELETE`
- `CREATE`, `DROP`, `ALTER`
- `TRUNCATE`, `COPY...FROM`
- 事务性查询: `SELECT...FOR UPDATE`, `SELECT...FOR SHARE`
- 序列函数: `NEXTVAL`, `SETVAL`, `CURRVAL`

### 读操作 → 从库

- 普通的 `SELECT` 查询
- 只读函数调用

## 🧪 测试读写分离

连接到 Pgpool 后，可以通过以下命令验证：

```sql
-- 查看节点状态
SHOW pool_nodes;

-- 查看连接信息
SHOW pool_processes;

-- 测试写操作 (路由到主库)
INSERT INTO test_table (name) VALUES ('test');

-- 测试读操作 (路由到从库)
SELECT * FROM test_table;
```

## 📝 注意事项

1. **数据库权限**: 确保 Pgpool 用户在主从数据库都有相应权限
2. **网络连通性**: 确保 Pgpool 容器能访问主从数据库
3. **流复制**: 确保主从数据库的流复制配置正确
4. **防火墙**: 确保相关端口已开放

## 🔧 故障排除

### 查看详细日志

```bash
docker-compose logs -f pgpool
```

### 检查数据库连接

```bash
# 进入 pgpool 容器
docker exec -it pgpool bash

# 测试数据库连接
pg_isready -h your-primary-host -p 5432 -U postgres
pg_isready -h your-replica-host -p 5432 -U postgres
```

### 常见问题

1. **连接被拒绝**: 检查数据库地址和端口配置
2. **认证失败**: 检查用户名和密码配置
3. **读写分离不生效**: 检查 `pool_nodes` 状态和日志

## 📚 相关文档

- [Pgpool-II 官方文档](http://www.pgpool.net/docs/latest/en/html/)
- [Bitnami Pgpool 镜像文档](https://hub.docker.com/r/bitnami/pgpool)
