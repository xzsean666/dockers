# WireGuard Client 配置指南

## 前提条件

- 你已经在 server 端成功运行了 WireGuard 服务器
- 服务器已经生成了多个 peer 配置文件（peer1, peer2, peer3, ..., peer10）

## 多客户端配置说明

### Server 端配置文件结构

```
/root/dockers/wireguard/server/config/
├── wg0.conf                    # 服务器主配置文件
├── peer1/                      # 第一个客户端配置
│   ├── peer1.conf             # 客户端1的配置文件
│   ├── peer1.png              # 二维码
│   └── presharedkey-peer1     # 预共享密钥
├── peer2/                      # 第二个客户端配置
│   ├── peer2.conf
│   ├── peer2.png
│   └── presharedkey-peer2
├── peer3/                      # 第三个客户端配置
│   ├── peer3.conf
│   ├── peer3.png
│   └── presharedkey-peer3
├── ...                         # peer4 到 peer10
└── peer10/                     # 第十个客户端配置
```

## 为每个客户端服务器配置步骤

### 重要：每个客户端服务器使用不同的 peer 配置

**假设这台客户端服务器要使用 peer3 的配置：**

### 1. 复制指定 peer 的配置文件

```bash
# 方法1：直接复制并重命名
scp /root/dockers/wireguard/server/config/peer3/peer3.conf user@client-server:/root/dockers/wireguard/client/config/wg0.conf

# 方法2：复制所有文件然后重命名
scp /root/dockers/wireguard/server/config/peer3/* user@client-server:/root/dockers/wireguard/client/config/
# 然后在client端重命名
mv /root/dockers/wireguard/client/config/peer3.conf /root/dockers/wireguard/client/config/wg0.conf
```

### 2. 创建 client 端的 .env 文件

```bash
# WireGuard Client Configuration Environment Variables

# User and Group IDs
PUID=1000
PGID=1000

# Timezone
TZ=Asia/Shanghai

# Server Configuration (必须与server端匹配)
SERVER_URL=your-server-ip-or-domain
SERVER_PORT=51820

# Client Configuration
PEER_DNS=8.8.8.8,8.8.4.4
ALLOWED_IPS=0.0.0.0/0

# Logging
LOG_CONFS=true

# Storage Configuration
CONFIG_PATH=./config
```

### 3. 最终 client 端目录结构

```
/root/dockers/wireguard/client/
├── docker-compose.yml
├── .env
└── config/
    ├── wg0.conf               # peer3.conf 重命名而来
    └── presharedkey-peer3     # 预共享密钥（如果有）
```

### 4. 启动 client

```bash
cd /root/dockers/wireguard/client/
docker-compose up -d
```

## 多客户端部署建议

如果你有多台客户端服务器，建议这样分配：

- **客户端服务器 A** → 使用 `peer1` 配置
- **客户端服务器 B** → 使用 `peer2` 配置
- **客户端服务器 C** → 使用 `peer3` 配置
- ...以此类推

每个客户端服务器使用不同的 peer 配置，这样它们在 WireGuard 网络中就有不同的 IP 地址。

## 验证连接

启动后可以查看日志：

```bash
docker-compose logs -f wireguard-client
```

检查连接状态：

```bash
docker exec wireguard-client wg show
```

查看分配的 IP 地址：

```bash
docker exec wireguard-client ip addr show wg0
```

## 重要注意事项

1. **唯一性**：每个客户端服务器必须使用不同的 peer 配置（peer1, peer2, peer3 等）
2. **文件命名**：客户端容器内必须是 `wg0.conf` 文件名
3. **SERVER_URL**：必须设置为 server 端的公网 IP 或域名
4. **端口开放**：确保 server 端的 51820/udp 端口开放
5. **配置冲突**：不要让多个客户端使用同一个 peer 配置，会导致 IP 冲突
