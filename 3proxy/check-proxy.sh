#!/bin/bash

PROXY_URL="http://astrid:4CBa737x10IgZU676z@31.58.137.32:13128"
CHECK_URL="http://clients3.google.com/generate_204"

# 定义 Slack 脚本路径
SLACK_SCRIPT="/home/sean/sh/slack-message.sh"

# 设置 Slack Webhook URL（必须）
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/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"

# 设置主机名（可选）
export HOST_NAME="test1-server"


if ! curl --proxy "$PROXY_URL" --max-time 5 --silent --fail "$CHECK_URL" > /dev/null; then
    echo "$(date) ❌ Proxy check failed. Restarting container..."
    docker restart local-proxy
    
    # 等待5秒后再次检查
    sleep 5
    
    if ! curl --proxy "$PROXY_URL" --max-time 5 --silent --fail "$CHECK_URL" > /dev/null; then
        echo "$(date) ❌ Proxy still failed after restart. Sending alert..."
        $SLACK_SCRIPT "$(date) :x: Proxy check failed after restart."
    else
        echo "$(date) ✅ Proxy recovered after restart"
    fi
else
    echo "$(date) ✅ Proxy OK"
fi
