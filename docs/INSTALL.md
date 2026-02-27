# 安装指南

## 🚀 快速开始

### 前置要求

- Linux 系统（支持 systemd）
- Bash 4.0+
- SQLite3
- mailx（发送邮件）
- OpenClaw >= 2026.2.23
- Opencode >= 1.0.0（可选，用于 AI 修复）

### 安装步骤

#### 1. 安装依赖

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y sqlite3 mailutils

# CentOS/RHEL
sudo yum install -y sqlite3 mailx
```

#### 2. 复制脚本

```bash
# 复制脚本到 OpenClaw 目录
cp scripts/*.sh ~/.openclaw/scripts/

# 赋予执行权限
chmod +x ~/.openclaw/scripts/*.sh
```

#### 3. 配置邮件

编辑 `~/.openclaw/scripts/send-email.sh`，修改 SMTP 配置：

```bash
SMTP_SERVER="smtp.163.com"
SMTP_PORT="465"
SMTP_USER="your@email.com"
SMTP_PASS="your_password"
FROM_EMAIL="your@email.com"
TO_EMAIL="your@email.com"
```

#### 4. 测试邮件

```bash
bash ~/.openclaw/scripts/test-email-new-format.sh
```

#### 5. 初始化数据库

```bash
# 备份脚本会自动初始化数据库
bash ~/.openclaw/scripts/backup-gateway-db.sh
```

#### 6. 配置 Systemd

```bash
# 复制定时器文件
sudo cp systemd/*.service /etc/systemd/system/
sudo cp systemd/*.timer /etc/systemd/system/

# 重载 systemd
sudo systemctl daemon-reload

# 启用定时器
sudo systemctl enable openclaw-gateway-watchdog.timer
sudo systemctl enable openclaw-gateway-heartbeat.timer

# 启动定时器
sudo systemctl start openclaw-gateway-watchdog.timer
sudo systemctl start openclaw-gateway-heartbeat.timer
```

#### 7. 验证安装

```bash
# 查看定时器状态
sudo systemctl status openclaw-gateway-watchdog.timer
sudo systemctl status openclaw-gateway-heartbeat.timer

# 查看看门狗状态
bash ~/.openclaw/scripts/watchdog-manager.sh status

# 查看备份
bash ~/.openclaw/scripts/backup-db-query.sh
```

## 📋 验证清单

- [ ] 依赖已安装
- [ ] 脚本已复制到 `~/.openclaw/scripts/`
- [ ] 邮件配置正确
- [ ] 测试邮件发送成功
- [ ] 数据库已初始化
- [ ] Systemd 定时器已启用
- [ ] 看门狗状态正常

## 🧪 测试

### 简化测试（5 分钟）

```bash
yes | bash ~/.openclaw/scripts/test-watchdog-simple.sh
```

### 完整测试（带邮件报告）

```bash
bash ~/.openclaw/scripts/test-watchdog-full.sh
```

## 🔧 故障排查

### 邮件发送失败

检查 SMTP 配置：

```bash
cat ~/.openclaw/scripts/send-email.sh
```

测试邮件：

```bash
bash ~/.openclaw/scripts/test-email-new-format.sh
```

### 看门狗不运行

检查定时器状态：

```bash
sudo systemctl status openclaw-gateway-watchdog.timer
sudo systemctl status openclaw-gateway-heartbeat.timer
```

查看日志：

```bash
bash ~/.openclaw/scripts/watchdog-manager.sh logs
```

### 数据库备份失败

检查数据库：

```bash
ls -lh ~/.openclaw/watchdog/gateway-backups.db
```

手动备份：

```bash
bash ~/.openclaw/scripts/backup-gateway-db.sh
```

## ⚙️ 配置选项

### 看门狗配置

编辑 `~/.openclaw/scripts/gateway-watchdog.sh`：

```bash
HEARTBEAT_TIMEOUT=300         # 心跳超时（秒）
BACKUP_INTERVAL=10800         # 备份间隔（秒，3 小时）
MAX_BACKUPS=30                # 最大备份数量
RECOVERY_WAIT=30              # 恢复等待时间（秒）
```

### 邮件通知

看门狗会在以下时刻发送邮件：
- Gateway 异常终止
- Gateway 恢复成功
- 配置备份完成
- 紧急告警（无法恢复）

## 📊 监控

### 查看状态

```bash
# 看门狗状态
bash ~/.openclaw/scripts/watchdog-manager.sh status

# 备份列表
bash ~/.openclaw/scripts/backup-db-query.sh

# 最近日志
bash ~/.openclaw/scripts/watchdog-manager.sh logs
```

### 心跳检查

```bash
# 查看最后心跳时间
cat ~/.openclaw/watchdog/heartbeat.timestamp

# 检查心跳是否超时
date +%s
```

## 🔒 写保护

启用写保护（防止意外修改）：

```bash
sudo bash ~/.openclaw/scripts/set-watchdog-protection.sh
```

管理写保护：

```bash
# 检查状态
bash ~/.openclaw/scripts/watchdog-protection.sh check

# 移除保护
bash ~/.openclaw/scripts/watchdog-protection.sh remove

# 添加保护
bash ~/.openclaw/scripts/watchdog-protection.sh add
```

## 📚 更多信息

- [系统架构](ARCHITECTURE.md)
- [邮件格式](EMAIL_FORMAT.md)
- [测试指南](TEST_GUIDE.md)

---

🐕 **安装完成，让 Gateway 守护你的 OpenClaw！**
