# WireGuard Docker Setup

基于 LinuxServer/WireGuard 的 Docker Compose 配置，包含服务端和客户端配置。

## 目录结构

```
WireGuard/
├── server/
│   └── docker-compose.yml     # WireGuard 服务端配置
├── client/
│   └── docker-compose.yml     # WireGuard 客户端配置
├── env.example               # 环境变量示例文件
└── README.md                # 说明文档
```

## 快速开始

### 1. 配置环境变量

```bash
# 复制环境变量示例文件
cp env.example .env

# 编辑环境变量
nano .env
```

### 2. 启动服务端

```bash
# 进入服务端目录
cd server/

# 启动 WireGuard 服务端
docker-compose up -d

# 查看日志
docker-compose logs -f
```

### 3. 获取客户端配置

服务端启动后会自动生成客户端配置文件，位置：

- `./config/peer1/peer1.conf`
- `./config/peer1/peer1.png` (QR 码)

### 4. 配置客户端

方式一：使用生成的配置文件

```bash
# 复制服务端生成的配置到客户端
cp server/config/peer1/peer1.conf client/client-config/

# 启动客户端
cd client/
docker-compose up -d
```

方式二：手机客户端扫描二维码

- 使用 WireGuard 手机应用
- 扫描 `server/config/peer1/peer1.png` 二维码

## 环境变量说明

| 变量名          | 描述                 | 默认值        |
| --------------- | -------------------- | ------------- |
| PUID            | 用户 ID              | 1000          |
| PGID            | 组 ID                | 1000          |
| TZ              | 时区                 | Asia/Shanghai |
| SERVER_URL      | 服务器公网 IP 或域名 | auto          |
| SERVER_PORT     | WireGuard 端口       | 51820         |
| WEB_PORT        | Web 管理界面端口     | 5000          |
| PEERS_COUNT     | 客户端数量           | 1             |
| PEER_DNS        | DNS 服务器           | auto          |
| INTERNAL_SUBNET | 内网子网             | 10.13.13.0    |
| ALLOWED_IPS     | 允许的 IP 范围       | 0.0.0.0/0     |
| LOG_CONFS       | 记录配置日志         | true          |
| CONFIG_PATH     | 配置文件路径         | ./config      |

## 网络安全注意事项

1. **防火墙设置**：确保服务器防火墙开放了 SERVER_PORT 端口（默认 51820/udp）
2. **IP 转发**：服务器需要开启 IP 转发功能
3. **安全组**：云服务器需要在安全组中开放相应端口
4. **DNS 设置**：建议使用安全的 DNS 服务器（如 1.1.1.1, 8.8.8.8）

## 常用命令

```bash
# 查看服务状态
docker-compose ps

# 查看日志
docker-compose logs -f

# 重启服务
docker-compose restart

# 停止服务
docker-compose down

# 更新镜像
docker-compose pull
docker-compose up -d
```

## 故障排除

1. **容器启动失败**：检查内核模块是否支持 WireGuard
2. **连接超时**：检查防火墙和网络配置
3. **权限问题**：确认 PUID/PGID 设置正确
4. **配置不生效**：删除 config 目录重新生成配置

## 参考链接

- [LinuxServer WireGuard](https://hub.docker.com/r/linuxserver/wireguard)
- [WireGuard 官方文档](https://www.wireguard.com/)
