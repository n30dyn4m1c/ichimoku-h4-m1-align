"""Data layer: fetch daily OHLC and resample to completed weekly/monthly bars.

Weekly bars are Friday-labelled, monthly bars are month-end labelled (both
label by period *end*, matching MT5's bar time). A bucket whose label lands
after the last available daily bar is still forming and is dropped, so every
bar fed to the alignment check is a completed one.
"""

import pandas as pd
import yfinance as yf

import config


def fetch_daily(ticker):
    """Daily OHLC for `ticker`, oldest -> newest, with lower-case columns."""
    df = yf.download(
        ticker,
        period=config.HISTORY,
        interval="1d",
        auto_adjust=False,
        progress=False,
        threads=False,
    )
    if df is None or df.empty:
        return None
    df = df[["Open", "High", "Low", "Close"]].dropna()
    df.columns = ["open", "high", "low", "close"]
    df.index = pd.to_datetime(df.index)
    df = df[~df.index.duplicated(keep="last")].sort_index()
    return df


def resample(df, rule):
    grouped = df.resample(rule)
    out = pd.DataFrame(
        {
            "open": grouped["open"].first(),
            "high": grouped["high"].max(),
            "low": grouped["low"].min(),
            "close": grouped["close"].last(),
        }
    ).dropna()
    return out


def resample_completed(df, rule):
    """Resample to `rule` and drop a trailing bucket that is still forming."""
    out = resample(df, rule)
    if len(out) > 1 and out.index[-1] > df.index[-1]:
        out = out.iloc[:-1]
    return out
