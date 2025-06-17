#!/bin/bash

# 显示当前crontab内容（带序号）
show_crontab() {
    crontab -l | awk '{print NR ") " $0}'
}

# 添加新的cron任务
add_cron_job() {
    (crontab -l 2>/dev/null; echo "$1") | crontab -
    echo "已添加新的cron任务"
}

# 添加每几分钟执行一次的cron任务
add_periodic_job() {
    read -p "请输入任务命令: " task
    read -p "请输入每几分钟执行一次 (1-59): " interval
    if [ "$interval" -gt 0 ] && [ "$interval" -lt 60 ]; then
        (crontab -l 2>/dev/null; echo "*/$interval * * * * $task") | crontab -
        echo "已添加新的周期性cron任务"
    else
        echo "无效的时间间隔，请输入1-59之间的数字"
    fi
}

# 删除指定序号的cron任务
remove_cron_job_by_index() {
    read -p "请输入要删除的任务序号: " index
    crontab -l | sed "${index}d" | crontab -
    echo "已删除指定序号的cron任务"
}

# 删除所有cron任务
remove_all_jobs() {
    crontab -r
    echo "已删除所有cron任务"
}

# 主菜单
main_menu() {
    echo "Crontab管理工具"
    echo "1. 显示当前crontab内容"
    echo "2. 添加新的cron任务"
    echo "3. 添加周期性cron任务"
    echo "4. 删除指定序号的cron任务"
    echo "5. 删除所有cron任务"
    echo "6. 退出"
    read -p "请选择操作 (1-6): " choice

    case $choice in
        1) show_crontab ;;
        2) 
            read -p "请输入新的cron任务: " new_job
            add_cron_job "$new_job"
            ;;
        3) add_periodic_job ;;
        4) remove_cron_job_by_index ;;
        5) remove_all_jobs ;;
        6) exit 0 ;;
        *) echo "无效的选择,请重试" ;;
    esac

    main_menu
}

main_menu