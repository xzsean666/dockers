#!/bin/bash

# Docker PostgreSQL 环境配置示例
# 复制此文件并修改为实际配置

# ===== Docker环境配置 =====

# 1. 从宿主机连接到Docker容器 (推荐)
export PGPOOL_HOST="localhost"
export PGPOOL_PORT="5432"  # 根据你的docker-compose.yml中的PGPOOL_PORT设置

# 2. 如果在Docker网络内部运行脚本，使用服务名
# export PGPOOL_HOST="pgpool"  # 使用docker-compose中的服务名
# export PGPOOL_PORT="5432"    # 容器内部端口

# ===== 数据库认证配置 =====
export PGPOOL_USER="postgres"
export PGPOOL_DB="postgres"
export POSTGRESQL_PASSWORD="your_actual_password"  # 替换为实际密码

# ===== 其他配置 =====
export POSTGRESQL_SLAVE_CONTAINER_NAME="postgresql-slave"
export PGPOOL_CONTAINER_NAME="pgpool"
export POSTGRESQL_MASTER_HOST="master_db_host"
export POSTGRESQL_MASTER_PORT_NUMBER="5432"

echo "Docker PostgreSQL 环境配置已加载！"
echo "Pgpool连接: ${PGPOOL_HOST}:${PGPOOL_PORT}"
echo "数据库用户: ${PGPOOL_USER}" 