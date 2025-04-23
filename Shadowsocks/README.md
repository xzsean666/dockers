# Shadowsocks Docker 部署

这是一个使用 Docker 部署的 Shadowsocks 服务器。

## 配置说明

1. 修改 `config/config.json` 中的配置：

   - `server_port`: 服务端口（默认 8388）
   - `password`: 连接密码
   - `method`: 加密方式（默认 chacha20-ietf-poly1305）

2. 启动服务：

```bash
docker-compose up -d
```

3. 查看日志：

```bash
docker-compose logs -f
```

## 客户端配置

### Clash Verge 配置示例

```yaml
proxies:
  - name: Shadowsocks
    type: ss
    server: your_server_ip
    port: 8388
    cipher: chacha20-ietf-poly1305
    password: your_password_here
```

## 安全建议

1. 使用强密码
2. 修改默认端口
3. 配置防火墙规则
4. 定期更换密码
5. 考虑使用 CDN

## 故障排查

1. 检查端口是否被占用：

```bash
netstat -tulpn | grep 8388
```

2. 检查容器状态：

```bash
docker-compose ps
```

3. 查看容器日志：

```bash
docker-compose logs -f
```
