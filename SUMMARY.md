# Ichimoku H4-M1 Alignment EA — Summary

## What It Does

MetaTrader 5 EA trading GOLDm# (configurable) using Ichimoku Cloud alignment across H4 → M1 (6 timeframes), location-filtered by PO3 dealing ranges. Half of each batch takes profit at tiered PO3 levels; the signal exit for the rest is driven by M15 kijun cross; every position also carries an ATR-based protective stop loss.

---

## Entry

Runs on every M1 bar close. Enters when all 6 TFs (H4, H1, M30, M15, M5, M1) price and chikou are aligned above/below their respective clouds, no position is open, the current spread is within `InpMaxSpreadPoints`, and the PO3 location filters approve (see below). Opens `count` market orders at lot size determined by account equity, each with a stop loss `InpATRMultiplier × ATR(M15, InpATRPeriod)` away from entry (widened to the broker's minimum stop distance if needed). Order placement stops at the first rejection (e.g. out of margin), and an entry is skipped entirely if the ATR value can't be read — the EA never opens unprotected positions while `InpUseStopLoss` is on.

---

## PO3 Dealing Ranges

Fixed grid of power-of-three price levels (Hopiplaka): every multiple of `3^n × InpPO3Unit`. Gold with unit 1.0 → base 81 grid (…3888, 3969, 4050…); a multiple carrying a higher power of 3 outranks its neighbours (3888 = 16×3⁵ → 243-grade; 4374 = 2×3⁷ → 2187-grade). Current dealing range = `floor(price/step)×step` … `+step`; midpoint = equilibrium, lower half discount, upper half premium.

- **Bias filter**: if the H4 lookback extreme (180 bars) tagged a 729-grade level within `0.4 ×` base rung and price was rejected away from it, entries against the rejection are blocked until price reclaims the level (or a newer opposite tag supersedes it).
- **Room filter**: entry skipped when the first 243-grade level ahead is closer than `InpPO3MinRR ×` stop distance.
- **Tiered TPs**: even-indexed orders target TP1 = nearest 81-rung worth ≥ `MinRR` R; odd-indexed target TP2 = nearest 243-grade level beyond TP1; both front-run by `InpPO3BufferATR × ATR(M15)`; nothing within `MaxRR` R → no TP (runner). TPs that would violate the broker's minimum stop distance are dropped.

Entry alerts append the PO3 range, premium/discount position, and both TPs.

---

## Exit

Orders that reach their PO3 TP close there. All remaining positions close when the M15 bar-1 close crosses the M15 kijun (bar 1) against the open direction — i.e. for a long, the M15 close ends below the M15 kijun; for a short, the M15 close ends above the M15 kijun. Independently, each position's ATR stop loss caps the loss on fast adverse moves between M15 closes.

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
| > $8000 | 2 | dynamic — sized so 1% of equity (`InpHighEquityRiskPct`) is risked across both orders if the ATR stop is hit |

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
| `InpHighEquityRiskPct` | 1.0 | % of equity risked per trade once equity exceeds $8000 (`RiskBasedLots()`) |
| `InpUsePO3` | `true` | PO3 dealing-range TPs and entry filters |
| `InpPO3Unit` | 1.0 | Price per PO3 unit (whole dollars on gold; 0.0001 for 5-digit FX) |
| `InpPO3BasePower` / `InpPO3StrongPower` / `InpPO3BiasPower` | 4 / 5 / 6 | Level grades: 81 / 243 / 729 units |
| `InpPO3MinRR` / `InpPO3MaxRR` | 1.5 / 8.0 | R-multiple window for a level to qualify as a TP |
| `InpPO3BufferATR` | 0.25 | Front-run TP buffer = ATR(M15) × this |
| `InpPO3RoomFilter` / `InpPO3BiasFilter` | `true` | Location filters (room to next strong level; major-level rejection bias) |
| `InpPO3BiasBars` / `InpPO3BiasTolFrac` | 180 / 0.4 | Bias lookback (H4 bars) and tag tolerance (fraction of base rung) |

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
