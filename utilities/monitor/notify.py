"""Telegram notifications for the D1/W1/MN monitor.

Configure via environment variables:
    TELEGRAM_BOT_TOKEN   bot token from @BotFather
    TELEGRAM_CHAT_ID     your chat id (or group id) to send messages to
"""

import os
import urllib.request
import urllib.parse
import json


def send_telegram(message):
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    chat_id = os.environ.get("TELEGRAM_CHAT_ID")
    if not token or not chat_id:
        print("[notify] TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID not set - skipping Telegram send")
        return False

    url = "https://api.telegram.org/bot%s/sendMessage" % token
    payload = json.dumps({"chat_id": chat_id, "text": message}).encode()
    req = urllib.request.Request(
        url, data=payload, headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            body = resp.read().decode()
        ok = json.loads(body).get("ok", False)
        if ok:
            print("[notify] telegram message sent")
        else:
            print("[notify] telegram send failed: %s" % body)
        return ok
    except Exception as exc:  # noqa: BLE001
        print("[notify] telegram error: %s" % exc)
        return False


def send(message):
    print("----")
    print(message)
    print("----")
    send_telegram(message)
