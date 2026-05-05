# Ichimoku H1-M1 Alignment EA — Summary

## What It Does

MetaTrader 5 EA trading GOLDm# (configurable) using Ichimoku Cloud alignment across H1 → M1 (5 timeframes). No SL or TP — exit is driven by M15 kijun cross.

---

## Entry

Runs on every M1 bar close. Enters when all 5 TFs (H1, M30, M15, M5, M1) price and chikou are aligned above/below their respective clouds and no position is open. Opens `count` market positions at lot size determined by account equity.

---

## Exit

Closes all positions when the M15 close crosses the M15 kijun against the open direction.

---

## Equity-Based Risk

`GetEquityRisk()` determines position count and lot size at entry:

| Equity | Count | Lots |
|--------|-------|------|
| ≤ $30  | 1 | 0.10 |
| ≤ $50  | 2 | 0.10 |
| ≤ $70  | 3 | 0.10 |
| ≤ $100 | 4 | 0.10 |
| ≤ $130 | 5 | 0.10 |
| ≤ $150 | 7 | 0.10 |
| ≤ $170 | 9 | 0.10 |
| ≤ $200 | 5 | 0.20 |
| ≤ $300 | 4 | 0.30 |
| ≤ $400 | 5 | 0.30 |
| ≤ $500 | 6 | 0.30 |
| ≤ $600 | 7 | 0.30 |
| ≤ $1000 | 4 | 0.50 |
| ≤ $3000 | 3 | 0.30 |
| ≤ $5000 | 3 | 0.20 |
| ≤ $8000 | 3 | 0.10 |
| > $8000 | 2 | 0.10 |

---

## Ichimoku Signal Rules

Checked on confirmed bar (shift 1). A TF is **bullish** when:
- Price close above cloud
- Chikou Span above its cloud (at chikou's chart position)

**Bearish** is the mirror. All 5 TFs (H1, M30, M15, M5, M1) must agree for a signal.

---

## Alerts

Every entry and exit emits `Print()`, `Alert()`, and `SendNotification()` with local PC time (12-hour format).

---

## State / Restart

`state[symbol]` tracks direction per symbol. On restart, `SyncStateFromPositions()` restores state from open positions using magic number `MAGIC = 20260501`.

---

## Inputs

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `Symbols` | `GOLDm#` | Comma-separated watch list (up to 60) |
| `Tenkan / Kijun / SenkouB` | 9 / 26 / 52 | Ichimoku periods |
| `Slippage` | 30 | Max slippage in points |
