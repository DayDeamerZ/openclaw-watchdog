#!/bin/bash
# OpenClaw Gateway 看门狗管理脚本

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

show_status() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}🐕 OpenClaw Gateway 看门狗状态${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    echo -e "${YELLOW}📊 Gateway 服务:${NC}"
    systemctl --user status openclaw-gateway 2>&1 | grep -E "(Active:|Loaded:|Main PID:)" | head -3
    echo ""

    echo -e "${YELLOW}⏰ 看门狗定时器:${NC}"
    systemctl status openclaw-gateway-watchdog.timer 2>&1 | grep -E "(Active:|Trigger:)" | head -2
    echo ""

    echo -e "${YELLOW}💓 心跳定时器:${NC}"
    systemctl status openclaw-gateway-heartbeat.timer 2>&1 | grep -E "(Active:|Trigger:)" | head -2
    echo ""

    echo -e "${YELLOW}📅 下次运行:${NC}"
    systemctl list-timers | grep -E "(openclaw|NEXT)" | grep -v "^NEXT"
    echo ""

    echo -e "${YELLOW}🔍 Gateway 进程:${NC}"
    if pgrep -f "openclaw-gateway" > /dev/null; then
        local pid=$(pgrep -f "openclaw-gateway" | head -1)
        echo -e "  ${GREEN}✓ 运行中${NC} (PID: $pid)"
        ps -p "$pid" -o pid,%cpu,%mem,etime,cmd --no-headers
    else
        echo -e "  ${RED}✗ 未运行${NC}"
    fi
    echo ""

    echo -e "${YELLOW}💓 心跳状态:${NC}"
    if [ -f "/root/.openclaw/watchdog/heartbeat.timestamp" ]; then
        local last=$(cat /root/.openclaw/watchdog/heartbeat.timestamp)
        local now=$(date +%s)
        local diff=$((now - last))
        if [ $diff -lt 300 ]; then
            echo -e "  ${GREEN}✓ 正常${NC} (${diff}秒前更新)"
        else
            echo -e "  ${RED}✗ 超时${NC} (${diff}秒前更新)"
        fi
    else
        echo -e "  ${RED}✗ 心跳文件不存在${NC}"
    fi
    echo ""

    echo -e "${YELLOW}📝 看门狗日志 (最后10行):${NC}"
    if [ -f "/root/.openclaw/watchdog/watchdog.log" ]; then
        tail -10 /root/.openclaw/watchdog/watchdog.log | sed 's/^/  /'
    else
        echo "  日志文件不存在"
    fi
    echo ""
}

start_watchdog() {
    echo -e "${BLUE}启动看门狗定时器...${NC}"
    systemctl start openclaw-gateway-watchdog.timer
    systemctl start openclaw-gateway-heartbeat.timer
    echo -e "${GREEN}✓ 看门狗定时器已启动${NC}"
}

stop_watchdog() {
    echo -e "${BLUE}停止看门狗定时器...${NC}"
    systemctl stop openclaw-gateway-watchdog.timer
    systemctl stop openclaw-gateway-heartbeat.timer
    echo -e "${YELLOW}✓ 看门狗定时器已停止${NC}"
}

enable_watchdog() {
    echo -e "${BLUE}启用看门狗开机自启...${NC}"
    systemctl enable openclaw-gateway-watchdog.timer
    systemctl enable openclaw-gateway-heartbeat.timer
    echo -e "${GREEN}✓ 看门狗已设置为开机自启${NC}"
}

disable_watchdog() {
    echo -e "${BLUE}禁用看门狗开机自启...${NC}"
    systemctl disable openclaw-gateway-watchdog.timer
    systemctl disable openclaw-gateway-heartbeat.timer
    echo -e "${YELLOW}✓ 看门狗已禁用开机自启${NC}"
}

manual_check() {
    echo -e "${BLUE}手动运行看门狗检查...${NC}"
    /root/.openclaw/scripts/gateway-watchdog.sh
}

show_logs() {
    echo -e "${BLUE}查看看门狗日志...${NC}"
    if [ -f "/root/.openclaw/watchdog/watchdog.log" ]; then
        tail -f /root/.openclaw/watchdog/watchdog.log
    else
        echo -e "${RED}日志文件不存在${NC}"
    fi
}

show_help() {
    echo "OpenClaw Gateway 看门狗管理脚本"
    echo ""
    echo "用法: $0 <命令>"
    echo ""
    echo "命令:"
    echo "  status    - 查看看门狗状态"
    echo "  start     - 启动看门狗定时器"
    echo "  stop      - 停止看门狗定时器"
    echo "  enable    - 启用看门狗开机自启"
    echo "  disable   - 禁用看门狗开机自启"
    echo "  check     - 手动运行看门狗检查"
    echo "  logs      - 查看看门狗日志"
    echo "  help      - 显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 status     # 查看状态"
    echo "  $0 check      # 手动检查"
    echo "  $0 logs       # 查看日志"
}

# 主逻辑
case "${1:-status}" in
    status)
        show_status
        ;;
    start)
        start_watchdog
        ;;
    stop)
        stop_watchdog
        ;;
    enable)
        enable_watchdog
        ;;
    disable)
        disable_watchdog
        ;;
    check)
        manual_check
        ;;
    logs)
        show_logs
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}错误: 未知命令 '$1'${NC}"
        echo ""
        show_help
        exit 1
        ;;
esac
