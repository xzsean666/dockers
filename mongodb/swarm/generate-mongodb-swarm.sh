#!/bin/bash

# 默认参数
CONFIG_SERVERS=3
SHARDS=2
REPLICAS_PER_SHARD=3
MONGOS_ROUTERS=2
OUTPUT_FILE="docker-compose-swarm.yml"

# 帮助信息
function show_help {
  echo "使用方法: $0 [选项]"
  echo "选项:"
  echo "  -c, --config-servers     配置服务器数量 (默认: 3)"
  echo "  -s, --shards             分片数量 (默认: 2)"
  echo "  -r, --replicas           每个分片的副本数量 (默认: 3)"
  echo "  -m, --mongos             Mongos 路由器数量 (默认: 2)"
  echo "  -o, --output             输出文件名 (默认: docker-compose-swarm.yml)"
  echo "  -h, --help               显示帮助信息"
  exit 0
}

# 解析命令行参数
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -c|--config-servers) CONFIG_SERVERS="$2"; shift ;;
    -s|--shards) SHARDS="$2"; shift ;;
    -r|--replicas) REPLICAS_PER_SHARD="$2"; shift ;;
    -m|--mongos) MONGOS_ROUTERS="$2"; shift ;;
    -o|--output) OUTPUT_FILE="$2"; shift ;;
    -h|--help) show_help ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
  shift
done

# 验证参数
if [[ $CONFIG_SERVERS -lt 3 ]]; then
  echo "警告: 配置服务器数量应至少为3以保证高可用性"
  CONFIG_SERVERS=3
fi

if [[ $REPLICAS_PER_SHARD -lt 3 ]]; then
  echo "警告: 每个分片的副本数应至少为3以保证高可用性"
  REPLICAS_PER_SHARD=3
fi

# 创建docker-compose文件头部
cat > $OUTPUT_FILE << EOL
version: '3.8'

services:
EOL

# 添加配置服务器
for ((i=1; i<=$CONFIG_SERVERS; i++)); do
  cat >> $OUTPUT_FILE << EOL
  # 配置服务器 $i
  config-server-$i:
    image: mongo:6.0
    command: mongod --configsvr --replSet configrs --port 27017 --dbpath /data/db
    volumes:
      - config-server-$i-data:/data/db
    networks:
      - mongodb-network
    deploy:
      placement:
        constraints:
          - node.labels.role==mongodb
        max_replicas_per_node: 1
      replicas: 1
      restart_policy:
        condition: on-failure
    environment:
      MONGO_INITDB_ROOT_USERNAME: \${MONGO_ROOT_USER:-admin}
      MONGO_INITDB_ROOT_PASSWORD: \${MONGO_ROOT_PASSWORD:-admin123}

EOL
done

# 添加分片服务器
for ((s=1; s<=$SHARDS; s++)); do
  for ((r=1; r<=$REPLICAS_PER_SHARD; r++)); do
    cat >> $OUTPUT_FILE << EOL
  # 分片 $s 副本 $r
  shard$s-server-$r:
    image: mongo:6.0
    command: mongod --shardsvr --replSet shard${s}rs --port 27017 --dbpath /data/db
    volumes:
      - shard$s-server-$r-data:/data/db
    networks:
      - mongodb-network
    deploy:
      placement:
        constraints:
          - node.labels.role==mongodb
        max_replicas_per_node: 1
      replicas: 1
      restart_policy:
        condition: on-failure
    environment:
      MONGO_INITDB_ROOT_USERNAME: \${MONGO_ROOT_USER:-admin}
      MONGO_INITDB_ROOT_PASSWORD: \${MONGO_ROOT_PASSWORD:-admin123}

EOL
  done
done

# 构建配置服务器列表
CONFIG_SERVER_LIST=""
for ((i=1; i<=$CONFIG_SERVERS; i++)); do
  if [[ $i -gt 1 ]]; then
    CONFIG_SERVER_LIST+=","
  fi
  CONFIG_SERVER_LIST+="config-server-$i:27017"
done

# 添加mongos路由器
for ((i=1; i<=$MONGOS_ROUTERS; i++)); do
  if [[ $i -eq 1 ]]; then
    PORT=27017
  else
    PORT=$((30700+$i-1))
  fi
  cat >> $OUTPUT_FILE << EOL
  # Mongos 路由服务器 $i
  mongos-router-$i:
    image: mongo:6.0
    command: mongos --configdb configrs/$CONFIG_SERVER_LIST --port 27017 --bind_ip_all
    ports:
      - "$PORT:27017"
    networks:
      - mongodb-network
    depends_on:
EOL

  # 添加所有依赖
  for ((c=1; c<=$CONFIG_SERVERS; c++)); do
    echo "      - config-server-$c" >> $OUTPUT_FILE
  done
  
  for ((s=1; s<=$SHARDS; s++)); do
    for ((r=1; r<=$REPLICAS_PER_SHARD; r++)); do
      echo "      - shard$s-server-$r" >> $OUTPUT_FILE
    done
  done

  cat >> $OUTPUT_FILE << EOL
    deploy:
      placement:
        constraints:
          - node.labels.role==mongodb
        max_replicas_per_node: 1
      replicas: 1
      restart_policy:
        condition: on-failure

EOL
done

# 生成初始化脚本
mkdir -p scripts
INIT_SCRIPT="scripts/init-mongodb.sh"

cat > $INIT_SCRIPT << EOL
#!/bin/bash

# 等待服务启动
sleep 30

echo "Initializing Config Server Replica Set..."
mongo --host config-server-1:27017 -u \${MONGO_ROOT_USER:-admin} -p \${MONGO_ROOT_PASSWORD:-admin123} --authenticationDatabase admin <<EOF
rs.initiate(
  {
    _id: "configrs",
    configsvr: true,
    members: [
EOL

# 添加配置服务器成员
for ((i=1; i<=$CONFIG_SERVERS; i++)); do
  if [[ $i -eq $CONFIG_SERVERS ]]; then
    echo "      { _id: $((i-1)), host: \"config-server-$i:27017\" }" >> $INIT_SCRIPT
  else
    echo "      { _id: $((i-1)), host: \"config-server-$i:27017\" }," >> $INIT_SCRIPT
  fi
done

cat >> $INIT_SCRIPT << EOL
    ]
  }
)
EOF

echo "Waiting for Config Server Replica Set to initialize..."
sleep 20

EOL

# 添加分片replica set初始化
for ((s=1; s<=$SHARDS; s++)); do
  cat >> $INIT_SCRIPT << EOL
echo "Initializing Shard $s Replica Set..."
mongo --host shard$s-server-1:27017 <<EOF
rs.initiate(
  {
    _id: "shard${s}rs",
    members: [
EOL

  # 添加分片成员
  for ((r=1; r<=$REPLICAS_PER_SHARD; r++)); do
    if [[ $r -eq $REPLICAS_PER_SHARD ]]; then
      echo "      { _id: $((r-1)), host: \"shard$s-server-$r:27017\" }" >> $INIT_SCRIPT
    else
      echo "      { _id: $((r-1)), host: \"shard$s-server-$r:27017\" }," >> $INIT_SCRIPT
    fi
  done

  cat >> $INIT_SCRIPT << EOL
    ]
  }
)
EOF

echo "Waiting for Shard $s Replica Set to initialize..."
sleep 20

EOL
done

# 添加分片到集群
cat >> $INIT_SCRIPT << EOL
echo "Adding shards to the cluster..."
mongo --host mongos-router-1:27017 <<EOF
EOL

for ((s=1; s<=$SHARDS; s++)); do
  SHARD_SERVERS=""
  for ((r=1; r<=$REPLICAS_PER_SHARD; r++)); do
    if [[ $r -gt 1 ]]; then
      SHARD_SERVERS+=","
    fi
    SHARD_SERVERS+="shard$s-server-$r:27017"
  done
  echo "sh.addShard(\"shard${s}rs/$SHARD_SERVERS\")" >> $INIT_SCRIPT
done

cat >> $INIT_SCRIPT << EOL
EOF

echo "Enabling sharding for test database and collection..."
mongo --host mongos-router-1:27017 <<EOF
sh.enableSharding("testdb")
db.createCollection("testdb.testcollection")
sh.shardCollection("testdb.testcollection", { "_id": "hashed" })
EOF

echo "MongoDB Sharded Cluster Initialization Complete!"
EOL

chmod +x $INIT_SCRIPT

# 将初始化服务添加到compose文件
cat >> $OUTPUT_FILE << EOL
  # 初始化服务
  mongo-init:
    image: mongo:6.0
    volumes:
      - ./scripts:/scripts
    networks:
      - mongodb-network
    entrypoint: ["bash", "/scripts/init-mongodb.sh"]
    depends_on:
EOL

# 添加所有依赖
for ((i=1; i<=$MONGOS_ROUTERS; i++)); do
  echo "      - mongos-router-$i" >> $OUTPUT_FILE
done

for ((c=1; c<=$CONFIG_SERVERS; c++)); do
  echo "      - config-server-$c" >> $OUTPUT_FILE
done

for ((s=1; s<=$SHARDS; s++)); do
  for ((r=1; r<=$REPLICAS_PER_SHARD; r++)); do
    echo "      - shard$s-server-$r" >> $OUTPUT_FILE
  done
done

cat >> $OUTPUT_FILE << EOL
    deploy:
      restart_policy:
        condition: on-failure
        max_attempts: 3
      placement:
        constraints:
          - node.labels.role==mongodb

networks:
  mongodb-network:
    driver: overlay
    attachable: true

volumes:
EOL

# 添加所有数据卷
for ((c=1; c<=$CONFIG_SERVERS; c++)); do
  echo "  config-server-$c-data:" >> $OUTPUT_FILE
done

for ((s=1; s<=$SHARDS; s++)); do
  for ((r=1; r<=$REPLICAS_PER_SHARD; r++)); do
    echo "  shard$s-server-$r-data:" >> $OUTPUT_FILE
  done
done

echo "已生成 MongoDB Swarm 配置文件: $OUTPUT_FILE 和初始化脚本: $INIT_SCRIPT" 