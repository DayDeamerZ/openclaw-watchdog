#!/bin/bash
# 简化版看门狗测试（不发送邮件，不自动重启，仅观察）

set -e

WATCHDOG_SCRIPT="$HOME/.openclaw/scripts/gateway-watchdog.sh"
LOG_FILE="$HOME/.openclaw/watchdog/watchdog.log"
TEST_LOG="/tmp/gateway-watchdog-simple-test.log"

echo "🧪 Gateway 看门狗简化测试"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 检查当前状态
echo "📊 当前状态:"
if pgrep -f "openclaw-gateway" > /dev/null; then
    echo "  ✓ Gateway 运行中 (PID: $(pgrep -f openclaw-gateway | head -1))"
else
    echo "  ✗ Gateway 未运行"
fi

if [ -f "$HOME/.openclaw/watchdog/heartbeat.timestamp" ]; then
    last=$(cat "$HOME/.openclaw/watchdog/heartbeat.timestamp")
    now=$(date +%s)
    diff=$((now - last))
    echo "  ✓ 心跳文件存在 (${diff}秒前更新)"
else
    echo "  ✗ 心跳文件不存在"
fi

echo ""
echo "⚠️  此测试会停止 Gateway，然后观察看门狗是否在 5 分钟内自动恢复"
echo "⚠️  如果看门狗不工作，你需要手动启动 Gateway"
echo ""
read -p "确认测试? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

# 记录初始状态
{
    echo "=== 测试开始: $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "初始 PID: $(pgrep -f openclaw-gateway | head -1)"
} > "$TEST_LOG"

# 停止 Gateway
echo ""
echo "🛑 停止 Gateway..."
GATEWAY_PID=$(pgrep -f openclaw-gateway | head -1)
kill "$GATEWAY_PID"
sleep 2

if pgrep -f openclaw-gateway > /dev/null; then
    echo "  尝试强制停止..."
    kill -9 "$GATEWAY_PID"
    sleep 1
fi

echo "  ✓ Gateway 已停止"

# 观察看门狗
echo ""
echo "⏳ 观察看门狗（每 10 秒检查一次，最多 5 分钟）..."
echo ""

for i in {1..30}; do
    sleep 10

    if pgrep -f openclaw-gateway > /dev/null; then
        NEW_PID=$(pgrep -f openclaw-gateway | head -1)
        elapsed=$((i * 10))
        echo "  ✅ 看门狗已恢复 Gateway！"
        echo "  新 PID: $NEW_PID"
        echo "  用时: ${elapsed} 秒 ($((elapsed / 60)) 分钟)"

        {
            echo ""
            echo "=== 看门狗恢复 ==="
            echo "恢复时间: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "用时: ${elapsed} 秒"
            echo "新 PID: $NEW_PID"
            echo ""
            echo "最近的看门狗日志:"
            tail -10 "$LOG_FILE"
        } >> "$TEST_LOG"

        echo ""
        echo "📄 测试日志已保存: $TEST_LOG"
        echo ""
        echo "✅ 测试通过！看门狗工作正常"
        exit 0
    fi

    echo "  [$i/30] $(date '+%H:%M:%S') - Gateway 仍未启动..."
done

echo ""
echo "❌ 测试失败"
echo "看门狗未能在 5 分钟内恢复 Gateway"
echo ""
echo "可能原因:"
echo "  1. 看门狗 cron 任务未配置"
echo "  2. 看门狗脚本执行出错"
echo "  3. Gateway 启动命令有问题"
echo ""
echo "请手动启动 Gateway:"
echo "  openclaw gateway start"
echo ""
echo "完整测试日志: $TEST_LOG"
