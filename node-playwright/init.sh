#!/bin/bash

# Create directories
mkdir -p app/crontab
mkdir -p app/logs

# Create startup script
cat > app/startup.sh << 'EOF'
#!/bin/bash
# Startup script for the application
EOF
chmod +x app/startup.sh

# Create crontab scripts
CRONTAB_SCRIPTS=(
    "mins1.sh"
    "mins5.sh"
    "mins15.sh"
    "mins30.sh"
    "hour1.sh"
    "hour6.sh"
    "hour12.sh"
    "day.sh"
)

for script in "${CRONTAB_SCRIPTS[@]}"; do
    cat > "app/crontab/$script" << 'EOF'
#!/bin/bash
# Crontab script: $script
# Add your commands here
EOF
    chmod +x "app/crontab/$script"
done

# Create the script content
cat > app/init-crontab.sh << 'EOF'
#!/bin/bash
(crontab -l 2>/dev/null; echo "*/1 * * * * /app/crontab/mins1.sh") | crontab -
(crontab -l 2>/dev/null; echo "*/5 * * * * /app/crontab/mins5.sh") | crontab -
(crontab -l 2>/dev/null; echo "*/15 * * * * /app/crontab/mins15.sh") | crontab -
(crontab -l 2>/dev/null; echo "*/30 * * * * /app/crontab/mins30.sh") | crontab -
(crontab -l 2>/dev/null; echo "0 * * * * /app/crontab/hour1.sh") | crontab -
(crontab -l 2>/dev/null; echo "0 */6 * * * /app/crontab/hour6.sh") | crontab -
(crontab -l 2>/dev/null; echo "0 */12 * * * /app/crontab/hour12.sh") | crontab -
(crontab -l 2>/dev/null; echo "0 0 * * * /app/crontab/day.sh") | crontab -
EOF

# Make the script executable
chmod +x app/init-crontab.sh

# Create bot.sh script
cat > app/bot.sh << 'EOF'
#!/bin/bash

# Check if command is provided
if [ $# -eq 0 ]; then
    echo "Error: Please provide command parameters"
    echo "Usage: ./bot.sh <command>"
    echo "Example: ./bot.sh 'main/src/index.js --type day --param1 value1'"
    exit 1
fi

COMMAND="$*"  # Get all parameters as one string

# Create logs directory if it doesn't exist
mkdir -p /app/logs

LOG_FILE="/app/logs/$COMMAND.log"

echo "$(date): 开始执行 $COMMAND 脚本" >> $LOG_FILE

cd /app/common/rpc-monitor-service

YARN_PATH="/usr/local/bin/yarn"
NODE_PATH="/usr/local/bin/node"

$NODE_PATH $COMMAND >> $LOG_FILE 2>&1

echo "$(date): $COMMAND 脚本执行完成" >> $LOG_FILE
EOF

# Make bot.sh executable
chmod +x app/bot.sh
cp GSM.sh app/GSM.sh
chmod +x app/GSM.sh

echo "Directory structure and files created successfully!"
echo "Crontab entries have been added successfully!"

