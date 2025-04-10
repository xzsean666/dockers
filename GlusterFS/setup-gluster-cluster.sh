#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}GlusterFS集群设置脚本${NC}"

# 在这里预先定义所有集群节点的IP地址
# 修改这个数组以包含所有节点的IP地址
ALL_NODES=(
    "192.168.31.17"
    "192.168.31.135"
)

# 卷名称配置
VOLUME_NAME="gfs_volume"  # 修改为您想要的卷名称

# 获取本机IP地址 (使用主网卡的IP)
MY_IP=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}本机IP: $MY_IP${NC}"

# 检查本机IP是否在集群节点列表中
if [[ ! " ${ALL_NODES[@]} " =~ " ${MY_IP} " ]]; then
    echo -e "${RED}警告: 本机IP ($MY_IP) 不在预定义的集群节点列表中${NC}"
    echo -e "${YELLOW}是否继续? (y/n)${NC}"
    read -r continue_setup
    if [[ "$continue_setup" != "y" && "$continue_setup" != "Y" ]]; then
        echo -e "${RED}设置已取消${NC}"
        exit 1
    fi
fi

# 创建所需目录
mkdir -p ./gluster-data/brick
mkdir -p ./gluster-config

# 启动GlusterFS容器
echo -e "${YELLOW}启动GlusterFS容器...${NC}"
docker-compose down -v # 先停止并清理任何已存在的容器
docker-compose up -d

# 等待GlusterFS服务启动（增加更长的等待时间）
echo -e "${YELLOW}等待GlusterFS服务启动...${NC}"
sleep 30  # 增加等待时间，确保服务完全启动

# 获取容器ID
CONTAINER_ID=$(docker ps | grep gluster-node | awk '{print $1}')
if [ -z "$CONTAINER_ID" ]; then
    echo -e "${RED}错误: 未找到GlusterFS容器${NC}"
    exit 1
fi

# 显示容器详细信息和网络配置
echo -e "${YELLOW}容器详细信息:${NC}"
docker inspect $CONTAINER_ID | grep -E "IPAddress|NetworkMode"
echo -e "${YELLOW}容器网络配置:${NC}"
docker exec $CONTAINER_ID ip addr
docker exec $CONTAINER_ID hostname

# 确保glusterd服务正在运行
echo -e "${YELLOW}确保GlusterFS守护进程正在运行...${NC}"
# Don't use systemctl which requires working systemd
docker exec $CONTAINER_ID sh -c "pkill glusterd || true"
sleep 2
docker exec $CONTAINER_ID sh -c "mkdir -p /var/run/gluster && mkdir -p /var/log/glusterfs"
docker exec $CONTAINER_ID sh -c "glusterd -p /var/run/glusterd.pid"
sleep 10  # Give more time for the service to start

# Verify glusterd is running
docker exec $CONTAINER_ID sh -c "ps aux | grep glusterd"
docker exec $CONTAINER_ID sh -c "netstat -tlpn | grep 24007 || true"

# 检查GlusterFS服务状态
echo -e "${YELLOW}检查GlusterFS服务状态...${NC}"
docker exec $CONTAINER_ID ps aux | grep glusterd
docker exec $CONTAINER_ID netstat -tulpn | grep glusterd
docker exec $CONTAINER_ID gluster --version

# 检查端口是否正确开放
echo -e "${YELLOW}检查GlusterFS端口...${NC}"
docker exec $CONTAINER_ID netstat -tulpn | grep 24007

# 检查防火墙状态
echo -e "${YELLOW}检查防火墙状态...${NC}"
docker exec $CONTAINER_ID sh -c "command -v firewall-cmd && firewall-cmd --state || echo '没有安装 firewalld'"
docker exec $CONTAINER_ID sh -c "command -v ufw && ufw status || echo '没有安装 ufw'"

echo -e "${GREEN}GlusterFS服务已启动${NC}"

# 找出其他节点的IP (排除本机IP)
PEER_IPS=()
for ip in "${ALL_NODES[@]}"; do
    if [ "$ip" != "$MY_IP" ]; then
        PEER_IPS+=("$ip")
    fi
done

if [ ${#PEER_IPS[@]} -eq 0 ]; then
    echo -e "${YELLOW}没有其他节点IP，将仅设置单节点。${NC}"
else
    # 测试与其他节点的连接
    for ip in "${PEER_IPS[@]}"; do
        echo -e "${YELLOW}测试与节点 $ip 的连接...${NC}"
        docker exec $CONTAINER_ID ping -c 3 $ip
        docker exec $CONTAINER_ID nc -zv $ip 24007 || echo "无法连接到 $ip:24007"
    done

    # Before adding peers, update container's hosts file with peer information
    for ip in "${PEER_IPS[@]}"; do
        # Add an entry to hosts file for each peer
        PEER_HOSTNAME="gluster-node-${ip//\./-}"  # Create a hostname like gluster-node-192-168-31-135
        echo -e "${YELLOW}Adding host entry for ${ip} as ${PEER_HOSTNAME}${NC}"
        
        # Instead of directly writing to /etc/hosts which is mounted as read-only
        # Create or update a custom hosts file inside the container
        docker exec $CONTAINER_ID sh -c "echo '${ip} ${PEER_HOSTNAME}' >> /etc/hosts"
        docker exec $CONTAINER_ID sh -c "cat /etc/hosts.gluster >> /tmp/combined_hosts"
        docker exec $CONTAINER_ID sh -c "cat /etc/hosts >> /tmp/combined_hosts"
        docker exec $CONTAINER_ID sh -c "cp /tmp/combined_hosts /etc/hosts.custom"
        # Use the custom hosts file for name resolution
        docker exec $CONTAINER_ID sh -c "export HOSTALIASES=/etc/hosts.custom"
    done

    # 添加peers
    for ip in "${PEER_IPS[@]}"; do
        echo -e "${YELLOW}添加节点 $ip 作为peer...${NC}"
        # 先确保可以连接到对方节点的GlusterFS端口
        docker exec $CONTAINER_ID nc -zv $ip 24007
        conn_status=$?
        
        if [ $conn_status -ne 0 ]; then
            echo -e "${RED}无法连接到节点 $ip 的GlusterFS端口，请检查网络和防火墙设置${NC}"
            continue
        fi
        
        # 将IP添加到/etc/hosts，确保主机名可正确解析
        docker exec $CONTAINER_ID sh -c "grep -v '$ip' /etc/hosts > /tmp/hosts"
        docker exec $CONTAINER_ID sh -c "echo '$ip gluster-peer-$ip' >> /tmp/hosts"
        docker exec $CONTAINER_ID sh -c "cat /tmp/hosts > /etc/hosts"
        
        # 尝试添加对等节点，现在使用IP而不是主机名
        for attempt in {1..3}; do
            echo -e "${YELLOW}尝试 #${attempt} 添加节点 $ip${NC}"
            # 直接使用IP地址而不是主机名
            docker exec $CONTAINER_ID gluster peer probe $ip
            PROBE_STATUS=$?
            
            if [ $PROBE_STATUS -eq 0 ]; then
                echo -e "${GREEN}成功添加节点 $ip${NC}"
                break
            else
                echo -e "${RED}添加失败，等待重试...${NC}"
                # 显示更详细的错误信息
                docker exec $CONTAINER_ID glusterd --no-daemon --log-level DEBUG &
                sleep 2
                docker exec $CONTAINER_ID killall glusterd
                sleep 3
                docker exec $CONTAINER_ID glusterd
                sleep 5
            fi
        done
        
        # 检查peer状态
        echo -e "${YELLOW}检查peer状态...${NC}"
        docker exec $CONTAINER_ID gluster peer status
    done
fi

# 只在第一个节点上创建卷
# 通过比较当前IP和预定义列表中的第一个IP来确定
FIRST_NODE=${ALL_NODES[0]}

if [ "$MY_IP" == "$FIRST_NODE" ] && [ ${#PEER_IPS[@]} -gt 0 ]; then
    echo -e "${YELLOW}当前节点是主节点，将创建分布式复制卷: $VOLUME_NAME${NC}"
    
    # 等待所有peer连接就绪
    echo -e "${YELLOW}等待所有peer连接就绪...${NC}"
    sleep 10
    
    # 构建卷创建命令
    VOLUME_CMD="gluster volume create $VOLUME_NAME replica ${#ALL_NODES[@]}"
    
    for ip in "${ALL_NODES[@]}"; do
        # 直接使用IP而不是主机名
        VOLUME_CMD="$VOLUME_CMD $ip:/data/brick"
    done
    
    echo -e "${YELLOW}创建卷: $VOLUME_NAME${NC}"
    echo -e "${YELLOW}执行: $VOLUME_CMD${NC}"
    
    docker exec $CONTAINER_ID bash -c "$VOLUME_CMD"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}卷创建成功${NC}"
        
        # 启动卷
        echo -e "${YELLOW}启动卷: $VOLUME_NAME${NC}"
        docker exec $CONTAINER_ID gluster volume start $VOLUME_NAME
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}卷启动成功${NC}"
            # 显示卷信息
            docker exec $CONTAINER_ID gluster volume info $VOLUME_NAME
        else
            echo -e "${RED}卷启动失败${NC}"
        fi
    else
        echo -e "${RED}卷创建失败${NC}"
    fi
elif [ "$MY_IP" != "$FIRST_NODE" ]; then
    echo -e "${YELLOW}当前节点不是主节点，跳过卷创建步骤${NC}"
fi

echo -e "${GREEN}GlusterFS集群设置完成!${NC}" 