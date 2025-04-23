#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查参数
if [ $# -lt 2 ]; then
    echo -e "${RED}用法: $0 <服务器IP> <密码> [端口] [加密方式]${NC}"
    echo -e "示例: $0 1.2.3.4 your_password 8388 chacha20-ietf-poly1305"
    exit 1
fi

# 设置变量
SERVER_IP=$1
PASSWORD=$2
PORT=${3:-8388}
METHOD=${4:-"chacha20-ietf-poly1305"}

# 生成配置
cat > config.yaml << EOF
proxies:
  - name: "Shadowsocks"
    type: ss
    server: $SERVER_IP
    port: $PORT
    cipher: $METHOD
    password: $PASSWORD

proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
      - "Shadowsocks"

rules:
  - MATCH,PROXY
EOF

# 生成 base64 编码的订阅链接
BASE64_CONFIG=$(base64 -w 0 config.yaml)
SUB_URL="https://你的域名/sub?config=$BASE64_CONFIG"

echo -e "\n${GREEN}配置已生成:${NC}"
echo -e "${YELLOW}配置文件:${NC} config.yaml"
echo -e "${YELLOW}订阅链接:${NC} $SUB_URL"
echo -e "\n${GREEN}使用方法:${NC}"
echo "1. 将订阅链接添加到 Clash Verge"
echo "2. 更新配置"
echo "3. 选择节点并启用"

# 清理临时文件
rm config.yaml 