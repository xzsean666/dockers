# 使用Node.js 20.12.2作为基础镜像
FROM node:20.12.2

# 安装cron和其他必要工具，并清理缓存
RUN apt-get update && \
    apt-get install -y --no-install-recommends cron curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 创建工作目录
WORKDIR /app

# 复制crontab管理脚本并设置执行权限
COPY manage-crontab.sh /usr/local/bin/manage-crontab
RUN chmod +x /usr/local/bin/manage-crontab
RUN ln -s /usr/local/bin/manage-crontab /usr/local/bin/mc

# 创建 cron 日志文件并设置适当的权限
RUN touch /var/log/cron.log && chmod 0644 /var/log/cron.log

# 设置启动命令
CMD ["sh", "-c", "cron && tail -f /var/log/cron.log"]
