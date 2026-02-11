# Folder Backup Docker

基于 Docker 的自动目录备份工具，支持本地备份和云端备份（S3、Backblaze B2、Cloudflare R2）。

## 功能特性

- **多目录备份**: 挂载多个目录到 `/sources/` 下，自动逐个备份
- **本地备份**: 备份到本地挂载目录，可选
- **云端备份**: 支持 S3 兼容存储、Backblaze B2、Cloudflare R2
- **灵活模式**: 仅本地 / 仅云端 / 本地+云端
- **备份轮转**: 本地和云端分别可配置保留份数
- **定时执行**: 内置 cron 定时任务，可自定义执行计划
- **ZSTD 压缩**: 高效压缩，支持多线程，可调节压缩等级
- **Slack 通知**: 可选的备份成功/失败通知
- **排除文件**: 支持自定义排除模式

## 快速开始

### 1. 复制配置文件

```bash
cp .example.env .env
```

### 2. 编辑 `.env`

根据需要配置备份参数和云存储凭证。

### 3. 配置 `docker-compose.yml`

挂载需要备份的目录和本地备份目录：

```yaml
services:
  backup:
    build: .
    container_name: folder-backup
    restart: unless-stopped
    env_file:
      - .env
    volumes:
      # 备份源目录（只读挂载）
      - /home/user/projects:/sources/projects:ro
      - /home/user/configs:/sources/configs:ro
      - /var/data/app:/sources/app-data:ro

      # 本地备份目录（可选，不挂载则仅备份到云端）
      - /mnt/backup-drive:/backups
    environment:
      - TZ=Asia/Shanghai
```

### 4. 启动

```bash
docker compose up -d
```

## 配置说明

### 基础配置

| 环境变量 | 默认值 | 说明 |
|---------|--------|------|
| `CRON_SCHEDULE` | `0 2 * * *` | 定时备份计划（cron 格式） |
| `RUN_ON_STARTUP` | `false` | 启动时立即执行一次备份 |
| `TZ` | `UTC` | 时区 |
| `MAX_BACKUPS` | `7` | 本地备份保留份数 |
| `CLOUD_MAX_BACKUPS` | 同 `MAX_BACKUPS` | 云端备份保留份数 |
| `COMPRESSION_LEVEL` | `3` | ZSTD 压缩等级（1-19） |
| `BACKUP_PREFIX` | 空 | 备份文件名前缀 |
| `EXCLUDE_PATTERNS` | 空 | 排除模式，逗号分隔 |
| `DRY_RUN` | `0` | Dry Run 模式 |

### 本地备份

| 环境变量 | 默认值 | 说明 |
|---------|--------|------|
| `BACKUP_LOCAL_DIR` | 空 | 容器内备份目录路径，设为 `/backups` 并挂载 volume |

### S3 兼容存储

| 环境变量 | 说明 |
|---------|------|
| `S3_ENDPOINT` | S3 端点 URL |
| `S3_BUCKET` | 存储桶名称 |
| `S3_ACCESS_KEY` | Access Key |
| `S3_SECRET_KEY` | Secret Key |
| `S3_REGION` | 区域（默认 `us-east-1`） |
| `S3_PATH` | 存储路径前缀（默认 `backups`） |
| `S3_FORCE_PATH_STYLE` | 强制路径风格（MinIO 需要 `true`） |

### Backblaze B2

| 环境变量 | 说明 |
|---------|------|
| `B2_ACCOUNT_ID` | B2 Account ID |
| `B2_APP_KEY` | B2 Application Key |
| `B2_BUCKET` | 存储桶名称 |
| `B2_PATH` | 存储路径前缀（默认 `backups`） |

### Cloudflare R2

| 环境变量 | 说明 |
|---------|------|
| `R2_ENDPOINT` | R2 端点 URL |
| `R2_ACCESS_KEY` | R2 Access Key |
| `R2_SECRET_KEY` | R2 Secret Key |
| `R2_BUCKET` | 存储桶名称 |
| `R2_PATH` | 存储路径前缀（默认 `backups`） |

### Slack 通知

| 环境变量 | 说明 |
|---------|------|
| `SLACK_WEBHOOK_URL` | Slack Webhook URL |

## 备份策略示例

### 仅本地备份

```env
BACKUP_LOCAL_DIR=/backups
MAX_BACKUPS=7
```

```yaml
volumes:
  - /data/myapp:/sources/myapp:ro
  - /mnt/backup:/backups
```

### 仅云端备份（无本地）

```env
# 不设置 BACKUP_LOCAL_DIR
R2_ENDPOINT=https://xxx.r2.cloudflarestorage.com
R2_ACCESS_KEY=xxx
R2_SECRET_KEY=xxx
R2_BUCKET=my-backups
R2_PATH=server1
CLOUD_MAX_BACKUPS=14
```

```yaml
volumes:
  - /data/myapp:/sources/myapp:ro
  # 不需要挂载 /backups
```

### 本地 + 多云备份

```env
BACKUP_LOCAL_DIR=/backups
MAX_BACKUPS=7
CLOUD_MAX_BACKUPS=30

S3_BUCKET=my-s3-backup
S3_ACCESS_KEY=xxx
S3_SECRET_KEY=xxx

R2_ENDPOINT=https://xxx.r2.cloudflarestorage.com
R2_ACCESS_KEY=xxx
R2_SECRET_KEY=xxx
R2_BUCKET=my-r2-backup
```

## 备份文件结构

```
/backups/
├── projects_backup/
│   ├── projects_20250130_020000.tar.zst
│   ├── projects_20250131_020000.tar.zst
│   └── projects_20250201_020000.tar.zst
├── configs_backup/
│   ├── configs_20250130_020000.tar.zst
│   └── configs_20250131_020000.tar.zst
└── app-data_backup/
    └── app-data_20250201_020000.tar.zst
```

## 手动执行备份

```bash
docker exec folder-backup /usr/local/bin/backup.sh
```

## 查看日志

```bash
docker logs folder-backup
```
