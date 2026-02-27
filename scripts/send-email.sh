#!/bin/bash
# 邮件发送脚本 - 用于Gateway看门狗告警

SMTP_SERVER="your-smtp-server"
SMTP_PORT="465"
SMTP_USER="your-smtp-user"
SMTP_PASS="your-smtp-pass"
FROM_EMAIL="your-smtp-post"
TO_EMAIL="to-email"

# 使用 mailx 发送邮件（支持SMTP认证）
send_email() {
    local subject="$1"
    local body="$2"
    local attachment="${3:-}"

    # 创建临时邮件内容
    local temp_file=$(mktemp)
    
    # 邮件正文
    echo "$body" > "$temp_file"
    
    # 附件信息
    if [ -n "$attachment" ] && [ -f "$attachment" ]; then
        echo "" >> "$temp_file"
        echo "---" >> "$temp_file"
        echo "附件: $(basename $attachment)" >> "$temp_file"
    fi
    
    # 发送邮件（使用 -s 参数指定主题）
    # 使用 -a 参数添加 From 头
    cat "$temp_file" | mailx -v \
        -S smtp="smtps://$SMTP_SERVER:$SMTP_PORT" \
        -S smtp-auth=login \
        -S smtp-auth-user="$SMTP_USER" \
        -S smtp-auth-password="$SMTP_PASS" \
        -S from="OpenClaw Gateway Watchdog <$FROM_EMAIL>" \
        -S ssl-verify=ignore \
        -s "$subject" \
        "$TO_EMAIL" 2>&1
    
    local result=$?
    rm -f "$temp_file"
    return $result
}

# 如果直接运行脚本
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    if [ $# -lt 2 ]; then
        echo "用法: $0 <主题> <内容> [附件路径]"
        exit 1
    fi
    
    send_email "$1" "$2" "$3"
    exit $?
fi
