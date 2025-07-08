#!/bin/bash

REPO_URL="https://github.com/AstridTechnologies/quant-trade.git"
PROJECT_NAME="nexustrader"
CACHE_FILE="/tmp/${PROJECT_NAME}_git_sha"
LOCK_FILE="/tmp/${PROJECT_NAME}_cicd.lock"
DOCKER_DIR="/hdd16/sean/uv-cursor"

# 检查是否已有实例在运行
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "$(date): CI/CD 脚本已在运行中，跳过本次执行"
    exit 0
fi

# 读取 .env 文件中的 GITHUB_TOKEN
if [ -f "$DOCKER_DIR/.env" ]; then
    source "$DOCKER_DIR/.env"
fi

# 检查是否设置了 GITHUB_TOKEN
if [ -z "$GITHUB_TOKEN" ]; then
    echo "$(date): 错误: 未找到 GITHUB_TOKEN，请检查 .env 文件" >&2
    exit 1
fi

# 构建带认证的仓库URL
AUTH_REPO_URL="https://${GITHUB_TOKEN}@github.com/AstridTechnologies/quant-trade.git"

# 获取远程最新 commit SHA
REMOTE_SHA=$(git ls-remote "$AUTH_REPO_URL" HEAD | cut -f1)

# 获取缓存中的上次 SHA（如果有）
if [ -f "$CACHE_FILE" ]; then
    LOCAL_SHA=$(cat "$CACHE_FILE")
else
    LOCAL_SHA=""
fi

# 如果 SHA 变了，就执行 Docker 重启
if [ "$REMOTE_SHA" != "$LOCAL_SHA" ]; then
    echo "$(date): 检测到新提交，重启 Docker 服务..."
    cd "$DOCKER_DIR" || exit 1
        # 检查基础镜像是否存在，如果不存在则构建
    if ! docker images | grep -q "uv-ssh-base.*latest"; then
        echo "$(date): 基础镜像 uv-ssh-base:latest 不存在，开始构建..."
        sudo docker compose -f docker-compose.base.yml build
        echo "$(date): 基础镜像构建完成"
    else
        echo "$(date): 基础镜像已存在，跳过构建"
    fi
    sudo docker compose down
    sudo docker compose build
    sudo docker compose up -d

    # 更新缓存 SHA
    echo "$REMOTE_SHA" > "$CACHE_FILE"
    echo "$(date): 重启完成，缓存已更新为 $REMOTE_SHA"
else
    echo "$(date): 无新提交，无需操作"
fi

# 锁会在脚本结束时自动释放
