#!/bin/bash
(crontab -l 2>/dev/null; echo "*/1 * * * * /app/crontab/mins1.sh >> /app/logs/cron_jobs.log 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "*/5 * * * * /app/crontab/mins5.sh >> /app/logs/cron_jobs.log 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "*/15 * * * * /app/crontab/mins15.sh >> /app/logs/cron_jobs.log 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "*/30 * * * * /app/crontab/mins30.sh >> /app/logs/cron_jobs.log 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "0 * * * * /app/crontab/hour1.sh >> /app/logs/cron_jobs.log 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "0 */6 * * * /app/crontab/hour6.sh >> /app/logs/cron_jobs.log 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "0 */12 * * * /app/crontab/hour12.sh >> /app/logs/cron_jobs.log 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "0 0 * * * /app/crontab/day.sh >> /app/logs/cron_jobs.log 2>&1") | crontab -
