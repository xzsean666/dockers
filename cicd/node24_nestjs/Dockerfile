FROM node:24.10

# CI/CD 配置变量
ENV ENABLE_CICD=true
ENV START_COMMAND="pnpm install && pnpm build && pnpm start:prod"

# 设置工作目录
WORKDIR /app

# 设置 apt 国内源（阿里云镜像 - Bookworm）
RUN rm -f /etc/apt/sources.list.d/debian.sources && \
    echo "deb http://mirrors.aliyun.com/debian/ bookworm main contrib non-free non-free-firmware" > /etc/apt/sources.list && \
    echo "deb http://mirrors.aliyun.com/debian-security/ bookworm-security main contrib non-free non-free-firmware" >> /etc/apt/sources.list

# 安装系统依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    cron \
    && rm -rf /var/lib/apt/lists/*

# 安装 pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

# 设置 pnpm 使用淘宝镜像源
RUN pnpm config set registry https://registry.npmmirror.com

# 复制 package.json 并安装依赖（lock 文件可选）
COPY package.json ./

# 安装依赖（允许所有构建脚本）
ENV CI=true
# 如果没有 pnpm-workspace.yaml，创建默认配置允许所有构建

COPY pnpm-workspace.yaml ./ 
COPY pnpm-lock.yaml ./

RUN pnpm install

# 复制启动脚本
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
