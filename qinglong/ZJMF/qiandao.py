import requests
import time
from datetime import datetime

accounts = [
    {
        "uid": ,
        "cookie": ""
    },
    {
        "uid": ,
        "cookie": ""
    }
]

def sign_in(account):
    print(f"开始为 uid={account['uid']} 签到...")
    headers = {
        "Content-Type": "application/x-www-form-urlencoded",
        "Cookie": account["cookie"],
    }
    data = f"uid={account['uid']}"
    url = "https://www.域名.com/addons?_plugin=4&_controller=index&_action=index"
    try:
        resp = requests.post(url, headers=headers, data=data)
        resp.raise_for_status()
        result = resp.json()
        print(f"uid={account['uid']} 签到结果:", result)
    except Exception as e:
        print(f"uid={account['uid']} 签到出错:", e)

if __name__ == "__main__":
    print("## 开始执行... ", datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    for acc in accounts:
        sign_in(acc)
        time.sleep(1.5)
    print("## 执行结束... ", datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
