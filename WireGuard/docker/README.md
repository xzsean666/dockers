# WireGuard 全互通 VPN 自动化部署

这是一个自动化脚本，用于快速部署 WireGuard 全互通（Mesh）VPN 网络，让多台机器可以完全互联。

## 📋 功能特点

- 🔗 **全互通**: 每个节点都可以直接连接其他所有节点
- ⚙️ **自动化**: 一键生成所有配置文件和密钥
- 🛠️ **管理脚本**: 提供完整的启动、停止、状态检查脚本
- 📊 **连通测试**: 自动测试节点间网络连通性
- 🔒 **安全**: 每个节点使用独立的密钥对

## 🚀 快速开始

### 前置要求

确保所有节点都已安装 WireGuard：

```bash
# Ubuntu/Debian
sudo apt update && sudo apt install wireguard

# CentOS/RHEL/Rocky Linux
sudo yum install epel-release
sudo yum install wireguard-tools

# 或使用 dnf (较新版本)
sudo dnf install wireguard-tools
```

### 生成配置

```bash
# 克隆或下载此项目
cd WireGuard

# 生成5个节点的全互通VPN配置（端口从51820开始）
./init.sh 5 51820

# 或使用默认端口51820
./init.sh 5
```

### 目录结构

生成后的目录结构：

```
WireGuard/
├── init.sh                    # 主配置生成脚本
├── configs/                   # 配置文件目录
│   ├── node1.conf
│   ├── node2.conf
│   └── ...
├── keys/                      # 密钥文件目录
│   ├── node1_private.key
│   ├── node1_public.key
│   └── ...
├── scripts/                   # 管理脚本目录
│   ├── start.sh              # 启动节点
│   ├── stop.sh               # 停止节点
│   ├── status.sh             # 状态检查
│   ├── test_connectivity.sh  # 连通测试
│   └── restart_all.sh        # 重启所有
└── DEPLOYMENT_SUMMARY.md     # 部署摘要
```

## 📖 部署步骤

### 1. 配置 Endpoint 地址

生成配置后，需要编辑每个配置文件，取消注释并设置正确的公网 IP：

```bash
# 编辑 configs/node1.conf
# 将以下行取消注释并设置正确的IP
# Endpoint = YOUR_NODE_1_PUBLIC_IP:51820
```

### 2. 分发配置文件

将对应的配置文件复制到各个节点：

```bash
# 节点1 需要 node1.conf
# 节点2 需要 node2.conf
# 以此类推...

# 示例：使用 scp 传输
scp configs/node1.conf user@node1-ip:/etc/wireguard/wg0.conf
scp configs/node2.conf user@node2-ip:/etc/wireguard/wg0.conf
```

### 3. 配置防火墙

在每个节点上开放对应端口：

```bash
# Ubuntu/Debian (使用 ufw)
sudo ufw allow 51820:51824/udp  # 假设5个节点，端口范围51820-51824

# CentOS/RHEL (使用 firewalld)
sudo firewall-cmd --add-port=51820-51824/udp --permanent
sudo firewall-cmd --reload

# 或者直接使用 iptables
sudo iptables -A INPUT -p udp --dport 51820:51824 -j ACCEPT
```

### 4. 启动 WireGuard

在每个节点上启动 WireGuard：

```bash
# 方法1：使用我们的脚本
./scripts/start.sh 1  # 在节点1上运行

# 方法2：直接使用 wg-quick
sudo wg-quick up /path/to/node1.conf

# 方法3：设置为系统服务
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
```

### 5. 测试连通性

```bash
# 使用测试脚本
./scripts/test_connectivity.sh

# 或手动测试
ping 10.0.100.1  # 测试连接到节点1
ping 10.0.100.2  # 测试连接到节点2
```

## 🛠️ 管理命令

### 脚本管理

```bash
# 启动指定节点
./scripts/start.sh [节点编号]

# 停止指定节点
./scripts/stop.sh [节点编号]

# 查看状态
./scripts/status.sh

# 测试连通性
./scripts/test_connectivity.sh

# 重启所有节点
./scripts/restart_all.sh
```

### 手动管理

```bash
# 查看 WireGuard 状态
sudo wg show

# 查看接口信息
ip addr show wg0

# 查看路由
ip route | grep 10.0.100

# 启动/停止
sudo wg-quick up wg0
sudo wg-quick down wg0
```

## 🔧 高级配置

### 网关模式

如果需要某个节点作为网关（访问互联网），在配置文件的 `[Interface]` 部分取消注释：

```ini
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
```

并在客户端配置中添加默认路由：

```ini
AllowedIPs = 0.0.0.0/0
```

### DNS 配置

在配置文件的 `[Interface]` 部分可以添加 DNS：

```ini
DNS = 8.8.8.8, 8.8.4.4
# 或使用其他DNS服务器
DNS = 1.1.1.1, 1.0.0.1
```

### 自定义网络段

编辑 `init.sh` 脚本中的 `NETWORK_BASE` 变量：

```bash
NETWORK_BASE="10.0.200"  # 使用 10.0.200.0/24 网段
```

## 🔍 故障排除

### 连接问题

1. **检查防火墙**: 确保所有节点的防火墙都开放了对应端口
2. **检查 NAT**: 如果节点在 NAT 后面，可能需要端口转发
3. **检查网络**: 使用 `tcpdump` 或 `wireshark` 查看数据包

```bash
# 检查网络接口
ip addr show wg0

# 检查路由表
ip route show table all | grep wg0

# 实时查看连接
sudo wg show all
```

### 常见错误

- **Permission denied**: 确保以 root 权限运行或配置 sudo
- **Address already in use**: 检查端口是否被占用
- **Operation not supported**: 确保内核支持 WireGuard

### 日志查看

```bash
# 查看系统日志
sudo journalctl -u wg-quick@wg0

# 查看内核消息
sudo dmesg | grep wireguard
```

## 📝 配置示例

### 3 节点全互通网络

```bash
./init.sh 3 51820
```

生成的网络拓扑：

- 节点 1: 10.0.100.1:51820
- 节点 2: 10.0.100.2:51821
- 节点 3: 10.0.100.3:51822

每个节点都可以直接连接其他两个节点。

## 🔒 安全注意事项

1. **密钥安全**: 妥善保管私钥文件，不要泄露
2. **网络访问**: 合理配置 `AllowedIPs`，避免过度开放
3. **防火墙**: 只开放必要的端口
4. **更新**: 定期更新 WireGuard 到最新版本

## 📄 许可证

本项目采用 MIT 许可证。

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

---

**注意**: 这个脚本会自动生成配置，但仍需要根据你的实际网络环境进行调整。在生产环境使用前，请务必进行充分测试。
