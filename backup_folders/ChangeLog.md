# ChangeLog

## 2026-02-11

### backup_folders - 新增目录备份 Docker 工具

- 新增 `backup.sh`: 主备份脚本，支持环境变量配置，多目录自动发现备份
- 新增 `entrypoint.sh`: Docker 入口脚本，支持 cron 定时任务
- 新增 `Dockerfile`: 基于 Alpine 3.21，包含 bash、tar、zstd、rclone、curl
- 新增 `docker-compose.yml`: Docker Compose 配置模板
- 新增 `.example.env`: 环境变量配置示例
- 新增 `README.md`: 项目文档
- 支持功能:
  - 本地备份 + 云端备份（S3、B2、R2）
  - 仅云端备份（不挂载本地备份目录时）
  - 本地与云端分别设置备份保留份数
  - ZSTD 多线程压缩
  - Slack 通知
  - Cron 定时执行 + 启动时立即执行选项
