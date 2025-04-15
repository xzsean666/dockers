#!/bin/bash

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