# Ichimoku H4-H1 Alignment EA — Summary

## What It Does

MetaTrader 5 EA trading GOLDm# (configurable) using Ichimoku Cloud alignment on H4 and H1. No SL or TP — exit is driven by M15 kijun cross.

---

## Entry

Runs on every M1 bar close. Enters when both H4 and H1 price and chikou are aligned above/below their respective tenkan, kijun, and cloud, and no position is open. Opens `count` market orders at lot size determined by account equity.

---

## Exit

Closes all positions when the M15 bar-1 close crosses the M15 kijun (bar 1) against the open direction.

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

Checked on confirmed bar (shift 1). A TF is **bullish** when price and chikou are clear of all three Ichimoku levels:

| Level | Price condition | Chikou condition |
|-------|----------------|-----------------|
| Tenkan-sen | Price > Tenkan (bar 1) | Chikou > Tenkan at chikou's position |
| Kijun-sen | Price > Kijun (bar 1) | Chikou > Kijun at chikou's position |
| Kumo cloud | Price > cloud top (bar 1) | Chikou > cloud top at chikou's position |

**Bearish** is the mirror (price and chikou below all three). Both H4 and H1 must agree for a signal.

### Buffer Offset Detail

`CheckAlign()` uses these offsets when calling `CopyBuffer`:

| Value | Formula | Purpose |
|-------|---------|---------|
| `sh = 1` | — | Last confirmed bar |
| `sh + Kijun` (= 27) | shift into Senkou buffer | Cloud at bar 1 (Senkou is plotted Kijun bars ahead) |
| `chShift = sh + Kijun` (= 27) | shift into Chikou buffer | Chikou value at bar 1 (Chikou is plotted Kijun bars back) |
| `chCloud = sh + SenkouB` (= 53) | shift for cloud at chikou's position | Cloud 52 bars before bar 1 — the cloud chikou "sees" |

---

## Alerts

Every entry and exit emits `Print()`, `Alert()`, and `SendNotification()` with local PC time (12-hour format).

---

## State / Restart

`state[symbol]` tracks direction per symbol. On restart, `SyncStateFromPositions()` restores state from open positions filtered by magic number `MAGIC = 20260501` (date-stamped: May 1, 2026).

---

## Inputs

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `Symbols` | `GOLDm#` | Comma-separated watch list (up to 60 symbols) |
| `Tenkan / Kijun / SenkouB` | 9 / 26 / 52 | Ichimoku periods |
| `Slippage` | 30 | Max slippage in points |

---

## Timeframe Alignment Order

Entry requires both H4 and H1 to agree. M15 is loaded only for the exit check.

| Index | Timeframe | Role |
|-------|-----------|------|
| 0 | H4 | Highest — trend anchor (entry) |
| 1 | H1 | Confirmation (entry) |
| 2 | M15 | Exit reference (IDX_M15) |
