# OpenClau Gateway Watchdog 🐕

OpenClau Gateway 智能看门狗系统 - 自动监控、恢复、备份和告警。

## ✨ 特性

- 🔍 **多层检测** - 进程存活 + 心跳超时 + 功能验证
- 🛡️ **四级恢复** - 基础重启 → 强制重启 → Opencode AI 修复 → 紧急告警
- 💾 **自动备份** - SQLite 数据库存储，每 3 小时备份，保留 30 份
- 📧 **邮件告警** - 所有关键时刻实时通知
- ⚙️ **Systemd 管理** - 开机自启，定时器管理
- 🔒 **写保护** - 防止意外修改，安全可靠

## 📋 系统要求

- Linux 系统（支持 systemd）
- Bash 4.0+
- SQLite3
- mailx（发送邮件）
- OpenClaw >= 2026.2.23
- Opencode >= 1.0.0（可选，用于 AI 修复）

## 🚀 快速开始

详见服务器上的文档或完整脚本。

---
🐕 让 Gateway 守护你的 OpenClau！
