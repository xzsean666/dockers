# 使用Node.js 24.2.0作为基础镜像
FROM node:24.2.0

# 设置 pnpm 环境变量（遵循官方文档建议）
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

# 创建并配置阿里云源
RUN rm -rf /etc/apt/sources.list.d/* && \
    rm -f /etc/apt/sources.list && \
    echo "deb https://mirrors.aliyun.com/debian/ bookworm main" > /etc/apt/sources.list && \
    echo "deb https://mirrors.aliyun.com/debian-security bookworm-security main" >> /etc/apt/sources.list && \
    echo "deb https://mirrors.aliyun.com/debian/ bookworm-updates main" >> /etc/apt/sources.list

# 更新并安装 Playwright 所需的依赖
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    cron \
    curl \
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

# 设置显示环境变量
ENV DISPLAY=:99

# 启用 corepack 并安装 pnpm 和 pm2
RUN corepack enable && npm install -g pm2

# 创建工作目录
WORKDIR /app

# 使用pnpm安装playwright，然后用npx下载浏览器
RUN pnpm add -g playwright@latest && \
    npx playwright install --with-deps

# 复制crontab管理脚本并设置执行权限
COPY manage-crontab.sh /usr/local/bin/manage-crontab
RUN chmod +x /usr/local/bin/manage-crontab
RUN ln -s /usr/local/bin/manage-crontab /usr/local/bin/mc

# 创建 cron 日志文件并设置适当的权限
RUN touch /var/log/cron.log && chmod 0644 /var/log/cron.log

# 创建启动脚本
RUN echo '#!/bin/bash' > /usr/local/bin/start.sh && \
    echo '' >> /usr/local/bin/start.sh && \
    echo '# 确保 pnpm 配置正确' >> /usr/local/bin/start.sh && \
    echo 'pnpm config set package-import-method hardlink' >> /usr/local/bin/start.sh && \
    echo 'pnpm config set symlink false' >> /usr/local/bin/start.sh && \
    echo '' >> /usr/local/bin/start.sh && \
    echo '# 启动 Xvfb 虚拟显示器' >> /usr/local/bin/start.sh && \
    echo 'echo "🖥️  启动虚拟显示器..."' >> /usr/local/bin/start.sh && \
    echo 'Xvfb :99 -screen 0 1920x1080x24 &' >> /usr/local/bin/start.sh && \
    echo '' >> /usr/local/bin/start.sh && \
    echo '# 执行应用的启动脚本（如果存在）' >> /usr/local/bin/start.sh && \
    echo 'if [ -f /app/startup.sh ]; then' >> /usr/local/bin/start.sh && \
    echo '  echo "🚀 执行应用启动脚本..."' >> /usr/local/bin/start.sh && \
    echo '  /app/startup.sh' >> /usr/local/bin/start.sh && \
    echo 'fi' >> /usr/local/bin/start.sh && \
    echo '' >> /usr/local/bin/start.sh && \
    echo '# 启动 cron 服务' >> /usr/local/bin/start.sh && \
    echo 'echo "⏰ 启动 cron 服务..."' >> /usr/local/bin/start.sh && \
    echo 'cron' >> /usr/local/bin/start.sh && \
    echo '' >> /usr/local/bin/start.sh && \
    echo '# 保持容器运行' >> /usr/local/bin/start.sh && \
    echo 'tail -f /var/log/cron.log' >> /usr/local/bin/start.sh && \
    chmod +x /usr/local/bin/start.sh

# 设置启动命令
CMD ["/usr/local/bin/start.sh"]
