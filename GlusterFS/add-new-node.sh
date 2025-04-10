#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}GlusterFS集群添加新节点脚本${NC}"

# 卷名称配置 - 确保与现有卷相同
VOLUME_NAME="gfs_volume"  # 修改为您现有的卷名称

# 获取本机IP地址
MY_IP=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}本机IP: $MY_IP${NC}"

# 新节点设置
if [ "$1" == "new" ]; then
    echo -e "${YELLOW}作为新节点设置...${NC}"
    
    # 创建所需目录
    mkdir -p ./gluster-data/brick
    mkdir -p ./gluster-config
    
    # 启动GlusterFS容器
    echo -e "${YELLOW}启动GlusterFS容器...${NC}"
    docker-compose up -d
    
    # 等待GlusterFS服务启动
    echo -e "${YELLOW}等待GlusterFS服务启动...${NC}"
    sleep 10
    
    # 获取容器ID
    CONTAINER_ID=$(docker ps | grep gluster-node | awk '{print $1}')
    if [ -z "$CONTAINER_ID" ]; then
        echo -e "${RED}错误: 未找到GlusterFS容器${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}新节点容器已启动: $MY_IP${NC}"
    echo -e "${YELLOW}请在主节点上运行: ./add-new-node.sh master $MY_IP${NC}"
    
    exit 0
fi

# 主节点设置 - 添加新节点
if [ "$1" == "master" ]; then
    if [ -z "$2" ]; then
        echo -e "${RED}错误: 请提供新节点的IP地址${NC}"
        echo -e "${YELLOW}用法: ./add-new-node.sh master <新节点IP>${NC}"
        exit 1
    fi
    
    NEW_NODE_IP="$2"
    echo -e "${YELLOW}作为主节点运行，将添加新节点: $NEW_NODE_IP${NC}"
    
    # 获取容器ID
    CONTAINER_ID=$(docker ps | grep gluster-node | awk '{print $1}')
    if [ -z "$CONTAINER_ID" ]; then
        echo -e "${RED}错误: 未找到GlusterFS容器${NC}"
        exit 1
    fi
    
    # 添加新节点为peer
    echo -e "${YELLOW}添加节点 $NEW_NODE_IP 作为peer...${NC}"
    docker exec $CONTAINER_ID gluster peer probe $NEW_NODE_IP
    if [ $? -ne 0 ]; then
        echo -e "${RED}添加节点失败${NC}"
        exit 1
    fi
    
    # 等待peer连接就绪
    echo -e "${YELLOW}等待peer连接就绪...${NC}"
    sleep 5
    
    # 检查peer状态
    docker exec $CONTAINER_ID gluster peer status
    
    # 获取卷信息
    echo -e "${YELLOW}获取卷信息...${NC}"
    VOLUME_INFO=$(docker exec $CONTAINER_ID gluster volume info $VOLUME_NAME)
    if [ $? -ne 0 ]; then
        echo -e "${RED}获取卷信息失败，请确认卷名称正确${NC}"
        exit 1
    fi
    
    # 检查卷类型并获取副本数
    echo "$VOLUME_INFO" | grep "Type:"
    REPLICA_COUNT=$(echo "$VOLUME_INFO" | grep "Number of Bricks:" | awk '{print $4}')
    NEW_REPLICA_COUNT=$((REPLICA_COUNT + 1))
    
    echo -e "${YELLOW}当前副本数: $REPLICA_COUNT, 新副本数: $NEW_REPLICA_COUNT${NC}"
    
    # 添加brick到卷
    echo -e "${YELLOW}添加新节点的brick到卷...${NC}"
    docker exec $CONTAINER_ID gluster volume add-brick $VOLUME_NAME replica $NEW_REPLICA_COUNT $NEW_NODE_IP:/data/brick force
    if [ $? -ne 0 ]; then
        echo -e "${RED}添加brick失败${NC}"
        exit 1
    fi
    
    # 检查卷信息
    echo -e "${YELLOW}检查更新后的卷信息...${NC}"
    docker exec $CONTAINER_ID gluster volume info $VOLUME_NAME
    
    # 开始重平衡
    echo -e "${YELLOW}开始数据重平衡...${NC}"
    docker exec $CONTAINER_ID gluster volume rebalance $VOLUME_NAME start
    
    echo -e "${GREEN}新节点 $NEW_NODE_IP 已成功添加到集群${NC}"
    echo -e "${YELLOW}数据重平衡已启动，可以通过以下命令检查状态:${NC}"
    echo -e "${YELLOW}docker exec <容器ID> gluster volume rebalance $VOLUME_NAME status${NC}"
    
    exit 0
fi

# 显示使用帮助
echo -e "${RED}错误: 请指定操作模式${NC}"
echo -e "${YELLOW}用法:${NC}"
echo -e "${YELLOW}  作为新节点: ./add-new-node.sh new${NC}"
echo -e "${YELLOW}  作为主节点: ./add-new-node.sh master <新节点IP>${NC}" 