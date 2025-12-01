FROM python:3.12-slim

# CI/CD 配置变量
ENV ENABLE_CICD=true
ENV START_COMMAND="python main.py"
ENV UV_INDEX_URL=https://mirrors.aliyun.com/pypi/simple

# 设置工作目录
WORKDIR /app

# 设置 apt 国内源（阿里云镜像 - Trixie）
RUN rm -f /etc/apt/sources.list.d/debian.sources && \
    echo "deb http://mirrors.aliyun.com/debian/ trixie main contrib non-free non-free-firmware" > /etc/apt/sources.list && \
    echo "deb http://mirrors.aliyun.com/debian-security/ trixie-security main contrib non-free non-free-firmware" >> /etc/apt/sources.list

# 安装系统依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    git \
    cron \
    && rm -rf /var/lib/apt/lists/*

# 安装 uv
RUN pip install --no-cache-dir -i https://mirrors.aliyun.com/pypi/simple uv

# 复制依赖文件
COPY pyproject.toml uv.lock* ./

# 安装 Python 依赖到系统环境
RUN uv pip install --system --no-cache --index-url https://mirrors.aliyun.com/pypi/simple -r pyproject.toml

# 设置环境变量
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# 复制启动脚本
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
