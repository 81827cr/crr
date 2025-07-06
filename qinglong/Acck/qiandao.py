#!/usr/bin/env python3
"""
ACCK 多账户签到脚本（带 TG BOT 通知，Token 和 ChatID 写死脚本内）
"""

import requests
import pyotp
import time
import sys
import os

# === Telegram 配置（写死在这里）===
TG_BOT_TOKEN = "电报BOT秘钥"
TG_CHAT_ID = "通知对话ID"

class Color:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    END = '\033[0m'

def send_telegram_message(token: str, chat_id: str, text: str):
    if not token or not chat_id:
        print(f"{Color.YELLOW}⚠️ Telegram配置未填写，跳过通知{Color.END}")
        return
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    try:
        resp = requests.post(url, json={"chat_id": chat_id, "text": text})
        if resp.status_code == 200:
            print(f"{Color.GREEN}✅ Telegram通知发送成功{Color.END}")
        else:
            print(f"{Color.RED}❌ Telegram通知发送失败: {resp.text}{Color.END}")
    except Exception as e:
        print(f"{Color.RED}❌ 发送Telegram通知异常: {e}{Color.END}")

class ACCKAccount:
    def __init__(self, email, password, totp_secret=None):
        self.email = email
        self.password = password
        self.totp_secret = totp_secret
        self.session = requests.Session()
        self.token = None
        self._init_headers()

    def _init_headers(self):
        self.session.headers.update({
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                          "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36",
            "Referer": "https://acck.io",
            "Origin": "https://acck.io",
            "Content-Type": "application/json;charset=UTF-8"
        })

    def login(self):
        payload = {
            "email": self.email,
            "password": self.password,
            "token": "",
            "verifyCode": ""
        }
        print(f"{Color.CYAN}ℹ️ 登录账户: {self.email}{Color.END}")
        resp = self.session.post("https://api.acck.io/api/v1/user/login", json=payload, timeout=20)
        data = resp.json()

        if data.get("status_code") == 0 and "二步验证" in data.get("status_msg", ""):
            if not self.totp_secret:
                raise Exception("需要TOTP但未配置密钥")
            totp = pyotp.TOTP(self.totp_secret)
            payload["token"] = totp.now()
            print(f"{Color.YELLOW}⚠️ 使用TOTP验证码登录中...{Color.END}")
            resp = self.session.post("https://api.acck.io/api/v1/user/login", json=payload, timeout=20)
            data = resp.json()
            if data.get("status_code") != 0:
                raise Exception("TOTP验证失败: " + data.get("status_msg", "未知错误"))

        if data.get("status_code") != 0:
            raise Exception("登录失败: " + data.get("status_msg", "未知错误"))

        self.token = data["data"]["token"]
        print(f"{Color.GREEN}✅ 登录成功，Token: {self.token[:10]}...{Color.END}")

    def checkin(self):
        if not self.token:
            raise Exception("未登录，无法签到")

        headers = {"Authorization": self.token}
        resp = self.session.get("https://sign-service.acck.io/api/acLogs/sign", headers=headers, timeout=20)
        try:
            data = resp.json()
        except Exception:
            msg = f"签到接口返回非JSON，原始内容：{resp.text}"
            print(f"{Color.RED}{msg}{Color.END}")
            send_telegram_message(TG_BOT_TOKEN, TG_CHAT_ID, f"[{self.email}] {msg}")
            raise

        if data.get("code") == 200:
            print(f"{Color.GREEN}✅ 签到成功: {data.get('msg', '')}{Color.END}")
        elif data.get("msg") == "今日已签到":
            print(f"{Color.GREEN}ℹ️ 签到状态：今日已签到{Color.END}")
        else:
            err_msg = f"[{self.email}] 签到失败: {data}"
            print(f"{Color.RED}❌ {err_msg}{Color.END}")
            send_telegram_message(TG_BOT_TOKEN, TG_CHAT_ID, err_msg)


    def get_balance(self):
        if not self.token:
            return None

        headers = {"Authorization": self.token}
        resp = self.session.get("https://api.acck.io/api/v1/user/index", headers=headers, timeout=20)
        data = resp.json()
        if data.get("status_code") != 0:
            msg = f"[{self.email}] 获取余额失败: {data.get('status_msg', '未知错误')}"
            print(f"{Color.RED}❌ {msg}{Color.END}")
            send_telegram_message(TG_BOT_TOKEN, TG_CHAT_ID, msg)
            return None

        info = data.get("data", {})
        money = info.get("money", 0)
        try:
            money = float(money) / 100
        except Exception:
            money = 0.0

        ak_coin = info.get("ak_coin", "N/A")
        print(f"{Color.BLUE}💰 余额信息 - AK币: {ak_coin}，现金: ¥{money:.2f}{Color.END}")

def parse_accounts(env_var: str):
    accounts = []
    if not env_var:
        print(f"{Color.RED}❌ 环境变量 ACCK_ACCOUNTS 未设置或为空{Color.END}")
        return accounts

    for idx, acc_str in enumerate(env_var.split("|"), 1):
        parts = acc_str.strip().split(":")
        if len(parts) < 2:
            print(f"{Color.YELLOW}⚠️ 跳过无效账户配置: {acc_str}{Color.END}")
            continue
        email = parts[0]
        password = parts[1]
        totp_secret = parts[2] if len(parts) > 2 else None
        accounts.append({"email": email, "password": password, "totp_secret": totp_secret})
    return accounts

def main():
    print(f"{Color.BLUE}★ ACCK 多账户签到脚本（Telegram通知写死版） ★{Color.END}")
    print(f"{Color.YELLOW}⚠️ 请设置环境变量 ACCK_ACCOUNTS{Color.END}")
    print(f"{Color.YELLOW}格式示例: email1:password1:totp1|email2:password2|email3:password3:totp3{Color.END}")

    env_accounts = os.getenv("ACCK_ACCOUNTS", "")
    accounts = parse_accounts(env_accounts)
    if not accounts:
        print(f"{Color.RED}❌ 未找到有效账户，退出{Color.END}")
        return

    for i, acc in enumerate(accounts, 1):
        print(f"\n{Color.CYAN}--- 处理账户{i}: {acc['email']} ---{Color.END}")
        account = ACCKAccount(acc["email"], acc["password"], acc["totp_secret"])
        try:
            account.login()
            account.checkin()
            account.get_balance()
        except Exception as e:
            err_msg = f"[{acc['email']}] 脚本异常: {str(e)}"
            print(f"{Color.RED}❌ {err_msg}{Color.END}")
            send_telegram_message(TG_BOT_TOKEN, TG_CHAT_ID, err_msg)
        time.sleep(1)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n{Color.RED}❌ 用户中断脚本{Color.END}")
        sys.exit(0)
    except Exception as e:
        print(f"{Color.RED}❌ 脚本异常退出: {str(e)}{Color.END}")
        sys.exit(1)
