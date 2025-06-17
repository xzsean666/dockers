#!/bin/bash

# GitHub 更新检查脚本 - 支持私有仓库

# 获取 GitHub Token 和更新后操作脚本相关参数
if [ -n "$GITHUB_TOKEN" ]; then
    TOKEN="$GITHUB_TOKEN"
elif [ -n "$1" ] && [[ "$1" != /* ]]; then
    TOKEN="$1"
    shift  # 移除第一个参数
else
    TOKEN=""
fi

# 所有剩余的参数都将作为更新脚本的参数
if [ $# -gt 0 ]; then
    POST_UPDATE_SCRIPT="$1"
    shift  # 移除脚本路径
    POST_UPDATE_ARGS="$@"  # 保存剩余的所有参数
fi

# 输出时间戳
echo "开始检查更新: $(date '+%Y-%m-%d %H:%M:%S')"

# 获取远程仓库 URL
REPO_URL=$(git config --get remote.origin.url)

# 如果有token，配置凭证
if [ -n "$TOKEN" ]; then
    git config --local credential.helper '!f() { echo "username=oauth2"; echo "password='$TOKEN'"; }; f'
fi

# 获取当前分支名
BRANCH=$(git rev-parse --abbrev-ref HEAD)

# 保存当前的 commit hash
CURRENT_HASH=$(git rev-parse HEAD)

# 获取远程更新
git fetch origin "$BRANCH"

# 获取最新的 commit hash
LATEST_HASH=$(git rev-parse origin/"$BRANCH")

# 定义更新后执行的函数
post_update_actions() {
    echo -e "\n开始执行更新后的操作..."
    if [ -n "$POST_UPDATE_SCRIPT" ]; then
        if [ -f "$POST_UPDATE_SCRIPT" ] && [ -x "$POST_UPDATE_SCRIPT" ]; then
            echo "执行自定义更新脚本: $POST_UPDATE_SCRIPT $POST_UPDATE_ARGS"
            bash "$POST_UPDATE_SCRIPT" $POST_UPDATE_ARGS
        else
            echo "错误: 更新脚本不存在或没有执行权限: $POST_UPDATE_SCRIPT"
            exit 1
        fi
    else
        echo "未指定更新后操作脚本"
    fi
    echo "更新后操作执行完成"
}

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
        
        # 不再恢复本地修改，仅提示用户
        if [ "$STASHED" = true ]; then
            echo "本地修改已存储在 stash 中，未恢复"
        fi
        
        # 显示更新内容
        echo -e "\n更新内容如下："
        git --no-pager log --oneline "$CURRENT_HASH..$LATEST_HASH"
        
        # 调用更新后的操作函数
        post_update_actions
    else
        echo "更新失败！检测到合并冲突，尝试通过 stash 解决..."
        # 保存任何未提交的更改（包括合并冲突）
        git reset --hard HEAD
        git clean -fd
        
        # 重新尝试拉取更新
        if git pull origin "$BRANCH"; then
            echo "冲突已解决，更新完成！"
            
            # 显示更新内容
            echo -e "\n更新内容如下："
            git --no-pager log --oneline "$CURRENT_HASH..$LATEST_HASH"
            
            # 调用更新后的操作函数
            post_update_actions
        else
            echo "错误：解决冲突后仍然无法更新，可能需要手动干预。"
        fi
    fi
fi

# 清理凭证配置
if [ -n "$TOKEN" ]; then
    git config --local --unset credential.helper
fi

echo -e "\n检查完成: $(date '+%Y-%m-%d %H:%M:%S')"
