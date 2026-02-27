#!/bin/bash
# Gateway 备份数据库查询脚本

BACKUP_DB="$HOME/.openclaw/watchdog/gateway-backups.db"

case "${1:-list}" in
    list)
        echo "📋 Gateway 备份列表"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        sqlite3 -column -header "$BACKUP_DB" << 'EOF'
SELECT 
    backup_time as "备份时间",
    backup_type as "类型",
    substr(file_path, -30) as "文件路径"
FROM backups 
ORDER BY backup_timestamp DESC 
LIMIT 20;
EOF
        ;;

    count)
        echo "📊 备份统计"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        sqlite3 "$BACKUP_DB" << 'EOF'
SELECT 
    backup_type as "类型",
    COUNT(*) as "数量"
FROM backups 
GROUP BY backup_type 
ORDER BY COUNT(*) DESC;
EOF
        ;;

    latest)
        echo "🕐 最新备份"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        sqlite3 -column -header "$BACKUP_DB" << 'EOF'
SELECT 
    backup_time as "备份时间",
    backup_type as "类型",
    file_path as "文件路径"
FROM backups 
ORDER BY backup_timestamp DESC 
LIMIT 10;
EOF
        ;;

    restore)
        if [ -z "$2" ]; then
            echo "用法: $0 restore <backup_id>"
            echo "使用 '$0 list' 查看备份ID"
            exit 1
        fi
        
        local backup_id=$2
        echo "📥 恢复备份 ID: $backup_id"
        
        sqlite3 -column -header "$BACKUP_DB" << EOF
SELECT backup_type, file_path 
FROM backups 
WHERE id=$backup_id;
EOF
        
        echo ""
        read -p "确认恢复此备份? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sqlite3 "$BACKUP_DB" "SELECT content FROM backups WHERE id=$backup_id;" | \
            base64 -d | \
            tar -xzvf - -C /
            
            echo "✅ 恢复完成"
        else
            echo "已取消"
        fi
        ;;

    export)
        local output_dir="${2:-./backup-export}"
        echo "📤 导出备份到: $output_dir"
        mkdir -p "$output_dir"
        
        sqlite3 "$BACKUP_DB" << 'EOF' | while IFS='|' read -r id type content; do
            type=$(echo "$type" | sed 's/\//_/g')
            echo "$content" | base64 -d > "$output_dir/backup_${id}_${type}"
        done
SELECT id, backup_type, content FROM backups ORDER BY backup_timestamp DESC LIMIT ${3:-10};
EOF
        
        echo "✅ 导出完成"
        ls -lh "$output_dir"
        ;;

    size)
        echo "💾 数据库大小"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        du -h "$BACKUP_DB"
        echo ""
        sqlite3 "$BACKUP_DB" << 'EOF'
SELECT 
    '总备份数: ' || COUNT(*) as info
FROM backups
UNION ALL
SELECT 
    '数据库大小: ' || SIZE || ' bytes'
FROM (
    SELECT SUM(LENGTH(content)) as SIZE FROM backups
);
EOF
        ;;

    *)
        echo "Gateway 备份数据库查询工具"
        echo ""
        echo "用法: $0 <命令> [参数]"
        echo ""
        echo "命令:"
        echo "  list          - 查看备份列表（最近20个）"
        echo "  count         - 查看备份统计"
        echo "  latest        - 查看最新10个备份"
        echo "  restore <id>  - 恢复指定备份"
        echo "  export [dir]  - 导出备份到目录"
        echo "  size          - 查看数据库大小"
        echo ""
        echo "示例:"
        echo "  $0 list"
        echo "  $0 restore 123"
        echo "  $0 export ./my-backups"
        ;;
esac
