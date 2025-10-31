# Clash 代理服务管理

这是一个用于管理 Clash 代理服务的完整解决方案，包括交互式菜单、Docker 镜像加载、服务启动、配置修复、代理测试和 API 控制等功能。

## 前置要求

- Docker 和 Docker Compose 已安装
- curl 命令行工具
- Python 3 (用于 JSON 格式化，可选)
- `clash.tar` Docker 镜像文件

## 文件结构

```
clash/
├── docker-compose.yml    # Docker Compose 配置
├── helper.sh            # 主控制脚本（交互式菜单）
├── clash.tar            # Docker 镜像文件
├── config/              # Clash 配置目录 (自动创建)
└── README.md            # 本文档
```

## 快速开始

### 1. 启动脚本

```bash
cd /home/sean/git/dockers/clash

# 直接运行脚本，进入交互式菜单
./helper.sh
```

### 2. 选择操作

脚本会显示菜单，通过输入数字选择要执行的操作：

```
╔════════════════════════════════════════╗
║      Clash 代理管理助手 - 交互式菜单     ║
╚════════════════════════════════════════╝

【服务管理】
  1)  加载 Docker 镜像
  2)  启动服务
  3)  停止服务
  4)  重启服务
  5)  查看服务状态

【配置管理】
  6)  修复配置文件 (external-controller)

【代理测试】
  7)  测试 HTTP 代理
  8)  测试 SOCKS5 代理
  9)  测试所有代理

【API 控制】
  10) 获取代理列表
  11) 获取运行状态
  12) 切换代理

【其他】
  13) 查看实时日志
  0)  退出
```

## 核心功能

### 🔧 自动配置修复

**启动服务时自动修复：**

当执行选项 `2` (启动服务) 时，脚本会自动：
1. 启动 Clash Docker 容器
2. 等待配置文件生成
3. **自动检测并修复** `external-controller` 配置
   - 从 `127.0.0.1:9090` 改为 `0.0.0.0:9090`
   - 这样可以允许外部访问 API
   - 自动创建备份文件 `config.yml.backup`

**示例输出：**
```
[INFO] 启动 Clash 服务...
[SUCCESS] Clash 服务启动成功
[INFO] 正在自动修复配置文件...

[WARNING] 发现需要修复的配置
修改前:
external-controller: 127.0.0.1:9090
[INFO] 已创建备份文件: ./config/config.yml.backup
修改后:
external-controller: 0.0.0.0:9090
[SUCCESS] 配置文件修复成功！⚠️ 已改为 0.0.0.0:9090
```

### 手动修复配置

也可以选择菜单中的 `6` 进行手动修复：

```bash
./helper.sh
# 选择 6，手动修复配置
```

### 📋 命令参考

| 选项 | 功能 | 说明 |
|------|------|------|
| **1** | 加载 Docker 镜像 | docker load -i clash.tar |
| **2** | 启动服务 | 启动 Clash + 自动修复配置 |
| **3** | 停止服务 | 停止 Clash 容器 |
| **4** | 重启服务 | 停止后重新启动 |
| **5** | 查看服务状态 | 显示容器运行状态 |
| **6** | 修复配置文件 | 手动修复 external-controller |
| **7** | 测试 HTTP 代理 | 测试 HTTP 代理连接 |
| **8** | 测试 SOCKS5 代理 | 测试 SOCKS5 代理连接 |
| **9** | 测试所有代理 | 同时测试 HTTP 和 SOCKS5 |
| **10** | 获取代理列表 | 通过 API 获取所有可用代理 |
| **11** | 获取运行状态 | 获取 Clash 运行状态信息 |
| **12** | 切换代理 | 交互式切换代理 |
| **13** | 查看实时日志 | 显示 Clash 运行日志 (Ctrl+C 退出) |
| **0** | 退出 | 退出程序 |

## 使用示例

### 示例 1：首次启动

```bash
./helper.sh
# 输入 1，加载镜像
# 按 Enter 返回菜单
# 输入 2，启动服务（自动修复配置）
# 输入 5，查看状态
```

### 示例 2：测试代理

```bash
./helper.sh
# 输入 9，测试所有代理
```

### 示例 3：通过 API 获取代理列表

```bash
./helper.sh
# 输入 10，获取代理列表
```

### 示例 4：切换代理

```bash
./helper.sh
# 输入 12，切换代理
# 输入 GLOBAL（选择器名称）
# 输入要切换的代理名称
```

### 示例 5：查看日志

```bash
./helper.sh
# 输入 13，查看实时日志
# 按 Ctrl+C 退出日志查看
```

## 代理端口

| 类型 | 地址 | 用途 |
|------|------|------|
| HTTP 代理 | `127.0.0.1:17890` | HTTP/HTTPS 流量 |
| SOCKS5 代理 | `127.0.0.1:17891` | 通用 SOCKS5 代理 |
| API 接口 | `127.0.0.1:17892` | RESTful API 控制 |

## 配置目录

Clash 配置文件会挂载在 `./config` 目录下，对应容器内的 `/root/.config/clash` 目录。

```bash
# 查看配置文件
ls -la ./config

# 编辑配置文件（修改后需要重启）
vi ./config/config.yml

# 查看备份文件
ls -la ./config/config.yml.backup
```

## 外部控制器配置

### 为什么要修改 external-controller？

- **默认值** `127.0.0.1:9090` - 只能本地访问 API
- **修改值** `0.0.0.0:9090` - 允许任何 IP 地址访问 API

这对于以下场景很有用：
- 远程控制 Clash
- 集成到其他应用
- Docker 容器间通信

### 修改后的影响

修改 `external-controller` 后需要重启 Clash 服务，脚本会自动提示。

## 常见问题

### Q: 启动时配置没有被修复怎么办？

检查以下几点：
1. 服务是否成功启动：`./helper.sh` → 选项 5
2. 配置文件是否存在：`ls -la ./config/`
3. 手动修复：`./helper.sh` → 选项 6

### Q: 如何恢复配置文件的原始版本？

如果需要恢复原始配置：
```bash
# 查看是否有备份
ls -la ./config/config.yml.backup

# 恢复备份
cp ./config/config.yml.backup ./config/config.yml
```

然后重启服务：`./helper.sh` → 选项 4

### Q: 代理测试失败怎么办？

1. 检查服务是否运行：选项 5
2. 查看日志：选项 13
3. 确保网络连接正常
4. 检查配置文件是否有效

### Q: 如何修改代理端口？

编辑 `docker-compose.yml` 中的 `ports` 部分，例如：

```yaml
ports:
  - "18890:7890"  # 改为 18890
  - "18891:7891"  
  - "18892:9090"
```

然后重启服务：选项 4

### Q: 如何完全删除 Clash 容器和镜像？

```bash
# 停止并删除容器
./helper.sh  # 选项 3

# 删除镜像
docker rmi xzsean/clash:v1.18.0

# 删除配置 (可选)
rm -rf ./config
```

## 脚本特性

✅ 交互式菜单，易于操作
✅ 自动配置修复（external-controller）
✅ 完整的生命周期管理
✅ 代理连接测试（HTTP 和 SOCKS5）
✅ RESTful API 支持
✅ 彩色输出反馈
✅ 错误处理和验证
✅ 日志查看功能
✅ 自动备份配置文件

## 故障排查

### 启动失败

```bash
# 检查 Docker 是否运行
docker ps

# 查看详细错误
./helper.sh  # 选项 13 查看日志

# 尝试重新加载镜像
./helper.sh  # 选项 1
```

### 代理不响应

```bash
# 确认容器正在运行
./helper.sh  # 选项 5

# 检查端口是否被占用
sudo netstat -tulpn | grep 178

# 查看容器日志
./helper.sh  # 选项 13
```

### API 请求失败

确保：
1. Clash 服务正在运行（选项 5）
2. 配置已修复，external-controller 为 0.0.0.0:9090（选项 6）
3. 代理列表中有可用的代理
4. API 地址正确（`http://127.0.0.1:17892`）

## 更新日志

### v1.2
- ✨ 添加自动配置修复功能
- ✨ 启动服务时自动修复 external-controller
- 📝 优化菜单布局和说明

### v1.1
- ✨ 完整的交互式菜单
- ✨ 代理测试功能
- ✨ RESTful API 支持

### v1.0
- 初始版本，包含基础管理功能
