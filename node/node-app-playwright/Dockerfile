# 使用Node.js 24.2.0作为基础镜像 (支持Playwright)
FROM node:24.2.0

# 设置pnpm环境变量（遵循官方文档建议）
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

# 创建并配置阿里云源
RUN rm -rf /etc/apt/sources.list.d/* && \
    rm -f /etc/apt/sources.list && \
    echo "deb https://mirrors.aliyun.com/debian/ bookworm main" > /etc/apt/sources.list && \
    echo "deb https://mirrors.aliyun.com/debian-security bookworm-security main" >> /etc/apt/sources.list && \
    echo "deb https://mirrors.aliyun.com/debian/ bookworm-updates main" >> /etc/apt/sources.list

# 更新并安装 Playwright 所需的依赖和系统工具
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    cron \
    curl \
    python3 \
    python3-pip \
    python3-dev \
    make \
    g++ \
    gcc \
    libc6-dev \
    libsqlite3-dev \
    pkg-config \
    libglib2.0-0 \
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libdbus-1-3 \
    libxcb1 \
    libxkbcommon0 \
    libx11-6 \
    libxcomposite1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libpango-1.0-0 \
    libcairo2 \
    libasound2 \
    xvfb \
    libxtst6 \
    libxshmfence1 \
    fonts-noto-color-emoji \
    fonts-liberation \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 设置显示环境变量 (Playwright需要)
ENV DISPLAY=:99

# 设置工作目录
WORKDIR /app

# 启用corepack（这会自动启用pnpm）并安装PM2
RUN corepack enable && npm install -g pm2

# 复制package.json文件（利用Docker层缓存）
COPY package.json pnpm-lock.yaml* ./

# 优化pnpm配置（使用默认缓存位置）
RUN pnpm config set package-import-method hardlink --global && \
    pnpm config set symlink false --global && \
    pnpm config list

# 创建启动脚本
RUN echo '#!/bin/bash' > /usr/local/bin/start.sh && \
    echo '' >> /usr/local/bin/start.sh && \
    echo '# 切换到工作目录' >> /usr/local/bin/start.sh && \
    echo 'cd /app' >> /usr/local/bin/start.sh && \
    echo '' >> /usr/local/bin/start.sh && \
    echo '# 加载配置文件' >> /usr/local/bin/start.sh && \
    echo 'if [ ! -f ".docker.config" ]; then' >> /usr/local/bin/start.sh && \
    echo '  echo "❌ 未找到 .docker.config 配置文件"' >> /usr/local/bin/start.sh && \
    echo '  exit 1' >> /usr/local/bin/start.sh && \
    echo 'fi' >> /usr/local/bin/start.sh && \
    echo '' >> /usr/local/bin/start.sh && \
    echo '# 加载环境变量' >> /usr/local/bin/start.sh && \
    echo 'set -a' >> /usr/local/bin/start.sh && \
    echo '. ./.docker.config' >> /usr/local/bin/start.sh && \
    echo 'set +a' >> /usr/local/bin/start.sh && \
    echo '' >> /usr/local/bin/start.sh && \
    echo '# 设置时区' >> /usr/local/bin/start.sh && \
    echo 'if [ "$TIMEZONE" != "" ]; then' >> /usr/local/bin/start.sh && \
    echo '  export TZ=$TIMEZONE' >> /usr/local/bin/start.sh && \
    echo '  ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone' >> /usr/local/bin/start.sh && \
    echo '  echo "✅ 时区设置为: $TIMEZONE"' >> /usr/local/bin/start.sh && \
    echo 'fi' >> /usr/local/bin/start.sh && \
    echo '' >> /usr/local/bin/start.sh && \
    echo '# 确保pnpm配置正确' >> /usr/local/bin/start.sh && \
    echo 'pnpm config set package-import-method hardlink' >> /usr/local/bin/start.sh && \
    echo 'pnpm config set symlink false' >> /usr/local/bin/start.sh && \
    echo '' >> /usr/local/bin/start.sh && \
    echo '# 启动 Xvfb 虚拟显示器 (Playwright需要)' >> /usr/local/bin/start.sh && \
    echo 'echo "🖥️  启动虚拟显示器..."' >> /usr/local/bin/start.sh && \
    echo 'Xvfb :99 -screen 0 1920x1080x24 &' >> /usr/local/bin/start.sh && \
    echo '' >> /usr/local/bin/start.sh && \
    echo '# 检查并安装依赖（利用现有缓存）' >> /usr/local/bin/start.sh && \
    echo 'if [ ! -d "node_modules" ] || [ "package.json" -nt "node_modules" ]; then' >> /usr/local/bin/start.sh && \
    echo '  echo "📦 安装依赖中...（利用现有缓存）"' >> /usr/local/bin/start.sh && \
    echo '  pnpm install --frozen-lockfile' >> /usr/local/bin/start.sh && \
    echo '  echo "✅ 依赖安装完成"' >> /usr/local/bin/start.sh && \
    echo 'else' >> /usr/local/bin/start.sh && \
    echo '  echo "⏭️  依赖已存在，跳过安装"' >> /usr/local/bin/start.sh && \
    echo 'fi' >> /usr/local/bin/start.sh && \
    echo '' >> /usr/local/bin/start.sh && \
    echo '# 安装Playwright浏览器（如果playwright存在于依赖中）' >> /usr/local/bin/start.sh && \
    echo 'if [ -f "node_modules/.bin/playwright" ]; then' >> /usr/local/bin/start.sh && \
    echo '  echo "🎭 安装Playwright浏览器..."' >> /usr/local/bin/start.sh && \
    echo '  npx playwright install --with-deps' >> /usr/local/bin/start.sh && \
    echo '  echo "✅ Playwright浏览器安装完成"' >> /usr/local/bin/start.sh && \
    echo 'else' >> /usr/local/bin/start.sh && \
    echo '  echo "⏭️  未检测到Playwright依赖，跳过浏览器安装"' >> /usr/local/bin/start.sh && \
    echo 'fi' >> /usr/local/bin/start.sh && \
    echo '' >> /usr/local/bin/start.sh && \
    echo '# 检查是否启用Cron' >> /usr/local/bin/start.sh && \
    echo 'if [ "$CRON_ENABLED" = "true" ]; then' >> /usr/local/bin/start.sh && \
    echo '  echo "⏰ 配置定时任务..."' >> /usr/local/bin/start.sh && \
    echo '  mkdir -p /var/log && touch /var/log/cron.log' >> /usr/local/bin/start.sh && \
    echo '  echo "# 自动生成的定时任务" > /etc/cron.d/app-cron' >> /usr/local/bin/start.sh && \
    echo '  if [ "$CRON_JOBS" != "" ]; then' >> /usr/local/bin/start.sh && \
    echo '    echo "$CRON_JOBS" | tr ";" "\n" | while read -r job; do' >> /usr/local/bin/start.sh && \
    echo '      if [ "$job" != "" ]; then' >> /usr/local/bin/start.sh && \
    echo '        echo "$job" >> /etc/cron.d/app-cron' >> /usr/local/bin/start.sh && \
    echo '        echo "  添加定时任务: $job"' >> /usr/local/bin/start.sh && \
    echo '      fi' >> /usr/local/bin/start.sh && \
    echo '    done' >> /usr/local/bin/start.sh && \
    echo '  fi' >> /usr/local/bin/start.sh && \
    echo '  chmod 0644 /etc/cron.d/app-cron' >> /usr/local/bin/start.sh && \
    echo '  cron' >> /usr/local/bin/start.sh && \
    echo '  echo "✅ Cron服务已启动"' >> /usr/local/bin/start.sh && \
    echo 'else' >> /usr/local/bin/start.sh && \
    echo '  echo "⏭️  跳过Cron服务"' >> /usr/local/bin/start.sh && \
    echo 'fi' >> /usr/local/bin/start.sh && \
    echo '' >> /usr/local/bin/start.sh && \
    echo '# 检查是否启用PM2' >> /usr/local/bin/start.sh && \
    echo 'if [ "$PM2_ENABLED" = "true" ]; then' >> /usr/local/bin/start.sh && \
    echo '  echo "🚀 启动PM2应用: $PM2_NAME"' >> /usr/local/bin/start.sh && \
    echo '  pm2-runtime start "$PM2_SCRIPT" --name "$PM2_NAME"' >> /usr/local/bin/start.sh && \
    echo 'else' >> /usr/local/bin/start.sh && \
    echo '  echo "⏭️  跳过PM2服务"' >> /usr/local/bin/start.sh && \
    echo '  if [ "$APP_MAIN_SCRIPT" != "" ]; then' >> /usr/local/bin/start.sh && \
    echo '    echo "🔄 直接运行应用: $APP_MAIN_SCRIPT"' >> /usr/local/bin/start.sh && \
    echo '    node "$APP_MAIN_SCRIPT"' >> /usr/local/bin/start.sh && \
    echo '  else' >> /usr/local/bin/start.sh && \
    echo '    echo "❌ 未配置应用启动脚本"' >> /usr/local/bin/start.sh && \
    echo '    tail -f /var/log/cron.log' >> /usr/local/bin/start.sh && \
    echo '  fi' >> /usr/local/bin/start.sh && \
    echo 'fi' >> /usr/local/bin/start.sh && \
    chmod +x /usr/local/bin/start.sh

# 启动命令
CMD ["/usr/local/bin/start.sh"] 