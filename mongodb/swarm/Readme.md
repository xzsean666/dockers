## MongoDB Swarm 集群部署说明文档

### 1. 简介

这个工具用于在 Docker Swarm 环境中自动部署和配置 MongoDB 分片集群。它提供了灵活的配置选项，可以根据需要调整配置服务器、分片数量、副本集数量和路由器数量，确保高可用性和数据均衡分布。

### 2. 文件结构

部署工具包含以下文件：

* generate-mongodb-swarm.sh - 主脚本，用于生成 Docker Compose 文件和初始化脚本
* docker-compose-swarm.yml - 由脚本生成的 Docker Compose 配置文件
* scripts/init-mongodb.sh - 由脚本生成的 MongoDB 初始化脚本

### 3. 系统要求

* Docker Swarm 集群已初始化
* 集群中有足够的节点，并已标记角色（node.labels.role==mongodb）
* Docker 版本 19.03 或更高
* MongoDB 镜像 (默认使用 mongo:6.0)

### 4. 使用方法

docker swarm init

#### 4.1 准备工作

1. 确保 Docker Swarm 集群已经初始化：

   docker swarm init
2. 为节点添加标签（在每个应该运行 MongoDB 的节点上执行）：

   docker node update --label-add role=mongodb <NODE_ID>
3. 创建部署目录：

   bash

   Apply to generate-mon...

   Run

   **   **mkdir** **-p** **mongodb/swarm

   **   **cd** **mongodb/swarm
4. 将 generate-mongodb-swarm.sh 脚本复制到此目录并设置执行权限：

   bash

   Apply to generate-mon...

   Run

   **   **chmod** **+x** **generate-mongodb-swarm.sh

#### 4.2 生成配置文件

执行以下命令生成 Docker Compose 文件和初始化脚本：

bash

Apply to generate-mon...

Run

**./generate-mongodb-swarm.sh** **[**选项**]**

可用选项：* -c, --config-servers - 配置服务器数量 (默认: 3)

* -s, --shards - 分片数量 (默认: 2)
* -r, --replicas - 每个分片的副本数量 (默认: 3)
* -m, --mongos - Mongos 路由器数量 (默认: 2)
* -o, --output - 输出文件名 (默认: docker-compose-swarm.yml)
* -h, --help - 显示帮助信息

例如，创建一个包含 5 个配置服务器、3 个分片（每个分片 3 个副本）和 2 个 mongos 路由器的集群：

bash

Apply to generate-mon...

Run

**./generate-mongodb-swarm.sh** **--config-servers** **5** **--shards** **3** **--replicas** **3** **--mongos** **2**

#### 4.3 部署集群

生成配置文件后，使用以下命令部署到 Swarm 集群：

bash

Apply to generate-mon...

Run

**docker** **stack** **deploy** **-c** **docker-compose-swarm.yml** **mongodb**

#### 4.4 验证部署

检查服务是否正常运行：

bash

Apply to generate-mon...

Run

**docker** **service** **ls**

查看具体服务的日志：

bash

Apply to generate-mon...

Run

**docker** **service** **logs** **mongodb_mongos-router-1**

#### 4.5 连接到 MongoDB 集群

使用 Mongos 路由器连接到集群：

bash

Apply to generate-mon...

Run

**mongo** **--host** **<**SWARM_NODE_I**P**>**:27017**

或者使用第二个路由器：

bash

Apply to generate-mon...

Run

**mongo** **--host** **<**SWARM_NODE_I**P**>**:27018**

### 5. 集群架构说明

#### 5.1 组件说明

* 配置服务器 (Config Servers)：存储集群元数据，配置为一个副本集
* 分片 (Shards)：存储实际数据，每个分片是一个独立的副本集
* 路由器 (Mongos)：客户端连接点，负责路由查询到适当的分片
* 初始化容器 (mongo-init)：负责配置副本集、添加分片和启用分片功能

#### 5.2 高可用性

* 配置服务器和每个分片至少部署 3 个副本，确保高可用性
* 使用 max_replicas_per_node: 1 确保同一组件的副本分布在不同节点
* 所有服务配置了自动重启策略

#### 5.3 数据持久化

每个 MongoDB 实例使用命名卷进行数据持久化，即使容器重启或迁移，数据也不会丢失。

### 6. 管理操作

#### 6.1 扩展集群

要添加新的分片，需要修改生成脚本的参数并重新部署。

#### 6.2 备份与恢复

可以使用 MongoDB 标准备份工具如 mongodump 和 mongorestore：

bash

Apply to generate-mon...

Run

**# 备份**

**mongodump** **--host** **<**SWARM_NODE_I**P**>**:27017** **--out** **/backup/mongodb_**$**(**date** **+%Y-%m-%d**)**

**# 恢复**

**mongorestore** **--host** **<**SWARM_NODE_I**P**>**:27017** **/backup/mongodb_2023-01-01**

#### 6.3 监控

可以使用 MongoDB 自带的工具或第三方监控解决方案：

bash

Apply to generate-mon...

Run

**# 检查分片状态**

**mongo** **--host** **<**SWARM_NODE_I**P**>**:27017** **--eval** **"sh.status()"**

**# 检查副本集状态**

**mongo** **--host** **<**SWARM_NODE_I**P**>**:27017** **--eval** **"rs.status()"**

### 7. 故障排除

#### 7.1 常见问题

1. 初始化脚本失败

* 检查 mongo-init 服务的日志
* 可能需要增加初始化脚本中的等待时间

1. 节点间连接问题

* 确保集群内网络畅通
* 检查 Docker 网络配置

1. 认证问题

* 确保环境变量 MONGO_ROOT_USER 和 MONGO_ROOT_PASSWORD 正确设置

#### 7.2 日志检查

bash

Apply to generate-mon...

Run

**# 查看初始化容器日志**

**docker** **service** **logs** **mongodb_mongo-init**

**# 查看配置服务器日志**

**docker** **service** **logs** **mongodb_config-server-1**

**# 查看分片服务器日志**

**docker** **service** **logs** **mongodb_shard1-server-1**

### 8. 安全建议

1. 修改默认用户名和密码，使用环境变量传递
2. 配置网络安全组，限制对 MongoDB 端口的访问
3. 考虑启用 TLS/SSL 连接
4. 实施细粒度的访问控制

### 9. 性能优化

1. 根据工作负载特点配置分片键
2. 监控和调整缓存大小
3. 考虑使用 SSD 存储提高性能
4. 为高频查询创建适当的索引

---

以上文档提供了使用 generate-mongodb-swarm.sh 脚本部署和管理 MongoDB 分片集群的完整指南。根据实际环境和需求，您可能需要调整某些配置参数。
