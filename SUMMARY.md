# Ichimoku H4-M1 Alignment EA — Summary

## What It Does

MetaTrader 5 EA trading GOLDm# (configurable) using Ichimoku Cloud alignment across H4 → M15 (4 timeframes). Single active tier. No SL or TP — exit is driven by M15 Ichimoku signal break.

---

## Entry

Runs on every M1 bar close. Enters when all 4 TFs (H4, H1, M30, M15) are aligned and no position is open. M5 and M1 alignment not required. Opens `count` market positions at lot size determined by account equity.

---

## Exit

Closes all positions when the M15 Ichimoku signal no longer matches the open direction (goes neutral or flips).

---

## Equity-Based Risk

`GetEquityRisk()` determines position count and lot size at entry:

| Equity | Count | Lots |
|--------|-------|------|
| ≤ $50  | 1 | 0.10 |
| ≤ $100 | 2 | 0.10 |
| ≤ $200 | 3 | 0.10 |
| ≤ $300 | 3 | 0.20 |
| ≤ $400 | 3 | 0.30 |
| ≤ $500 | 3 | 0.40 |
| ≤ $600 | 3 | 0.50 |
| ≤ $1000 | 4 | 0.50 |
| ≤ $3000 | 3 | 0.30 |
| ≤ $5000 | 3 | 0.20 |
| ≤ $8000 | 3 | 0.10 |
| > $8000 | 2 | 0.10 |

---

## Ichimoku Signal Rules

Checked on confirmed bar (shift 1). A TF is **bullish** when:
- Price close above cloud, Tenkan, and Kijun
- Chikou Span above its cloud (26 bars back), Tenkan, Kijun, and price 26 bars back

**Bearish** is the mirror. All 4 TFs must agree for a signal.

---

## Alerts

Every entry and exit emits `Print()`, `Alert()`, and `SendNotification()` with local PC time (12-hour format).

---

## State / Restart

`tierState[symbol][tier]` tracks direction per tier. On restart, `SyncStateFromPositions()` restores state from open positions using magic number `MAGIC_H4 = 20260302`.

---

## Inputs

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `Symbols` | `GOLDm#` | Comma-separated watch list (up to 60) |
| `Tenkan / Kijun / SenkouB` | 9 / 26 / 52 | Ichimoku periods |
| `Slippage` | 30 | Max slippage in points |
