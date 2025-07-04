# UV with SSH Docker 配置

基于 `astral/uv:latest` 官方镜像的 Python 开发环境，添加 SSH 支持，配置中国镜像源。

## 特点

- ✅ **官方 UV 镜像**，轻量高效（~18MB）
- ✅ **预装最新 UV**，无需手动安装
- ✅ **SSH 密码登录**，方便开发调试
- ✅ **预装 Python**，开箱即用
- ✅ **基础开发工具**（vim, git 等）
- ✅ **中国 PyPI 镜像源**，提高下载速度
- ✅ **工作目录在 /root**，方便开发

## 镜像对比

| 特性     | 官方 UV 镜像 + SSH | 从 Ubuntu 构建 |
| -------- | ------------------ | -------------- |
| 镜像大小 | ~18MB              | ~500MB+        |
| 构建速度 | 极快               | 较慢           |
| UV 版本  | 官方最新           | 手动安装       |
| 稳定性   | 官方维护           | 自己维护       |
| 更新频率 | 跟随官方           | 手动更新       |

## 镜像源配置

### UV Python 包索引源（清华大学）

```bash
# 环境变量已配置
UV_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
UV_EXTRA_INDEX_URL=https://pypi.org/simple
```

## 使用方法

1. **修改密码**：
   在 `docker-compose.yml` 中修改 `ROOT_PASSWORD` 环境变量的值。

2. **初始化环境**：

   ```bash
   ./init.sh
   ```

3. **启动容器**：

   ```bash
   docker-compose up -d
   ```

4. **SSH 连接**：
   ```bash
   ssh root@localhost -p 10022
   ```
   密码是你在 `docker-compose.yml` 中设置的 `ROOT_PASSWORD`。

## 目录结构

- `./root`: 映射到容器的 `/root/workspace` 目录，存放你的 Python 项目
- `./ssh_keys`: 映射到容器的 `/root/.ssh` 目录，存放 SSH 密钥（可选）
- `uv_cache`: UV 缓存卷，提高包安装速度

## 端口说明

- `10022`: SSH 端口
- `8000`: 应用端口（可根据需要修改）

## 系统信息

容器基于官方 `astral/uv:latest` 镜像，已预装：

```bash
# 查看系统信息
cat /etc/os-release

# 查看 UV 版本（预装）
uv --version

# 查看镜像源配置
echo "UV_INDEX_URL: $UV_INDEX_URL"

# 查看工作目录
pwd
ls -la

# 查看 workspace 目录
ls -la workspace/
```

## Python 版本管理

容器内已预装 UV，可以安装和管理多个 Python 版本：

```bash
# 查看可用的 Python 版本
uv python list --only-installed
uv python list

# 安装特定 Python 版本（使用中国镜像源，速度更快）
uv python install 3.11
uv python install 3.12
uv python install 3.13

# 设置项目使用的 Python 版本
uv python pin 3.12

# 查看当前 Python 版本
uv python find
```

## 使用 UV

容器内已预装 UV 并配置中国镜像源，包安装速度更快：

```bash
# 进入工作空间
cd workspace

# 创建新项目
uv init my-project
cd my-project

# 安装依赖（自动使用中国镜像源）
uv add requests
uv add fastapi --dev

# 创建虚拟环境并同步依赖
uv sync

# 运行 Python 脚本
uv run script.py

# 运行应用
uv run fastapi dev app.py
```

## 镜像源说明

本配置使用以下中国镜像源以提高下载速度：

1. **Python 包索引**：清华大学 PyPI 镜像
2. **备用索引**：官方 PyPI

官方镜像已经包含 UV，无需额外配置安装源。

## 示例工作流程

```bash
# 1. SSH 进入容器
ssh root@localhost -p 10022

# 2. 查看系统信息和配置
uv --version  # 显示预装的 UV 版本
echo "Python 包索引: $UV_INDEX_URL"

# 3. 安装所需的 Python 版本（快速）
uv python install 3.12

# 4. 进入工作目录
cd workspace  # 对应宿主机的 ./root 目录

# 5. 创建新项目
uv init my-fastapi-project
cd my-fastapi-project

# 6. 添加依赖（从中国镜像源下载，速度快）
uv add fastapi uvicorn

# 7. 创建简单的应用
echo 'from fastapi import FastAPI
app = FastAPI()

@app.get("/")
def read_root():
    return {"Hello": "官方 UV 镜像 + SSH"}' > main.py

# 8. 运行应用
uv run uvicorn main:app --host 0.0.0.0 --port 8000
```

## 与其他方案的区别

| 方面     | 官方 UV 镜像 + SSH | Ubuntu 构建版本 | 纯官方 UV 镜像 |
| -------- | ------------------ | --------------- | -------------- |
| 镜像大小 | ~18MB              | ~500MB+         | ~18MB          |
| 构建速度 | 极快               | 较慢            | 无需构建       |
| SSH 支持 | ✅                 | ✅              | ❌             |
| 开发便利 | 极高               | 高              | 中等           |
| 维护成本 | 低                 | 高              | 无             |

## 优势总结

✅ **轻量高效**：使用官方镜像，体积小，启动快  
✅ **稳定可靠**：跟随官方更新，稳定性有保障  
✅ **开发友好**：SSH 支持让开发调试变得简单  
✅ **网络优化**：中国镜像源，包安装速度快  
✅ **即开即用**：预装 UV，无需额外配置

## 安全建议

- 生产环境中，建议使用 SSH 密钥认证而不是密码
- 修改默认 SSH 端口
- 定期更新密码
- 定期重新构建镜像以获取最新的 UV 版本
