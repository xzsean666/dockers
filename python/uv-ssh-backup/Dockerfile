# 使用 Ubuntu 22.04 LTS 作为基础镜像
FROM ubuntu:22.04

# 设置非交互式安装，避免安装过程中的提示
ENV DEBIAN_FRONTEND=noninteractive

# 先使用默认源安装证书和基础工具
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# 配置 Ubuntu 阿里云镜像源
RUN rm -rf /etc/apt/sources.list.d/* && \
    rm -f /etc/apt/sources.list && \
    echo "deb https://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse" > /etc/apt/sources.list && \
    echo "deb https://mirrors.aliyun.com/ubuntu/ jammy-security main restricted universe multiverse" >> /etc/apt/sources.list && \
    echo "deb https://mirrors.aliyun.com/ubuntu/ jammy-updates main restricted universe multiverse" >> /etc/apt/sources.list && \
    echo "deb https://mirrors.aliyun.com/ubuntu/ jammy-backports main restricted universe multiverse" >> /etc/apt/sources.list

# 更新源并安装其他软件包
RUN apt-get update && apt-get install -y \
    openssh-server \
    cron \
    sudo \
    vim \
    git \
    python3 \
    python3-pip \
    wget \
    && rm -rf /var/lib/apt/lists/*

# 通过 pip 安装 uv
RUN pip3 install -i https://pypi.tuna.tsinghua.edu.cn/simple uv

# 设置 uv 使用中国镜像源
ENV UV_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple

COPY manage-crontab.sh /usr/local/bin/manage-crontab
RUN chmod +x /usr/local/bin/manage-crontab
RUN ln -s /usr/local/bin/manage-crontab /usr/local/bin/mc

# 配置SSH
RUN mkdir /var/run/sshd && \
    ssh-keygen -A && \
    echo 'root:111111' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# 创建工作目录
WORKDIR /app
RUN mkdir -p /app

# 暴露SSH端口
EXPOSE 22

# 启动SSH服务
CMD ["/usr/sbin/sshd", "-D"] 