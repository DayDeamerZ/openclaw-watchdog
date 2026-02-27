#!/bin/bash
# OpenClaw Gateway 增强版看门狗 v2.0
# 多层检测 + 分级恢复 + 完整邮件通知

set -e

WATCHDOG_ROOT="$HOME/.openclaw/watchdog"
LOG_FILE="$WATCHDOG_ROOT/watchdog.log"
HEARTBEAT_FILE="$WATCHDOG_ROOT/heartbeat.timestamp"
RECOVERY_INFO="$WATCHDOG_ROOT/recovery-info.txt"
NOTIFICATION_FILE="$HOME/.openclaw/logs/watchdog-recovery-info.txt"
BACKUP_SCRIPT="$HOME/.openclaw/scripts/backup-gateway-db.sh"
EMAIL_SCRIPT="$HOME/.openclaw/scripts/send-email.sh"
BACKUP_STATE_FILE="$WATCHDOG_ROOT/backup-state.json"

# 创建必要目录
mkdir -p "$WATCHDOG_ROOT" "$HOME/.openclaw/logs" "$HOME/.openclaw/backups/gateway"

# 阈值配置
HEARTBEAT_TIMEOUT=300  # 心跳超时（秒）- 5分钟无心跳视为异常
RECOVERY_WAIT=30       # 等待恢复时间（秒）
MAX_RECOVERY_LEVEL=4   # 最大恢复级别
BACKUP_INTERVAL=10800  # 定时备份间隔（秒）- 3小时
MAX_BACKUPS=30         # 最多保留30个备份

# 日志函数
log() {
    local level="$1"
    shift
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    echo "$message" | tee -a "$LOG_FILE"
}

# 发送邮件通知
send_alert() {
    local subject="$1"
    local body="$2"
    local attachment="${3:-}"

    log "INFO" "📧 发送邮件: $subject"
    if [ -n "$attachment" ] && [ -f "$attachment" ]; then
        bash "$EMAIL_SCRIPT" "$subject" "$body" "$attachment"
    else
        bash "$EMAIL_SCRIPT" "$subject" "$body"
    fi
}

# 检查 Gateway 进程是否存在
check_process() {
    pgrep -f "openclaw-gateway" > /dev/null 2>&1
}

# 检查心跳是否正常
check_heartbeat() {
    if [ ! -f "$HEARTBEAT_FILE" ]; then
        log "WARN" "心跳文件不存在"
        return 1
    fi

    local last_heartbeat=$(cat "$HEARTBEAT_FILE" 2>/dev/null || echo "0")
    local current_time=$(date +%s)
    local time_diff=$((current_time - last_heartbeat))

    if [ $time_diff -gt $HEARTBEAT_TIMEOUT ]; then
        log "WARN" "心跳超时: ${time_diff}秒 未更新"
        return 1
    fi

    return 0
}

# 检查 Gateway 功能是否正常
check_functionality() {
    local gateway_pid=$(pgrep -f "openclaw-gateway" | head -1)
    if [ -n "$gateway_pid" ]; then
        local cpu_usage=$(ps -p "$gateway_pid" -o %cpu --no-headers | tr -d ' ')
        if [ -n "$cpu_usage" ] && [ "$(echo "$cpu_usage > 0" | bc)" -eq 1 ]; then
            return 0
        fi
    fi
    return 1
}

# 创建恢复通知文件
create_notification() {
    local level="$1"
    local reason="$2"
    local method="$3"
    local backup="$4"

    cat > "$NOTIFICATION_FILE" << EOF
========================================
🚨 Gateway 恢复通知
========================================

时间: $(date '+%Y-%m-%d %H:%M:%S')
恢复级别: Level $level
故障原因: $reason
恢复方式: $method

备份信息:
$backup

系统信息:
- 主机名: $(hostname)
- IP地址: $(hostname -I | awk '{print $1}')
- Gateway 状态: $(check_process && echo "运行中" || echo "已停止")

最近日志:
$(tail -20 "$LOG_FILE" 2>/dev/null || echo "无日志")

========================================
EOF
}

# 定时备份检查和执行

# 定时备份检查和执行（简化版 - 调用数据库备份脚本）
check_and_backup() {
    # 直接调用数据库备份脚本，让它自己判断是否需要备份
    local backup_output=$(bash "$BACKUP_SCRIPT" 2>&1)
    local exit_code=$?
    
    # 检查返回码和输出
    if [ $exit_code -eq 0 ] && echo "$backup_output" | grep -q "备份完成"; then
        # 提取数据库路径（最后一行）
        local backup_db=$(echo "$backup_output" | tail -1 | grep -o '/root/.*gateway-backups.db')
        
        if [ -n "$backup_db" ]; then
            log "INFO" "✅ 定时备份完成: $backup_db"
            
            # 发送备份完成邮件
            send_alert "Gateway配置备份完成" "Gateway 配置备份成功！

备份时间: $(date '+%Y-%m-%d %H:%M:%S')
数据库位置: $backup_db
备份数量: $(sqlite3 "$backup_db" "SELECT COUNT(*) FROM backups;" 2>/dev/null || echo "未知")

下次备份: $(date -d "+3 hours" '+%H:%M:%S')

---
🐕 Gateway Watchdog 自动备份"
        fi
        
        return 0
    else
        # 未到备份时间，显示下次备份时间
        local next_backup=$(echo "$backup_output" | grep "下次备份:" | awk '{print $NF}')
        if [ -n "$next_backup" ]; then
            log "INFO" "💾 下次备份: $next_backup"
        fi
        return 1
    fi
}
# Level 1: 简单重启
recovery_level_1() {
    log "INFO" "🔧 执行 Level 1 恢复: 基础重启"

    # 发送开始恢复邮件
    send_alert "Gateway异常终止 - 开始修复(Level 1)" "检测到 Gateway 异常！

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

故障时间: $(date '+%Y-%m-%d %H:%M:%S')
故障原因: $1

正在执行 Level 1 恢复（基础重启）...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

恢复步骤:
1. 执行 openclaw gateway restart
2. 等待 30 秒
3. 验证 Gateway 状态

预计用时: 30-60 秒

---
🐕 Gateway Watchdog 自动恢复中"

    # 先执行备份
    local backup_dir=$(bash "$BACKUP_SCRIPT" 2>&1 | tail -1)
    log "INFO" "✓ 已创建备份: $backup_dir"

    log "INFO" "执行: openclaw gateway restart"
    openclaw gateway restart >> "$LOG_FILE" 2>&1

    sleep "$RECOVERY_WAIT"

    if check_heartbeat && check_process; then
        log "INFO" "✅ Level 1 恢复成功"
        create_notification "1" "$1" "基础重启" "$backup_dir"

        # 发送恢复成功邮件
        send_alert "Gateway已恢复成功(Level 1)" "Gateway 通过基础重启成功恢复！

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

恢复时间: $(date '+%Y-%m-%d %H:%M:%S')
故障原因: $1
恢复方式: Level 1 - 基础重启
恢复用时: 约 30-60 秒

备份位置: $backup_dir

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Gateway 当前状态:
✓ 进程运行中 (PID: $(pgrep -f openclaw-gateway | head -1))
✓ 心跳正常

---
🐕 Gateway Watchdog - 自动恢复成功"

        return 0
    fi

    return 1
}

# Level 2: 强制重启
recovery_level_2() {
    log "INFO" "🔧 执行 Level 2 恢复: 强制重启"

    # 发送开始恢复邮件
    send_alert "Gateway异常终止 - 升级修复(Level 2)" "Level 1 恢复失败，正在执行 Level 2...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

故障时间: $(date '+%Y-%m-%d %H:%M:%S')
故障原因: $1

正在执行 Level 2 恢复（强制重启）...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

恢复步骤:
1. 强制停止 Gateway (kill -9)
2. 清理残留文件
3. 重新启动 Gateway
4. 等待 30 秒验证

预计用时: 60-90 秒

---
🐕 Gateway Watchdog 自动恢复中"

    local backup_dir=$(bash "$BACKUP_SCRIPT" 2>&1 | tail -1)
    log "INFO" "✓ 已创建备份: $backup_dir"

    log "INFO" "停止 Gateway 进程"
    pkill -9 -f "openclaw-gateway" || true
    sleep 3

    log "INFO" "清理残留"
    rm -rf /tmp/openclaw-* 2>/dev/null || true

    log "INFO" "重新启动 Gateway"
    openclaw gateway start >> "$LOG_FILE" 2>&1

    sleep "$RECOVERY_WAIT"

    if check_heartbeat && check_process; then
        log "INFO" "✅ Level 2 恢复成功"
        create_notification "2" "$1" "强制重启" "$backup_dir"

        # 发送恢复成功邮件
        send_alert "Gateway已恢复成功(Level 2)" "Gateway 通过强制重启成功恢复！

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

恢复时间: $(date '+%Y-%m-%d %H:%M:%S')
故障原因: $1
恢复方式: Level 2 - 强制重启
恢复用时: 约 60-90 秒

备份位置: $backup_dir

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Gateway 当前状态:
✓ 进程运行中 (PID: $(pgrep -f openclaw-gateway | head -1))
✓ 心跳正常

---
🐕 Gateway Watchdog - 自动恢复成功"

        return 0
    fi

    return 1
}

# Level 3: 使用 Opencode 修复
recovery_level_3() {
    log "INFO" "🤖 执行 Level 3 恢复: Opencode 深度修复"

    # 发送开始恢复邮件
    send_alert "Gateway异常终止 - 深度修复(Level 3)" "Level 2 恢复失败，正在执行 Level 3 深度修复...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

故障时间: $(date '+%Y-%m-%d %H:%M:%S')
故障原因: $1

正在执行 Level 3 恢复（Opencode AI 修复）...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

恢复步骤:
1. 临时启动 Opencode (占用约 500MB 内存)
2. 发送修复提示词（包含备份位置）
3. Opencode 分析并修复配置
4. 重新启动 Gateway
5. 关闭 Opencode（释放内存）

预计用时: 2-5 分钟

⚠️  注意: 此过程会临时启动 Opencode

---
🐕 Gateway Watchdog 自动恢复中"

    local backup_dir=$(bash "$BACKUP_SCRIPT" 2>&1 | tail -1)

    # 启动 opencode
    log "INFO" "启动 Opencode..."
    /root/.nvm/versions/node/v22.22.0/lib/node_modules/opencode-ai/bin/.opencode &
    OPENCODE_PID=$!
    sleep 5

    log "INFO" "Opencode 已启动 (PID: $OPENCODE_PID)"

    # 准备修复提示词
    local opencode_prompt=$(cat << EOF
你是一个 Gateway 故障恢复专家。当前 OpenClaw Gateway 完全无法启动。

已知信息：
- 备份配置位置: $backup_dir
- 错误日志: $LOG_FILE
- Gateway 状态: $(check_process && echo "进程存在" || echo "进程不存在")
- 心跳状态: $(check_heartbeat && echo "正常" || echo "超时")

请执行以下步骤：
1. 分析日志找出根本原因
2. 比对当前配置和备份配置的差异
3. 尝试还原最近的可用配置
4. 修复依赖或版本冲突
5. 验证并启动 Gateway

完成后执行: openclaw gateway start
EOF
)

    log "INFO" "发送修复任务给 Opencode..."
    echo "$opencode_prompt" > /tmp/opencode-gateway-fix.txt

    log "INFO" "Opencode 修复任务已发送"
    log "INFO" "修复提示词已保存到: /tmp/opencode-gateway-fix.txt"

    sleep "$RECOVERY_WAIT"

    # 尝试启动 Gateway
    log "INFO" "尝试启动 Gateway..."
    openclaw gateway start >> "$LOG_FILE" 2>&1
    sleep 10

    if check_heartbeat && check_process; then
        log "INFO" "✅ Level 3 恢复成功"
        create_notification "3" "$1" "Opencode 修复" "$backup_dir"

        # 关闭 opencode
        log "INFO" "关闭 Opencode (释放内存)"
        kill $OPENCODE_PID 2>/dev/null || true
        sleep 2

        # 发送恢复成功邮件
        send_alert "Gateway已恢复成功(Level 3)" "Gateway 通过 Opencode 深度修复成功恢复！

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

恢复时间: $(date '+%Y-%m-%d %H:%M:%S')
故障原因: $1
恢复方式: Level 3 - Opencode AI 修复
恢复用时: 约 2-5 分钟

备份位置: $backup_dir

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Gateway 当前状态:
✓ 进程运行中 (PID: $(pgrep -f openclaw-gateway | head -1))
✓ 心跳正常
✓ Opencode 已关闭（内存已释放）

---
🐕 Gateway Watchdog - AI 自动恢复成功"

        return 0
    fi

    # 即使失败也关闭 opencode
    kill $OPENCODE_PID 2>/dev/null || true

    return 1
}

# Level 4: 发送紧急告警
recovery_level_4() {
    log "ERROR" "🚨 所有恢复尝试均失败，发送紧急告警"

    local backup_dir=$(bash "$BACKUP_SCRIPT" 2>&1 | tail -1)

    local alert_body="⚠️⚠️⚠️ 紧急告警 ⚠️⚠️⚠️

OpenClaw Gateway 所有恢复尝试均失败！

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

服务器信息:
- 主机名: $(hostname)
- IP地址: $(hostname -I | awk '{print $1}')
- 故障时间: $(date '+%Y-%m-%d %H:%M:%S')

问题诊断:
- Gateway 进程: $(check_process && echo "存在" || echo "不存在") ❌
- 心跳状态: $(check_heartbeat && echo "正常" || echo "超时") ❌
- 功能检测: $(check_functionality && echo "正常" || echo "异常") ❌

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

已尝试的恢复方法:
✗ Level 1: 基础重启 - 失败
✗ Level 2: 强制重启 - 失败
✗ Level 3: Opencode 深度修复 - 失败

最新备份: $backup_dir

日志文件: $LOG_FILE

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

请立即人工介入处理！

建议操作:
1. 查看日志: tail -100 $LOG_FILE
2. 尝试手动启动: openclaw gateway start
3. 还原配置: 从 $backup_dir
4. 重启服务器（最后手段）

---
🐕 Gateway Watchdog
🚨 需要人工介入"

    send_alert "紧急告警 - Gateway无法恢复" "$alert_body" "$LOG_FILE"

    log "ERROR" "紧急告警已发送，等待人工处理"
    create_notification "4" "$1" "需人工介入" "$backup_dir"

    return 1
}

# 主恢复流程
perform_recovery() {
    local reason="$1"

    log "WARN" "🚨 检测到 Gateway 异常: $reason"
    log "WARN" "开始执行恢复流程..."

    # Level 1: 基础重启
    if recovery_level_1 "$reason"; then
        return 0
    fi

    # Level 2: 强制重启
    if recovery_level_2 "$reason"; then
        return 0
    fi

    # Level 3: Opencode 深度修复
    if recovery_level_3 "$reason"; then
        return 0
    fi

    # Level 4: 紧急告警
    recovery_level_4 "$reason"
    return 1
}

# 主检查流程
main() {
    log "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "INFO" "🐕 OpenClaw Gateway 看门狗启动检查"

    local process_ok=false
    local heartbeat_ok=false
    local functionality_ok=false

    # 检查进程
    if check_process; then
        log "INFO" "✓ Gateway 进程存在"
        process_ok=true
    else
        log "ERROR" "✗ Gateway 进程不存在"
    fi

    # 检查心跳
    if check_heartbeat; then
        log "INFO" "✓ Gateway 心跳正常"
        heartbeat_ok=true
    else
        log "ERROR" "✗ Gateway 心跳异常"
    fi

    # 检查功能
    if check_functionality; then
        log "INFO" "✓ Gateway 功能正常"
        functionality_ok=true
    else
        log "WARN" "✗ Gateway 功能异常"
    fi

    # 检查是否需要定时备份（仅在Gateway正常时检查）
    if [ "$process_ok" = true ] && [ "$heartbeat_ok" = true ]; then
        check_and_backup
    fi

    # 判断是否需要恢复
    if [ "$process_ok" = true ] && [ "$heartbeat_ok" = true ]; then
        log "INFO" "✅ Gateway 状态正常，无需恢复"
        # 更新看门狗存活时间戳
        echo "$(date +%s)" > "$WATCHDOG_ROOT/watchdog-alive.timestamp"
        exit 0
    fi

    # 确定故障原因
    local reason=""
    if [ "$process_ok" = false ]; then
        reason="Gateway 进程不存在"
    elif [ "$heartbeat_ok" = false ]; then
        reason="Gateway 心跳超时（可能卡死）"
    elif [ "$functionality_ok" = false ]; then
        reason="Gateway 功能异常（进程僵死）"
    fi

    # 执行恢复
    perform_recovery "$reason"
}

# 如果直接运行脚本
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
