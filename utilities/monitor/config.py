# Symbol watch list for the MS-W1-D1 alignment monitor.
#
# `name`   is the display label used in alerts and the state file.
# `ticker` is the Yahoo Finance symbol used to fetch daily OHLC data.
#          These are independent-data proxies for the XM MT5 symbols; fine
#          for a rare (weekly/monthly) signal monitor, not for exact fills.
#
# Yahoo symbols: crypto "BTC-USD"/"ETH-USD"; metals use the COMEX futures
# contracts "GC=F"/"SI=F" as proxies for XAUUSD/XAGUSD spot (Yahoo's spot
# symbols are delisted); indices "^NDX"/"^DJI"/"^GSPC"; FX "EURUSD=X",
# "GBPUSD=X", "JPY=X" (USDJPY), "AUDUSD=X", "USDCAD=X". FX list is limited
# to the most common trending majors — high-volatility crosses like GBPJPY
# are deliberately excluded.
SYMBOLS = [
    {"name": "BTC/USD",  "ticker": "BTC-USD"},
    {"name": "ETH/USD",  "ticker": "ETH-USD"},
    {"name": "XAUUSD",   "ticker": "GC=F"},
    {"name": "XAGUSD",   "ticker": "SI=F"},
    {"name": "US100",    "ticker": "^NDX"},
    {"name": "US30",     "ticker": "^DJI"},
    {"name": "EURUSD",   "ticker": "EURUSD=X"},
    {"name": "GBPUSD",   "ticker": "GBPUSD=X"},
    {"name": "USDJPY",   "ticker": "JPY=X"},
    {"name": "AUDUSD",   "ticker": "AUDUSD=X"},
    {"name": "USDCAD",   "ticker": "USDCAD=X"},
]

# Ichimoku periods — must match the EA inputs (Tenkan, Kijun, SenkouB).
TENKAN  = 9
KIJUN   = 26
SENKOU_B = 52

# How much daily history to fetch. Monthly alignment needs the cloud value at
# the chikou's plotted position, i.e. 2*KIJUN + SENKOU_B + 1 = 105 completed
# monthly bars (see ichimoku.align_last_bar), so ~9 years is the practical
# minimum; "max" is safe on all Yahoo symbols.
HISTORY = "max"
