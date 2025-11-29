FROM python:3.12-slim

# CI/CD 配置变量
ENV ENABLE_CICD=false
ENV START_COMMAND="uv run main.py"

# 设置工作目录
WORKDIR /app

# 安装系统依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    git \
    cron \
    && rm -rf /var/lib/apt/lists/*

# 安装 uv
RUN pip install --no-cache-dir uv

# 复制依赖文件
COPY pyproject.toml uv.lock* ./

# 安装 Python 依赖到系统环境（不创建虚拟环境）
RUN uv pip install --system --no-cache -r pyproject.toml

# 设置环境变量
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# 复制启动脚本
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
