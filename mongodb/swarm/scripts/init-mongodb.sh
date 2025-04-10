#!/bin/bash

# 等待服务启动
sleep 30

echo "Initializing Config Server Replica Set..."
mongo --host config-server-1:27017 -u ${MONGO_ROOT_USER:-admin} -p ${MONGO_ROOT_PASSWORD:-admin123} --authenticationDatabase admin <<EOF
rs.initiate(
  {
    _id: "configrs",
    configsvr: true,
    members: [
      { _id: 0, host: "config-server-1:27017" },
      { _id: 1, host: "config-server-2:27017" },
      { _id: 2, host: "config-server-3:27017" }
    ]
  }
)
EOF

echo "Waiting for Config Server Replica Set to initialize..."
sleep 20

echo "Initializing Shard 1 Replica Set..."
mongo --host shard1-server-1:27017 <<EOF
rs.initiate(
  {
    _id: "shard1rs",
    members: [
      { _id: 0, host: "shard1-server-1:27017" },
      { _id: 1, host: "shard1-server-2:27017" },
      { _id: 2, host: "shard1-server-3:27017" }
    ]
  }
)
EOF

echo "Waiting for Shard 1 Replica Set to initialize..."
sleep 20

echo "Initializing Shard 2 Replica Set..."
mongo --host shard2-server-1:27017 <<EOF
rs.initiate(
  {
    _id: "shard2rs",
    members: [
      { _id: 0, host: "shard2-server-1:27017" },
      { _id: 1, host: "shard2-server-2:27017" },
      { _id: 2, host: "shard2-server-3:27017" }
    ]
  }
)
EOF

echo "Waiting for Shard 2 Replica Set to initialize..."
sleep 20

echo "Adding shards to the cluster..."
mongo --host mongos-router-1:27017 <<EOF
sh.addShard("shard1rs/shard1-server-1:27017,shard1-server-2:27017,shard1-server-3:27017")
sh.addShard("shard2rs/shard2-server-1:27017,shard2-server-2:27017,shard2-server-3:27017")
EOF

echo "Enabling sharding for test database and collection..."
mongo --host mongos-router-1:27017 <<EOF
sh.enableSharding("testdb")
db.createCollection("testdb.testcollection")
sh.shardCollection("testdb.testcollection", { "_id": "hashed" })
EOF

echo "MongoDB Sharded Cluster Initialization Complete!"
