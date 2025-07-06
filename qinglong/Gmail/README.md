## GmailExcessAlert (Gmail 发信监控脚本(带电报推送))
使用教程

本脚本用于 自动监控 Gmail 发信数量，当某个账号当天发送的邮件数量超过设定的阈值（默认：400 封）后，通过 Telegram Bot 向指定用户发送超额提醒消息。非常适合用于邮件发送服务、自动化邮件平台等场景，防止触发 Gmail 限制或封号。

✨ 功能特性
✅ 支持多个 Gmail 账户同时监控<br>
✅ 精确统计当天 Gmail 的发件数量<br>
✅ 超额自动通过 Telegram Bot 推送提醒<br>
✅ 支持记录防重复提醒<br>
✅ 可每日运行（推荐部署定时任务）

📦 环境依赖
Python 3.6+<br>
Gmail 应用专用密码（用于登录 IMAP）<br>
Telegram Bot 秘钥 和 推送用户ID<br>
requests 模块（安装方式见下方）

### 🚀 使用教程
**1.安装依赖**
pip install requests

**2.修改配置**
{"email": "这里为邮箱账户", "app_password": "这里为邮箱的应用秘钥"}<br>
DAILY_LIMIT = 这里是设置到达多少封邮件后推送电报BOT<br>
TELEGRAM_BOT_TOKEN = "你的Telegram Bot Token"<br>
TELEGRAM_CHAT_ID = "你的Telegram Chat ID"

**3.其它内容**
🛡️ App Password 获取方式：<br>
访问 https://myaccount.google.com/apppasswords 使用双重验证登录后生成。

💬 Chat ID 获取方式：
给你的 Telegram Bot 发送一条消息，然后访问<br>
https://api.telegram.org/bot<你的Token>/getUpdates<br>
在返回内容中查找 "chat":{"id":xxxxxxxx} 即可。

**示例通知效果**

⚠️ Gmail 发信超额提醒<br>
账户: 你的邮箱<br>
今日已发: 412 封<br>
限制: 400 封
