#!/bin/bash

# WireGuard 全互通 VPN 配置生成脚本
# 用于创建多节点全互通 VPN 网络，让机器人可以互相访问

set -e  # 遇到错误立即退出

# 配置变量
NETWORK_BASE="10.0.100"  # VPN 网络段：10.0.100.0/24
DEFAULT_START_PORT=51820  # 默认起始端口

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示使用方法
usage() {
    echo "WireGuard 全互通 VPN 配置生成脚本"
    echo ""
    echo "用法:"
    echo "  $0 <节点数量> [起始端口] [公网IP列表...]"
    echo ""
    echo "参数:"
    echo "  节点数量: 要创建的节点数量 (必需)"
    echo "  起始端口: WireGuard 监听端口起始值 (可选, 默认: $DEFAULT_START_PORT)"
    echo "  公网IP列表: 各节点的公网IP地址 (可选，无公网IP可省略)"
    echo ""
    echo "网络拓扑: 全互通 (Mesh)"
    echo "  - 每个节点都可以直接与其他所有节点通信"
    echo ""
    echo "示例:"
    echo "  $0 3                             # 创建3个节点，使用默认端口"
    echo "  $0 3 51830                       # 创建3个节点，从端口51830开始"
    echo "  $0 3 51820 192.168.1.10           # 只有节点1有公网IP"
    echo "  $0 4 51820 1.2.3.4 5.6.7.8        # 节点1和节点3有公网IP"
    echo ""
    echo "生成的网络:"
    echo "  - 节点1: ${NETWORK_BASE}.1:起始端口"
    echo "  - 节点2: ${NETWORK_BASE}.2:起始端口+1"
    echo "  - 节点3: ${NETWORK_BASE}.3:起始端口+2"
    echo "  - ..."
    echo ""
    echo "注意: 有公网IP的节点将自动配置Endpoint，无公网IP的需要手动配置"
}

# 检查依赖
check_dependencies() {
    log_info "检查依赖..."

    if ! command -v wg &> /dev/null; then
        log_error "未找到 wg 命令。请安装 WireGuard:"
        log_error "  Ubuntu/Debian: sudo apt install wireguard"
        log_error "  CentOS/RHEL: sudo yum install wireguard-tools"
        exit 1
    fi

    log_success "依赖检查通过"
}

# 创建目录结构
create_directories() {
    log_info "创建目录结构..."

    mkdir -p configs
    mkdir -p keys
    mkdir -p scripts

    log_success "目录结构创建完成"
}

# 生成密钥对
generate_keys() {
    local node_count=$1
    log_info "生成 $node_count 个节点的密钥对..."

    for ((i=1; i<=node_count; i++)); do
        local private_key_file="keys/node${i}_private.key"
        local public_key_file="keys/node${i}_public.key"

        # 生成私钥
        wg genkey > "$private_key_file"

        # 从私钥生成公钥
        wg pubkey < "$private_key_file" > "$public_key_file"

        log_info "节点 $i 密钥对生成完成"
    done

    log_success "所有密钥对生成完成"
}

# 生成 WireGuard 配置文件
generate_config() {
    local node_num=$1
    local node_count=$2
    local port=$3

    local private_key_file="keys/node${node_num}_private.key"
    local config_file="configs/node${node_num}.conf"

    local node_ip="${NETWORK_BASE}.${node_num}"

    log_info "生成节点 $node_num 配置 (IP: $node_ip, 端口: $port)..."

    # Interface 部分
    cat > "$config_file" << EOF
# WireGuard 全互通 VPN - 节点 ${node_num}
# IP: ${node_ip}
# 端口: ${port}

[Interface]
PrivateKey = $(cat "$private_key_file")
Address = ${node_ip}/24
ListenPort = ${port}
# DNS = 8.8.8.8, 8.8.4.4

# 网关模式配置 (取消注释以启用)
# PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
# PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

EOF

    # 智能连接模型: 根据节点是否有公网IP决定连接方式
    for ((j=1; j<=node_count; j++)); do
        if [ "$j" -ne "$node_num" ]; then
            local peer_public_key_file="keys/node${j}_public.key"
            local peer_ip="${NETWORK_BASE}.${j}"
            local peer_port=$((port - node_num + j))

            cat >> "$config_file" << EOF

[Peer]
PublicKey = $(cat "$peer_public_key_file")
AllowedIPs = ${NETWORK_BASE}.0/24
EOF

            # 如果节点j有公网IP，添加Endpoint
            if [ ${#public_ip_array[@]} -gt 0 ] && [ "${public_ip_array[$((j-1))]}" != "none" ]; then
                local peer_public_ip="${public_ip_array[$((j-1))]}"
                cat >> "$config_file" << EOF
Endpoint = ${peer_public_ip}:${peer_port}
EOF
            else
                # 如果节点j没有公网IP，注释掉Endpoint
                cat >> "$config_file" << EOF
# Endpoint = YOUR_NODE_${j}_PUBLIC_IP:${peer_port}  # 节点${j}无公网IP，无法直接连接
EOF
            fi

            # 如果当前节点没有公网IP，添加PersistentKeepalive到有公网IP的节点
            if [ ${#public_ip_array[@]} -gt 0 ] && [ "${public_ip_array[$((node_num-1))]}" == "none" ] && [ "${public_ip_array[$((j-1))]}" != "none" ]; then
                cat >> "$config_file" << EOF
PersistentKeepalive = 25
EOF
            else
                cat >> "$config_file" << EOF
# PersistentKeepalive = 25
EOF
            fi
        fi
    done

    log_info "节点 $node_num 配置生成完成"
}

# 生成所有节点的配置
generate_configs() {
    local node_count=$1
    local start_port=$2

    log_info "生成 $node_count 个节点的 WireGuard 配置..."

    for ((i=1; i<=node_count; i++)); do
        local port=$((start_port + i - 1))
        generate_config "$i" "$node_count" "$port"
    done

    log_success "所有节点配置生成完成"
}

# 生成管理脚本
generate_scripts() {
    log_info "生成管理脚本..."

    # 启动脚本
    cat > scripts/start.sh << 'EOF'
#!/bin/bash
# WireGuard 启动脚本

set -e

NODE_NUM=$1

if [ -z "$NODE_NUM" ]; then
    echo "用法: $0 <节点编号>"
    echo "示例: $0 1  # 启动节点1"
    exit 1
fi

CONFIG_FILE="configs/node${NODE_NUM}.conf"
INTERFACE="wg${NODE_NUM}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误: 配置文件 $CONFIG_FILE 不存在"
    exit 1
fi

echo "启动 WireGuard 节点 $NODE_NUM..."

# 创建接口
sudo ip link add $INTERFACE type wireguard

# 设置配置
sudo wg setconf $INTERFACE "$CONFIG_FILE"

# 启动接口
sudo ip link set $INTERFACE up

echo "节点 $NODE_NUM 启动成功"
echo "接口: $INTERFACE"
echo "配置: $CONFIG_FILE"
EOF

    # 停止脚本
    cat > scripts/stop.sh << 'EOF'
#!/bin/bash
# WireGuard 停止脚本

set -e

NODE_NUM=$1

if [ -z "$NODE_NUM" ]; then
    echo "用法: $0 <节点编号>"
    echo "示例: $0 1  # 停止节点1"
    exit 1
fi

INTERFACE="wg${NODE_NUM}"

echo "停止 WireGuard 节点 $NODE_NUM..."

# 停止接口
sudo ip link set $INTERFACE down

# 删除接口
sudo ip link delete $INTERFACE

echo "节点 $NODE_NUM 已停止"
EOF

    # 状态检查脚本
    cat > scripts/status.sh << 'EOF'
#!/bin/bash
# WireGuard 状态检查脚本

echo "=== WireGuard 接口状态 ==="
sudo wg show all

echo ""
echo "=== 网络接口状态 ==="
ip addr show | grep -E "(wg|inet.*10\.0\.100)" || echo "未找到 WireGuard 接口"

echo ""
echo "=== 路由表 ==="
ip route | grep "10.0.100" || echo "未找到相关路由"
EOF

    # 连通性测试脚本
    cat > scripts/test_connectivity.sh << 'EOF'
#!/bin/bash
# WireGuard 连通性测试脚本

NETWORK_BASE="10.0.100"
NODE_COUNT=$(ls configs/ | wc -l)

echo "=== WireGuard 连通性测试 ==="
echo "网络段: $NETWORK_BASE.0/24"
echo "节点数量: $NODE_COUNT"
echo ""

# 测试到每个节点的连通性
for ((i=1; i<=NODE_COUNT; i++)); do
    TARGET_IP="$NETWORK_BASE.$i"
    echo -n "测试连接到节点 $i ($TARGET_IP): "

    if ping -c 3 -W 2 "$TARGET_IP" &> /dev/null; then
        echo "✓ 连通"
    else
        echo "✗ 无法连接"
    fi
done

echo ""
echo "=== WireGuard 接口信息 ==="
sudo wg show
EOF

    # 重启所有节点脚本
    cat > scripts/restart_all.sh << 'EOF'
#!/bin/bash
# 重启所有 WireGuard 节点

NODE_COUNT=$(ls configs/ | wc -l)

echo "重启所有 $NODE_COUNT 个 WireGuard 节点..."

for ((i=1; i<=NODE_COUNT; i++)); do
    echo "重启节点 $i..."
    ./scripts/stop.sh "$i" 2>/dev/null || true
    sleep 1
    ./scripts/start.sh "$i"
    echo "节点 $i 重启完成"
    echo ""
done

echo "所有节点重启完成"
EOF

    # 设置脚本执行权限
    chmod +x scripts/*.sh

    log_success "管理脚本生成完成"
}

# 生成部署摘要
generate_deployment_summary() {
    local node_count=$1
    local start_port=$2

    log_info "生成部署摘要..."

    cat > DEPLOYMENT_SUMMARY.md << EOF
# WireGuard 全互通 VPN 部署摘要

生成时间: $(date)
节点数量: $node_count
网络段: ${NETWORK_BASE}.0/24
起始端口: $start_port

## 网络拓扑

EOF

    for ((i=1; i<=node_count; i++)); do
        local port=$((start_port + i - 1))
        cat >> DEPLOYMENT_SUMMARY.md << EOF
### 节点 $i
- **IP 地址**: ${NETWORK_BASE}.$i
- **监听端口**: $port
- **配置文件**: configs/node${i}.conf
- **私钥文件**: keys/node${i}_private.key
- **公钥文件**: keys/node${i}_public.key

EOF
    done

    cat >> DEPLOYMENT_SUMMARY.md << EOF
## 部署步骤

### 1. 配置 Endpoint 地址

为每个节点设置正确的公网 IP 地址：

\`\`\`bash
# 编辑每个节点的配置文件
nano configs/node1.conf  # 设置节点1的公网IP
nano configs/node2.conf  # 设置节点2的公网IP
# ... 依此类推

# 在 [Peer] 部分取消注释并设置正确的公网IP:
# Endpoint = YOUR_NODE_X_PUBLIC_IP:PORT
\`\`\`

### 2. 分发配置文件

将对应的配置文件复制到各个节点：

\`\`\`bash
# 示例：使用 scp 传输
scp configs/node1.conf user@node1-ip:/etc/wireguard/wg0.conf
scp configs/node2.conf user@node2-ip:/etc/wireguard/wg0.conf
# ... 依此类推
\`\`\`

### 3. 配置防火墙

在每个节点上开放对应端口：

\`\`\`bash
# Ubuntu/Debian
sudo ufw allow $start_port:$((start_port + node_count - 1))/udp

# CentOS/RHEL
sudo firewall-cmd --add-port=$start_port-$((start_port + node_count - 1))/udp --permanent
sudo firewall-cmd --reload
\`\`\`

### 4. 启动 WireGuard

\`\`\`bash
# 在节点1上运行
sudo wg-quick up /etc/wireguard/wg0.conf

# 或使用提供的脚本
./scripts/start.sh 1  # 启动节点1
./scripts/start.sh 2  # 启动节点2
# ... 依此类推
\`\`\`

### 5. 测试连通性

\`\`\`bash
# 使用测试脚本
./scripts/test_connectivity.sh

# 或手动测试
ping ${NETWORK_BASE}.1  # 测试连接到节点1
ping ${NETWORK_BASE}.2  # 测试连接到节点2
# ... 依此类推
\`\`\`

## 管理命令

- **查看状态**: \`./scripts/status.sh\`
- **启动节点**: \`./scripts/start.sh <节点编号>\`
- **停止节点**: \`./scripts/stop.sh <节点编号>\`
- **重启所有**: \`./scripts/restart_all.sh\`
- **测试连通性**: \`./scripts/test_connectivity.sh\`

## 安全注意事项

1. 妥善保管私钥文件，不要泄露
2. 合理配置防火墙，只开放必要端口
3. 定期更新 WireGuard 到最新版本
4. 监控网络流量和连接状态

## 故障排除

### 常见问题

1. **连接失败**: 检查防火墙设置和端口转发
2. **无法 ping 通**: 确认 Endpoint 地址配置正确
3. **密钥错误**: 确保使用正确的私钥文件

### 调试命令

\`\`\`bash
# 查看 WireGuard 状态
sudo wg show

# 查看网络接口
ip addr show wg0

# 查看路由
ip route | grep ${NETWORK_BASE}

# 查看系统日志
sudo journalctl -u wg-quick@wg0
\`\`\`
EOF

    log_success "部署摘要生成完成"
}

# 主函数
main() {
    # 参数检查
    if [ $# -lt 1 ]; then
        usage
        exit 1
    fi

    local node_count=$1
    local start_port=${2:-$DEFAULT_START_PORT}
    local public_ips=""

    # 处理公网IP参数 (从第3个参数开始都是IP)
    if [ $# -ge 3 ]; then
        shift 2  # 移除前两个参数
        public_ips="$*"  # 剩余的所有参数都是IP
    fi

    # 验证参数
    if ! [[ "$node_count" =~ ^[0-9]+$ ]] || [ "$node_count" -lt 2 ] || [ "$node_count" -gt 254 ]; then
        log_error "节点数量必须是 2-254 之间的整数"
        exit 1
    fi

    if ! [[ "$start_port" =~ ^[0-9]+$ ]] || [ "$start_port" -lt 1 ] || [ "$start_port" -gt 65535 ]; then
        log_error "端口号必须是 1-65535 之间的整数"
        exit 1
    fi

    # 检查端口范围是否足够
    local max_port=$((start_port + node_count - 1))
    if [ "$max_port" -gt 65535 ]; then
        log_error "端口范围超出有效范围 (起始端口: $start_port, 节点数量: $node_count, 最大端口: $max_port)"
        exit 1
    fi

    # 验证公网IP参数
    local public_ip_array=()
    local has_public_ip=false

    # 初始化数组，所有节点默认没有公网IP
    for ((i=0; i<node_count; i++)); do
        public_ip_array[i]="none"
    done

    if [ -n "$public_ips" ]; then
        # 将提供的IP参数转换为数组
        IFS=' ' read -ra provided_ips <<< "$public_ips"
        local provided_count=${#provided_ips[@]}

        if [ $provided_count -gt $node_count ]; then
            log_error "提供的公网IP数量 ($provided_count) 不能超过节点数量 ($node_count)"
            exit 1
        fi

        # 验证IP地址格式并填充数组
        for ((i=0; i<provided_count; i++)); do
            local ip="${provided_ips[i]}"
            if ! [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                log_error "无效的IP地址格式: $ip"
                exit 1
            fi
            public_ip_array[i]="$ip"
            has_public_ip=true
        done

        log_info "配置了 $provided_count 个公网IP"
    else
        log_warning "未提供公网IP配置，Endpoint 将被注释，需要手动配置"
    fi

    log_info "开始生成 WireGuard 全互通 VPN 配置..."
    log_info "节点数量: $node_count"
    log_info "起始端口: $start_port"
    log_info "网络段: ${NETWORK_BASE}.0/24"

    # 执行步骤
    check_dependencies
    create_directories
    generate_keys "$node_count"
    generate_configs "$node_count" "$start_port"
    generate_scripts
    generate_deployment_summary "$node_count" "$start_port"

    log_success "WireGuard VPN 配置生成完成！"
    echo ""
    log_info "生成的目录结构："
    echo "  configs/     - WireGuard 配置文件"
    echo "  keys/        - 密钥文件（请妥善保管）"
    echo "  scripts/     - 管理脚本"
    echo "  DEPLOYMENT_SUMMARY.md - 部署指南"
    echo ""
    log_info "接下来请："
    echo "  1. 编辑配置文件，设置正确的公网 IP 地址"
    echo "  2. 将配置文件分发到各个节点"
    echo "  3. 配置防火墙开放相应端口"
    echo "  4. 启动 WireGuard 服务"
    echo "  5. 测试网络连通性"
    echo ""
    log_info "详细说明请查看 DEPLOYMENT_SUMMARY.md"
}

# 运行主函数
main "$@"
