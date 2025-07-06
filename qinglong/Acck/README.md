## 📜 Acck 多账户签到脚本（带电报BOT通知版）

### 🔧 功能简介

这是一个用于 **自动签到 Acck 平台账户** 的 Python 脚本，支持通过单个环境变量同时配置多个账户，并自动执行以下操作：

- ✅ 多账户登录（邮箱 + 密码，支持 TOTP 二步验证）
- ✅ 自动完成每日签到
- ✅ 获取账户余额（AK币 + 现金）
- ✅ 美观的终端输出，方便查看每个账户的状态

### 💡 使用方法

#### 1️⃣ 安装依赖

```
pip install curl_cffi pyotp python-dotenv
```

#### 2️⃣ 配置环境变量 ACCK_ACCOUNTS
格式如下：
```
邮箱1:密码1:TOTP密钥1|邮箱2:密码2|邮箱3:密码3:TOTP密钥3
```

示例：
```
export ACCK_ACCOUNTS="user1@example.com:pass1:JBSWY3DPEHPK3PXP|user2@example.com:pass2|user3@example.com:pass3:JBSWY3DPEHPK3PXQ"
```
第二个账户没有启用 TOTP，可以只写邮箱和密码。


#### 3️⃣ 运行脚本
```
python qiandao.py
```

## 📦 特性亮点

- 🔐 支持 TOTP 动态验证码自动生成与验证
- 👥 多账户自动登录并签到，兼容无 TOTP 用户
- ⚠️ 错误提示清晰，便于排查问题
- 💰 自动转换现金单位（分 → 元）
- ⏱️ 输出运行耗时，执行效率一目了然
