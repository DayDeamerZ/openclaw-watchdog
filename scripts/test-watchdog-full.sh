#!/bin/bash
# Gateway 看门狗完整测试程序
# 测试场景: 关闭 Gateway → 等待看门狗自动恢复 → 验证结果

set -e

WATCHDOG_SCRIPT="$HOME/.openclaw/scripts/gateway-watchdog.sh"
LOG_FILE="$HOME/.openclaw/watchdog/watchdog.log"
TEST_LOG="/tmp/gateway-watchdog-test.log"
EMAIL_SCRIPT="$HOME/.openclaw/scripts/send-email.sh"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    local color="$1"
    shift
    echo -e "${color}[$(date '+%H:%M:%S')]${NC} $*" | tee -a "$TEST_LOG"
}

log_green() {
    log "$GREEN" "$@"
}

log_red() {
    log "$RED" "$@"
}

log_yellow() {
    log "$YELLOW" "$@"
}

log_blue() {
    log "$BLUE" "$@"
}

# 检查 Gateway 是否运行
check_gateway() {
    pgrep -f "openclaw-gateway" > /dev/null 2>&1
}

# 获取 Gateway PID
get_gateway_pid() {
    pgrep -f "openclaw-gateway" | head -1
}

# 等待 Gateway 启动
wait_gateway_start() {
    local timeout="$1"
    local elapsed=0

    log_blue "⏳ 等待 Gateway 启动（最多 ${timeout} 秒）..."

    while [ $elapsed -lt $timeout ]; do
        if check_gateway; then
            log_green "✓ Gateway 已启动 (PID: $(get_gateway_pid))"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        echo -n "."
    done

    echo ""
    log_red "✗ Gateway 未在 ${timeout} 秒内启动"
    return 1
}

# 等待看门狗恢复
wait_watchdog_recovery() {
    local timeout="$1"
    local elapsed=0

    log_blue "⏳ 等待看门狗恢复 Gateway（最多 ${timeout} 秒）..."

    while [ $elapsed -lt $timeout ]; do
        if check_gateway; then
            log_green "✓ 看门狗已恢复 Gateway (PID: $(get_gateway_pid))"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        echo -n "."
    done

    echo ""
    log_red "✗ 看门狗未在 ${timeout} 秒内恢复 Gateway"
    return 1
}

# 记录系统状态
record_status() {
    local marker="$1"

    {
        echo "=== $marker ==="
        echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Gateway 进程:"
        ps aux | grep -i gateway | grep -v grep || echo "  未运行"
        echo "心跳文件:"
        if [ -f "$HOME/.openclaw/watchdog/heartbeat.timestamp" ]; then
            local last=$(cat "$HOME/.openclaw/watchdog/heartbeat.timestamp")
            local now=$(date +%s)
            local diff=$((now - last))
            echo "  上次更新: $diff 秒前"
        else
            echo "  不存在"
        fi
        echo "Cron 任务:"
        crontab -l | grep -E "(heartbeat|watchdog)" || echo "  无相关任务"
        echo ""
    } >> "$TEST_LOG"
}

# 发送测试报告邮件
send_test_report() {
    local result="$1"
    local details="$2"

    local subject=""
    local body=""

    if [ "$result" = "PASS" ]; then
        subject="✅ Gateway 看门狗测试通过"
    else
        subject="❌ Gateway 看门狗测试失败"
    fi

    body="🧪 Gateway 看门狗测试报告

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

测试时间: $(date '+%Y-%m-%d %H:%M:%S')
服务器: $(hostname)
IP地址: $(hostname -I | awk '{print $1}')

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

测试结果: $result

$details

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

完整日志:
$(cat "$TEST_LOG")

---
Gateway Watchdog Test
🐕 自动测试系统"

    bash "$EMAIL_SCRIPT" "$subject" "$body"
    log_blue "📧 测试报告已发送到邮箱"
}

# 清理并恢复
cleanup_and_restore() {
    log_yellow ""
    log_yellow "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_yellow "🧹 清理并恢复环境"
    log_yellow "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 如果 Gateway 未运行，尝试启动
    if ! check_gateway; then
        log_yellow "Gateway 未运行，尝试启动..."
        openclaw gateway start >> "$TEST_LOG" 2>&1
        sleep 5
    fi

    # 确保 Gateway 运行中
    if check_gateway; then
        log_green "✓ Gateway 已恢复运行 (PID: $(get_gateway_pid))"
    else
        log_red "✗ Gateway 启动失败，请手动检查"
    fi

    log_yellow ""
    log_yellow "测试结束"
}

# 主测试流程
main() {
    clear
    log_blue "╔════════════════════════════════════════════╗"
    log_blue "║  🧪 Gateway 看门狗完整测试程序             ║"
    log_blue "║  测试看门狗是否能在 Gateway 停止后自动恢复 ║"
    log_blue "╚════════════════════════════════════════════╝"
    log_blue ""

    # 检查是否以 root 运行
    if [ "$EUID" -ne 0 ]; then
        log_red "✗ 此脚本需要 root 权限"
        log_yellow "请使用: sudo $0"
        exit 1
    fi

    log_yellow "⚠️  警告: 此测试会停止 Gateway 进程"
    log_yellow "看门狗应该在 2-4 分钟内自动恢复"
    log_yellow "如果看门狗正常工作，Gateway 会自动重启"
    log_yellow ""
    read -p "确认开始测试? (y/N): " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_yellow "测试已取消"
        exit 0
    fi

    # 初始化测试日志
    > "$TEST_LOG"
    log_blue "测试开始: $(date '+%Y-%m-%d %H:%M:%S')"
    log_blue ""

    # 步骤 1: 检查初始状态
    log_blue "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_blue "📋 步骤 1: 检查初始状态"
    log_blue "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if ! check_gateway; then
        log_red "✗ Gateway 当前未运行"
        log_yellow "尝试启动 Gateway..."
        openclaw gateway start >> "$TEST_LOG" 2>&1
        sleep 5

        if ! check_gateway; then
            log_red "✗ Gateway 启动失败，测试中止"
            exit 1
        fi
    fi

    local initial_pid=$(get_gateway_pid)
    log_green "✓ Gateway 运行中 (PID: $initial_pid)"

    # 检查看门狗 cron
    if crontab -l | grep -q "gateway-watchdog.sh"; then
        log_green "✓ 看门狗 cron 任务已配置"
    else
        log_red "✗ 看门狗 cron 任务未配置"
        log_yellow "请先运行看门狗部署脚本"
        exit 1
    fi

    # 检查心跳 cron
    if crontab -l | grep -q "update-heartbeat.sh"; then
        log_green "✓ 心跳 cron 任务已配置"
    else
        log_red "✗ 心跳 cron 任务未配置"
        log_yellow "请先运行看门狗部署脚本"
        exit 1
    fi

    record_status "初始状态"
    log_blue ""

    # 步骤 2: 停止 Gateway
    log_blue "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_blue "🛑 步骤 2: 停止 Gateway"
    log_blue "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    log_yellow "正在停止 Gateway (PID: $initial_pid)..."
    pkill -f "openclaw-gateway"

    sleep 3

    if check_gateway; then
        log_red "✗ Gateway 停止失败"
        log_yellow "尝试强制停止..."
        pkill -9 -f "openclaw-gateway"
        sleep 2

        if check_gateway; then
            log_red "✗ Gateway 强制停止也失败"
            log_yellow "请手动检查"
            cleanup_and_restore
            exit 1
        fi
    fi

    log_green "✓ Gateway 已停止"
    record_status "Gateway 停止后"
    log_blue ""

    # 步骤 3: 等待看门狗恢复
    log_blue "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_blue "⏳ 步骤 3: 等待看门狗自动恢复"
    log_blue "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    log_yellow "看门狗每 2 分钟检查一次"
    log_yellow "最多等待 5 分钟..."
    log_blue ""

    if wait_watchdog_recovery 300; then
        local recovered_pid=$(get_gateway_pid)
        log_green "✓✓✓ 看门狗测试通过！"
        log_green "看门狗成功恢复了 Gateway (新 PID: $recovered_pid)"

        record_status "看门狗恢复后"

        # 分析恢复日志
        log_blue ""
        log_blue "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_blue "📊 恢复日志分析"
        log_blue "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        log_yellow "最近的看门狗日志:"
        tail -20 "$LOG_FILE" | while IFS= read -r line; do
            echo "  $line"
        done | tee -a "$TEST_LOG"

        # 发送测试报告
        log_blue ""
        send_test_report "PASS" "
看门狗成功检测到 Gateway 停止并自动恢复。

恢复用时: 约 2-4 分钟
恢复方式: 自动重启
新进程 PID: $recovered_pid

✅ 看门狗工作正常！
"

        log_blue ""
        log_green "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_green "🎉 测试完成 - 看门狗工作正常"
        log_green "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        cleanup_and_restore
        exit 0
    else
        log_red "✗✗✗ 看门狗测试失败！"
        log_red "看门狗未能在 5 分钟内恢复 Gateway"

        record_status "测试失败"

        # 发送失败报告
        log_blue ""
        send_test_report "FAIL" "
看门狗未能检测到 Gateway 停止或未能自动恢复。

可能原因:
1. 看门狗 cron 任务未正确配置
2. 看门狗脚本执行出错
3. Gateway 启动命令有问题
4. 系统资源不足

请检查日志:
$LOG_FILE
$TEST_LOG

❌ 看门狗可能有问题，需要人工检查
"

        log_blue ""
        log_red "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_red "❌ 测试失败 - 看门狗可能有问题"
        log_red "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        cleanup_and_restore
        exit 1
    fi
}

# 捕获 Ctrl+C
trap cleanup_and_restore INT

# 运行测试
main "$@"
