#!/bin/bash

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}请使用sudo运行此脚本${NC}"
    exit 1
fi

# 检查必要的命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}错误: $1 未安装${NC}"
        exit 1
    fi
}

check_command docker
check_command docker-compose

# 创建必要的目录
echo -e "${YELLOW}创建必要的目录...${NC}"
mkdir -p data config

# 检查.env文件是否存在
if [ ! -f .env ]; then
    echo -e "${RED}错误: .env 文件不存在${NC}"
    echo -e "${YELLOW}请确保已配置好 .env 文件${NC}"
    exit 1
fi

# 检查PostgreSQL连接
echo -e "${YELLOW}检查PostgreSQL连接...${NC}"
PG_URL=$(grep JFS_META_URL .env | cut -d '=' -f2)
if ! docker run --rm --env-file .env juicedata/juicefs status $PG_URL &> /dev/null; then
    echo -e "${RED}错误: 无法连接到PostgreSQL数据库${NC}"
    exit 1
fi

# 格式化文件系统（如果尚未格式化）
echo -e "${YELLOW}检查文件系统格式化状态...${NC}"
if ! docker run --rm --env-file .env juicedata/juicefs status $PG_URL &> /dev/null; then
    echo -e "${YELLOW}格式化文件系统...${NC}"
    docker run --rm \
        --env-file .env \
        juicedata/juicefs format \
        --storage $(grep JFS_STORAGE .env | cut -d '=' -f2) \
        --bucket $(grep JFS_BUCKET .env | cut -d '=' -f2) \
        $PG_URL myjfs
fi

# 启动JuiceFS服务
echo -e "${YELLOW}启动JuiceFS服务...${NC}"
docker-compose up -d

# 等待服务启动
echo -e "${YELLOW}等待服务启动...${NC}"
sleep 5

# 检查服务状态
if docker ps | grep -q juicefs; then
    echo -e "${GREEN}JuiceFS服务已成功启动${NC}"
    
    # 显示挂载状态
    echo -e "${YELLOW}文件系统状态:${NC}"
    docker exec juicefs juicefs status /data
    
    # 测试写入
    echo -e "${YELLOW}执行测试写入...${NC}"
    docker exec juicefs sh -c "echo 'JuiceFS test file' > /data/test.txt"
    
    # 显示测试文件
    echo -e "${YELLOW}测试文件内容:${NC}"
    docker exec juicefs cat /data/test.txt
    
    echo -e "${GREEN}部署完成！${NC}"
    echo -e "${YELLOW}JuiceFS已挂载到 ./data 目录${NC}"
else
    echo -e "${RED}错误: JuiceFS服务启动失败${NC}"
    exit 1
fi 