# Ichimoku H4-M1 Alignment EA — Summary

## What It Does

MetaTrader 5 EA trading GOLDm# (configurable) using Ichimoku Cloud alignment across H4 → M1 (6 timeframes). Signal exit is driven by M15 kijun cross; every position also carries an ATR-based protective stop loss (no TP).

---

## Entry

Runs on every M1 bar close. Enters when all 6 TFs (H4, H1, M30, M15, M5, M1) price and chikou are aligned above/below their respective clouds, no position is open, and the current spread is within `InpMaxSpreadPoints`. Opens `count` market orders at lot size determined by account equity, each with a stop loss `InpATRMultiplier × ATR(M15, InpATRPeriod)` away from entry (widened to the broker's minimum stop distance if needed). Order placement stops at the first rejection (e.g. out of margin), and an entry is skipped entirely if the ATR value can't be read — the EA never opens unprotected positions while `InpUseStopLoss` is on.

---

## Exit

Closes all positions when the M15 bar-1 close crosses the M15 kijun (bar 1) against the open direction — i.e. for a long, the M15 close ends below the M15 kijun; for a short, the M15 close ends above the M15 kijun. Independently, each position's ATR stop loss caps the loss on fast adverse moves between M15 closes.

---

## Equity-Based Risk

`GetEquityRisk()` determines position count and lot size at entry. All counts are even, with the lowest tier opening 2:

| Equity | Count | Lots |
|--------|-------|------|
| ≤ $30  | 2  | 0.10 |
| ≤ $50  | 2  | 0.10 |
| ≤ $70  | 4  | 0.10 |
| ≤ $100 | 4  | 0.10 |
| ≤ $130 | 6  | 0.10 |
| ≤ $150 | 8  | 0.10 |
| ≤ $170 | 10 | 0.10 |
| ≤ $200 | 6  | 0.20 |
| ≤ $300 | 4  | 0.30 |
| ≤ $400 | 6  | 0.30 |
| ≤ $500 | 6  | 0.30 |
| ≤ $600 | 8  | 0.30 |
| ≤ $1000 | 4 | 0.50 |
| ≤ $3000 | 4 | 0.30 |
| ≤ $5000 | 4 | 0.20 |
| ≤ $8000 | 4 | 0.10 |
| > $8000 | 2 | 0.10 |

---

## Ichimoku Signal Rules

Checked on confirmed bar (shift 1). The chikou span for bar 1 is by definition that bar's close, plotted `Kijun` bars back — so the chikou conditions compare the bar-1 close against the candle and Ichimoku levels at that plotted position. A TF is **bullish** when:

| Level | Price condition | Chikou condition |
|-------|----------------|-----------------|
| Tenkan-sen | Price > Tenkan (bar 1) | Close (bar 1) > Tenkan at chikou's position |
| Kijun-sen | Price > Kijun (bar 1) | Close (bar 1) > Kijun at chikou's position |
| Kumo cloud | Price > cloud top (bar 1) | Close (bar 1) > cloud top at chikou's position |
| Price action | — | Close (bar 1) > high of the candle at chikou's position |

**Bearish** is the mirror (price and chikou below all levels, chikou below the candle low). All 6 TFs (H4, H1, M30, M15, M5, M1) must agree for a signal.

### Buffer Offset Detail

`CheckAlign()` uses these offsets when calling `CopyBuffer`:

| Value | Formula | Purpose |
|-------|---------|---------|
| `sh = 1` | — | Last confirmed bar |
| `sh + Kijun` (= 27) | shift into Senkou buffer | Cloud at bar 1 (Senkou is plotted Kijun bars ahead) |
| `chShift = sh + Kijun` (= 27) | chikou's chart position for bar 1 | Where bar 1's chikou is plotted — reference candle, Tenkan, and Kijun are read here |
| `chCloud = chShift + Kijun` (= 53) | shift for cloud at chikou's position | Cloud 52 bars before bar 1 — the cloud chikou "sees" |

The chikou *value* itself is taken directly as `close[1]` from rates (not from the indicator buffer) — the buffer read at offset 27 in earlier versions actually returned the close from 27 bars ago, which silently reduced the chikou filter to a lagged copy of the price check.

---

## Alerts

Every entry and exit emits `Print()`, `Alert()`, and `SendNotification()` with local PC time (12-hour format).

---

## State / Restart

`state[symbol]` tracks direction per symbol. `SyncStateFromPositions()` rebuilds it from open positions (filtered by magic number `MAGIC = 20260501`) on init and on every tick — clearing first, so positions closed by stop loss or manually free the symbol for re-entry instead of leaving stale state.

---

## Inputs

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `Symbols` | `GOLDm#` | Comma-separated watch list (up to 60 symbols) |
| `Tenkan / Kijun / SenkouB` | 9 / 26 / 52 | Ichimoku periods |
| `Slippage` | 30 | Max slippage in points |
| `InpUseStopLoss` | `true` | Attach an ATR-based stop loss to every entry |
| `InpATRPeriod` | 14 | ATR period, computed on M15 |
| `InpATRMultiplier` | 2.0 | Stop distance = ATR × multiplier |
| `InpMaxSpreadPoints` | 60 | Skip entries when spread exceeds this (0 = no limit); tune per broker |

---

## Timeframe Alignment Order

Timeframes are checked highest to lowest — all must agree before entry:

| Index | Timeframe | Role |
|-------|-----------|------|
| 0 | H4 | Highest — trend anchor |
| 1 | H1 | Intermediate |
| 2 | M30 | Intermediate |
| 3 | M15 | Exit reference (IDX_M15) |
| 4 | M5 | Fine filter |
| 5 | M1 | Trigger bar |
