#!/bin/bash

# 检查是否提供了.env文件
if [ ! -f .env ]; then
    echo "Error: .env file not found!"
    exit 1
fi

# 加载环境变量
source .env

# 验证必需的环境变量
required_vars=(
    "FRP_PORT"
    "DASHBOARD_PORT"
    "DASHBOARD_USER"
    "DASHBOARD_PWD"
    "FRP_TOKEN"
    "ALLOW_PORTS_START"
    "ALLOW_PORTS_END"
    "SERVER_IP"
    "LOCAL_PORTS_START"
    "LOCAL_PORTS_END"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: Environment variable $var is not set!"
        exit 1
    fi
done

# 验证端口号是否为数字
validate_port() {
    if ! [[ "$1" =~ ^[0-9]+$ ]] || [ "$1" -lt 1 ] || [ "$1" -gt 65535 ]; then
        echo "Error: Invalid port number: $1"
        exit 1
    fi
}

validate_port "$FRP_PORT"
validate_port "$DASHBOARD_PORT"
validate_port "$ALLOW_PORTS_START"
validate_port "$ALLOW_PORTS_END"
validate_port "$LOCAL_PORTS_START"
validate_port "$LOCAL_PORTS_END"

# 验证端口范围
if [ "$ALLOW_PORTS_START" -gt "$ALLOW_PORTS_END" ]; then
    echo "Error: ALLOW_PORTS_START ($ALLOW_PORTS_START) must be <= ALLOW_PORTS_END ($ALLOW_PORTS_END)"
    exit 1
fi

if [ "$LOCAL_PORTS_START" -gt "$LOCAL_PORTS_END" ]; then
    echo "Error: LOCAL_PORTS_START ($LOCAL_PORTS_START) must be <= LOCAL_PORTS_END ($LOCAL_PORTS_END)"
    exit 1
fi

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 创建必要的目录
mkdir -p frp/server frp/client

# 生成服务器端配置文件
cat > frp/server/frps.toml << EOF
# 基础配置
bindAddr = "0.0.0.0"
bindPort = ${FRP_PORT}

# Dashboard配置
webServer.addr = "0.0.0.0"
webServer.port = ${DASHBOARD_PORT}
webServer.user = "${DASHBOARD_USER}"
webServer.password = "${DASHBOARD_PWD}"

# 认证配置
auth.method = "token"
auth.token = "${FRP_TOKEN}"

# 端口配置
transport.maxPoolCount = 10
allowPorts = [
    { start = ${ALLOW_PORTS_START}, end = ${ALLOW_PORTS_END} }
]
EOF

# 生成服务器端docker-compose.yml
cat > frp/server/docker-compose.yml << EOF
version: '3'
services:
  frps:
    image: snowdreamtech/frps:0.63.0-alpine
    container_name: frps
    restart: always
    network_mode: host
    volumes:
      - ./frps.toml:/etc/frp/frps.toml
EOF

# 生成客户端配置文件
cat > frp/client/frpc.toml << EOF
serverAddr = "${SERVER_IP}"
serverPort = ${FRP_PORT}
auth.token = "${FRP_TOKEN}"

# 端口转发配置
EOF

# 生成端口转发配置（修复变量引用问题）
for ((local_port=$LOCAL_PORTS_START, remote_port=$ALLOW_PORTS_START; 
      local_port<=$LOCAL_PORTS_END && remote_port<=$ALLOW_PORTS_END; 
      local_port++, remote_port++)); do
    cat >> frp/client/frpc.toml << EOF
[[proxies]]
name = "tcp-${local_port}"
type = "tcp"
localPort = ${local_port}
remotePort = ${remote_port}
EOF
done

# 生成客户端docker-compose.yml
cat > frp/client/docker-compose.yml << EOF
version: '3'
services:
  frpc:
    image: snowdreamtech/frpc:0.63.0-alpine
    container_name: frpc
    restart: always
    network_mode: host
    volumes:
      - ./frpc.toml:/etc/frp/frpc.toml
EOF

echo "FRP configuration files have been generated successfully!"
echo "Server configuration is in frp/server/"
echo "Client configuration is in frp/client/"
echo ""
echo "Configuration summary:"
echo "- FRP Version: snowdreamtech 0.63.0-alpine"
echo "- FRP Port: $FRP_PORT"
echo "- Dashboard: http://localhost:$DASHBOARD_PORT (${DASHBOARD_USER}/${DASHBOARD_PWD})"
echo "- Allowed remote ports: $ALLOW_PORTS_START-$ALLOW_PORTS_END"
echo "- Local ports mapped: $LOCAL_PORTS_START-$LOCAL_PORTS_END"
