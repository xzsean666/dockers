# Odyssey PostgreSQL 连接池和读写分离

这个目录包含了使用 [Yandex Odyssey](https://github.com/yandex/odyssey) 实现 PostgreSQL 读写分离的完整配置。

## 功能特性

- ✅ **读写分离**: 自动将写操作路由到主库，读操作路由到从库
- ✅ **连接池**: 高效的连接池管理
- ✅ **负载均衡**: 支持多个从库的负载均衡
- ✅ **事务管理**: 高级事务池管理
- ✅ **SSL/TLS 支持**: 安全连接支持
- ✅ **监控和日志**: 详细的连接和查询日志

## 文件结构

```
postgresql/odyssey/
├── example.odyssey.env      # 环境配置文件
├── odyssey.conf.template    # Odyssey 配置模板
├── docker-compose.yml       # Docker Compose 配置
├── deploy-odyssey.sh        # 自动部署脚本
├── test-connection.sh       # 连接测试脚本
└── README.md               # 说明文档
```

## 快速开始

### 1. 配置环境变量

编辑 `example.odyssey.env` 文件，配置你的 PostgreSQL 主从服务器信息：

```bash
# PostgreSQL Master (写操作)
POSTGRES_MASTER_HOST=你的主数据库IP
POSTGRES_MASTER_PORT=5432
POSTGRES_MASTER_DB=MyDB
POSTGRES_MASTER_USER=sean
POSTGRES_MASTER_PASSWORD=111111

# PostgreSQL Slave (读操作)
POSTGRES_SLAVE_HOST=你的从数据库IP
POSTGRES_SLAVE_PORT=5432
POSTGRES_SLAVE_DB=MyDB
POSTGRES_SLAVE_USER=sean
POSTGRES_SLAVE_PASSWORD=111111
```

### 2. 运行部署脚本

```bash
cd postgresql/odyssey
chmod +x deploy-odyssey.sh
./deploy-odyssey.sh
```

这个脚本会自动完成以下操作：

- 克隆 Odyssey 源代码
- 生成配置文件
- 构建 Docker 镜像
- 启动 Odyssey 服务

### 3. 测试连接

```bash
chmod +x test-connection.sh
./test-connection.sh
```

## 使用方法

### 应用程序连接

Odyssey 提供了不同的数据库名来实现读写分离：

**写操作连接** (路由到主库):

```bash
psql -h localhost -p 6432 -d write_MyDB -U write_sean
```

**读操作连接** (路由到从库):

```bash
psql -h localhost -p 6432 -d read_MyDB -U read_sean
```

**默认连接** (主库):

```bash
psql -h localhost -p 6432 -d MyDB -U sean
```

### 应用程序配置示例

#### Python (psycopg2)

```python
import psycopg2
from psycopg2.pool import SimpleConnectionPool

# 写操作连接池
write_pool = SimpleConnectionPool(
    1, 20,
    host='localhost',
    port=6432,
    database='write_MyDB',
    user='write_sean',
    password='111111'
)

# 读操作连接池
read_pool = SimpleConnectionPool(
    1, 20,
    host='localhost',
    port=6432,
    database='read_MyDB',
    user='read_sean',
    password='111111'
)
```

#### Node.js (pg)

```javascript
const { Pool } = require('pg');

// 写操作连接池
const writePool = new Pool({
  host: 'localhost',
  port: 6432,
  database: 'write_MyDB',
  user: 'write_sean',
  password: '111111',
  max: 20,
});

// 读操作连接池
const readPool = new Pool({
  host: 'localhost',
  port: 6432,
  database: 'read_MyDB',
  user: 'read_sean',
  password: '111111',
  max: 20,
});
```

#### Go (pq)

```go
import (
    "database/sql"
    _ "github.com/lib/pq"
)

writeDB, err := sql.Open("postgres",
    "host=localhost port=6432 dbname=write_MyDB user=write_sean password=111111 sslmode=disable")

readDB, err := sql.Open("postgres",
    "host=localhost port=6432 dbname=read_MyDB user=read_sean password=111111 sslmode=disable")
```

## 管理命令

### 查看服务状态

```bash
docker-compose ps
```

### 查看日志

```bash
docker-compose logs -f odyssey
```

### 重启服务

```bash
docker-compose restart odyssey
```

### 停止服务

```bash
docker-compose down
```

### 重新构建

```bash
docker-compose build --no-cache
docker-compose up -d
```

## 配置说明

### 连接池配置

- `POOL_SIZE`: 每个数据库的连接池大小 (默认: 25)
- `POOL_TIMEOUT`: 连接超时时间，毫秒 (默认: 4000)
- `POOL_TTL`: 连接生存时间，秒 (默认: 60)
- `POOL_CANCEL`: 是否支持查询取消 (默认: yes)
- `POOL_ROLLBACK`: 是否自动回滚 (默认: yes)

### 性能配置

- `WORKERS`: 工作线程数 (默认: 4)
- `CLIENT_MAX`: 最大客户端连接数 (默认: 100)
- `READAHEAD`: 读缓冲区大小 (默认: 8192)
- `CACHE_COROUTINE`: 协程缓存数量 (默认: 128)

### 日志配置

- `LOG_TO_STDOUT`: 输出到标准输出 (默认: yes)
- `LOG_DEBUG`: 调试日志 (默认: no)
- `LOG_SESSION`: 会话日志 (默认: yes)
- `LOG_QUERY`: 查询日志 (默认: no)

## 监控

### 连接状态监控

Odyssey 提供了详细的连接统计信息：

```bash
# 查看连接统计
docker-compose exec odyssey odyssey -c /etc/odyssey.conf --show-stats
```

### 健康检查

服务自带健康检查，可以通过以下方式查看：

```bash
# 检查服务健康状态
docker-compose ps odyssey
```

## 故障排除

### 常见问题

1. **连接失败**

   - 检查主从数据库是否可访问
   - 确认防火墙设置
   - 验证用户名和密码

2. **读写分离不工作**

   - 确认使用了正确的数据库名前缀 (`write_` 或 `read_`)
   - 检查 Odyssey 配置文件
   - 查看 Odyssey 日志

3. **性能问题**
   - 调整连接池大小
   - 增加工作线程数
   - 优化网络延迟

### 调试模式

启用详细日志：

```bash
# 编辑配置文件，设置 LOG_DEBUG=yes
# 然后重启服务
docker-compose restart odyssey
```

## 升级和维护

### 升级 Odyssey

```bash
# 拉取最新代码
cd odyssey-src
git pull origin master
cd ..

# 重新构建
docker-compose build --no-cache
docker-compose up -d
```

### 备份配置

建议定期备份配置文件：

```bash
tar -czf odyssey-config-$(date +%Y%m%d).tar.gz *.env *.conf *.yml
```

## 安全建议

1. 使用强密码
2. 启用 SSL/TLS 连接
3. 限制网络访问
4. 定期更新 Odyssey 版本
5. 监控连接日志

## 支持

- [Odyssey GitHub](https://github.com/yandex/odyssey)
- [Odyssey 文档](https://github.com/yandex/odyssey/tree/master/documentation)
- [PostgreSQL 文档](https://www.postgresql.org/docs/)

## 许可证

本配置基于 Odyssey 的 BSD-3-Clause 许可证。
