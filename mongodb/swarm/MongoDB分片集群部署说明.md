# MongoDB 分片集群部署说明文档

## 前提条件

- 已安装 Docker 和 Docker Swarm
- 至少有一个已加入 Swarm 集群的节点
- 为部署 MongoDB 的节点添加标签

## 部署步骤

### 1. 添加节点标签

为要部署 MongoDB 的节点添加标签：

docker node update --label-add role=mongodb <节点ID或节点名称>

可以通过以下命令查看节点列表：

docker node ls

### 2. 创建配置文件目录结构

创建以下目录结构：

mongodb/
├── swarm/
│   ├── docker-compose-swarm.yml
│   └── scripts/
│       └── init-mongodb.sh

确保 init-mongodb.sh 具有执行权限：

chmod +x mongodb/swarm/scripts/init-mongodb.sh

### 3. 设置环境变量（可选）

可以创建一个 .env 文件来设置 MongoDB 的用户名和密码，或者使用默认值：

# .env 文件示例
MONGO_ROOT_USER=admin
MONGO_ROOT_PASSWORD=admin123

### 4. 部署集群

在包含 docker-compose-swarm.yml 文件的目录中执行以下命令：

docker stack deploy -c docker-compose-swarm.yml mongodb

### 5. 查看部署状态

使用以下命令检查服务部署状态：

docker service ls

查看具体服务的详情：

docker service ps mongodb_mongos-router-1

### 6. 连接到 MongoDB 集群

集群初始化完成后，可以通过以下方式连接：

- 主要路由地址：<宿主机IP>:27017
- 备用路由地址：<宿主机IP>:30701

连接命令示例：

mongo --host <宿主机IP> --port 27017 -u admin -p admin123 --authenticationDatabase admin

## 集群结构说明

此部署创建了一个完整的 MongoDB 分片集群，包括：

- 3个配置服务器节点（Config Server Replica Set）
- 2个分片，每个分片包含3个副本（Shard Replica Sets）
- 2个路由服务器（Mongos Routers）
- 1个初始化服务，用于配置副本集和分片

## 验证集群状态

连接到集群后，可以使用以下命令验证集群状态：

// 查看分片状态
sh.status()

// 查看集群状态
db.adminCommand({ listShards: 1 })

// 测试分片数据库
use testdb
for (let i = 0; i < 1000; i++) {
  db.testcollection.insertOne({ counter: i, value: "test" + i })
}

## 停止和删除集群

如需停止和删除集群，使用以下命令：

docker stack rm mongodb

注意：这将保留卷数据。如需删除卷数据，请手动删除相关卷。

## 注意事项

1. 生产环境中，应设置更强的密码
2. 根据实际需求调整内存和CPU限制
3. 考虑使用持久化存储而非默认的Docker卷
4. 定期备份MongoDB数据
5. 监控集群状态，确保高可用性 