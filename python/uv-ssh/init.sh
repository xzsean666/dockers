#!/bin/bash

# UV SSH Docker 初始化脚本
# 创建必要的目录并设置权限，适配 sudo 执行和容器内 root 用户

echo "正在初始化 UV SSH Docker 环境..."

# 创建目录
mkdir -p root
mkdir -p ssh_keys

# 检测实际的用户（即使用 sudo 执行也能获取原始用户）
if [ -n "$SUDO_USER" ]; then
    # 如果是通过 sudo 执行，获取原始用户信息
    REAL_USER="$SUDO_USER"
    REAL_USER_ID=$(id -u "$SUDO_USER")
    REAL_GROUP_ID=$(id -g "$SUDO_USER")
    echo "检测到 sudo 执行，原始用户: $REAL_USER (UID: $REAL_USER_ID, GID: $REAL_GROUP_ID)"
else
    # 直接执行
    REAL_USER=$(whoami)
    REAL_USER_ID=$(id -u)
    REAL_GROUP_ID=$(id -g)
    echo "当前用户: $REAL_USER (UID: $REAL_USER_ID, GID: $REAL_GROUP_ID)"
fi

# 设置目录权限
# 容器内是 root (UID 0)，但我们需要确保宿主机用户也能访问
chmod 755 root
chmod 755 ssh_keys

# 设置目录所有者为执行用户，确保可以访问
chown "$REAL_USER_ID:$REAL_GROUP_ID" root
chown "$REAL_USER_ID:$REAL_GROUP_ID" ssh_keys

# 确保目录对所有用户可读写（容器内的 root 和宿主机用户都能访问）
chmod 777 root
chmod 755 ssh_keys  # SSH 目录稍微严格一些

echo "目录创建完成："
echo "  - root/ (所有者: $REAL_USER, 权限: $(ls -ld root | cut -d' ' -f1))"
echo "  - ssh_keys/ (所有者: $REAL_USER, 权限: $(ls -ld ssh_keys | cut -d' ' -f1))"

echo ""
echo "现在可以运行以下命令启动容器："
echo "  docker-compose up -d"
echo "  或者: sudo docker-compose up -d"
echo ""
echo "SSH 连接命令："
echo "  ssh root@localhost -p 10022"
echo "  默认密码: your_password_here"

echo "初始化完成！" 