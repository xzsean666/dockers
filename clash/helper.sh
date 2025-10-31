#!/bin/bash

# Clash Helper Script - 交互式版本
# 用于管理 Clash 代理服务

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAR_FILE="$SCRIPT_DIR/clash.tar"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
CONTAINER_NAME="clash"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 打印信息函数
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 清屏
clear_screen() {
    clear
}

# 暂停并等待用户按键
pause() {
    echo ""
    read -p "按 Enter 继续..."
}

# 加载 Docker 镜像
load_image() {
    clear_screen
    echo -e "${CYAN}=== 加载 Docker 镜像 ===${NC}\n"
    
    if [ ! -f "$TAR_FILE" ]; then
        error "找不到 clash.tar 文件: $TAR_FILE"
        pause
        return 1
    fi
    
    info "正在加载 Docker 镜像: $TAR_FILE"
    docker load -i "$TAR_FILE" || {
        error "Docker 镜像加载失败"
        pause
        return 1
    }
    success "Docker 镜像加载成功"
    pause
}

# 启动 Clash 服务
start_service() {
    clear_screen
    echo -e "${CYAN}=== 启动 Clash 服务 ===${NC}\n"
    
    info "启动 Clash 服务..."
    cd "$SCRIPT_DIR"
    
    # 创建配置目录（如果不存在）
    mkdir -p "$SCRIPT_DIR/config"
    
    docker-compose -f "$COMPOSE_FILE" up -d || {
        error "Clash 服务启动失败"
        pause
        return 1
    }
    success "Clash 服务启动成功"
    sleep 3
    
    # 自动修复配置文件
    info "正在自动修复配置文件..."
    echo ""
    fix_config_internal
    
    pause
}

# 修复配置文件（内部函数，不显示暂停）
fix_config_internal() {
    local config_dir="$SCRIPT_DIR/config"
    local config_file="$config_dir/config.yaml"
    
    # 检查配置目录是否存在
    if [ ! -d "$config_dir" ]; then
        warning "配置目录不存在，将在下次启动时创建"
        return 1
    fi
    
    # 检查配置文件是否存在
    if [ ! -f "$config_file" ]; then
        warning "配置文件不存在，请稍候..."
        return 1
    fi
    
    local config_changed=false
    local backup_created=false
    
    # 检查并修复 external-controller
    if grep -q "external-controller.*127.0.0.1" "$config_file"; then
        if [ "$backup_created" = false ]; then
            cp "$config_file" "${config_file}.backup"
            info "已创建备份文件: ${config_file}.backup"
            backup_created=true
        fi
        
        warning "发现需要修复的配置 (external-controller)"
        echo -e "${YELLOW}修改前:${NC}"
        grep "external-controller" "$config_file" || true
        
        sed -i 's/external-controller: 127\.0\.0\.1:9090/external-controller: 0.0.0.0:9090/' "$config_file"
        
        echo -e "${GREEN}修改后:${NC}"
        grep "external-controller" "$config_file" || true
        success "external-controller 已修复为 0.0.0.0:9090"
        config_changed=true
    fi
    
    # 检查并修复 allow-lan
    if grep -q "allow-lan: false" "$config_file"; then
        if [ "$backup_created" = false ]; then
            cp "$config_file" "${config_file}.backup"
            info "已创建备份文件: ${config_file}.backup"
            backup_created=true
        fi
        
        warning "发现需要修复的配置 (allow-lan)"
        echo -e "${YELLOW}修改前:${NC}"
        grep "allow-lan:" "$config_file" || true
        
        sed -i 's/allow-lan: false/allow-lan: true/' "$config_file"
        
        echo -e "${GREEN}修改后:${NC}"
        grep "allow-lan:" "$config_file" || true
        success "allow-lan 已修复为 true"
        config_changed=true
    fi
    
    if [ "$config_changed" = true ]; then
        success "配置文件修复完成！"
        warning "需要重启 Clash 服务使配置生效"
        return 0
    else
        success "配置文件无需修复或已修复"
        echo "当前配置:"
        echo -e "  external-controller: $(grep 'external-controller:' "$config_file" 2>/dev/null || echo '未找到')"
        echo -e "  allow-lan: $(grep 'allow-lan:' "$config_file" 2>/dev/null || echo '未找到')"
        return 0
    fi
}

# 停止 Clash 服务
stop_service() {
    clear_screen
    echo -e "${CYAN}=== 停止 Clash 服务 ===${NC}\n"
    
    info "停止 Clash 服务..."
    cd "$SCRIPT_DIR"
    
    docker-compose -f "$COMPOSE_FILE" down || {
        error "Clash 服务停止失败"
        pause
        return 1
    }
    success "Clash 服务已停止"
    pause
}

# 查看服务状态
status_service() {
    clear_screen
    echo -e "${CYAN}=== Clash 服务状态 ===${NC}\n"
    
    info "检查 Clash 服务状态..."
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        success "Clash 服务正在运行"
        echo ""
        docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    else
        warning "Clash 服务未运行"
    fi
    pause
}

# 重启服务
restart_service() {
    clear_screen
    echo -e "${CYAN}=== 重启 Clash 服务 ===${NC}\n"
    
    info "重启 Clash 服务..."
    stop_service
    sleep 1
    start_service
    success "Clash 服务已重启"
}

# 查看日志
view_logs() {
    clear_screen
    echo -e "${CYAN}=== Clash 服务日志 ===${NC}"
    echo -e "按 Ctrl+C 退出日志查看\n"
    
    cd "$SCRIPT_DIR"
    docker-compose -f "$COMPOSE_FILE" logs -f "${CONTAINER_NAME}" || true
}

# 测试 HTTP 代理
test_http_proxy() {
    local proxy_port="17890"
    info "测试 HTTP 代理 (127.0.0.1:$proxy_port)..."
    
    if curl -x "http://127.0.0.1:$proxy_port" -s -I "http://www.google.com" > /dev/null 2>&1; then
        success "HTTP 代理测试成功"
        return 0
    else
        warning "HTTP 代理测试失败或网络不可达"
        return 1
    fi
}

# 测试 SOCKS5 代理
test_socks5_proxy() {
    local proxy_port="17891"
    info "测试 SOCKS5 代理 (127.0.0.1:$proxy_port)..."
    
    if curl -x "socks5://127.0.0.1:$proxy_port" -s -I "http://www.google.com" > /dev/null 2>&1; then
        success "SOCKS5 代理测试成功"
        return 0
    else
        warning "SOCKS5 代理测试失败或网络不可达"
        return 1
    fi
}

# 测试所有代理
test_all_proxies() {
    clear_screen
    echo -e "${CYAN}=== 测试所有代理 ===${NC}\n"
    
    info "运行所有代理测试...\n"
    test_http_proxy || true
    echo ""
    test_socks5_proxy || true
    
    pause
}

# 获取 Clash 代理列表
get_proxies() {
    clear_screen
    echo -e "${CYAN}=== Clash 代理列表 ===${NC}\n"
    
    local api_url="http://127.0.0.1:17892/proxies"
    info "获取 Clash 代理列表..."
    echo ""
    
    response=$(curl -s "$api_url" 2>&1)
    if echo "$response" | grep -q "proxies"; then
        echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
        success "代理列表获取成功"
    else
        error "获取代理列表失败"
        echo "$response"
    fi
    
    pause
}

# 获取当前代理状态
get_proxy_status() {
    clear_screen
    echo -e "${CYAN}=== Clash 运行状态 ===${NC}\n"
    
    local api_url="http://127.0.0.1:17892/clash"
    info "获取 Clash 状态..."
    echo ""
    
    response=$(curl -s "$api_url" 2>&1)
    if [ -n "$response" ]; then
        echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
        success "状态信息获取成功"
    else
        error "获取状态失败"
    fi
    
    pause
}

# 切换代理
switch_proxy_interactive() {
    clear_screen
    echo -e "${CYAN}=== 切换代理 ===${NC}\n"
    
    local config_file="$SCRIPT_DIR/config/config.yaml"
    
    # 检查配置文件
    if [ ! -f "$config_file" ]; then
        error "配置文件不存在: $config_file"
        pause
        return 1
    fi
    
    # 获取所有的 groups (选择器)
    local groups=()
    local group_types=()
    while IFS= read -r line; do
        if [[ $line =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*\'?\"?([^\'\"]*)\'?\"? ]]; then
            groups+=("${BASH_REMATCH[1]}")
        fi
    done < <(grep -A 100 "^proxy-groups:" "$config_file" | grep "name:" | head -20)
    
    if [ ${#groups[@]} -eq 0 ]; then
        warning "未找到任何代理组(proxy-groups)"
        pause
        return 1
    fi
    
    # 显示选择器列表
    info "找到以下代理组:"
    echo ""
    for i in "${!groups[@]}"; do
        echo -e "  ${GREEN}$((i+1)))${NC} ${groups[$i]}"
    done
    echo ""
    
    read -p "请选择要切换的代理组 (输入数字): " selector_idx
    
    # 验证输入
    if ! [[ $selector_idx =~ ^[0-9]+$ ]] || [ "$selector_idx" -lt 1 ] || [ "$selector_idx" -gt ${#groups[@]} ]; then
        error "无效的选择"
        pause
        return 1
    fi
    
    local selector="${groups[$((selector_idx-1))]}"
    info "已选择代理组: ${GREEN}$selector${NC}"
    echo ""
    
    # 获取该组下所有可用的代理
    local proxies=()
    local in_group=0
    local group_found=0
    
    while IFS= read -r line; do
        # 检查是否进入目标 group
        if [[ $line =~ name:[[:space:]]*\'?\"?$selector\'?\"? ]]; then
            in_group=1
            group_found=1
            continue
        fi
        
        # 如果进入了该组
        if [ $in_group -eq 1 ]; then
            # 检查是否到达下一个 group（通过缩进和 name 字段判断）
            if [[ $line =~ ^[[:space:]]*-[[:space:]]*name: ]] && ! [[ $line =~ $selector ]]; then
                break
            fi
            
            # 提取 proxies 列表中的代理名称
            if [[ $line =~ ^[[:space:]]*-[[:space:]]*\'?\"?([^\'\"]*)\'?\"?[[:space:]]*$ ]]; then
                local proxy_name="${BASH_REMATCH[1]}"
                if [ ! -z "$proxy_name" ] && [ "$proxy_name" != "null" ]; then
                    proxies+=("$proxy_name")
                fi
            fi
        fi
    done < <(sed -n "/^proxy-groups:/,/^[a-z]/p" "$config_file" | grep -A 500 "name: '$selector'")
    
    # 如果用 API 获取不到，尝试从 API 获取
    if [ ${#proxies[@]} -eq 0 ]; then
        info "从配置文件解析失败，尝试从 API 获取代理列表..."
        local api_response=$(curl -s "http://127.0.0.1:17892/proxies" 2>&1)
        
        if echo "$api_response" | grep -q '"proxies"'; then
            # 从 API 响应中提取代理名称（正确处理含有空格的名称）
            mapfile -t proxies < <(echo "$api_response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    proxy_names = set()
    for proxy_group in data.get('proxies', {}).values():
        if isinstance(proxy_group, list):
            for proxy in proxy_group:
                if isinstance(proxy, str):
                    proxy_names.add(proxy)
        elif isinstance(proxy_group, dict):
            name = proxy_group.get('name', '')
            if name:
                proxy_names.add(name)
    for name in sorted(proxy_names):
        print(name)
except: pass
" 2>/dev/null)
        fi
    fi
    
    if [ ${#proxies[@]} -eq 0 ]; then
        error "未找到该代理组中的任何代理"
        pause
        return 1
    fi
    
    # 显示代理列表
    info "该代理组中的可用代理:"
    echo ""
    for i in "${!proxies[@]}"; do
        echo -e "  ${GREEN}$((i+1)))${NC} ${proxies[$i]}"
    done
    echo ""
    
    read -p "请选择要切换到的代理 (输入数字): " proxy_idx
    
    # 验证输入
    if ! [[ $proxy_idx =~ ^[0-9]+$ ]] || [ "$proxy_idx" -lt 1 ] || [ "$proxy_idx" -gt ${#proxies[@]} ]; then
        error "无效的选择"
        pause
        return 1
    fi
    
    local proxy_name="${proxies[$((proxy_idx-1))]}"
    info "正在切换代理: ${GREEN}$selector${NC} -> ${GREEN}$proxy_name${NC}"
    echo ""
    
    # 调用 API 切换代理
    local api_url="http://127.0.0.1:17892/proxies/${selector}"
    response=$(curl -s -X PUT "$api_url" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$proxy_name\"}" 2>&1)
    
    if echo "$response" | grep -q "$proxy_name"; then
        success "代理切换成功！当前选择: $proxy_name"
    elif [ -z "$response" ]; then
        success "代理切换请求已发送"
    else
        warning "切换结果:"
        echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
    fi
    
    pause
}

# 修复配置文件
fix_config() {
    clear_screen
    echo -e "${CYAN}=== 修复 Clash 配置 ===${NC}\n"
    
    fix_config_internal
    
    pause
}

# 显示主菜单
show_main_menu() {
    clear_screen
    echo -e "${CYAN}"
    cat << "EOF"
╔════════════════════════════════════════╗
║      Clash 代理管理助手 - 交互式菜单     ║
╚════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    echo -e "${YELLOW}【服务管理】${NC}"
    echo -e "  ${GREEN}1)${NC}  加载 Docker 镜像"
    echo -e "  ${GREEN}2)${NC}  启动服务"
    echo -e "  ${GREEN}3)${NC}  停止服务"
    echo -e "  ${GREEN}4)${NC}  重启服务"
    echo -e "  ${GREEN}5)${NC}  查看服务状态"
    
    echo ""
    echo -e "${YELLOW}【配置管理】${NC}"
    echo -e "  ${GREEN}6)${NC}  修复配置文件 (external-controller)"
    
    echo ""
    echo -e "${YELLOW}【代理测试】${NC}"
    echo -e "  ${GREEN}7)${NC}  测试 HTTP 代理"
    echo -e "  ${GREEN}8)${NC}  测试 SOCKS5 代理"
    echo -e "  ${GREEN}9)${NC}  测试所有代理"
    
    echo ""
    echo -e "${YELLOW}【API 控制】${NC}"
    echo -e "  ${GREEN}10)${NC} 获取代理列表"
    echo -e "  ${GREEN}11)${NC} 获取运行状态"
    echo -e "  ${GREEN}12)${NC} 切换代理"
    
    echo ""
    echo -e "${YELLOW}【其他】${NC}"
    echo -e "  ${GREEN}13)${NC} 查看实时日志"
    echo -e "  ${GREEN}0)${NC}  ${RED}退出${NC}"
    
    echo ""
    echo -e "${CYAN}代理端口配置:${NC}"
    echo -e "  • HTTP:    127.0.0.1:17890"
    echo -e "  • SOCKS5:  127.0.0.1:17891"
    echo -e "  • API:     127.0.0.1:17892"
    echo ""
}

# 显示关于信息
show_about() {
    clear_screen
    cat << 'EOF'
╔════════════════════════════════════════╗
║        Clash 助手脚本 v1.1              ║
║       交互式菜单版本                    ║
╚════════════════════════════════════════╝

主要功能:
  ✓ Docker 镜像管理（加载/卸载）
  ✓ 服务生命周期控制（启动/停止/重启）
  ✓ 配置文件修复（external-controller）
  ✓ 代理连接测试（HTTP/SOCKS5）
  ✓ RESTful API 控制
  ✓ 实时日志查看
  ✓ 彩色输出反馈

使用提示:
  • 选择任意选项后，按 Enter 键执行
  • 大多数操作完成后按 Enter 键返回菜单
  • 查看日志时按 Ctrl+C 退出

需要帮助? 请参考 README.md 文件

EOF
    pause
}

# 主循环
main_loop() {
    while true; do
        show_main_menu
        
        read -p "请选择操作 (输入数字 0-13): " choice
        
        case "$choice" in
            1)
                load_image
                ;;
            2)
                start_service
                ;;
            3)
                stop_service
                ;;
            4)
                restart_service
                ;;
            5)
                status_service
                ;;
            6)
                fix_config
                ;;
            7)
                clear_screen
                echo -e "${CYAN}=== 测试 HTTP 代理 ===${NC}\n"
                test_http_proxy
                pause
                ;;
            8)
                clear_screen
                echo -e "${CYAN}=== 测试 SOCKS5 代理 ===${NC}\n"
                test_socks5_proxy
                pause
                ;;
            9)
                test_all_proxies
                ;;
            10)
                get_proxies
                ;;
            11)
                get_proxy_status
                ;;
            12)
                switch_proxy_interactive
                ;;
            13)
                view_logs
                ;;
            0)
                clear_screen
                echo -e "${GREEN}感谢使用 Clash 助手脚本！${NC}"
                echo "再见！"
                exit 0
                ;;
            *)
                clear_screen
                error "无效的选择，请输入 0-13 之间的数字"
                sleep 1
                ;;
        esac
    done
}

# 如果提供了命令行参数，使用传统模式
if [ $# -gt 0 ]; then
    case "$1" in
        interactive|--interactive|-i)
            main_loop
            ;;
        *)
            error "不支持的参数: $1"
            echo "使用方式: $0 [interactive|--interactive|-i]"
            exit 1
            ;;
    esac
else
    # 默认启动交互式菜单
    main_loop
fi
