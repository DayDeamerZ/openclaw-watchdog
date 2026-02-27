#!/bin/bash
# 移除看门狗写保护的辅助函数
# 仅供 Opencode 或紧急修复使用

WATCHDOG_FILES=(
    "$HOME/.openclaw/scripts/gateway-watchdog.sh"
    "$HOME/.openclaw/scripts/gateway-watchdog.sh.old"
    "$HOME/.openclaw/scripts/backup-gateway-db.sh"
    "$HOME/.openclaw/scripts/backup-db-query.sh"
    "$HOME/.openclaw/scripts/watchdog-manager.sh"
    "$HOME/.openclaw/scripts/update-heartbeat.sh"
    "$HOME/.openclaw/scripts/send-email.sh"
    "$HOME/.openclaw/watchdog/"
    "/etc/systemd/system/openclaw-gateway-watchdog.service"
    "/etc/systemd/system/openclaw-gateway-watchdog.timer"
    "/etc/systemd/system/openclaw-gateway-heartbeat.service"
    "/etc/systemd/system/openclaw-gateway-heartbeat.timer"
)

# 移除写保护
remove_protection() {
    echo "🔓 移除看门狗写保护..."
    for file in "${WATCHDOG_FILES[@]}"; do
        if [ -e "$file" ]; then
            chattr -i "$file" 2>/dev/null && echo "  ✓ 已移除保护: $file"
        fi
    done
    echo "✅ 保护已移除，现在可以修改看门狗文件"
}

# 重新启用写保护
add_protection() {
    echo "🔒 重新启用看门狗写保护..."
    for file in "${WATCHDOG_FILES[@]}"; do
        if [ -e "$file" ]; then
            chattr +i "$file" 2>/dev/null && echo "  ✓ 已保护: $file"
        fi
    done
    echo "✅ 保护已重新启用"
}

# 检查保护状态
check_protection() {
    echo "🔍 检查看门狗保护状态..."
    for file in "${WATCHDOG_FILES[@]}"; do
        if [ -e "$file" ]; then
            local attrs=$(lsattr -d "$file" 2>/dev/null | grep -o '^[-i]*' || echo "")
            if [[ "$attrs" == *"i"* ]]; then
                echo "  ✓ 受保护: $file"
            else
                echo "  ✗ 未保护: $file"
            fi
        fi
    done
}

# 如果直接运行脚本
case "${1:-check}" in
    remove)
        remove_protection
        ;;
    add)
        add_protection
        ;;
    check)
        check_protection
        ;;
    *)
        echo "看门狗保护管理工具"
        echo ""
        echo "用法: $0 <命令>"
        echo ""
        echo "命令:"
        echo "  remove  - 移除写保护"
        echo "  add     - 重新启用写保护"
        echo "  check   - 检查保护状态"
        echo ""
        echo "示例:"
        echo "  $0 remove   # 移除保护，允许修改"
        echo "  $0 add      # 重新启用保护"
        echo "  $0 check    # 查看保护状态"
        ;;
esac
