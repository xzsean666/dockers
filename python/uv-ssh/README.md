# UV SSH Container

基于 uv 包管理器的 Python SSH 开发环境，默认保留代理设置。

## 环境变量说明

- `ROOT_PASSWORD`: SSH root 用户密码
- `GITHUB_TOKEN`: 访问私有 GitHub 仓库的 token

## 使用方法

1. 复制环境变量文件：

```bash
cp .env.example .env
```

2. 编辑`.env`文件，设置必要的环境变量

3. 构建并启动容器：

```bash
docker-compose up -d
```

4. SSH 连接到容器：

```bash
ssh root@localhost -p 10022
```

## 代理说明

容器默认保留构建时的代理设置，可以正常访问外网和私有仓库。
