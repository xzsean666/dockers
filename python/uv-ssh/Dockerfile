# 使用自定义的基础镜像
FROM uv-ssh-base:latest

# 设置代理环境变量
ENV http_proxy="http://astrid:4CBa737x10IgZU676z@31.58.137.32:13128"
ENV https_proxy="http://astrid:4CBa737x10IgZU676z@31.58.137.32:13128"

# 接收构建参数但不保留为环境变量
ARG GITHUB_TOKEN

# 复制项目文件到临时位置进行构建
COPY pyproject.toml /tmp/build/

# 配置 git 使用 token，创建虚拟环境，安装依赖
RUN cd /tmp/build && \
    # 配置git认证
    git config --global url."https://${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/" && \
    # 验证git配置
    git config --global --list | grep url && \
    # 创建虚拟环境
    uv venv /usr/local/quantvenv --python 3.12 && \
    echo 'source /usr/local/quantvenv/bin/activate' >> /root/.bashrc && \
    # 安装pip
    /usr/local/quantvenv/bin/python -m ensurepip --upgrade && \
    # 设置环境变量确保uv使用正确的虚拟环境
    export UV_PROJECT_ENVIRONMENT=/usr/local/quantvenv && \
    # 创建锁文件（这里可能需要访问私有仓库）
    echo "Creating lock file..." && \
    uv lock --verbose && \
    # 同步依赖
    echo "Syncing dependencies..." && \
    uv sync --frozen --verbose && \
    # 验证安装
    echo "Verifying installation..." && \
    ls -la /usr/local/quantvenv/lib/python*/site-packages/ | grep -i nexus || echo "nexustrader not found in site-packages" && \
    # 清理 git 配置和临时文件
    git config --global --unset url."https://${GITHUB_TOKEN}@github.com/".insteadOf && \
    rm -rf /tmp/build

# 移除代理环境变量
ENV http_proxy=""
ENV https_proxy=""

# 创建启动脚本来动态设置密码和优化SSH
RUN echo '#!/bin/bash\n\
    set -e\n\
    \n\
    # 设置root密码（如果提供了ROOT_PASSWORD环境变量）\n\
    if [ -n "$ROOT_PASSWORD" ]; then\n\
    echo "root:$ROOT_PASSWORD" | chpasswd\n\
    else\n\
    echo "Warning: No ROOT_PASSWORD environment variable provided"\n\
    fi\n\
    \n\
    # 优化SSH登录速度\n\
    sed -i "s/^#\\?UseDNS.*/UseDNS no/" /etc/ssh/sshd_config\n\
    sed -i "s/^#\\?GSSAPIAuthentication.*/GSSAPIAuthentication no/" /etc/ssh/sshd_config\n\
    sed -i "s/^hosts:.*/hosts: files/" /etc/nsswitch.conf\n\
    \n\
    # 启动SSH服务\n\
    exec /usr/sbin/sshd -D\n\
    ' > /start.sh && \
    chmod +x /start.sh

# 使用启动脚本
CMD ["/start.sh"] 