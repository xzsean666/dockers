#!/bin/bash

# Function to check and install pm2
check_and_install_pm2() {
    if ! command -v pm2 &> /dev/null; then
        echo "pm2 未安装。尝试使用 npm 进行全局安装..."
        if command -v npm &> /dev/null; then
            npm install pm2 -g
            if [ $? -ne 0 ]; then
                echo "npm 安装 pm2 失败。尝试使用 yarn..."
                if command -v yarn &> /dev/null; then
                    yarn global add pm2
                    if [ $? -ne 0 ]; then
                        echo "yarn 安装 pm2 失败。尝试使用 pnpm..."
                        if command -v pnpm &> /dev/null; then
                            pnpm install pm2 -g
                            if [ $? -ne 0 ]; then
                                echo "pnpm 安装 pm2 失败。请手动安装 pm2 (npm install -g pm2, yarn global add pm2, 或 pnpm install -g pm2)。"
                                exit 1
                            fi
                        else
                            echo "未找到 pnpm 命令。请手动安装 pm2。"
                            exit 1
                        fi
                    fi
                else
                    echo "未找到 yarn 命令。请手动安装 pm2。"
                    exit 1
                fi
            fi
        else
            echo "未找到 npm 命令。请手动安装 pm2。"
            exit 1
        fi
        # 再次检查是否安装成功
        if ! command -v pm2 &> /dev/null; then
            echo "pm2 安装失败，请手动安装。"
            exit 1
        fi
        echo "pm2 安装成功！"
    fi
}

# Function to build PM2 start command
build_pm2_command() {
    local app_name="$1"
    local start_path="$2"
    local cmd="pm2 start \"$start_path\" --name \"$app_name\""
    
    # Add basic node arguments
    cmd="$cmd --node-args=\"--max-old-space-size=4096\""
    
    echo "$cmd"
}

# Check if parameters are provided
if [ $# -eq 0 ]; then
    echo "请提供参数: --start <启动路径> 或 --stop 或 --restart [启动路径] 或 --status 或 --logs"
    echo ""
    echo "用法:"
    echo "  $0 --start <启动路径>      启动 bot (例如: $0 --start dist/main.js)"
    echo "  $0 --stop                 停止 bot"
    echo "  $0 --restart              重启已运行的 bot"
    echo "  $0 --restart <启动路径>    重启 bot 或启动新 bot (如果未运行)"
    echo "  $0 --status               查看 bot 状态"
    echo "  $0 --logs [行数]           查看 bot 日志 (默认显示最近50行)"
    echo ""
    echo "示例:"
    echo "  $0 --start dist/main.js"
    echo "  $0 --start src/index.js"
    echo "  $0 --start bot.js"
    echo "  $0 --logs"
    echo "  $0 --logs 100"
    exit 1
fi

# Get current directory name
CURRENT_DIR=$(pwd)
DIR_NAME=$(basename "$CURRENT_DIR")
APP_NAME_FILE="bot.name"

case "$1" in
    --start)
        # Check if start path is provided
        if [ -z "$2" ]; then
            echo "错误：请提供启动路径"
            echo "用法: $0 --start <启动路径>"
            echo "例如: $0 --start dist/main.js"
            exit 1
        fi
        
        START_PATH="$2"
        
        # Check if start file exists
        if [ ! -f "$START_PATH" ]; then
            echo "错误：找不到启动文件 '$START_PATH'"
            exit 1
        fi
        
        # Check and install pm2
        check_and_install_pm2

        # Check if bot is already running
        if [ -f "$APP_NAME_FILE" ]; then
            EXISTING_NAME=$(cat "$APP_NAME_FILE")
            if pm2 list | grep -q "$EXISTING_NAME"; then
                echo "Bot $EXISTING_NAME 已在运行中。"
                echo "使用 '$0 --stop' 停止，或使用 '$0 --restart' 重启"
                exit 1
            fi
        fi

        # Generate dynamic name and save it
        TIMESTAMP=$(date '+%Y%m%d%H%M%S')
        APP_NAME="${DIR_NAME}-bot-${TIMESTAMP}"
        echo "$APP_NAME" > "$APP_NAME_FILE"
        echo "Bot 名称已记录到 $APP_NAME_FILE: $APP_NAME"

        # Build and execute PM2 command
        PM2_CMD=$(build_pm2_command "$APP_NAME" "$START_PATH")
        echo "执行命令: $PM2_CMD"
        eval "$PM2_CMD"
        
        if [ $? -eq 0 ]; then
            echo "Bot 已使用 pm2 启动："
            echo "  名称: $APP_NAME"
            echo "  启动文件: $START_PATH"
            echo "  模式: fork"
            echo ""
            pm2 list
        else
            echo "pm2 启动 bot 失败。"
            rm "$APP_NAME_FILE" # Clean up name file if start fails
            exit 1
        fi
        ;;

    --stop)
        # Check if name file exists
        if [ ! -f "$APP_NAME_FILE" ]; then
            echo "找不到 bot 名称文件 ($APP_NAME_FILE)。"
            echo "请手动查找并停止 pm2 进程:"
            echo "  pm2 list"
            echo "  pm2 stop <name|id>"
            echo "  pm2 delete <name|id>"
            exit 1
        fi

        # Read application name from file
        APP_NAME=$(cat "$APP_NAME_FILE")

        # Check if the process exists in pm2 list
        if ! pm2 list | grep -q "$APP_NAME"; then
            echo "警告：pm2 列表中找不到名为 $APP_NAME 的进程。"
            echo "可能已经被手动停止，清理名称文件..."
            rm "$APP_NAME_FILE"
            exit 0
        fi

        # Stop application with pm2
        echo "正在停止 pm2 bot: $APP_NAME..."
        pm2 stop "$APP_NAME"
        pm2 delete "$APP_NAME" # Delete from pm2 list after stopping

        # Remove name file
        rm "$APP_NAME_FILE"
        echo "pm2 bot $APP_NAME 已停止并从 pm2 列表中移除。"
        ;;

    --restart)
        # Check if name file exists and process is running
        if [ -f "$APP_NAME_FILE" ]; then
            APP_NAME=$(cat "$APP_NAME_FILE")
            if pm2 list | grep -q "$APP_NAME"; then
                # Bot is running, restart it
                echo "正在重启 pm2 bot: $APP_NAME..."
                pm2 restart "$APP_NAME" --update-env

                if [ $? -eq 0 ]; then
                    echo "pm2 bot $APP_NAME 已重启。"
                    echo ""
                    pm2 list
                else
                    echo "pm2 重启 bot 失败。"
                    exit 1
                fi
                exit 0
            else
                # Bot name file exists but process not running
                echo "警告：找到 bot 名称文件但进程未运行，清理旧的名称文件..."
                rm "$APP_NAME_FILE"
            fi
        fi

        # No running bot found, check if start path is provided
        if [ -z "$2" ]; then
            echo "未找到正在运行的 bot，且未提供启动路径。"
            echo "请使用以下命令之一："
            echo "  $0 --restart <启动路径>    # 启动新的 bot"
            echo "  $0 --start <启动路径>      # 启动新的 bot"
            exit 1
        fi

        START_PATH="$2"
        
        # Check if start file exists
        if [ ! -f "$START_PATH" ]; then
            echo "错误：找不到启动文件 '$START_PATH'"
            exit 1
        fi

        # Check and install pm2
        check_and_install_pm2

        echo "未找到正在运行的 bot，启动新的 bot..."

        # Generate dynamic name and save it
        TIMESTAMP=$(date '+%Y%m%d%H%M%S')
        APP_NAME="${DIR_NAME}-bot-${TIMESTAMP}"
        echo "$APP_NAME" > "$APP_NAME_FILE"
        echo "Bot 名称已记录到 $APP_NAME_FILE: $APP_NAME"

        # Build and execute PM2 command
        PM2_CMD=$(build_pm2_command "$APP_NAME" "$START_PATH")
        echo "执行命令: $PM2_CMD"
        eval "$PM2_CMD"
        
        if [ $? -eq 0 ]; then
            echo "Bot 已使用 pm2 启动："
            echo "  名称: $APP_NAME"
            echo "  启动文件: $START_PATH"
            echo "  模式: fork"
            echo ""
            pm2 list
        else
            echo "pm2 启动 bot 失败。"
            rm "$APP_NAME_FILE" # Clean up name file if start fails
            exit 1
        fi
        ;;

    --status)
        if [ -f "$APP_NAME_FILE" ]; then
            APP_NAME=$(cat "$APP_NAME_FILE")
            echo "当前 bot 名称: $APP_NAME"
            echo ""
            if pm2 list | grep -q "$APP_NAME"; then
                echo "Bot 状态:"
                pm2 show "$APP_NAME"
            else
                echo "Bot 未在 pm2 中运行。"
            fi
        else
            echo "未找到 bot 名称文件，可能没有通过此脚本启动的 bot。"
            echo ""
            echo "所有 pm2 进程:"
            pm2 list
        fi
        ;;

    --logs)
        # Check if name file exists
        if [ -f "$APP_NAME_FILE" ]; then
            APP_NAME=$(cat "$APP_NAME_FILE")
            if pm2 list | grep -q "$APP_NAME"; then
                # Get lines parameter (default 50)
                LINES="${2:-50}"
                echo "显示 bot $APP_NAME 的最近 $LINES 行日志:"
                echo "======================================"
                pm2 logs "$APP_NAME" --lines "$LINES"
            else
                echo "Bot $APP_NAME 未在 pm2 中运行。"
                echo ""
                echo "所有 pm2 进程的日志:"
                pm2 logs --lines "${2:-50}"
            fi
        else
            echo "未找到 bot 名称文件，显示所有 pm2 进程的日志:"
            echo "======================================"
            pm2 logs --lines "${2:-50}"
        fi
        ;;

    *)
        echo "无效的参数。请使用 --start <启动路径> 或 --stop 或 --restart 或 --status 或 --logs"
        exit 1
        ;;
esac