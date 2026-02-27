#!/bin/bash
# Gateway 心跳更新脚本
# 由 Gateway 定期调用，证明自己还活着

HEARTBEAT_FILE="$HOME/.openclaw/watchdog/heartbeat.timestamp"
mkdir -p "$(dirname "$HEARTBEAT_FILE")"

# 更新心跳时间戳
echo "$(date +%s)" > "$HEARTBEAT_FILE"

# 可选：记录一些状态信息
echo "Last heartbeat: $(date '+%Y-%m-%d %H:%M:%S')" >> "$HOME/.openclaw/watchdog/heartbeat.log"
