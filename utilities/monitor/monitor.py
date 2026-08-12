#!/usr/bin/env python3
"""MS/W1/D1 Ichimoku alignment monitor.

Fetches daily OHLC for the symbol list in config.py, resamples to completed
weekly/monthly bars, and evaluates the same MS->W1->D1 (highest to lowest)
alignment the EA uses. When a symbol shows all three timeframes aligned the
same way it sends a Telegram message (needs TELEGRAM_BOT_TOKEN /
TELEGRAM_CHAT_ID env vars). Only notifies on a *change* (state is kept in
state/state.json), so a rare signal that persists for weeks won't spam you
daily.

Run locally:   python monitor/monitor.py [--heartbeat] [--state-dir state]
Run on CI:     see .github/workflows/ms-w1-d1-monitor.yml (artifact-backed
               state so dedupe works across ephemeral runners).
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import config
from data import fetch_daily, resample_completed
from ichimoku import align_last_bar
from notify import send

DIR_LABEL = {1: "LONG", -1: "SHORT"}


def evaluate(ticker):
    """Return (d1, w1, mn, close) or None on data failure."""
    daily = fetch_daily(ticker)
    if daily is None or len(daily) < 60:
        return None

    today = datetime.now(timezone.utc).date()
    # A bar whose date is still today may not be closed yet. Drop it so we
    # always evaluate against completed bars. Weekend runs keep Friday's bar.
    if daily.index[-1].date() == today:
        daily = daily.iloc[:-1]
    if len(daily) < 40:
        return None

    weekly = resample_completed(daily, "W-FRI")
    monthly = resample_completed(daily, "ME")

    return (
        align_last_bar(daily),
        align_last_bar(weekly),
        align_last_bar(monthly),
        float(daily["close"].iloc[-1]),
    )


def aligned(d1, w1, mn):
    return d1 != 0 and d1 == w1 == mn


def format_signal(sym, d1, w1, mn, close):
    d = DIR_LABEL[d1]
    lines = [
        "[MS-W1-D1 ALIGNED] %s %s" % (d, sym["name"]),
        "  MS=%d W1=%d D1=%d   close=%.4f" % (mn, w1, d1, close),
        "  ticker: %s" % sym["ticker"],
    ]
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description="D1/W1/MN Ichimoku alignment monitor")
    ap.add_argument("--state-dir", default="state", help="dir holding state.json")
    ap.add_argument("--heartbeat", action="store_true",
                    help="send a Telegram message even when nothing is aligned")
    args = ap.parse_args()

    os.makedirs(args.state_dir, exist_ok=True)
    state_path = os.path.join(args.state_dir, "state.json")
    state = {}
    if os.path.exists(state_path):
        try:
            with open(state_path) as f:
                state = json.load(f)
        except (ValueError, OSError):
            state = {}

    new_state = {}
    messages = []

    for sym in config.SYMBOLS:
        name = sym["name"]
        try:
            res = evaluate(sym["ticker"])
        except Exception as exc:  # noqa: BLE001 - keep scanning other symbols
            print("[%s] ERROR: %s" % (name, exc))
            continue
        if res is None:
            print("[%s] no data" % name)
            continue

        d1, w1, mn, close = res
        print("[%s] MS=%d W1=%d D1=%d close=%.4f" % (name, mn, w1, d1, close))

        if aligned(d1, w1, mn):
            prev = state.get(name)
            if prev != d1:  # new signal or direction flip
                messages.append(format_signal(sym, d1, w1, mn, close))
            new_state[name] = d1
        else:
            if name in state:
                messages.append("[MS-W1-D1] %s: alignment CLEARED (was %s)"
                                % (name, DIR_LABEL.get(state[name], state[name])))
            # cleared symbols are dropped from state

    if messages:
        send("\n\n".join(messages))
    elif args.heartbeat:
        send("[MS-W1-D1 monitor] heartbeat: %d symbols checked, none aligned"
             % len(config.SYMBOLS))

    with open(state_path, "w") as f:
        json.dump(new_state, f, indent=2)
    print("state written to %s" % state_path)


if __name__ == "__main__":
    main()
