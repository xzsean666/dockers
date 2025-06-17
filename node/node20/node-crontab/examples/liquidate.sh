#!/bin/bash

# 设置日志文件路径
LOG_FILE="/app/liquidate.log"

# 记录开始时间
echo "$(date): 开始执行 liquidate 脚本" >> $LOG_FILE

# 进入项目目录
cd /app/macaron/macaron-helper-sdk

# 使用绝对路径执行 yarn 和 node 命令
YARN_PATH="/usr/local/bin/yarn"
NODE_PATH="/usr/local/bin/node"

# 确保所有依赖都已安装
# $YARN_PATH install >> $LOG_FILE 2>&1

# 运行liquidate命令并记录输出
$NODE_PATH dist/scripts/liquidate.js >> $LOG_FILE 2>&1

# 记录结束时间
echo "$(date): liquidate 脚本执行完成" >> $LOG_FILE