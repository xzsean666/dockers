#!/bin/bash

# 添加调试输出
set -x

echo "Starting GlusterFS setup script..."

# 等待GlusterFS服务就绪 - 增加重试机制
MAX_RETRIES=10
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  echo "Waiting for GlusterFS services to be ready... Attempt $(($RETRY_COUNT + 1))/$MAX_RETRIES"
  sleep 30
  
  # 检查本地glusterd服务是否运行
  if pgrep glusterd > /dev/null; then
    echo "Local glusterd service is running!"
    break
  fi
  
  RETRY_COUNT=$(($RETRY_COUNT + 1))
  
  if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "Maximum retry attempts reached. Local glusterd service is not running. Exiting."
    
    # 尝试手动启动 glusterd
    echo "Attempting to manually start glusterd..."
    mkdir -p /var/run/gluster
    mkdir -p /var/log/glusterfs
    /usr/sbin/glusterd -p /var/run/glusterd.pid --log-level INFO --no-daemon &
    
    # 再等待 30 秒
    sleep 30
    
    if ! pgrep glusterd > /dev/null; then
      echo "Still cannot start glusterd. Printing system diagnostics:"
      
      echo "--- Process List ---"
      ps aux
      
      echo "--- System Logs ---"
      tail -n 50 /var/log/messages || echo "No messages log"
      
      echo "--- Mounted Filesystems ---"
      mount
      
      echo "--- Disk Space ---"
      df -h
      
      echo "--- Network Configuration ---"
      ip addr
      
      echo "--- Container Status ---"
      if command -v docker > /dev/null; then
        docker ps
      fi
      
      exit 1
    else
      echo "Successfully started glusterd manually!"
    fi
  fi
done

# 发现其他 GlusterFS 节点
echo "Discovering other GlusterFS nodes..."
# 等待 DNS 解析更新
sleep 15

# 尝试多种方法获取节点列表
echo "Trying to resolve GlusterFS nodes..."
NODES=$(getent hosts tasks.glusterfs-server | awk '{print $1}')

if [ -z "$NODES" ]; then
  echo "getent failed, trying nslookup..."
  NODES=$(nslookup tasks.glusterfs-server 2>/dev/null | grep Address | grep -v '#' | awk '{print $2}' | grep -v ':')
fi

if [ -z "$NODES" ]; then
  echo "nslookup failed, trying dig..."
  NODES=$(dig +short tasks.glusterfs-server 2>/dev/null)
fi

if [ -z "$NODES" ]; then
  echo "All DNS lookups failed. Trying to use Docker DNS directly..."
  NODES=$(dig +short tasks.glusterfs-server @127.0.0.11 2>/dev/null)
fi

CURRENT_NODE=$(hostname -i)

echo "All nodes: $NODES"
echo "Current node: $CURRENT_NODE"

# 检查是否成功发现了节点
if [ -z "$NODES" ]; then
  echo "No GlusterFS nodes discovered after all attempts. Creating a standalone volume."
  # 如果找不到其他节点，将当前节点作为唯一节点
  NODES=$CURRENT_NODE
fi

# 添加所有其他节点作为对等点
for NODE_IP in $NODES; do
  if [ "$NODE_IP" != "$CURRENT_NODE" ]; then
    echo "Adding peer: $NODE_IP"
    # 增加重试机制
    for i in {1..5}; do
      if gluster peer probe $NODE_IP; then
        echo "Successfully added peer $NODE_IP"
        break
      else
        echo "Peer probe attempt $i failed for $NODE_IP, retrying in 5 seconds..."
        sleep 5
      fi
    done
  fi
done

# 等待对等连接建立
echo "Waiting for peer connections to establish..."
sleep 15

# 显示对等状态
echo "Checking peer status:"
gluster peer status || echo "Could not check peer status"

# 获取所有节点的列表用于创建卷
NODE_LIST=""
for NODE_IP in $NODES; do
  NODE_LIST="$NODE_LIST $NODE_IP:/data/brick"
done

# 创建并启动卷
echo "Creating volume data-vol with nodes: $NODE_LIST"
REPLICA_COUNT=$(echo "$NODES" | wc -w)
echo "Using replica count: $REPLICA_COUNT"

# 尝试创建卷
if ! gluster volume info data-vol > /dev/null 2>&1; then
  echo "Volume does not exist. Creating..."
  # 确保 brick 目录存在
  mkdir -p /data/brick
  chmod 777 /data/brick
  
  # 检查是否单节点
  if [ "$REPLICA_COUNT" -eq 1 ]; then
    echo "Creating single node volume..."
    gluster volume create data-vol $NODE_LIST force || echo "Failed to create volume"
  else
    echo "Creating replicated volume..."
    gluster volume create data-vol replica $REPLICA_COUNT $NODE_LIST force || echo "Failed to create volume"
  fi
else
  echo "Volume already exists"
fi

# 尝试启动卷
if gluster volume info data-vol | grep "Status: Started" > /dev/null; then
  echo "Volume is already started"
else
  echo "Starting volume data-vol"
  gluster volume start data-vol || echo "Failed to start volume"
fi

# 显示卷信息
echo "Volume information:"
gluster volume info || echo "Could not get volume info"

echo "GlusterFS setup completed." 