#!/usr/bin/env python3
"""Download HistData.com M1 bars for the VPS EA simulator.

HistData serves free M1 bid bars as one zip per past year and one per month
for the current year. Each chunk is cached in data/raw/ (re-runs skip what is
already there, so a failed run can simply be repeated), then all chunks are
joined into data/<PAIR>.pkl.

Timestamps: HistData labels its files "EST", but the stamps follow US
daylight saving - they are New York local time. They are stored as they come
(naive New York time); vpssim.py converts them to the broker's server time.
Reading them as a fixed UTC-5 puts every summer month an hour late, which
moves every H4 and D1 bar boundary (notes §68/§69).

Usage:
    python3 utilities/vps-sim/download.py                    # XAUUSD, 2023 to now
    python3 utilities/vps-sim/download.py --from-year 2022
    python3 utilities/vps-sim/download.py --pair EURUSD
"""
import argparse
import datetime as dt
import io
import os
import re
import time
import zipfile

import pandas as pd
import requests

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
RAW = os.path.join(DATA, "raw")
PAGE = "https://www.histdata.com/download-free-forex-historical-data/?/ascii/1-minute-bar-quotes/{pair}/{path}"
FIELDS = ("tk", "date", "datemonth", "platform", "timeframe", "fxpair")


def fetch(session, pair, year, month=None):
    """One HistData chunk as a DataFrame (t as 'YYYYMMDD HHMMSS', o, h, l, c, v)."""
    path = f"{year}" + (f"/{month}" if month else "")
    url = PAGE.format(pair=pair.lower(), path=path)
    page = session.get(url, timeout=60).text
    form = {k: re.search(f'name="{k}" id="{k}" value="([^"]*)"', page).group(1) for k in FIELDS}
    r = session.post("https://www.histdata.com/get.php", data=form, headers={"Referer": url}, timeout=300)
    z = zipfile.ZipFile(io.BytesIO(r.content))
    name = [n for n in z.namelist() if n.endswith(".csv")][0]
    return pd.read_csv(z.open(name), sep=";", header=None, names=["t", "o", "h", "l", "c", "v"], dtype={"t": str})


def chunks(from_year):
    today = dt.date.today()
    out = [(y, None) for y in range(from_year, today.year)]
    out += [(today.year, m) for m in range(1, today.month + 1)]   # this month may not exist yet
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pair", default="XAUUSD")
    ap.add_argument("--from-year", type=int, default=2023)
    ap.add_argument("--passes", type=int, default=4, help="retry passes over missing chunks")
    a = ap.parse_args()
    os.makedirs(RAW, exist_ok=True)

    s = requests.Session()
    s.headers["User-Agent"] = "Mozilla/5.0"
    want = chunks(a.from_year)
    for p in range(a.passes):
        missing = [(y, m) for y, m in want if not os.path.exists(os.path.join(RAW, f"{a.pair}_{y}_{m or 0}.pkl"))]
        if not missing:
            break
        for y, m in missing:
            try:
                df = fetch(s, a.pair, y, m)
                df.to_pickle(os.path.join(RAW, f"{a.pair}_{y}_{m or 0}.pkl"))
                print(f"{a.pair} {y}{'-%02d' % m if m else ''}: {len(df):,} bars", flush=True)
            except Exception as e:
                print(f"{a.pair} {y}{'-%02d' % m if m else ''}: not available ({type(e).__name__})", flush=True)
                time.sleep(10)
            time.sleep(1)

    have = [os.path.join(RAW, f"{a.pair}_{y}_{m or 0}.pkl") for y, m in want]
    have = [f for f in have if os.path.exists(f)]
    if not have:
        raise SystemExit("nothing downloaded")
    df = pd.concat([pd.read_pickle(f) for f in have])
    df["t"] = pd.to_datetime(df.t.astype(str), format="%Y%m%d %H%M%S")    # naive New York local time
    df = df.drop(columns="v").drop_duplicates("t").sort_values("t").reset_index(drop=True)
    out = os.path.join(DATA, f"{a.pair}.pkl")
    df.to_pickle(out)
    print(f"wrote {out}: {len(df):,} bars, {df.t.iloc[0]} .. {df.t.iloc[-1]} (New York time)")


if __name__ == "__main__":
    main()
