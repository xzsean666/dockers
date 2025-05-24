# PostgreSQL WAL-G with S3/B2 Backup

这个配置支持使用 WAL-G 进行 PostgreSQL 备份，兼容 AWS S3 和 Backblaze B2 存储。

## 快速开始

### 1. 选择存储后端

#### 🔹 使用 AWS S3

```bash
cp env.s3.example .env
# 编辑 .env 文件，填入你的AWS凭据
```

#### 🔹 使用 Backblaze B2

```bash
cp env.b2.example .env
# 编辑 .env 文件，填入你的B2凭据
```

#### 🔹 自定义配置

```bash
cp env.example .env
# 根据需要修改配置
```

### 2. 编辑配置文件

根据你选择的存储后端，编辑 `.env` 文件：

**AWS S3 配置：**

- `AWS_ACCESS_KEY_ID`: AWS 访问密钥 ID
- `AWS_SECRET_ACCESS_KEY`: AWS 私有访问密钥
- `AWS_REGION`: S3 桶所在区域（如：us-east-1）
- `WALG_S3_PREFIX`: s3://your-bucket-name/path/to/backups

**Backblaze B2 配置：**

- `AWS_ACCESS_KEY_ID`: B2 Application Key ID
- `AWS_SECRET_ACCESS_KEY`: B2 Application Key
- `AWS_REGION`: us-west-004（或其他 B2 区域）
- `AWS_ENDPOINT_URL`: https://s3.us-west-004.backblazeb2.com
- `AWS_S3_FORCE_PATH_STYLE`: true
- `WALG_S3_PREFIX`: s3://your-b2-bucket-name/path/to/backups

### 3. 启动服务

```bash
docker-compose up -d
```

## 备份操作

### 创建备份

```bash
docker exec postgresql-master wal-g backup-push /bitnami/postgresql/data
```

### 列出备份

```bash
docker exec postgresql-master wal-g backup-list
```

### 从备份恢复

1. 停止服务：`docker-compose down`
2. 设置环境变量：
   ```bash
   export RESTORE_FROM_BACKUP=true
   export BACKUP_NAME=backup_20240101_120000  # 或使用 LATEST
   ```
3. 启动服务：`docker-compose up -d`

## 性能建议

- **AWS S3**: 推荐并发数 4-8
- **Backblaze B2**: 推荐并发数 2-4

## 故障排除

### 检查 WAL-G 状态

```bash
docker exec postgresql-master wal-g --version
docker logs postgresql-master
```

### 测试连接

```bash
# 测试S3/B2连接
docker exec postgresql-master wal-g backup-list
```

### 常见问题

1. **权限错误**: 确保 S3/B2 凭据有正确的读写权限
2. **网络问题**: 检查防火墙和网络连接
3. **路径错误**: 确认 WALG_S3_PREFIX 格式正确

## 文件说明

- `env.example`: 通用配置模板（支持 S3 和 B2）
- `env.s3.example`: AWS S3 专用配置模板
- `env.b2.example`: Backblaze B2 专用配置模板
- `docker-compose.yml`: Docker 编排文件
- `wal-g.conf`: WAL-G 配置文件
- `backup_restore.sh`: 备份恢复脚本
