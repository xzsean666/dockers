# rclone-sync 架构文档

## 目标

`rclone-sync` 是一个基于 Docker 的 rclone 作业编排器，用来把一个或多个源目录同步、复制、归档或清理到另一个存储位置。源和目标都使用 rclone path 表达，例如 `b2:bucket/path`、`gdrive:folder`、`s3:bucket/prefix`、`/data/local/path`。

核心目标：

- 支持任意 rclone backend，不把实现绑死在 B2、Google Drive、S3 或本地目录。
- 面向 Docker Hub 发布，支持只传环境变量就运行一个常见同步任务。
- 支持多目录、多作业、全局过滤、单作业过滤、单目录覆盖过滤。
- 源和目标目录结构保持一致：配置只声明两边 root 和一组相同的相对目录，不做 `from -> to` 重命名映射。
- 支持按修改时间选择文件，例如只处理 3 天前、3 个月前、最近 24 小时、某个日期之前、某个日期之后、两个日期之间的数据。
- 支持排除特定后缀、目录、glob 规则和外部过滤文件。
- 把危险行为显式化：目标删除、源删除、排除文件删除都必须通过明确模式和安全开关启用。
- 默认先 dry-run，并产生审计报告，便于确认将复制、删除、跳过和报错的文件。

非目标：

- 不实现自有云存储协议，所有传输能力交给 rclone。
- 不做双向同步。双向同步应另行评估 rclone `bisync`，不作为第一版能力。
- 不把凭证写进作业配置。凭证只放在 rclone config、Docker secrets 或环境变量里。

## 调研依据

- rclone `sync` 会让目标端匹配源端，只修改目标端，不会删除源端，但会按需要删除目标端多余文件。官方建议用 `--dry-run` 或 `--interactive` 先测试。
  参考：https://rclone.org/commands/rclone_sync/
- rclone `copy` 会复制源端到目标端并跳过相同文件，不会删除目标端文件。
  参考：https://rclone.org/commands/rclone_copy/
- rclone `move` 会把文件移动到目标端，无法服务端移动时会先复制再在成功后删除源端文件。官方同样提示先 dry-run。
  参考：https://rclone.org/commands/rclone_move/
- rclone `delete` 支持 include/exclude 过滤，只删除文件，目录结构默认保留，可配 `--rmdirs` 删除空目录。
  参考：https://rclone.org/commands/rclone_delete/
- `--min-age` 选择更老的文件，`--max-age` 选择更新的文件，二者只作用于文件，不作用于目录本身。时间单位支持 `ms/s/m/h/d/w/M/y`。
  参考：https://rclone.org/filtering/ 和 https://rclone.org/docs/#time-and-duration-options
- 官方 Docker 镜像由 rclone 维护，生产使用建议固定版本 tag；配置目录应整体挂载到 `/config/rclone`，因为 token 刷新会更新配置文件。
  参考：https://rclone.org/install/#docker-installation
- rclone 支持完全通过环境变量配置 remote。规则是 `RCLONE_CONFIG_` + remote 名称 + `_` + 配置项名，全部大写，例如 `RCLONE_CONFIG_SRC_TYPE=b2`。
  参考：https://rclone.org/docs/#environment-variables

## 操作模型

| operation | 底层 rclone 命令 | 删除源端 | 删除目标端多余文件 | 用途 |
| --- | --- | --- | --- | --- |
| `copy` | `rclone copy` | 否 | 否 | 普通备份、增量复制、目标保留历史 |
| `mirror` | `rclone sync` | 否 | 是 | 目标严格镜像源端 |
| `archive` | `rclone move` | 是，复制成功后 | 否 | 把老数据迁到目标后释放源端空间 |
| `prune` | `rclone delete` | 是 | 不需要目标 | 只清理源端过期数据 |
| `check` | `rclone check` | 否 | 否 | 校验源和目标一致性 |

命名上不用 `sync` 作为顶层 mode，因为用户常把“同步”理解为复制、镜像、归档的统称。配置里使用 `copy`、`mirror`、`archive`、`prune`，避免误触发删除行为。

## 时间窗口语义

作业配置使用业务语义，runner 再翻译为 rclone 参数：

| 配置 | rclone 参数 | 含义 |
| --- | --- | --- |
| `age.older_than: 3d` | `--min-age 3d` | 只处理 3 天或更早之前修改的文件 |
| `age.newer_than: 24h` | `--max-age 24h` | 只处理最近 24 小时内修改的文件 |
| `age.between.older_than: 3d` + `age.between.newer_than: 3M` | `--min-age 3d --max-age 3M` | 只处理 3 天到 3 个月之间的文件 |
| `date.before: 2026-01-01` | runner 转成 `--min-age` | 只处理 2026-01-01 之前修改的文件 |
| `date.after: 2026-01-01` | runner 转成 `--max-age` | 只处理 2026-01-01 之后修改的文件 |
| `date.after` + `date.before` | runner 转成 `--min-age` + `--max-age` | 只处理两个日期之间修改的文件 |

注意：

- 时间过滤基于 rclone 看到的文件修改时间，不是对象创建时间。
- `older_than` / `newer_than` 用相对时间，适合 Docker env 简单使用；`date.before` / `date.after` 用绝对日期，runner 在执行时根据当前时间换算为 rclone age 参数。
- `--min-age` 和 `--max-age` 只筛选文件，不筛选目录本身。需要清理空目录时，对 `archive` 可启用 `delete_empty_source_dirs`，对 `prune` 可启用 `rmdirs`。
- 月份 `M` 和年份 `y` 是 rclone 支持的相对时间单位。跨后端使用前需要通过 dry-run 报告确认结果符合预期。

## 系统架构

```text
Docker container
├── entrypoint
│   ├── validate env
│   ├── run once / cron loop / manual command
│   └── dispatch runner
├── runner
│   ├── load /config/jobs.yaml or build single job from env
│   ├── validate job schema and safety rules
│   ├── expand jobs into directory tasks
│   ├── render rclone argv arrays
│   ├── execute preflight dry-run / actual run
│   ├── write reports and logs
│   └── optional post-run check
└── rclone
    ├── uses /config/rclone/rclone.conf
    ├── reads filter files from /filters
    └── transfers between remotes and local mounts
```

推荐实现：

- 基础镜像：`rclone/rclone:<pinned-version>`，再安装 `python3`、`pyyaml`、`tzdata`、`supercronic` 或使用 Alpine `crond`。
- runner：Python。原因是 YAML 解析、参数数组构造、安全校验和报告生成比 shell 更可靠。
- 执行 rclone 时使用 argv 数组，不拼 shell 字符串，降低路径、空格、通配符和注入风险。
- 日志输出到 stdout，同时把每次运行的结构化报告写入 `/logs/runs/<timestamp>/<job>/<task>/`。

## 容器目录

```text
/config/rclone/          rclone.conf 所在目录，需整体挂载，可读写
/config/jobs.yaml        作业配置，可选；不挂载时使用 env-only 模式
/filters/                include/exclude/filter 文件
/data/                   本地源或目标统一挂载入口
/logs/                   rclone 日志、combined 报告、错误报告
/state/                  job lock、last-run 状态、首次运行确认状态
/tmp/                    临时文件和生成的 filter 文件
```

本地目录统一挂载到 `/data` 下，并作为 root 传给作业配置。例如源本地 root 用 `/data/source`，目标本地 root 用 `/data/target` 或 `/data/backups/my-bucket`。

## 路径模型

第一版采用固定目录结构模型：

```text
source_task_path = join_rclone_path(source_root, directory)
target_task_path = join_rclone_path(target_root, directory)
```

`join_rclone_path` 需要同时兼容 remote path 和本地路径：`b2:bucket + photos` 变成 `b2:bucket/photos`，`dst:bucket/prefix + photos` 变成 `dst:bucket/prefix/photos`，`/data/source + photos` 变成 `/data/source/photos`。当 `directory` 是 `.` 时，不追加子路径。

示例：

```text
source_root: b2:my-bucket
target_root: /data/backups/my-bucket
directories:
  - photos
  - documents/2026

展开后：
  b2:my-bucket/photos          -> /data/backups/my-bucket/photos
  b2:my-bucket/documents/2026  -> /data/backups/my-bucket/documents/2026
```

目标指定 prefix path 的例子：

```text
source_root: b2:my-bucket
target_root: dst:backup/server-a/2026
directories:
  - photos
  - logs/app1

展开后：
  b2:my-bucket/photos    -> dst:backup/server-a/2026/photos
  b2:my-bucket/logs/app1 -> dst:backup/server-a/2026/logs/app1
```

规则：

- `directories` 只能是相对目录，不能以 `/` 开头，不能包含 `..`。
- `.` 表示 root 本身，即 `source_root -> target_root`。
- 允许在 `target_root` 里指定目标 prefix path，例如 `dst:bucket/backup/server-a` 或 `/data/target/server-a`。
- 不支持每个目录单独 `from/to` 改名。需要目标整体放到不同前缀时，调整 `target_root`；目录自身仍保持同名结构。
- `directories` item 可以是字符串，也可以是对象；对象只允许覆盖 `path`、`filters`、`age`、`safety` 这类行为字段，不能设置不同的目标目录。
- 如果源或目标是本地目录，就把本地 root 挂载到容器内，例如 `/srv/source:/data/source:ro`，然后配置 `source_root: /data/source`。

## 配置模型

`rclone-sync` 支持两种配置入口：

1. `env-only`：没有挂载 `/config/jobs.yaml` 时，从环境变量生成一个单 job。Docker Hub 默认主推这个模式。
2. `jobs.yaml`：需要多个 job、复杂过滤或不同调度时使用 YAML。

### Docker Hub env-only 模式

最小配置：

```env
RCLONE_SYNC_SOURCE_ROOT=src:my-bucket
RCLONE_SYNC_TARGET_ROOT=/data/backups/my-bucket
RCLONE_SYNC_DIRECTORIES=photos,documents
RCLONE_SYNC_MODE=copy
RCLONE_SYNC_OLDER_THAN=
RCLONE_SYNC_EXCLUDE_EXTENSIONS=.tmp,.part
```

语义：

- `RCLONE_SYNC_OLDER_THAN` 不填时，不加时间过滤，同步所选目录里的全部文件。
- `RCLONE_SYNC_OLDER_THAN=3d` 时，只处理修改时间在 3 天或更早之前的文件，底层是 `--min-age 3d`。
- `RCLONE_SYNC_OLDER_THAN=3M` 时，只处理修改时间在 3 个月或更早之前的文件。
- `RCLONE_SYNC_DATE_BEFORE=2026-01-01` 时，只处理 2026-01-01 之前修改的文件。
- `RCLONE_SYNC_DATE_AFTER=2026-01-01` 时，只处理 2026-01-01 之后修改的文件。
- 时间过滤基于 rclone 看到的修改时间，不是对象创建时间。

通用 env：

| 环境变量 | 默认值 | 说明 |
| --- | --- | --- |
| `RCLONE_SYNC_MODE` | `copy` | `copy` 保留目标额外文件；`mirror` 删除目标多余文件；`archive` 复制成功后删除源端；`prune` 只删除源端 |
| `RCLONE_SYNC_SOURCE_ROOT` | 必填 | 源 root，例如 `src:bucket/prefix` 或 `/data/source` |
| `RCLONE_SYNC_TARGET_ROOT` | `prune` 可空 | 目标 root，可带指定 prefix path，例如 `dst:bucket/prefix`、`drive:backup/server-a` 或 `/data/target/server-a` |
| `RCLONE_SYNC_DIRECTORIES` | `.` | 同名相对目录列表，CSV 或换行分隔，例如 `photos,documents/logs` |
| `RCLONE_SYNC_OLDER_THAN` | 空 | 只处理多久以前的文件，例如 `3d`、`3M`、`1y`；空表示全部 |
| `RCLONE_SYNC_NEWER_THAN` | 空 | 高级用法，只处理多久以内的文件，映射 `--max-age` |
| `RCLONE_SYNC_DATE_BEFORE` | 空 | 只处理某个日期之前修改的文件，例如 `2026-01-01` 或 `2026-01-01T00:00:00+08:00` |
| `RCLONE_SYNC_DATE_AFTER` | 空 | 只处理某个日期之后修改的文件，例如 `2026-01-01` |
| `RCLONE_SYNC_EXCLUDE_EXTENSIONS` | 空 | 排除后缀列表，CSV，例如 `.tmp,.part,.bak`，runner 转成 `*.tmp` 和 `**/*.tmp` 等规则 |
| `RCLONE_SYNC_EXCLUDE` | 空 | CSV 排除规则，例如 `**/.DS_Store,**/*.tmp` |
| `RCLONE_SYNC_EXCLUDE_FROM` | 空 | 排除规则文件路径，例如 `/filters/exclude.txt` |
| `RCLONE_SYNC_DRY_RUN` | `true` | 是否只预演。发布镜像默认安全，真实执行时设为 `false` |
| `RCLONE_SYNC_ALLOW_DESTRUCTIVE` | `false` | `mirror`、`archive`、`prune` 真实执行必须设为 `true` |
| `RCLONE_SYNC_MAX_DELETE` | `1000` | 删除保护上限 |
| `RCLONE_SYNC_MAX_DELETE_SIZE` | `100G` | 删除体积保护上限 |
| `RCLONE_SYNC_ALLOW_UNLIMITED_DELETE` | `false` | 显式设为 `true` 时禁用删除数量和体积保护 |
| `RCLONE_SYNC_SCHEDULE` | 空 | cron 表达式；空表示按容器模式决定 run-once 或常驻 |
| `RCLONE_SYNC_RUN_ON_STARTUP` | `true` | 启动时执行一次 |

兼容简单布尔别名：

- `RCLONE_SYNC_DELETE_SOURCE=true` 且未设置 `RCLONE_SYNC_MODE` 时，等价于 `RCLONE_SYNC_MODE=archive`。
- `RCLONE_SYNC_DELETE_TARGET_EXTRAS=true` 且未设置 `RCLONE_SYNC_MODE` 时，等价于 `RCLONE_SYNC_MODE=mirror`。
- 两个别名不能同时为 `true`。如果同时配置，会直接失败并提示用户改用显式 `RCLONE_SYNC_MODE`。

#### 目录、日期、后缀示例

同步任意本地文件夹到 B2，只同步 2026-01-01 之前修改的文件，并排除临时文件后缀：

```yaml
services:
  rclone-sync:
    image: yourname/rclone-sync:latest
    environment:
      RCLONE_SYNC_SOURCE_ROOT: /data/source
      RCLONE_SYNC_TARGET_ROOT: dst:backup/server-a
      RCLONE_SYNC_DIRECTORIES: "."
      RCLONE_SYNC_MODE: copy
      RCLONE_SYNC_DATE_BEFORE: "2026-01-01"
      RCLONE_SYNC_EXCLUDE_EXTENSIONS: ".tmp,.part,.bak"
      RCLONE_SYNC_EXCLUDE: "**/cache/**,**/.DS_Store"
      RCLONE_SYNC_DRY_RUN: "false"
      RCLONE_CONFIG_DST_TYPE: b2
      RCLONE_CONFIG_DST_ACCOUNT: xxx
      RCLONE_CONFIG_DST_KEY: xxx
    volumes:
      - /srv/any-folder:/data/source:ro
      - ./logs:/logs
      - ./state:/state
```

同步多个子目录到同名目标目录，只同步 3 个月前的数据：

```env
RCLONE_SYNC_SOURCE_ROOT=src:bucket
RCLONE_SYNC_TARGET_ROOT=dst:archive/bucket
RCLONE_SYNC_DIRECTORIES=photos,documents,logs/app1
RCLONE_SYNC_MODE=copy
RCLONE_SYNC_OLDER_THAN=3M
RCLONE_SYNC_EXCLUDE_EXTENSIONS=.tmp,.log,.bak
```

过滤规则说明：

- `RCLONE_SYNC_EXCLUDE_EXTENSIONS=.tmp,.part` 会生成 `--exclude *.tmp --exclude **/*.tmp --exclude *.part --exclude **/*.part`，同时覆盖当前目录和子目录。
- 后缀里的点可写可不写，`.tmp` 和 `tmp` 都按 `**/*.tmp` 处理。
- `RCLONE_SYNC_EXCLUDE` 直接使用 rclone glob，例如 `**/cache/**,**/*.iso`。
- 排除目录用 `**/dirname/**`，排除后缀用 `**/*.ext`。
- 需要大量规则时，把规则写进文件并挂载到 `/filters/exclude.txt`，再设置 `RCLONE_SYNC_EXCLUDE_FROM=/filters/exclude.txt`。

#### Provider env 处理

不同存储服务商的凭证字段确实不一样，所以设计上分三层处理：

1. 最通用：直接使用 rclone 官方 env。用户自己定义 remote 名，例如 `src:`、`dst:`。
2. 简化映射：用户设置 `RCLONE_SYNC_SOURCE_CONFIG_*` / `RCLONE_SYNC_TARGET_CONFIG_*`，runner 自动转成 `RCLONE_CONFIG_SRC_*` / `RCLONE_CONFIG_DST_*`。
3. 本地目录：不需要 remote 配置，只把宿主机目录挂载到 `/data/...`，然后把 root 写成 `/data/...`。

推荐 remote 名：

```text
source remote: src:
target remote: dst:
```

直接使用 rclone 官方 env 的例子：

```env
RCLONE_SYNC_SOURCE_ROOT=src:my-bucket
RCLONE_CONFIG_SRC_TYPE=b2
RCLONE_CONFIG_SRC_ACCOUNT=xxx
RCLONE_CONFIG_SRC_KEY=xxx

RCLONE_SYNC_TARGET_ROOT=dst:archive
RCLONE_CONFIG_DST_TYPE=drive
RCLONE_CONFIG_DST_SERVICE_ACCOUNT_FILE=/secrets/gdrive.json
```

使用简化映射的例子：

```env
RCLONE_SYNC_SOURCE_ROOT=src:my-bucket
RCLONE_SYNC_SOURCE_CONFIG_TYPE=b2
RCLONE_SYNC_SOURCE_CONFIG_ACCOUNT=xxx
RCLONE_SYNC_SOURCE_CONFIG_KEY=xxx

RCLONE_SYNC_TARGET_ROOT=dst:archive
RCLONE_SYNC_TARGET_CONFIG_TYPE=drive
RCLONE_SYNC_TARGET_CONFIG_SERVICE_ACCOUNT_FILE=/secrets/gdrive.json
```

runner 映射规则：

```text
RCLONE_SYNC_SOURCE_CONFIG_TYPE       -> RCLONE_CONFIG_SRC_TYPE
RCLONE_SYNC_SOURCE_CONFIG_ACCOUNT    -> RCLONE_CONFIG_SRC_ACCOUNT
RCLONE_SYNC_TARGET_CONFIG_TYPE       -> RCLONE_CONFIG_DST_TYPE
RCLONE_SYNC_TARGET_CONFIG_ENDPOINT   -> RCLONE_CONFIG_DST_ENDPOINT
```

常见 provider 示例：

```env
# Backblaze B2
RCLONE_CONFIG_SRC_TYPE=b2
RCLONE_CONFIG_SRC_ACCOUNT=xxx
RCLONE_CONFIG_SRC_KEY=xxx

# S3 / MinIO / Cloudflare R2 / Wasabi 等 S3 兼容服务
RCLONE_CONFIG_DST_TYPE=s3
RCLONE_CONFIG_DST_PROVIDER=Cloudflare
RCLONE_CONFIG_DST_ACCESS_KEY_ID=xxx
RCLONE_CONFIG_DST_SECRET_ACCESS_KEY=xxx
RCLONE_CONFIG_DST_ENDPOINT=https://<account>.r2.cloudflarestorage.com
RCLONE_CONFIG_DST_REGION=auto

# Google Drive service account
RCLONE_CONFIG_DST_TYPE=drive
RCLONE_CONFIG_DST_SERVICE_ACCOUNT_FILE=/secrets/gdrive.json
RCLONE_CONFIG_DST_TEAM_DRIVE=
```

本地目标例子：

```yaml
services:
  rclone-sync:
    image: yourname/rclone-sync:latest
    environment:
      RCLONE_SYNC_SOURCE_ROOT: src:my-bucket
      RCLONE_SYNC_TARGET_ROOT: /data/target
      RCLONE_SYNC_DIRECTORIES: photos,documents
      RCLONE_SYNC_MODE: copy
      RCLONE_SYNC_DRY_RUN: "false"
      RCLONE_CONFIG_SRC_TYPE: b2
      RCLONE_CONFIG_SRC_ACCOUNT: xxx
      RCLONE_CONFIG_SRC_KEY: xxx
    volumes:
      - /mnt/backup:/data/target
      - ./logs:/logs
      - ./state:/state
```

删除源端的归档例子：

```yaml
services:
  rclone-sync:
    image: yourname/rclone-sync:latest
    environment:
      RCLONE_SYNC_SOURCE_ROOT: src:my-bucket
      RCLONE_SYNC_TARGET_ROOT: dst:archive/my-bucket
      RCLONE_SYNC_DIRECTORIES: logs,exports
      RCLONE_SYNC_MODE: archive
      RCLONE_SYNC_OLDER_THAN: 3M
      RCLONE_SYNC_DRY_RUN: "false"
      RCLONE_SYNC_ALLOW_DESTRUCTIVE: "true"
      RCLONE_CONFIG_SRC_TYPE: b2
      RCLONE_CONFIG_SRC_ACCOUNT: xxx
      RCLONE_CONFIG_SRC_KEY: xxx
      RCLONE_CONFIG_DST_TYPE: drive
      RCLONE_CONFIG_DST_SERVICE_ACCOUNT_FILE: /secrets/gdrive.json
    volumes:
      - ./gdrive.json:/secrets/gdrive.json:ro
      - ./logs:/logs
      - ./state:/state
```

### YAML 模式

示例：

```yaml
version: 1

global:
  timezone: Asia/Shanghai
  dry_run_default: true
  require_confirm_for_destructive: true
  log_level: INFO
  stats: 30s
  transfers: 4
  checkers: 8
  retries: 3
  low_level_retries: 10
  max_parallel_jobs: 1
  rclone_config: /config/rclone/rclone.conf

defaults:
  safety:
    max_delete: 1000
    max_delete_size: 100G
    allow_delete_excluded: false
    deny_root_path: true
    deny_overlapping_paths: true
  filters:
    exclude:
      - "**/.DS_Store"
      - "**/Thumbs.db"
      - "**/*.tmp"

jobs:
  - name: b2-to-local-copy
    enabled: true
    schedule: "0 2 * * *"
    operation: copy
    source_root: "b2:my-bucket"
    target_root: "/data/backups/my-bucket"
    directories:
      - "photos"
      - "documents"
    age:
      newer_than: 24h
    filters:
      exclude_from:
        - /filters/common-exclude.txt
    verify:
      check_after: false

  - name: b2-old-archive-to-gdrive
    enabled: true
    schedule: "0 3 * * *"
    operation: archive
    source_root: "b2:my-bucket"
    target_root: "gdrive:archive/my-bucket"
    directories:
      - "logs"
      - "exports"
    age:
      older_than: 3M
    archive:
      delete_empty_source_dirs: true
    safety:
      dry_run: true

  - name: mirror-critical-to-second-bucket
    enabled: true
    schedule: "30 2 * * *"
    operation: mirror
    source_root: "b2:critical"
    target_root: "s3:critical-replica"
    directories:
      - "."
    safety:
      dry_run: true
      max_delete: 100
      backup_dir: "s3:critical-replica-deleted/${RUN_DATE}"
      allow_delete_excluded: false

  - name: prune-source-old-temp
    enabled: true
    schedule: "15 4 * * *"
    operation: prune
    source_root: "b2:my-bucket"
    directories:
      - "tmp"
    age:
      older_than: 3d
    filters:
      include:
        - "**/*.tmp"
      exclude:
        - "keep/**"
    prune:
      rmdirs: true
    safety:
      dry_run: true
      max_delete: 10000
```

### 字段说明

- `operation`：只能是 `copy`、`mirror`、`archive`、`prune`、`check`。
- `source_root` / `target_root`：rclone path root。`prune` 不需要 `target_root`。
- `directories`：同名相对目录列表。每个目录都会拼接到 `source_root` 和 `target_root` 后面，并展开成独立 rclone 命令，避免一个目录失败影响报告定位。目录项可以写成字符串，也可以写成 `{path, filters, age, safety}` 对象，但不能写目标目录。
- `age`：相对时间过滤。支持 `older_than`、`newer_than`、`between`。
- `date`：绝对日期过滤。支持 `before`、`after`、`between`；runner 转成 rclone age 参数。
- `filters.include` / `filters.exclude`：直接渲染为重复的 `--include` / `--exclude`。
- `filters.exclude_extensions`：后缀排除简写，例如 `[.tmp, .part, .bak]`，runner 转成 `**/*.tmp` 等 exclude 规则。
- `filters.exclude_from` / `filter_from` / `files_from`：挂载到 `/filters` 后传给 rclone。
- `safety.max_delete` / `max_delete_size`：删除保护上限。`mirror` 直接映射到 rclone 的 `--max-delete`，并在当前 rclone 支持时追加 `--max-delete-size`；`archive` 和 `prune` 由 runner 先列出候选源文件并在执行前拦截。
- `safety.backup_dir`：仅对 `mirror`、`copy`、`archive` 生效，用于保存会被覆盖或删除的目标端旧文件。必须和目标端在同一个 remote 约束下使用。
- `extra_flags`：高级扩展，默认只允许安全白名单，例如 `--bwlimit`、`--tpslimit`、`--drive-chunk-size`、`--s3-chunk-size`。破坏性 flag 不允许放在这里。

## rclone 参数映射

`copy`：

```text
rclone copy <source_task_path> <target_task_path>
  --config /config/rclone/rclone.conf
  --combined <report>
  --error <error-report>
  --stats 30s
  [filters]
  [age flags]
  [performance flags]
  [--dry-run]
```

`mirror`：

```text
rclone sync <source_task_path> <target_task_path>
  --config /config/rclone/rclone.conf
  --combined <report>
  --error <error-report>
  --max-delete <n>
  [--max-delete-size <size> if supported by rclone]
  [--backup-dir <path>]
  [filters]
  [age flags]
  [--dry-run]
```

`archive`：

```text
# runner first counts selected source files with lsjson/lsf and enforces safety.max_delete
rclone move <source_task_path> <target_task_path>
  --config /config/rclone/rclone.conf
  --combined <report>
  --error <error-report>
  [--delete-empty-src-dirs]
  [filters]
  [age flags]
  [--dry-run]
```

`prune`：

```text
# runner first counts selected source files with lsjson/lsf and enforces safety.max_delete
rclone delete <source_task_path>
  --config /config/rclone/rclone.conf
  --error <error-report>
  [--rmdirs]
  [filters]
  [age flags]
  [--dry-run]
```

## 执行流程

1. 启动时打印 rclone 版本、runner 版本、当前时区。
2. 如果存在 `/config/jobs.yaml`，读取 YAML 并做 schema 校验；否则读取 `RCLONE_SYNC_*` 环境变量并生成一个单 job 配置。
3. 将 `RCLONE_SYNC_SOURCE_CONFIG_*` / `RCLONE_SYNC_TARGET_CONFIG_*` 映射成 rclone 官方 `RCLONE_CONFIG_SRC_*` / `RCLONE_CONFIG_DST_*`，并保留用户直接传入的 `RCLONE_CONFIG_*`。
4. 合并 `global`、`defaults`、job、directory item 四层配置。
5. 规范化用户友好字段：
   - 将 `RCLONE_SYNC_DATE_BEFORE` / `RCLONE_SYNC_DATE_AFTER` 或 YAML `date` 换算成 rclone `--min-age` / `--max-age`。
   - 将 `RCLONE_SYNC_EXCLUDE_EXTENSIONS` 或 YAML `filters.exclude_extensions` 展开成 `--exclude **/*.ext`。
   - 合并 extension exclude、glob exclude、exclude file，保留 rclone 原生过滤顺序。
6. 对破坏性作业做安全校验：
   - `mirror` 必须配置 `max_delete` 或显式 `allow_unlimited_delete: true`。
   - `mirror`、`archive`、`prune` 真实执行必须同时满足 `dry_run: false` 和 `RCLONE_SYNC_ALLOW_DESTRUCTIVE=true`。
   - 相对时间 `older_than/newer_than` 和绝对日期 `date.before/date.after` 可以组合，但生成的时间窗口不能为空；如果 `after` 晚于 `before`，直接失败。
   - `archive` 和 `prune` 在真实执行前必须先用 `rclone lsjson --recursive --files-only` 或 `rclone lsf` 统计候选文件数量和体积，超过 `max_delete` 或 `max_delete_size` 则中止。
   - 默认拒绝 `source_root` 或 `target_root` 是空路径、`/`、`remote:` 根路径，除非 `allow_root_path: true`。
   - 默认拒绝源和目标重叠路径。
   - 默认拒绝 `directories` 里的绝对路径、`..`、空白路径；只有 `.` 可以表示 root。
   - 默认拒绝 `--delete-excluded`，除非 `allow_delete_excluded: true`。
7. 为每个 `directories` item 生成 task，并获取 `/state/locks/<job>.lock`，避免同一个作业重叠运行。
8. 对 destructive job 先执行 dry-run 预检，生成 `command.json`；如果当前 rclone 支持报告参数，还会生成 `combined.txt` 和 `errors.txt`。
9. 如果 job 处于真实执行模式，执行真实 rclone 命令。
10. 可选执行 `rclone check` 或 `rclone size` 作为后置校验。
11. 记录退出码、耗时、传输统计、删除统计、错误摘要。
12. 根据结果发送通知，第一版可预留 webhook 接口。

## 安全策略

默认值应偏保守：

- 全局默认 `dry_run_default: true`。
- 所有会删除数据的 operation 都要求显式关闭 dry-run，并设置 `RCLONE_SYNC_ALLOW_DESTRUCTIVE=true`。
- `mirror` 删除的是目标端多余文件，必须配置 `max_delete`。
- `archive` 和 `prune` 删除的是源端文件，runner 必须先枚举候选文件并套用 `max_delete` / `max_delete_size`，不能只依赖 rclone 命令自身。
- `archive` 删除的是源端已成功移动文件，必须带时间过滤或显式 `allow_all_source_move: true`。
- `prune` 只删除源端文件，必须带 `age` 或 `include`，不能无过滤删除整个路径。
- `--delete-excluded` 默认禁用，因为它会删除目标端被过滤排除的文件。
- 首次真实执行某个 destructive job 时，要求先存在最近一次 dry-run 报告，且报告未过期。
- 每次运行都保存 `command.json`；如果当前 rclone 支持 `--combined`，还会保存 rclone combined 报告，方便审计。

## 通用性设计

- 所有 remote 都只作为字符串传给 rclone，不在 wrapper 中硬编码 backend。
- 支持 rclone config file、rclone 环境变量、连接字符串三种 remote 配置方式。
- `directories` 使用相同相对路径拼接，能覆盖 bucket 子目录、本地目录、Google Drive 文件夹等场景，并保证两边目录结构一致。
- 性能参数做通用字段，例如 `transfers`、`checkers`、`bwlimit`、`tpslimit`，backend 专属参数放进受控 `extra_flags_allowlist`。
- 过滤使用 rclone 原生 filter 体系，支持 `exclude`、`include`、`exclude_from`、`filter_from`、`files_from`、`exclude_if_present`。
- 报告格式独立于 backend，便于后续接入 Prometheus、Webhook、邮件或 Slack。

## Docker Compose 草案

```yaml
services:
  rclone-sync:
    build: .
    container_name: rclone-sync
    restart: unless-stopped
    environment:
      TZ: Asia/Shanghai
      RUN_ON_STARTUP: "false"
      RCLONE_SYNC_CONFIG: /config/jobs.yaml
    volumes:
      - ./config/jobs.yaml:/config/jobs.yaml:ro
      - ./filters:/filters:ro
      - ./logs:/logs
      - ./state:/state
      - ~/.config/rclone:/config/rclone
      - /mnt/backup:/data/backups
      - /srv/source:/data/source:ro
```

## 审计

| 风险 | 影响 | 设计控制 |
| --- | --- | --- |
| `mirror` 配错源路径导致目标被大量删除 | 高 | 默认 dry-run、`max_delete`、根路径拒绝、最近 dry-run 报告要求、`backup_dir` 建议 |
| `archive` 或 `prune` 删除源端过多文件 | 高 | 必须显式关闭 dry-run、必须配置时间或 include、破坏性确认环境变量、runner 预检候选数量和体积 |
| `--delete-excluded` 与过滤条件组合误删目标 | 高 | 默认禁用，只能通过专门字段启用，不能经 `extra_flags` 注入 |
| 时间窗口不符合预期 | 中高 | 文档明确基于修改时间；预检报告必须展示候选文件；建议先用小目录验证 3d/3M 规则 |
| 不同 backend 的 modtime、hash、metadata 能力不同 | 中 | 默认用 rclone 标准比较；可选 `checksum`、`size_only`、`metadata`，并在 job 报告记录启用项 |
| 多目录作业非原子 | 中 | 每个 directory 独立 task、独立报告、失败可重试；不承诺跨目录事务 |
| rclone token 刷新失败 | 中 | 按官方建议挂载整个 `/config/rclone` 目录且可写，不只挂单个 conf 文件 |
| Shell 注入或路径含空格导致命令错解析 | 中 | runner 使用 argv 数组，不拼 shell 字符串 |
| API 限速或云端配额 | 中 | 支持 `bwlimit`、`tpslimit`、`transfers`、`checkers`、重试参数 |
| 本地文件权限错乱 | 中 | 支持 `PUID` / `PGID` 或 Docker `user:`，本地 volume 明确读写权限 |
| 日志泄露路径或 remote 名称 | 低中 | 不把 secret 放入 jobs.yaml；日志默认不打印环境变量和 rclone.conf |

审计结论：

- 架构上应优先实现 `copy`、`mirror`、`archive`、`prune` 四个明确 operation，而不是做一个接受任意 rclone 命令的 Docker。这样功能更通用，但删除风险可控。
- 第一版应默认 dry-run，并把“真实删除”设计成需要多重显式确认的行为。对备份和迁移类工具来说，误删防护比少写几个配置字段更重要。
- 时间窗口能力可以满足“同步 3 天前或 3 个月前的数据，然后删除源端”的需求，推荐用 `archive + age.older_than` 表达。
- 需要在实现阶段补充最小测试矩阵：本地到本地 dry-run、本地到本地 copy、mirror 删除上限、archive 老文件、prune include/exclude、路径重叠拒绝。

## 后续实现顺序

1. 添加 `Dockerfile`、`docker-compose.yml`、`README.md`，先主打 Docker Hub env-only 使用。
2. 实现 env-only 解析器：`RCLONE_SYNC_*` 到内部单 job 配置，`SOURCE_CONFIG_*` / `TARGET_CONFIG_*` 到 rclone remote env。
3. 实现 YAML 配置解析、参数渲染、安全校验。
4. 实现 run-once 和 cron 调度入口。
5. 添加本地到本地的集成测试脚本，不依赖真实云端凭证。
6. 添加 B2、Google Drive、S3/R2/MinIO 的 env 示例，不提交任何凭证。
