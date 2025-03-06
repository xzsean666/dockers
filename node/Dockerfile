# 使用Node.js 20.12.2作为基础镜像
FROM node:20.12.2

# 创建并配置阿里云源
RUN rm -rf /etc/apt/sources.list.d/* && \
    rm -f /etc/apt/sources.list && \
    echo "deb https://mirrors.aliyun.com/debian/ bookworm main" > /etc/apt/sources.list && \
    echo "deb https://mirrors.aliyun.com/debian-security bookworm-security main" >> /etc/apt/sources.list && \
    echo "deb https://mirrors.aliyun.com/debian/ bookworm-updates main" >> /etc/apt/sources.list

# 更新并安装必要工具
RUN apt-get update && \
    apt-get install -y --no-install-recommends cron curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g pnpm
# 创建工作目录
WORKDIR /app

# 复制crontab管理脚本并设置执行权限
COPY manage-crontab.sh /usr/local/bin/manage-crontab
RUN chmod +x /usr/local/bin/manage-crontab
RUN ln -s /usr/local/bin/manage-crontab /usr/local/bin/mc

# 创建 cron 日志文件并设置适当的权限
RUN touch /var/log/cron.log && chmod 0644 /var/log/cron.log
RUN touch startup.sh
RUN chmod +x startup.sh
# 设置启动命令
CMD ["sh", "-c", "cron && tail -f /var/log/cron.log"]
