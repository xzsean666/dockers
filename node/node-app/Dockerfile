# 使用Node.js官方镜像
FROM node:24.2.0

# 设置pnpm环境变量（遵循官方文档建议）
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

# 直接设置应用配置
ENV USE_PM2=true
ENV APP_MAIN_SCRIPT=dist/main.js
ENV NODE_ENV=production
ENV TIMEZONE=Asia/Shanghai
ENV CRON_ENABLED=false
ENV CRON_JOBS=""
ENV PROJECT_NAME=heartbeat-signal-backend

# 安装必要的系统依赖
RUN apt-get update && apt-get install -y \
    python3 \
    build-essential \
    sqlite3 \
    libsqlite3-dev \
    cron \
    tzdata \
    lsof \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /app

# 启用corepack并安装PM2
RUN corepack enable && npm install -g pm2

COPY . .

# 安装依赖（利用Docker层缓存）
RUN pnpm install

# 创建优化的启动脚本
RUN echo '#!/bin/sh' > /usr/local/bin/start.sh && \
    echo '' >> /usr/local/bin/start.sh && \
    echo '# 切换到工作目录' >> /usr/local/bin/start.sh && \
    echo 'cd /app' >> /usr/local/bin/start.sh && \
    echo '' >> /usr/local/bin/start.sh && \
    echo '# 设置时区' >> /usr/local/bin/start.sh && \
    echo 'if [ "$TIMEZONE" != "" ]; then' >> /usr/local/bin/start.sh && \
    echo '  export TZ=$TIMEZONE' >> /usr/local/bin/start.sh && \
    echo '  ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone' >> /usr/local/bin/start.sh && \
    echo '  echo "✅ 时区设置为: $TIMEZONE"' >> /usr/local/bin/start.sh && \
    echo 'fi' >> /usr/local/bin/start.sh && \
    echo '' >> /usr/local/bin/start.sh && \
    echo '# 检查是否启用Cron' >> /usr/local/bin/start.sh && \
    echo 'if [ "$CRON_ENABLED" = "true" ]; then' >> /usr/local/bin/start.sh && \
    echo '  echo "⏰ 配置定时任务..."' >> /usr/local/bin/start.sh && \
    echo '  mkdir -p /var/log && touch /var/log/cron.log' >> /usr/local/bin/start.sh && \
    echo '  echo "# 自动生成的定时任务" > /etc/crontabs/root' >> /usr/local/bin/start.sh && \
    echo '  if [ "$CRON_JOBS" != "" ]; then' >> /usr/local/bin/start.sh && \
    echo '    echo "$CRON_JOBS" | tr ";" "\n" | while read -r job; do' >> /usr/local/bin/start.sh && \
    echo '      if [ "$job" != "" ]; then' >> /usr/local/bin/start.sh && \
    echo '        echo "$job" >> /etc/crontabs/root' >> /usr/local/bin/start.sh && \
    echo '        echo "  添加定时任务: $job"' >> /usr/local/bin/start.sh && \
    echo '      fi' >> /usr/local/bin/start.sh && \
    echo '    done' >> /usr/local/bin/start.sh && \
    echo '  fi' >> /usr/local/bin/start.sh && \
    echo '  crond -b' >> /usr/local/bin/start.sh && \
    echo '  echo "✅ Cron服务已启动"' >> /usr/local/bin/start.sh && \
    echo 'else' >> /usr/local/bin/start.sh && \
    echo '  echo "⏭️  跳过Cron服务"' >> /usr/local/bin/start.sh && \
    echo 'fi' >> /usr/local/bin/start.sh && \
    echo '' >> /usr/local/bin/start.sh && \


    echo '# 使用pm2.sh脚本来管理应用启动' >> /usr/local/bin/start.sh && \
    echo 'if [ "$USE_PM2" = "true" ]; then' >> /usr/local/bin/start.sh && \
    echo '  echo "🚀 使用pm2.sh脚本启动应用..."' >> /usr/local/bin/start.sh && \
    echo '  if [ -f "./pm2.sh" ]; then' >> /usr/local/bin/start.sh && \
    echo '    # 启动PM2应用' >> /usr/local/bin/start.sh && \
    echo '    ./pm2.sh --start $APP_MAIN_SCRIPT' >> /usr/local/bin/start.sh && \
    echo '    if [ $? -eq 0 ]; then' >> /usr/local/bin/start.sh && \
    echo '      echo "✅ PM2应用启动成功"' >> /usr/local/bin/start.sh && \
    echo '      # 使用pm2-runtime保持容器运行' >> /usr/local/bin/start.sh && \
    echo '      pm2 logs --raw' >> /usr/local/bin/start.sh && \
    echo '    else' >> /usr/local/bin/start.sh && \
    echo '      echo "❌ PM2应用启动失败"' >> /usr/local/bin/start.sh && \
    echo '      exit 1' >> /usr/local/bin/start.sh && \
    echo '    fi' >> /usr/local/bin/start.sh && \
    echo '  else' >> /usr/local/bin/start.sh && \
    echo '    echo "❌ 找不到pm2.sh脚本"' >> /usr/local/bin/start.sh && \
    echo '    exit 1' >> /usr/local/bin/start.sh && \
    echo '  fi' >> /usr/local/bin/start.sh && \
    echo 'else' >> /usr/local/bin/start.sh && \
    echo '  echo "⏭️  跳过PM2服务"' >> /usr/local/bin/start.sh && \
    echo '  if [ "$APP_MAIN_SCRIPT" != "" ]; then' >> /usr/local/bin/start.sh && \
    echo '    echo "🔄 直接运行应用: $APP_MAIN_SCRIPT"' >> /usr/local/bin/start.sh && \
    echo '    node "$APP_MAIN_SCRIPT"' >> /usr/local/bin/start.sh && \
    echo '  else' >> /usr/local/bin/start.sh && \
    echo '    echo "❌ 未配置应用启动脚本"' >> /usr/local/bin/start.sh && \
    echo '    tail -f /dev/null' >> /usr/local/bin/start.sh && \
    echo '  fi' >> /usr/local/bin/start.sh && \
    echo 'fi' >> /usr/local/bin/start.sh && \
    chmod +x /usr/local/bin/start.sh

# 启动命令
ENTRYPOINT ["/usr/local/bin/start.sh"] 