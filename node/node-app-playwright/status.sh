#!/bin/bash

# 加载配置文件
if [ -f ".docker.config" ]; then
    # 加载环境变量
    set -a
    . ./.docker.config
    set +a
    
    PROJECT_NAME=${PROJECT_NAME:-app}
    APP_NAME=${APP_NAME:-app}
    PM2_ENABLED=${PM2_ENABLED:-false}
    CRON_ENABLED=${CRON_ENABLED:-false}
else
    PROJECT_NAME="app"
    APP_NAME="app"
    PM2_ENABLED="false"
    CRON_ENABLED="false"
    echo "⚠️  未找到 .docker.config 配置文件，使用默认值"
fi

SERVICE_NAME="app"
CONTAINER_NAME="app-service"

echo "======================================"
echo "      ${PROJECT_NAME^^} 应用状态检查"
echo "======================================"

# 检查 Docker 容器状态
echo ""
echo "📦 Docker 容器状态:"
docker-compose ps

# 检查容器是否运行
if ! docker ps | grep -q $CONTAINER_NAME; then
    echo "❌ 容器未运行"
    exit 1
fi

# 检查PM2状态（如果启用）
if [ "$PM2_ENABLED" = "true" ]; then
    echo ""
    echo "🔄 PM2 进程状态:"
    docker-compose exec $SERVICE_NAME pm2 status 2>/dev/null || echo "PM2未启动"
else
    echo ""
    echo "⏭️  PM2未启用"
fi

# 检查Cron状态（如果启用）
if [ "$CRON_ENABLED" = "true" ]; then
    echo ""
    echo "⏰ Cron 任务状态:"
    docker-compose exec $SERVICE_NAME ps aux | grep cron 2>/dev/null || echo "Cron进程未找到"
    
    echo ""
    echo "📋 最近的 Cron 日志 (最后10行):"
    docker-compose exec $SERVICE_NAME tail -10 /var/log/cron.log 2>/dev/null || echo "Cron日志不存在"
    
    echo ""
    echo "📅 配置的定时任务:"
    if [ "$CRON_JOBS" != "" ]; then
        echo "$CRON_JOBS" | tr ";" "\n" | while read -r job; do
            if [ "$job" != "" ]; then
                echo "  - $job"
            fi
        done
    else
        echo "  无定时任务配置"
    fi
else
    echo ""
    echo "⏭️  Cron未启用"
fi

echo ""
echo "📊 容器资源使用情况:"
docker stats $CONTAINER_NAME --no-stream 2>/dev/null || echo "容器未运行"

echo ""
echo "💾 磁盘使用情况:"
echo "主机日志目录: $(du -sh ./logs 2>/dev/null || echo '目录不存在')"

echo ""
echo "🔍 应用配置:"
echo "项目名称: $PROJECT_NAME"
echo "应用名称: $APP_NAME"
echo "主脚本: $APP_MAIN_SCRIPT"
echo "PM2启用: $PM2_ENABLED"
echo "Cron启用: $CRON_ENABLED"
echo "时区: $TIMEZONE"

echo ""
echo "======================================"
echo "快捷命令:"
echo "查看实时日志: docker-compose logs -f"
if [ "$PM2_ENABLED" = "true" ]; then
    echo "查看PM2日志: docker-compose exec app pm2 logs $APP_NAME"
fi
if [ "$CRON_ENABLED" = "true" ]; then
    echo "查看Cron日志: docker-compose exec app tail -f /var/log/cron.log"
fi
echo "进入容器: docker-compose exec app sh"
echo "重启服务: docker-compose restart"
echo "重新构建: docker-compose up --build -d"
echo "======================================" 