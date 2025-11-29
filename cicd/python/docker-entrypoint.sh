#!/bin/bash

# Docker 启动入口脚本
# 处理 CI/CD cron 任务和主程序启动

set -e

cd /app

# PID 文件路径
PID_FILE="/var/run/app.pid"

# ========== 辅助函数 ==========

is_app_running() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# 停止主程序
stop_app() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            echo "正在停止主程序 (PID: $PID)..."
            kill "$PID" 2>/dev/null || true
            # 等待进程结束
            for i in {1..10}; do
                if ! kill -0 "$PID" 2>/dev/null; then
                    echo "主程序已停止"
                    break
                fi
                sleep 1
            done
            # 如果还没停止，强制杀掉
            if kill -0 "$PID" 2>/dev/null; then
                echo "强制停止主程序..."
                kill -9 "$PID" 2>/dev/null || true
            fi
        fi
        rm -f "$PID_FILE"
    fi
}

# 启动主程序
start_app() {
    if is_app_running; then
        echo "检测到主程序已运行 (PID: $(cat \"$PID_FILE\"))，跳过重复启动"
        return
    fi
    echo "启动主程序: $START_COMMAND"
    eval "$START_COMMAND" &
    echo $! > "$PID_FILE"
    echo "主程序已启动 (PID: $(cat \"$PID_FILE\"))"
}

# 重启主程序
restart_app() {
    echo "重启主程序..."
    stop_app
    sleep 1
    start_app
}

monitor_app() {
    while true; do
        if ! is_app_running; then
            echo "主程序未运行，退出容器以触发 Docker 重启"
            exit 1
        fi

        PID=$(cat "$PID_FILE")

        # wait 返回非 0 不触发 set -e 退出
        set +e
        wait "$PID"
        EXIT_CODE=$?
        set -e

        if [ -f "$PID_FILE" ]; then
            NEW_PID=$(cat "$PID_FILE")
            if [ "$NEW_PID" != "$PID" ] && kill -0 "$NEW_PID" 2>/dev/null; then
                echo "检测到内部重启，继续监听新进程 (PID: $NEW_PID)"
                continue
            fi
        fi

        echo "主程序退出 (code: $EXIT_CODE)，退出容器以触发 Docker 重启"
        exit "$EXIT_CODE"
    done
}

handle_exit() {
    echo "收到停止信号，准备退出..."
    stop_app
    exit 0
}

trap handle_exit SIGTERM SIGINT

# ========== GSM (Git Sync Manager) 函数 ==========
gsm_check_update() {
    echo "开始检查更新: $(date '+%Y-%m-%d %H:%M:%S')"

    # 配置Git安全设置（防止Docker权限问题）
    git config --global --add safe.directory "$(pwd)" 2>/dev/null || true
    git config --global --add safe.directory /app 2>/dev/null || true

    # 配置Git网络设置（解决HTTP/2问题）
    git config --global http.version HTTP/1.1
    git config --global http.postBuffer 1048576000
    git config --global http.lowSpeedLimit 0
    git config --global http.lowSpeedTime 999999

    # 检查是否在Git仓库中
    if [ ! -d ".git" ]; then
        echo "错误：当前目录不是Git仓库"
        return 1
    fi

    # 如果有token，配置凭证
    if [ -n "$GITHUB_TOKEN" ]; then
        git config credential.helper '!f() { echo "username=oauth2"; echo "password='"$GITHUB_TOKEN"'"; }; f'
    fi

    # 获取当前分支名
    BRANCH=$(git rev-parse --abbrev-ref HEAD)

    # 保存当前的 commit hash
    CURRENT_HASH=$(git rev-parse HEAD)

    # 获取远程更新
    git fetch origin "$BRANCH"

    # 获取最新的 commit hash
    LATEST_HASH=$(git rev-parse origin/"$BRANCH")

    if [ "$CURRENT_HASH" = "$LATEST_HASH" ]; then
        echo "仓库已是最新状态"
    else
        echo "发现更新，正在拉取..."
        
        # 检查是否有本地修改
        if [ -n "$(git status --porcelain)" ]; then
            echo "检测到本地修改，正在执行 git stash 保存修改..."
            git stash push -m "自动保存的修改 $(date '+%Y-%m-%d %H:%M:%S')"
            STASHED=true
        else
            STASHED=false
        fi
        
        # 拉取更新
        if git pull origin "$BRANCH"; then
            echo "更新完成！"
            
            if [ "$STASHED" = true ]; then
                echo "本地修改已存储在 stash 中，未恢复"
            fi
            
            # 显示更新内容
            echo -e "\n更新内容如下："
            git --no-pager log --oneline "$CURRENT_HASH..$LATEST_HASH"
            
            # 执行更新后命令（重启应用）
            run_post_update
        else
            echo "更新失败！检测到合并冲突，尝试通过 reset 解决..."
            git reset --hard HEAD
            git clean -fd
            
            if git pull origin "$BRANCH"; then
                echo "冲突已解决，更新完成！"
                echo -e "\n更新内容如下："
                git --no-pager log --oneline "$CURRENT_HASH..$LATEST_HASH"
                
                # 执行更新后命令（重启应用）
                run_post_update
            else
                echo "错误：解决冲突后仍然无法更新，可能需要手动干预。"
            fi
        fi
    fi

    # 清理凭证配置
    if [ -n "$GITHUB_TOKEN" ]; then
        git config --unset credential.helper 2>/dev/null || true
    fi

    echo -e "\n检查完成: $(date '+%Y-%m-%d %H:%M:%S')"
}

# 执行更新后操作
run_post_update() {
    echo -e "\n开始执行更新后的操作..."
    
    if [ -n "$POST_UPDATE_COMMAND" ]; then
        echo "执行自定义更新命令: $POST_UPDATE_COMMAND"
        eval "$POST_UPDATE_COMMAND"
    else
        # 默认行为：重启应用
        restart_app
    fi
    
    echo "更新后操作执行完成"
}

# ========== 主入口 ==========

# 处理命令行参数
case "$1" in
    gsm)
        # GSM 模式：只检查更新
        gsm_check_update
        exit 0
        ;;
    stop)
        stop_app
        exit 0
        ;;
    restart)
        restart_app
        exit 0
        ;;
esac

# 如果启用了 CICD，设置 cron 任务
if [ "$ENABLE_CICD" = "true" ] || [ "$ENABLE_CICD" = "1" ]; then
    echo "CI/CD 已启用，配置 cron 任务..."
    
    # 创建 cron 任务文件
    # 每5分钟执行一次检查更新
    cat > /etc/cron.d/gsm-cron << EOF
# 每5分钟检查 Git 更新
*/5 * * * * root cd /app && GITHUB_TOKEN="$GITHUB_TOKEN" POST_UPDATE_COMMAND="$POST_UPDATE_COMMAND" START_COMMAND="$START_COMMAND" /bin/bash /docker-entrypoint.sh gsm >> /var/log/gsm-cron.log 2>&1
EOF
    
    # 设置正确的权限
    chmod 0644 /etc/cron.d/gsm-cron
    
    # 创建日志文件
    touch /var/log/gsm-cron.log
    
    # 启动 cron 服务
    cron
    
    echo "Cron 任务已配置，每5分钟检查 Git 更新"
    echo "START_COMMAND: $START_COMMAND"
    echo "POST_UPDATE_COMMAND: $POST_UPDATE_COMMAND"
    
    # 首次启动时执行一次检查更新
    echo "首次启动，检查更新..."
    gsm_check_update || true
else
    echo "CI/CD 未启用"
fi

# 确保主程序已运行，然后阻塞等待，便于 cron 内部重启后继续挂在 PID 1
start_app
monitor_app
