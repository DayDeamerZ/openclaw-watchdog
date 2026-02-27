#!/bin/bash
# Gateway 配置数据库备份脚本
# 使用 SQLite 数据库存储备份，以现实时间为基准

set -e

WATCHDOG_ROOT="$HOME/.openclaw/watchdog"
BACKUP_DB="$WATCHDOG_ROOT/gateway-backups.db"
MAX_BACKUPS=30

# 创建数据库和表
init_db() {
    sqlite3 "$BACKUP_DB" << 'EOF'
CREATE TABLE IF NOT EXISTS backups (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    backup_time TEXT NOT NULL,
    backup_timestamp INTEGER NOT NULL,
    backup_type TEXT NOT NULL,
    content TEXT,
    file_path TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS backup_config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 插入默认配置
INSERT OR IGNORE INTO backup_config (key, value) VALUES ('last_backup_hour', '-1');
EOF
}

# 读取上次备份小时
get_last_backup_hour() {
    sqlite3 "$BACKUP_DB" "SELECT value FROM backup_config WHERE key='last_backup_hour';" 2>/dev/null || echo "-1"
}

# 更新上次备份小时
update_last_backup_hour() {
    local hour=$1
    sqlite3 "$BACKUP_DB" "INSERT OR REPLACE INTO backup_config (key, value, updated_at) VALUES ('last_backup_hour', '$hour', CURRENT_TIMESTAMP);"
}

# 检查是否需要备份（每3小时：0, 3, 6, 9, 12, 15, 18, 21）
should_backup() {
    local current_hour=$(date +%H)
    local last_hour=$(get_last_backup_hour)
    
    echo "当前小时: $current_hour, 上次备份小时: $last_hour"
    
    # 计算距离上次备份的小时数
    if [ "$last_hour" = "-1" ]; then
        # 第一次备份
        return 0
    fi
    
    local hours_since=$(( (10#$current_hour - 10#$last_hour + 24) % 24 ))
    
    # 如果距离上次备份超过3小时，或正好是3小时的倍数时间点
    if [ $hours_since -ge 3 ] || [ "$((10#$current_hour % 3))" -eq 0 ]; then
        # 但要确保不是同一小时内重复备份
        if [ "$current_hour" != "$last_hour" ]; then
            return 0
        fi
    fi
    
    return 1
}

# 备份文件内容到数据库
backup_file_to_db() {
    local file_path="$1"
    local backup_type="$2"
    
    if [ ! -f "$file_path" ]; then
        echo "  跳过（不存在）: $file_path"
        return
    fi
    
    local filename=$(basename "$file_path")
    local content=$(base64 -w 0 "$file_path" 2>/dev/null || echo "")
    
    if [ -z "$content" ]; then
        echo "  跳过（读取失败）: $file_path"
        return
    fi
    
    sqlite3 "$BACKUP_DB" << EOF
INSERT INTO backups (backup_time, backup_timestamp, backup_type, file_path, content)
VALUES (
    '$(date "+%Y-%m-%d %H:%M:%S")',
    $(date +%s),
    '$backup_type',
    '$file_path',
    '$content'
);
EOF
    
    echo "  ✓ 已备份: $file_path ($backup_type)"
}

# 备份目录到数据库
backup_dir_to_db() {
    local dir_path="$1"
    local backup_type="$2"
    
    if [ ! -d "$dir_path" ]; then
        echo "  跳过（目录不存在）: $dir_path"
        return
    fi
    
    # 递归备份目录中的所有文件
    find "$dir_path" -type f | while read -r file; do
        local relative_path="${file#$dir_path/}"
        backup_file_to_db "$file" "$backup_type/$relative_path"
    done
}

# 备份 Gateway 配置
backup_gateway_config() {
    echo "📦 备份 Gateway 配置..."
    
    # 备份配置目录
    backup_dir_to_db "$HOME/.openclaw/config" "gateway/config"
    
    # 备份用户配置
    backup_file_to_db "$HOME/.openclaw/openclaw.json" "gateway/openclaw.json"
    backup_file_to_db "$HOME/.openclaw/.openclawrc" "gateway/.openclawrc"
    
    # 备份环境变量
    local env_content=$(env | grep -i openclaw | base64 -w 0)
    sqlite3 "$BACKUP_DB" << EOF
INSERT INTO backups (backup_time, backup_timestamp, backup_type, content)
VALUES ('$(date "+%Y-%m-%d %H:%M:%S")', $(date +%s), 'gateway/environment', '$env_content');
EOF
    echo "  ✓ 已备份: 环境变量"
}

# 备份所有 Skills
backup_all_skills() {
    echo "📚 备份所有 Skills..."
    
    local skills_dirs=(
        "$HOME/.openclaw/workspace/skills"
        "$HOME/.nvm/versions/node/v22.22.0/lib/node_modules/openclaw/skills"
        "/root/.openclaw/workspace/skills"
    )
    
    for skills_dir in "${skills_dirs[@]}"; do
        if [ -d "$skills_dir" ]; then
            echo "  备份目录: $skills_dir"
            # 备份每个技能目录
            find "$skills_dir" -mindepth 1 -maxdepth 1 -type d | while read -r skill_dir; do
                local skill_name=$(basename "$skill_dir")
                backup_dir_to_db "$skill_dir" "skills/$skill_name"
            done
        fi
    done
}

# 备份系统信息
backup_system_info() {
    echo "💻 备份系统信息..."
    
    local sys_info=$(cat << EOF
=== 系统信息 ===
时间: $(date "+%Y-%m-%d %H:%M:%S")
主机名: $(hostname)
IP地址: $(hostname -I | awk '{print $1}')
系统: $(uname -a)

=== Node 版本 ===
$(node --version 2>/dev/null || echo "未安装")

=== OpenClaw 版本 ===
$(openclaw --version 2>/dev/null || echo "未知")

=== Gateway 状态 ===
$(systemctl --user status openclaw-gateway 2>&1 | head -10 || echo "无法获取")

=== 进程列表 ===
$(ps aux | grep -E "(gateway|openclaw)" | grep -v grep || echo "无相关进程")
EOF
)
    
    local encoded_info=$(echo "$sys_info" | base64 -w 0)
    sqlite3 "$BACKUP_DB" << EOF
INSERT INTO backups (backup_time, backup_timestamp, backup_type, content)
VALUES ('$(date "+%Y-%m-%d %H:%M:%S")', $(date +%s), 'system_info', '$encoded_info');
EOF
    
    echo "  ✓ 已备份: 系统信息"
}

# 清理旧备份
cleanup_old_backups() {
    echo "🧹 清理旧备份（保留最近 $MAX_BACKUPS 份）..."
    
    # 获取需要删除的备份ID（保留最新的 MAX_BACKUPS 份）
    local ids_to_delete=$(sqlite3 "$BACKUP_DB" "SELECT id FROM backups ORDER BY backup_timestamp DESC LIMIT -1 OFFSET $MAX_BACKUPS;")
    
    if [ -n "$ids_to_delete" ]; then
        echo "$ids_to_delete" | while read -r id; do
            sqlite3 "$BACKUP_DB" "DELETE FROM backups WHERE id=$id;"
        done
        echo "  ✓ 已清理旧备份"
    else
        echo "  ✓ 无需清理"
    fi
}

# 主备份流程
main() {
    echo "🐕 Gateway 数据库备份系统"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # 初始化数据库
    init_db
    
    # 检查是否需要备份
    if ! should_backup; then
        local current_hour=$(date +'%H')
        local next_hour=$(( (10#$current_hour + 3) % 24 ))
        echo "⏰ 还未到备份时间"
        echo "   当前时间: $(date "+%H:%M:%S")"
        echo "   下次备份: ${next_hour}:00"
        return 0
    fi
    
    echo "✅ 开始备份..."
    echo "   备份时间: $(date "+%Y-%m-%d %H:%M:%S")"
    echo ""
    
    # 执行备份
    backup_gateway_config
    echo ""
    backup_all_skills
    echo ""
    backup_system_info
    echo ""
    
    # 清理旧备份
    cleanup_old_backups
    echo ""
    
    # 更新备份时间
    local current_hour=$(date +%H)
    update_last_backup_hour "$current_hour"
    
    # 显示统计
    local backup_count=$(sqlite3 "$BACKUP_DB" "SELECT COUNT(*) FROM backups;")
    local db_size=$(du -h "$BACKUP_DB" | cut -f1)
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ 备份完成！"
    echo "   备份数量: $backup_count 份"
    echo "   数据库大小: $db_size"
    echo "   数据库位置: $BACKUP_DB"
    echo "   下次备份: $(( (current_hour + 3) % 24 )):00"
    echo ""
    
    # 返回数据库路径（供其他脚本调用）
    echo "$BACKUP_DB"
}

# 如果直接运行脚本
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
