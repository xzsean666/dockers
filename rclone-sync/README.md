# rclone-sync

`rclone-sync` 是一个 Docker 化的 rclone 任务运行器。它用环境变量或 YAML 配置，把一个存储位置的数据复制、镜像、归档或清理到另一个位置。

常见用途：

- B2 bucket 归档到 Google Drive。
- B2、S3、R2、Google Drive 同步到本地目录。
- 本地目录备份到任意 rclone 支持的存储。
- 只处理指定时间之前的数据，例如 3 天前、约 3 个月前、某个日期之前。
- 排除 `.tmp`、`.part`、`.bak` 等后缀文件。
- 多个目录按相同相对路径同步到目标端指定 prefix。
- 部署后常驻运行，按 cron 周期执行。
- 可选 Slack webhook 通知容器启动、任务开始、任务完成和失败。

底层传输全部交给 rclone。镜像内置 Python runner，只用于配置解析、安全校验、调度和通知。

## 1. Docker Hub 快速开始

把示例 env 复制成真实 env：

```bash
cp rclone-sync.env.example rclone-sync.env
vim rclone-sync.env
```

先用 dry-run 启动：

```bash
docker run --rm \
  --name rclone-sync \
  --env-file ./rclone-sync.env \
  -v "$PWD/logs:/logs" \
  -v "$PWD/state:/state" \
  your-dockerhub-user/rclone-sync:latest
```

确认日志没问题后，再常驻运行：

```bash
docker run -d \
  --name rclone-sync \
  --restart unless-stopped \
  --env-file ./rclone-sync.env \
  -v "$PWD/logs:/logs" \
  -v "$PWD/state:/state" \
  your-dockerhub-user/rclone-sync:latest
```

发布到 Docker Hub 后，把 `your-dockerhub-user/rclone-sync:latest` 换成你的真实镜像名。

## 2. Docker Compose

默认 [docker-compose.yml](./docker-compose.yml) 面向 Docker Hub 用户，不做本地 build：

```yaml
services:
  rclone-sync:
    image: ${RCLONE_SYNC_IMAGE:-your-dockerhub-user/rclone-sync:latest}
    restart: unless-stopped
    env_file:
      - ${RCLONE_SYNC_ENV_FILE:-./rclone-sync.env}
    volumes:
      - ./logs:/logs
      - ./state:/state
      - ./filters:/filters:ro
```

使用：

```bash
cp rclone-sync.env.example rclone-sync.env
vim rclone-sync.env
RCLONE_SYNC_IMAGE=your-dockerhub-user/rclone-sync:latest docker compose up -d
```

本地开发构建用 override 文件：

```bash
RCLONE_SYNC_ENV_FILE=./tmp/real-b2-to-google-drive.env \
RCLONE_SYNC_NETWORK_MODE=host \
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build
```

`RCLONE_SYNC_ENV_FILE` 可以指定任意 env 文件。默认是 `./rclone-sync.env`。

`RCLONE_SYNC_NETWORK_MODE=host` 只在需要容器访问宿主机 `127.0.0.1` 代理时使用。默认 `bridge` 隔离更好。bridge 模式里，容器内的 `127.0.0.1` 是容器自己，不是宿主机。

## 3. 最安全的 B2 到 Google Drive 示例

[rclone-sync.env.example](./rclone-sync.env.example) 默认是 dry-run，不会真的移动或删除：

```env
TZ=Asia/Shanghai

RCLONE_SYNC_MODE=archive
RCLONE_SYNC_DRY_RUN=true
# RCLONE_SYNC_ALLOW_DESTRUCTIVE=true

RCLONE_SYNC_OLDER_THAN=3M
RCLONE_SYNC_EXCLUDE_EXTENSIONS=.tmp,.part,.bak
RCLONE_SYNC_DIRECTORIES=.

RCLONE_SYNC_RUN_ON_STARTUP=true
RCLONE_SYNC_SCHEDULE=0 3 * * *

RCLONE_SYNC_SOURCE_REMOTE=src
RCLONE_SYNC_SOURCE_BUCKET=your_b2_bucket_name
RCLONE_SYNC_SOURCE_PATH=your/source/prefix

RCLONE_CONFIG_SRC_TYPE=b2
RCLONE_CONFIG_SRC_ACCOUNT=your_b2_key_id
RCLONE_CONFIG_SRC_KEY=your_b2_application_key

RCLONE_SYNC_TARGET_REMOTE=dst
RCLONE_SYNC_TARGET_PATH=backup/b2-archive

RCLONE_CONFIG_DST_TYPE=drive
RCLONE_CONFIG_DST_SCOPE=drive
RCLONE_CONFIG_DST_CLIENT_ID=your_google_oauth_client_id
RCLONE_CONFIG_DST_CLIENT_SECRET=your_google_oauth_client_secret
RCLONE_SYNC_TARGET_CONFIG_TOKEN_REFRESH_TOKEN=your_google_oauth_refresh_token
```

这会展开为：

```text
src:your_b2_bucket_name/your/source/prefix -> dst:backup/b2-archive
```

Google Drive 没有 bucket。Google Drive 目标目录只填 `RCLONE_SYNC_TARGET_PATH`。

确认 dry-run 日志后，真实执行只改这两行：

```env
RCLONE_SYNC_DRY_RUN=false
RCLONE_SYNC_ALLOW_DESTRUCTIVE=true
```

`archive` 是 `rclone move`：传输成功后删除源端文件。默认还会删除空源目录：

```env
RCLONE_SYNC_DELETE_EMPTY_SOURCE_DIRS=true
```

本地目录归档时如果不想删除空目录，设为：

```env
RCLONE_SYNC_DELETE_EMPTY_SOURCE_DIRS=false
```

## 4. 模式和删除风险

| 模式 | 底层命令 | 删除源端 | 删除目标端多余文件 | 用途 |
| --- | --- | --- | --- | --- |
| `copy` | `rclone copy` | 否 | 否 | 普通复制、备份、目标保留历史 |
| `mirror` | `rclone sync` | 否 | 是 | 目标严格镜像源端 |
| `archive` | `rclone move` | 是，传输成功后 | 否 | 把旧数据搬到目标后释放源端空间 |
| `prune` | `rclone delete` | 是 | 无目标 | 只清理源端过期数据 |
| `check` | `rclone check` | 否 | 否 | 校验源和目标 |

默认安全：

```env
RCLONE_SYNC_DRY_RUN=true
```

会删除数据的真实执行必须同时设置：

```env
RCLONE_SYNC_DRY_RUN=false
RCLONE_SYNC_ALLOW_DESTRUCTIVE=true
```

`RCLONE_SYNC_ALLOW_DESTRUCTIVE` 必须来自环境变量。YAML 里不能绕过这个确认。

## 5. 删除保护

默认删除保护：

```env
RCLONE_SYNC_MAX_DELETE=1000
RCLONE_SYNC_MAX_DELETE_SIZE=100G
```

如果不填这两个，默认仍然生效。

`archive` 和 `prune` 删除的是源端文件。runner 会先用 `rclone lsjson` 枚举匹配文件，检查数量和大小，超过上限就中止。

`mirror` 删除的是目标端多余文件。runner 会把限制传给 rclone 的 `--max-delete`，如果当前 rclone 支持也会传 `--max-delete-size`。

调整上限：

```env
RCLONE_SYNC_MAX_DELETE=10000
RCLONE_SYNC_MAX_DELETE_SIZE=500G
```

明确要关闭限制时：

```env
RCLONE_SYNC_ALLOW_UNLIMITED_DELETE=true
```

不建议一开始关闭删除保护。

## 6. 路径规则

可以直接写 root：

```env
RCLONE_SYNC_SOURCE_ROOT=src:my-bucket/source-prefix
RCLONE_SYNC_TARGET_ROOT=dst:backup/b2-archive
```

也可以拆开写，适合 Docker env：

```env
RCLONE_SYNC_SOURCE_REMOTE=src
RCLONE_SYNC_SOURCE_BUCKET=my-bucket
RCLONE_SYNC_SOURCE_PATH=source-prefix
```

上面生成：

```text
src:my-bucket/source-prefix
```

B2、S3、R2 通常有 bucket：

```env
RCLONE_SYNC_SOURCE_REMOTE=src
RCLONE_SYNC_SOURCE_BUCKET=my-bucket
RCLONE_SYNC_SOURCE_PATH=logs/app1
```

Google Drive 通常没有 bucket：

```env
RCLONE_SYNC_TARGET_REMOTE=dst
RCLONE_SYNC_TARGET_PATH=backup/b2-archive
```

远端根路径默认拒绝，例如 `src:`、`src:/`、`src://`。如果真的要操作远端根，必须显式设置：

```env
RCLONE_SYNC_ALLOW_ROOT_PATH=true
```

不建议这样做。

## 7. 多目录和目标 prefix

源端和目标端目录结构保持一致。配置两个 root，再配置一组相对目录：

```env
RCLONE_SYNC_SOURCE_ROOT=src:my-bucket/source-prefix
RCLONE_SYNC_TARGET_ROOT=dst:backup/b2-archive
RCLONE_SYNC_DIRECTORIES=photos,documents,logs/app1
```

展开后：

```text
src:my-bucket/source-prefix/photos    -> dst:backup/b2-archive/photos
src:my-bucket/source-prefix/documents -> dst:backup/b2-archive/documents
src:my-bucket/source-prefix/logs/app1 -> dst:backup/b2-archive/logs/app1
```

同步整个 root：

```env
RCLONE_SYNC_DIRECTORIES=.
```

`directories` 必须是相对目录，不能以 `/` 开头，不能包含 `..`。

## 8. 时间过滤

时间过滤基于 rclone 看到的文件修改时间，不是对象创建时间。

不填时间过滤时，处理所选目录里的全部文件：

```env
# 不设置 RCLONE_SYNC_OLDER_THAN / DATE_BEFORE / DATE_AFTER
```

只处理 3 天以前：

```env
RCLONE_SYNC_OLDER_THAN=3d
```

只处理约 90 天以前：

```env
RCLONE_SYNC_OLDER_THAN=3M
```

`M` 按 30 天计算，`y` 按 365 天计算。需要精确日历边界时，用绝对日期：

```env
RCLONE_SYNC_DATE_BEFORE=2026-01-01
```

只处理某日期之后：

```env
RCLONE_SYNC_DATE_AFTER=2025-01-01
```

只处理日期窗口：

```env
RCLONE_SYNC_DATE_AFTER=2025-01-01
RCLONE_SYNC_DATE_BEFORE=2026-01-01
```

如果 `DATE_BEFORE` 是未来日期，runner 会拒绝执行，避免误把全部文件当成匹配。

## 9. 排除文件

按后缀排除：

```env
RCLONE_SYNC_EXCLUDE_EXTENSIONS=.tmp,.part,.bak
```

按 rclone glob 排除：

```env
RCLONE_SYNC_EXCLUDE=**/cache/**,**/.DS_Store,**/*.iso
```

使用过滤文件：

```env
RCLONE_SYNC_EXCLUDE_FROM=/filters/exclude.txt
```

Compose 挂载：

```yaml
volumes:
  - ./filters:/filters:ro
```

示例见 [filters/exclude.txt.example](./filters/exclude.txt.example)。

## 10. 本地目录

env 里必须使用容器内路径，不是宿主机路径。

B2 到本地目录：

```yaml
services:
  rclone-sync:
    image: your-dockerhub-user/rclone-sync:latest
    env_file:
      - ./b2-to-local.env
    volumes:
      - /srv/b2-backup:/data/target
      - ./logs:/logs
      - ./state:/state
```

env 示例见 [examples/b2-to-local.env.example](./examples/b2-to-local.env.example)。

本地目录到 Google Drive：

```yaml
services:
  rclone-sync:
    image: your-dockerhub-user/rclone-sync:latest
    env_file:
      - ./local-to-google-drive.env
    volumes:
      - /srv/source:/data/source:ro
      - ./logs:/logs
      - ./state:/state
```

env 示例见 [examples/local-to-google-drive.env.example](./examples/local-to-google-drive.env.example)。

## 11. Google Drive 凭证

rclone 里 Google Drive backend 类型叫 `drive`：

```env
RCLONE_CONFIG_DST_TYPE=drive
```

纯 env OAuth 至少需要：

```env
RCLONE_CONFIG_DST_TYPE=drive
RCLONE_CONFIG_DST_SCOPE=drive
RCLONE_CONFIG_DST_CLIENT_ID=your_google_oauth_client_id
RCLONE_CONFIG_DST_CLIENT_SECRET=your_google_oauth_client_secret
RCLONE_SYNC_TARGET_CONFIG_TOKEN_REFRESH_TOKEN=your_google_oauth_refresh_token
```

`client_id` 和 `client_secret` 只是 OAuth 应用凭证，不能单独访问某个 Drive。`refresh_token` 代表用户授权过这个应用访问 Drive。

`access_token` 和 `expiry` 不需要填。runner 会自动组装 rclone token，rclone 会自己刷新。

不用 rclone 获取 refresh token：

```bash
python3 tools/google-drive-refresh-token.py ./client_secret.json
```

脚本只使用 Python 标准库。浏览器授权后输出：

```env
RCLONE_SYNC_TARGET_CONFIG_TOKEN_REFRESH_TOKEN=...
```

也可以使用 Google OAuth Playground。Scope 用：

```text
https://www.googleapis.com/auth/drive
```

如果你已经有主机上的 rclone remote，例如 `gt:`：

```bash
rclone lsd gt:
```

可以挂载 `rclone.conf`：

```yaml
volumes:
  - ~/.config/rclone:/config/rclone
```

然后目标写：

```env
RCLONE_SYNC_TARGET_ROOT=gt:backup/b2-archive
```

这种模式下不要再配置 `RCLONE_CONFIG_DST_*`。

## 12. 其他存储服务商

rclone 原生 env remote 格式：

```text
RCLONE_CONFIG_<REMOTE_NAME>_<OPTION_NAME>
```

remote 名全部大写。例如路径使用 `src:`：

```env
RCLONE_SYNC_SOURCE_ROOT=src:my-bucket/source-prefix
RCLONE_CONFIG_SRC_TYPE=b2
RCLONE_CONFIG_SRC_ACCOUNT=your_b2_key_id
RCLONE_CONFIG_SRC_KEY=your_b2_application_key
```

Cloudflare R2 / S3 示例：

```env
RCLONE_SYNC_SOURCE_ROOT=src:my-bucket/source-prefix
RCLONE_CONFIG_SRC_TYPE=s3
RCLONE_CONFIG_SRC_PROVIDER=Cloudflare
RCLONE_CONFIG_SRC_ACCESS_KEY_ID=your_access_key_id
RCLONE_CONFIG_SRC_SECRET_ACCESS_KEY=your_secret_access_key
RCLONE_CONFIG_SRC_ENDPOINT=https://account-id.r2.cloudflarestorage.com
RCLONE_CONFIG_SRC_REGION=auto
```

快速示例建议固定使用 `src` 和 `dst`。如果自定义 remote 名，例如 `gdrive:`，也要同步改成对应的 `RCLONE_CONFIG_GDRIVE_*`，或用 `RCLONE_SYNC_TARGET_ROOT=gdrive:path` 配合 `RCLONE_SYNC_TARGET_CONFIG_*`。

## 13. Slack 通知

填 webhook 后会发送通知：

```env
RCLONE_SYNC_SLACK_WEBHOOK_URL=https://hooks.slack.com/services/xxx/yyy/zzz
RCLONE_SYNC_SLACK_EVENTS=startup,job_start,job_success,job_error,task_start,task_success,task_error
```

可选项：

```env
RCLONE_SYNC_SLACK_USERNAME=rclone-sync
RCLONE_SYNC_SLACK_CHANNEL=#backups
RCLONE_SYNC_SLACK_TIMEOUT=10
```

事件：

| 事件 | 说明 |
| --- | --- |
| `startup` | 容器 entrypoint 启动 |
| `job_start` | 一个 job 开始 |
| `job_success` | 一个 job 成功 |
| `job_error` | 一个 job 失败 |
| `task_start` | 一个目录 task 开始 |
| `task_success` | 一个目录 task 成功，包含耗时和预检候选数量 |
| `task_error` | 一个目录 task 失败 |

Slack 发送失败不会中断同步，只写容器日志。

## 14. 常驻运行

不设置 schedule 时，容器启动后执行一次，然后退出。

```env
RCLONE_SYNC_SCHEDULE=
```

设置 5 字段 cron 后，容器常驻：

```env
RCLONE_SYNC_RUN_ON_STARTUP=true
RCLONE_SYNC_SCHEDULE=0 3 * * *
```

时区来自：

```env
TZ=Asia/Shanghai
```

如果设置了 schedule 且启动任务失败，容器会退出；配合 `restart: unless-stopped` 时会重启。这样可以让错误显性暴露，而不是静默等待下一次 cron。

## 15. 日志和故障排查

建议始终挂载：

```yaml
volumes:
  - ./logs:/logs
  - ./state:/state
```

每次运行写入：

- `/logs/runs/<timestamp>/<job>/<task>/command.json`
- `/logs/runs/<timestamp>/<job>/<task>/result.json`
- `/logs/runs/<timestamp>/<job>/<task>/combined.txt`
- `/logs/runs/<timestamp>/<job>/<task>/errors.txt`

这些日志包含 bucket、prefix、文件名和命令参数，属于敏感运行数据，不要提交到 git。

当前镜像默认以 root 运行，`logs/` 和 `state/` 里可能产生 root-owned 文件。需要清理时可用 `sudo rm -rf logs state`，或在自己的 compose 中增加合适的 `user:` 设置并确认挂载目录权限。

看日志：

```bash
docker logs rclone-sync
```

用 compose 看日志：

```bash
docker compose logs -f rclone-sync
```

进入容器调试 rclone：

```bash
docker compose run --rm rclone-sync rclone lsd dst:
```

只手动跑一次：

```bash
docker compose run --rm rclone-sync run
```

## 16. YAML 模式

一个常见任务用 env 即可。多个 job 或复杂规则可以挂载 `/config/jobs.yaml`：

```yaml
services:
  rclone-sync:
    image: your-dockerhub-user/rclone-sync:latest
    volumes:
      - ./config.example.yaml:/config/jobs.yaml:ro
      - ~/.config/rclone:/config/rclone
      - ./logs:/logs
      - ./state:/state
```

参考 [config.example.yaml](./config.example.yaml)。

YAML 中即使配置了 destructive job，真实删除仍然需要环境变量：

```env
RCLONE_SYNC_ALLOW_DESTRUCTIVE=true
```

## 17. 发布和安全注意

- 不要提交真实 env、OAuth token、B2 key、Slack webhook。
- `.gitignore` 和 `.dockerignore` 已忽略 `tmp/`、`logs/`、`state/`、`rclone-sync.env`、`.env` 和常见密钥文件。
- Dockerfile 固定基础镜像 `rclone/rclone:1.70.3`，发布自己的镜像时建议同时打版本 tag 和 `latest`。
- 公开示例默认 dry-run。真实删除必须手动启用。
- 如果在 Google Cloud OAuth consent screen 里仍是 Testing，refresh token 可能只有 7 天有效。长期部署建议发布到 Production。

发布到 Docker Hub 可以用整个仓库根目录的公共脚本 `../publish-dockerhub.sh`。这个脚本可以发布不同目录里的 Dockerfile，靠 `--context` 和 `--file` 指定要构建哪个 Docker。

```bash
cd /home/sean/git/dockers

./publish-dockerhub.sh \
  --context rclone-sync \
  --file Dockerfile \
  --image your-dockerhub-user/rclone-sync \
  --tag 0.1.0
```

脚本默认会：

- 运行 Python 语法检查和本地 smoke test。
- 使用 buildx 构建 `linux/amd64,linux/arm64`。
- 推送 `your-dockerhub-user/rclone-sync:0.1.0`。
- 同时推送 `your-dockerhub-user/rclone-sync:latest`。

如果要自动登录 Docker Hub：

```bash
DOCKERHUB_USERNAME=your-dockerhub-user \
DOCKERHUB_TOKEN=your_dockerhub_access_token \
./publish-dockerhub.sh \
  --context rclone-sync \
  --file Dockerfile \
  --image your-dockerhub-user/rclone-sync \
  --tag 0.1.0
```

只发布指定 tag，不更新 `latest`：

```bash
./publish-dockerhub.sh \
  --context rclone-sync \
  --file Dockerfile \
  --image your-dockerhub-user/rclone-sync \
  --tag 0.1.0 \
  --no-latest
```

本地测试构建，不推送：

```bash
./publish-dockerhub.sh \
  --context rclone-sync \
  --file Dockerfile \
  --image your-dockerhub-user/rclone-sync \
  --tag 0.1.0 \
  --platforms linux/amd64 \
  --load
```

## 18. 已验证

已经真实测试过：

- env-only B2 到 Google Drive。
- `archive` 模式。
- `RCLONE_SYNC_OLDER_THAN=24h` 时间过滤。
- `.tmp/.part/.bak` 后缀排除。
- 成功后删除 B2 源端旧文件。
- Docker Compose 常驻 cron。
- Google Drive OAuth 只填 refresh token，不填 access token/expiry。
- Slack webhook 的 `startup/job_start/task_start/task_success/job_success` 通知。
