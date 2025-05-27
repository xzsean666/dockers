# PostgreSQL + WAL-G 备份方案

这是一个分离式的 PostgreSQL 备份方案，使用原生的`bitnami/postgresql:16`镜像和独立的 WAL-G 备份容器。

## 架构特点

- **分离式设计**: PostgreSQL 和 WAL-G 运行在不同的容器中，职责分离
- **无侵入性**: 不修改 PostgreSQL 镜像，保持官方镜像的纯净性
- **共享卷架构**: 通过共享卷提供 wal-g 二进制文件，避免重复文件复制
- **混合定时策略**: 宿主机负责完整备份，WAL-G 容器负责 WAL 归档和清理
- **灵活配置**: 支持多种 S3 兼容存储后端

## 目录结构

```
postgresql/wal-g/
├── docker-compose.yml      # 主要的服务定义
├── Dockerfile.wal-g        # WAL-G容器构建文件
├── env.example             # 环境变量示例
├── scripts/                # 脚本目录
│   ├── entrypoint.sh      # WAL-G容器入口脚本
│   ├── backup.sh          # 完整备份脚本
│   ├── wal_archive.sh     # WAL归档脚本
│   ├── cleanup.sh         # 清理脚本
│   └── manage.sh          # 手动管理脚本
├── data/                   # PostgreSQL数据目录 (自动创建)
└── README.md              # 本文档
```

## 快速开始

### 1. 配置环境变量

```bash
cp env.example .env
```

编辑`.env`文件，配置以下关键参数：

```bash
# PostgreSQL 基础配置
CONTAINER_NAME=postgres-wal-g
POSTGRESQL_DATABASE=mydb
POSTGRESQL_USERNAME=myuser
POSTGRESQL_PASSWORD=mypassword

# WAL-G S3 配置
WALG_S3_PREFIX=s3://your-bucket/wal-g
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
AWS_REGION=us-east-1
```

### 2. 启动服务

```bash
# 构建并启动所有服务
docker-compose up -d

# 查看服务状态
docker-compose ps

# 查看日志
docker-compose logs -f
```

### 3. 设置定时备份

```bash
# 设置宿主机定时备份（推荐）
chmod +x setup-cron.sh
./setup-cron.sh
```

### 4. 验证备份功能

```bash
# 使用管理脚本
chmod +x scripts/manage.sh
./scripts/manage.sh
```

## 服务说明

### PostgreSQL 容器

- **镜像**: `bitnami/postgresql:16` (官方镜像，未修改)
- **功能**: 数据库服务
- **配置**: 启用 WAL 归档到共享目录

### WAL-G 容器

- **基础镜像**: `ubuntu:22.04`
- **功能**: 备份、WAL 归档、恢复
- **定时任务**:
  - 完整备份: 每天凌晨 2 点 (可配置)
  - WAL 归档: 每 5 分钟检查一次
  - 清理任务: 每周日凌晨 3 点

## 备份策略

### 完整备份

- **频率**: 每天凌晨 2 点 (通过`BACKUP_SCHEDULE`配置)
- **存储**: S3 兼容存储
- **压缩**: LZ4 压缩算法

### WAL 归档

- **实时性**: PostgreSQL 写入 WAL 后立即归档到本地目录
- **传输**: WAL-G 容器每 5 分钟检查并上传到 S3
- **清理**: 自动清理超时的本地 WAL 文件

### 数据保留

- **默认保留**: 7 天 (通过`RETENTION_DAYS`配置)
- **最少保留**: 3 个完整备份 (即使超过保留期)
- **垃圾清理**: 自动清理孤立的 WAL 文件

## 管理操作

### 使用管理脚本

```bash
./scripts/manage.sh
```

管理脚本提供以下功能：

1. 查看所有备份
2. 创建完整备份
3. 恢复到最新备份
4. 恢复到指定时间点
5. 删除过期备份
6. 检查服务状态
7. 查看备份日志
8. 手动清理 WAL 文件
9. 备份统计信息

### 手动操作

```bash
# 手动创建备份
docker exec postgres-wal-g-wal-g /scripts/backup.sh

# 查看备份列表
docker exec postgres-wal-g-wal-g wal-g backup-list

# 手动清理WAL文件
docker exec postgres-wal-g-wal-g /scripts/wal_archive.sh

# 查看日志
docker logs postgres-wal-g-wal-g
```

## 恢复操作

### 恢复到最新备份

```bash
# 停止PostgreSQL
docker-compose stop postgresql

# 执行恢复
docker-compose run --rm wal-g bash -c "
    wal-g backup-fetch /postgresql-data LATEST
"

# 启动PostgreSQL
docker-compose start postgresql
```

### 时间点恢复 (PITR)

```bash
# 停止PostgreSQL
docker-compose stop postgresql

# 执行时间点恢复
docker-compose run --rm wal-g bash -c "
    rm -rf /postgresql-data/*
    wal-g backup-fetch /postgresql-data LATEST
    echo \"restore_command = 'wal-g wal-fetch %f %p'\" > /postgresql-data/recovery.conf
    echo \"recovery_target_time = '2024-01-15 10:30:00'\" >> /postgresql-data/recovery.conf
    echo \"recovery_target_action = 'promote'\" >> /postgresql-data/recovery.conf
"

# 启动PostgreSQL
docker-compose start postgresql
```

## 监控和告警

### 日志位置

- **容器日志**: `docker logs postgres-wal-g-wal-g`
- **备份日志**: `/var/log/cron/backup.log`
- **WAL 归档日志**: `/var/log/cron/wal_archive.log`
- **清理日志**: `/var/log/cron/cleanup.log`

### Webhook 通知

如果配置了`WEBHOOK_URL`，系统会在以下情况发送通知：

- 备份成功/失败
- 清理完成/失败
- 健康检查警告

### 健康检查

WAL-G 容器会定期检查：

- PostgreSQL 连接状态
- 最新备份时间
- WAL 归档队列长度
- S3 连接状态

## 故障排查

### 常见问题

1. **WAL-G 容器启动失败**

   ```bash
   # 检查环境变量配置
   docker-compose config

   # 查看详细错误
   docker-compose logs wal-g
   ```

2. **S3 连接失败**

   ```bash
   # 在容器内测试S3连接
   docker exec postgres-wal-g-wal-g wal-g st ls
   ```

3. **WAL 文件堆积**

   ```bash
   # 检查WAL归档状态
   docker exec postgres-wal-g-wal-g find /shared/wal-archive -type f | wc -l

   # 手动处理WAL文件
   docker exec postgres-wal-g-wal-g /scripts/wal_archive.sh
   ```

4. **备份恢复失败**

   ```bash
   # 检查备份列表
   docker exec postgres-wal-g-wal-g wal-g backup-list

   # 验证备份完整性
   docker exec postgres-wal-g-wal-g wal-g backup-show LATEST
   ```

### 调试模式

```bash
# 以调试模式启动WAL-G容器
docker-compose run --rm wal-g bash

# 在容器内手动执行脚本
/scripts/backup.sh
/scripts/wal_archive.sh
```

## 性能优化

### WAL-G 参数调优

```bash
# 在.env文件中调整
WALG_UPLOAD_CONCURRENCY=8      # 上传并发数
WALG_DOWNLOAD_CONCURRENCY=8    # 下载并发数
WALG_DISK_RATE_LIMIT=20971520  # 磁盘速率限制 (20MB/s)
WALG_NETWORK_RATE_LIMIT=20971520 # 网络速率限制 (20MB/s)
```

### PostgreSQL 参数调优

通过环境变量调整 PostgreSQL 配置：

```bash
# 在docker-compose.yml中添加
- POSTGRESQL_CHECKPOINT_SEGMENTS=64
- POSTGRESQL_CHECKPOINT_COMPLETION_TARGET=0.9
- POSTGRESQL_WAL_BUFFERS=16MB
```

## 安全注意事项

1. **密钥管理**: 使用环境变量或密钥管理系统存储敏感信息
2. **网络隔离**: 在生产环境中使用自定义网络
3. **访问控制**: 限制 S3 bucket 的访问权限
4. **加密传输**: 确保 S3 连接使用 HTTPS
5. **备份加密**: 考虑在 WAL-G 中启用加密功能

## 升级和维护

### 升级 WAL-G 版本

1. 修改`Dockerfile.wal-g`中的版本号
2. 重新构建容器: `docker-compose build wal-g`
3. 重启服务: `docker-compose up -d`

### 升级 PostgreSQL 版本

1. 备份当前数据
2. 修改`docker-compose.yml`中的镜像版本
3. 执行升级步骤
4. 验证数据完整性

## 许可证

本项目使用 MIT 许可证。
