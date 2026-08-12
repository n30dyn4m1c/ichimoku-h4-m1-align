"""Ichimoku MS/W1/D1 alignment — a faithful port of CheckAlign() in
ichimoku-ms-w1-d1-ea.mq5.

A timeframe's last *completed* bar counts as aligned only when price AND the
chikou span both sit clearly above (bullish) or clearly below (bearish) the
tenkan-sen, kijun-sen, and kumo on that timeframe.

Bar/offset conventions (mirroring the EA):
  * `df` is oldest -> newest; the LAST row is the last closed bar.
  * The price-side tenkan/kijun are read at the last closed bar; the cloud
    there is the Senkou value computed Kijun rows earlier (the spans are
    plotted Kijun bars into the future).
  * The chikou value equals the close of the last closed bar, plotted Kijun
    bars back; the reference candle and tenkan/kijun are read there, and the
    cloud at that position another Kijun rows further back.
"""

import pandas as pd

import config


def compute_levels(df):
    high = df["high"]
    low = df["low"]
    tenkan = (high.rolling(config.TENKAN).max() + low.rolling(config.TENKAN).min()) / 2.0
    kijun = (high.rolling(config.KIJUN).max() + low.rolling(config.KIJUN).min()) / 2.0
    senkou_a = (tenkan + kijun) / 2.0
    senkou_b = (high.rolling(config.SENKOU_B).max() + low.rolling(config.SENKOU_B).min()) / 2.0
    return tenkan, kijun, senkou_a, senkou_b


def align_last_bar(df):
    """Return 1 (bullish), -1 (bearish), or 0 (not aligned) for the last bar."""
    n = len(df)
    # Enough bars for every level read below: the chikou-side cloud is read
    # 2*KIJUN rows before the last closed bar, and Senkou B there needs its
    # own SENKOU_B-bar window before that.
    if n < config.SENKOU_B + 2 * config.KIJUN + 1:
        return 0

    tenkan, kijun, senkou_a, senkou_b = compute_levels(df)

    # last closed bar (oldest->newest: the final row)
    i0 = n - 1
    close_p = float(df["close"].iloc[i0])

    # The Senkou spans are plotted Kijun bars into the future, so the cloud
    # shown under the last closed bar is the Senkou value computed Kijun bars
    # earlier (mirrors the EA's CopyBuffer(..., sh + Kijun) read).
    iPriceCloud = n - 1 - config.KIJUN

    above = (
        close_p > tenkan.iloc[i0]
        and close_p > kijun.iloc[i0]
        and close_p > max(senkou_a.iloc[iPriceCloud], senkou_b.iloc[iPriceCloud])
    )
    below = (
        close_p < tenkan.iloc[i0]
        and close_p < kijun.iloc[i0]
        and close_p < min(senkou_a.iloc[iPriceCloud], senkou_b.iloc[iPriceCloud])
    )
    if not above and not below:
        return 0

    # chikou position: last closed bar, Kijun bars back
    i1 = n - 1 - config.KIJUN
    # Cloud at the chikou's plotted position: another Kijun bars further back.
    i2 = n - 1 - 2 * config.KIJUN
    chik = close_p  # the chikou span for the last closed bar is its close

    if above:
        if (
            chik > df["high"].iloc[i1]
            and chik > tenkan.iloc[i1]
            and chik > kijun.iloc[i1]
            and chik > max(senkou_a.iloc[i2], senkou_b.iloc[i2])
        ):
            return 1
        return 0

    if below:
        if (
            chik < df["low"].iloc[i1]
            and chik < tenkan.iloc[i1]
            and chik < kijun.iloc[i1]
            and chik < min(senkou_a.iloc[i2], senkou_b.iloc[i2])
        ):
            return -1
        return 0

    return 0


def alignment_summary(df):
    """Per-timeframe direction plus the last close, for alert messages."""
    n = len(df)
    if n < config.KIJUN + 1:
        return {"dir": 0, "close": None, "levels": {}}
    dirn = align_last_bar(df)
    return {"dir": dirn, "close": float(df["close"].iloc[-1]), "levels": {}}
