#!/bin/bash
# Gateway 看门狗写保护设置脚本
# 防止看门狗文件被意外修改或删除

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}🔒 Gateway 看门狗写保护设置${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 需要保护的文件和目录
PROTECTED_FILES=(
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

# 排除的目录（允许修改）
EXCLUDE_DIRS=(
    "$HOME/.openclaw/watchdog/logs"
    "$HOME/.openclaw/logs"
    "$HOME/.openclaw/watchdog/*.db"
    "$HOME/.openclaw/watchdog/*.json"
    "$HOME/.openclaw/watchdog/*.timestamp"
)

echo -e "${YELLOW}📋 将设置写保护的文件:${NC}"
for file in "${PROTECTED_FILES[@]}"; do
    if [ -e "$file" ]; then
        echo "  ✓ $file"
    else
        echo "  ⚠️  $file (不存在)"
    fi
done
echo ""

read -p "确认设置写保护? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

echo ""
echo -e "${GREEN}🔒 设置写保护...${NC}"

# 设置文件为 immutable（chattr +i）
set_protection() {
    local file="$1"
    
    if [ ! -e "$file" ]; then
        echo "  ⚠️  跳过（不存在）: $file"
        return
    fi
    
    # 使用 chattr 设置 immutable 属性
    if chattr +i "$file" 2>/dev/null; then
        echo "  ✅ 已保护: $file"
    else
        # 如果 chattr 不可用，使用 chmod
        chmod 444 "$file" 2>/dev/null && echo "  ⚠️  只读保护: $file" || echo "  ❌ 保护失败: $file"
    fi
}

# 保护所有文件
for file in "${PROTECTED_FILES[@]}"; do
    set_protection "$file"
done

echo ""
echo -e "${GREEN}🔒 设置目录保护（允许添加新文件，但不能删除目录）${NC}"

# 保护目录本身（但允许内部文件修改）
chattr +i "$HOME/.openclaw/watchdog/" 2>/dev/null && echo "  ✅ 已保护: $HOME/.openclaw/watchdog/"
chattr +i /etc/systemd/system/openclaw-gateway-watchdog.* 2>/dev/null && echo "  ✅ 已保护: /etc/systemd/system/openclaw-gateway-watchdog.*"

echo ""
echo -e "${GREEN}📝 创建保护记录${NC}"

PROTECTION_LOG="$HOME/.openclaw/watchdog/protection-info.txt"
cat > "$PROTECTION_LOG" << EOF
Gateway 看门狗写保护信息
========================

保护时间: $(date '+%Y-%m-%d %H:%M:%S')
保护方式: chattr +i (immutable) 或 chmod 444 (只读)

受保护的文件:
$(printf '%s\n' "${PROTECTED_FILES[@]}")

保护说明:
1. 这些文件被设置为不可修改（immutable）
2. 只有 root 用户可以移除保护
3. Opencode 需要时可以临时移除保护
4. 其他程序（包括 OpenClaw）无法修改

如何移除保护（仅限紧急情况或 Opencode 使用）:
1. sudo chattr -i <文件路径>
2. 或: sudo chmod 644 <文件路径>

重新启用保护:
1. sudo chattr +i <文件路径>
2. 或: sudo chmod 444 <文件路径>

⚠️  警告:
- 不要随意移除保护
- 修改前必须先备份
- Opencode 修复时会自动处理保护

EOF

echo "  ✅ 保护记录: $PROTECTION_LOG"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ 写保护设置完成！${NC}"
echo ""
echo -e "${YELLOW}📋 受保护的文件:${NC}"
lsattr -l "${PROTECTED_FILES[@]}" 2>/dev/null | grep '^[-i]' || echo "  (使用 lsattr 查看)"
echo ""
echo -e "${YELLOW}⚠️  注意事项:${NC}"
echo "  • 看门狗文件现在无法被修改或删除"
echo "  • 只有 root 可以移除保护"
echo "  • Opencode 修复时会自动处理"
echo "  • 其他程序（包括 OpenClaw）无法修改"
echo ""
echo -e "${YELLOW}🔓 移除保护（仅紧急情况）:${NC}"
echo "  sudo chattr -i ~/.openclaw/scripts/gateway-watchdog.sh"
echo "  sudo chattr -i /etc/systemd/system/openclaw-gateway-watchdog.*"
echo ""
