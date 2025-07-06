import imaplib
import datetime
import requests
import json
import os

# === 配置开始 ===
#一行一个
ACCOUNTS = [
    {"email": "example1@gmail.com", "app_password": "afmsgmalrdvqspwl"},
    {"email": "example2@gmail.com", "app_password": "afmsgmalrdvqspwl"}
]

DAILY_LIMIT = 400

TELEGRAM_BOT_TOKEN = "8888888888:BBEsht4WDKQ5RrCJWPXXfi1cNpk5gwwcaJA"#Telegram BOT Kye
TELEGRAM_CHAT_ID = "9999999999"#Telegram Chat ID

RECORD_FILE = "sent_record.json"

# === 配置结束 ===

def get_today_str():
    """返回今天的日期格式为 08-Jun-2025（IMAP 需要的格式）"""
    return datetime.datetime.now().strftime("%d-%b-%Y")


def load_record():
    if not os.path.exists(RECORD_FILE):
        return {}
    with open(RECORD_FILE, "r", encoding="utf-8") as f:
        return json.load(f)


def save_record(record):
    with open(RECORD_FILE, "w", encoding="utf-8") as f:
        json.dump(record, f)


def get_sent_count(email, app_password):
    try:
        imap = imaplib.IMAP4_SSL("imap.gmail.com")
        imap.login(email, app_password)

        status, mailboxes = imap.list()
        if status != "OK":
            print(f"[!] {email} 获取邮箱列表失败")
            return -1

        sent_folder = None
        for box in mailboxes:
            line = box.decode()
            if "\\Sent" in line:
                sent_folder = line.split(' "/" ')[1].strip('"')
                break
        if not sent_folder:
            print(f"[!] {email} 无法识别“已发送”文件夹")
            return -1

        status, _ = imap.select(f'"{sent_folder}"')
        if status != "OK":
            print(f"[!] 无法选择Sent文件夹: {email}")
            return -1

        today = get_today_str()
        result, data = imap.search(None, f'SINCE {today}')
        imap.logout()

        if result == "OK":
            msg_ids = data[0].split()
            return len(msg_ids)
        else:
            return -1
    except Exception as e:
        print(f"[!] 账号 {email} 登录失败或查询错误: {e}")
        return -1


def send_telegram(message):
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    payload = {
        "chat_id": TELEGRAM_CHAT_ID,
        "text": message,
        "parse_mode": "HTML"
    }
    try:
        r = requests.post(url, json=payload)
        r.raise_for_status()
        print(f"[✓] 已推送: {message.splitlines()[0]}")
    except Exception as e:
        print(f"[!] Telegram 推送失败: {e}")


def main():
    today = datetime.date.today().isoformat()
    record = load_record()

    if today not in record:
        record = {today: []}

    for account in ACCOUNTS:
        email = account["email"]
        app_password = account["app_password"]
        count = get_sent_count(email, app_password)

        if count == -1:
            continue

        print(f"[INFO] {email} 今日发送数量: {count}")

        if count > DAILY_LIMIT and email not in record[today]:
            message = (
                f"⚠️ Gmail 发信超额提醒\n"
                f"账户: <b>{email}</b>\n"
                f"今日已发: <b>{count}</b> 封\n"
                f"限制: {DAILY_LIMIT} 封"
            )
            send_telegram(message)
            record[today].append(email)
            save_record(record)


if __name__ == "__main__":
    main()
