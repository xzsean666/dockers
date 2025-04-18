#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 获取容器名称
get_container_name() {
    local container_name=$(grep -A 1 "container_name:" docker-compose.yml | grep -v "container_name:" | tr -d '[:space:]')
    echo "${container_name:-postgresql-master}"
}

# 设置容器名称变量
CONTAINER_NAME=$(get_container_name)

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}请使用sudo运行此脚本${NC}"
    exit 1
fi

# 显示菜单
show_menu() {
    echo -e "\n${GREEN}PostgreSQL 备份恢复工具${NC}"
    echo "1. 查看所有备份"
    echo "2. 创建完整备份"
    echo "3. 恢复到最新备份"
    echo "4. 恢复到指定时间点"
    echo "5. 删除过期备份"
    echo "6. 退出"
    echo -n "请选择操作 [1-6]: "
}

# 查看所有备份
list_backups() {
    echo -e "\n${YELLOW}正在列出所有备份...${NC}"
    docker exec $CONTAINER_NAME wal-g backup-list
}

# 创建完整备份
create_backup() {
    echo -e "\n${YELLOW}正在创建完整备份...${NC}"
    docker exec $CONTAINER_NAME wal-g backup-push /bitnami/postgresql/data
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}备份创建成功！${NC}"
    else
        echo -e "${RED}备份创建失败！${NC}"
    fi
}

# 恢复到最新备份
restore_latest() {
    echo -e "\n${YELLOW}正在恢复到最新备份...${NC}"
    read -p "此操作将覆盖当前数据，是否继续？(y/n): " confirm
    if [ "$confirm" != "y" ]; then
        echo "操作已取消"
        return
    fi

    docker-compose stop $CONTAINER_NAME
    docker-compose run --rm $CONTAINER_NAME bash -c "wal-g backup-fetch /bitnami/postgresql/data LATEST"
    docker-compose start $CONTAINER_NAME
    echo -e "${GREEN}恢复完成！${NC}"
}

# 恢复到指定时间点
restore_to_time() {
    echo -e "\n${YELLOW}请输入要恢复的时间点 (格式: YYYY-MM-DD HH:MM:SS UTC)${NC}"
    read -p "时间点: " target_time
    read -p "此操作将覆盖当前数据，是否继续？(y/n): " confirm
    if [ "$confirm" != "y" ]; then
        echo "操作已取消"
        return
    fi

    docker-compose stop $CONTAINER_NAME
    docker-compose run --rm $CONTAINER_NAME rm -rf /bitnami/postgresql/data/*
    docker-compose run --rm $CONTAINER_NAME bash -c "
        wal-g backup-fetch /bitnami/postgresql/data LATEST && 
        echo \"restore_command = 'wal-g wal-fetch %f %p'\" > /bitnami/postgresql/data/recovery.conf && 
        echo \"recovery_target_time = '$target_time'\" >> /bitnami/postgresql/data/recovery.conf && 
        echo \"recovery_target_action = 'promote'\" >> /bitnami/postgresql/data/recovery.conf
    "
    docker-compose start $CONTAINER_NAME
    echo -e "${GREEN}恢复完成！${NC}"
}

# 删除过期备份
delete_old_backups() {
    echo -e "\n${YELLOW}请输入要保留的备份数量${NC}"
    read -p "保留数量: " retain_count
    read -p "确认删除除最近 $retain_count 个备份外的所有备份？(y/n): " confirm
    if [ "$confirm" != "y" ]; then
        echo "操作已取消"
        return
    fi

    docker exec $CONTAINER_NAME wal-g delete retain FULL $retain_count
    echo -e "${GREEN}删除完成！${NC}"
}

# 主循环
while true; do
    show_menu
    read choice
    case $choice in
        1) list_backups ;;
        2) create_backup ;;
        3) restore_latest ;;
        4) restore_to_time ;;
        5) delete_old_backups ;;
        6) echo "退出程序"; exit 0 ;;
        *) echo -e "${RED}无效选择，请重试${NC}" ;;
    esac
done 