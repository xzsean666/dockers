#!/bin/bash

# 检查是否提供了.env文件
if [ ! -f .env ]; then
    echo "Error: .env file not found!"
    exit 1
fi

# 加载环境变量
source .env

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
    image: snowdreamtech/frps
    container_name: frps
    restart: always
    network_mode: host
    volumes:
      - ./frps.toml:/etc/frp/frps.toml
EOF

# 生成客户端配置文件
cat > frp/client/frpc.toml << EOF
serverAddr = "${SERVER_IP}"
serverPort = ${SERVER_PORT}
auth.token = "${FRP_TOKEN}"

# 端口转发配置
EOF

# 生成端口转发配置
for ((local_port=LOCAL_PORTS_START, remote_port=ALLOW_PORTS_START; 
      local_port<=LOCAL_PORTS_END && remote_port<=ALLOW_PORTS_END; 
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
    image: snowdreamtech/frpc
    container_name: frpc
    restart: always
    network_mode: host
    volumes:
      - ./frpc.toml:/etc/frp/frpc.toml
EOF

echo "FRP configuration files have been generated successfully!"
echo "Server configuration is in frp/server/"
echo "Client configuration is in frp/client/"
