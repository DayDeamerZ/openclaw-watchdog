# Gateway Watchdog 脚本说明

本目录包含看门狗的所有脚本文件。

## 📋 核心脚本

### gateway-watchdog.sh
**主看门狗脚本** - 每 2 分钟运行一次

功能：
- 多层检测（进程 + 心跳 + CPU）
- 四级恢复（基础 → 强制 → AI 修复 → 告警）
- 自动备份（每 3 小时）
- 邮件通知

### backup-gateway-db.sh
**数据库备份脚本**

功能：
- 备份 Gateway 配置到 SQLite
- 备份所有 Skills（用户 + 系统安装）
- 自动清理旧备份（保留 30 份）
- 支持 3 小时间隔（0, 3, 6, 9...）

### watchdog-manager.sh
**管理脚本** - 便捷管理命令

```bash
# 查看状态
bash ~/.openclaw/scripts/watchdog-manager.sh status

# 手动检查
bash ~/.openclaw/scripts/watchdog-manager.sh check

# 查看日志
bash ~/.openclaw/scripts/watchdog-manager.sh logs

# 查看备份
bash ~/.openclaw/scripts/watchdog-manager.sh backups
```

### update-heartbeat.sh
**心跳更新脚本** - 每 1 分钟运行一次

功能：
- 更新心跳时间戳
- 检测心跳超时（5 分钟）
- 触发告警

### send-email.sh
**邮件发送脚本**

功能：
- SMTP 邮件发送
- 支持 163 邮箱
- 配置在脚本内部

## 🧪 测试脚本

### test-watchdog-simple.sh
**简化测试** - 快速验证（5 分钟）

```bash
yes | bash ~/.openclaw/scripts/test-watchdog-simple.sh
```

### test-watchdog-full.sh
**完整测试** - 带邮件报告

```bash
bash ~/.openclaw/scripts/test-watchdog-full.sh
```

### test-email-new-format.sh
**邮件格式测试** - 测试新的邮件主题

## 🛡️ 工具脚本

### set-watchdog-protection.sh
**设置写保护**

```bash
sudo bash ~/.openclaw/scripts/set-watchdog-protection.sh
```

### watchdog-protection.sh
**管理写保护**

```bash
# 检查保护状态
bash ~/.openclaw/scripts/watchdog-protection.sh check

# 移除保护
bash ~/.openclaw/scripts/watchdog-protection.sh remove

# 添加保护
bash ~/.openclaw/scripts/watchdog-protection.sh add
```

### backup-db-query.sh
**查询备份数据库**

```bash
bash ~/.openclaw/scripts/backup-db-query.sh
```

## 📦 安装

将所有脚本复制到 OpenClaw 目录：

```bash
cp *.sh ~/.openclaw/scripts/
chmod +x ~/.openclaw/scripts/*.sh
```

## ⚙️ 配置

### 邮件配置

编辑 `send-email.sh`，修改 SMTP 配置：

```bash
SMTP_SERVER="smtp.163.com"
SMTP_PORT="465"
SMTP_USER="your@email.com"
SMTP_PASS="your_password"
```

### Systemd 配置

创建定时器：

```bash
# 复制定时器文件
sudo cp *.service /etc/systemd/system/
sudo cp *.timer /etc/systemd/system/

# 启用定时器
sudo systemctl enable openclaw-gateway-watchdog.timer
sudo systemctl enable openclaw-gateway-heartbeat.timer

# 启动定时器
sudo systemctl start openclaw-gateway-watchdog.timer
sudo systemctl start openclaw-gateway-heartbeat.timer
```

## 📊 监控指标

- **进程检测** - Gateway 进程是否存在
- **心跳检测** - 5 分钟无心跳视为异常
- **功能检测** - CPU 使用率验证
- **备份间隔** - 每 3 小时自动备份
- **检查频率** - 每 2 分钟检查一次

## 🎯 使用示例

### 日常使用

```bash
# 查看看门狗状态
bash ~/.openclaw/scripts/watchdog-manager.sh status

# 查看最近的备份
bash ~/.openclaw/scripts/backup-db-query.sh | tail -20

# 手动触发备份
bash ~/.openclaw/scripts/backup-gateway-db.sh
```

### 故障排查

```bash
# 查看日志
bash ~/.openclaw/scripts/watchdog-manager.sh logs

# 检查保护状态
bash ~/.openclaw/scripts/watchdog-protection.sh check

# 查看心跳时间
cat ~/.openclaw/watchdog/heartbeat.timestamp
```

## ⚠️ 注意事项

- **邮件配置**: 使用前必须配置 SMTP 服务器
- **权限要求**: 需要 root 权限设置 Systemd 服务
- **写保护**: 保护模式下无法修改脚本，需要先移除保护
- **Opencode**: Level 3 恢复需要安装 Opencode

## 📖 相关文档

- [SYSTEMD_SETUP.md](../docs/SYSTEMD_SETUP.md) - Systemd 配置说明
- [EMAIL_FORMAT.md](../docs/EMAIL_FORMAT.md) - 邮件格式规范
- [TEST_GUIDE.md](../docs/TEST_GUIDE.md) - 测试指南

---

🐕 **让 Gateway 守护你的 OpenClaw！**
