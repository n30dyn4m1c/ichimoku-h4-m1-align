# Ichimoku H4-M1 Alignment EA

A free MetaTrader 5 Expert Advisor that trades multi-timeframe Ichimoku Kinko Hyo alignment — from H4 down to M1 — with built-in ATR-based risk protection and equity-scaled position sizing.

> **Free to use.** Download it, run it on a demo account, break it, improve it. Feedback and pull requests are welcome — see [Feedback & Contributing](#feedback--contributing) below.

---

## ⚠️ Disclaimer

This EA is provided **for educational and research purposes only**. Trading leveraged instruments carries a high level of risk and can result in the loss of all invested capital. Nothing in this repository constitutes financial advice.

- **Backtest and forward-test on a demo account before risking real money.**
- Past performance (backtested or live) is not indicative of future results.
- The author and contributors accept no liability for losses incurred using this software.
- Use at your own risk.

---

## What It Does

The EA opens trades on a symbol (defaults to `GOLDm#`, configurable) only when **six timeframes — H4, H1, M30, M15, M5, and M1 — all agree** on trend direction using Ichimoku price *and* Chikou Span confirmation, and the location passes **PO3 dealing-range filters** (enough room to the next strong power-of-three level, and not fighting a recent rejection off a major level). Half of each order batch takes profit at tiered PO3 levels; the rest exits when price crosses the M15 Kijun-sen against the trade direction, backstopped by a hard ATR-based stop loss on every position. Position count and lot size scale automatically with account equity.

**Highlights:**
- ✅ 6-timeframe Ichimoku alignment filter (trend + Chikou confirmation) — cuts down on false signals from any single timeframe
- ✅ PO3 dealing-range integration (Hopiplaka) — fixed power-of-three price levels supply entry location filters and tiered take-profit targets
- ✅ ATR-based protective stop loss on every trade (respects broker minimum stop distance)
- ✅ Spread filter to avoid entries during wide/illiquid conditions
- ✅ Equity-tiered position sizing (auto-scales lot size and order count as your account grows or shrinks)
- ✅ Multi-symbol support (comma-separated watch list, up to 60 symbols)
- ✅ Crash/restart-safe — rebuilds internal state from open positions on every tick
- ✅ Push notifications, terminal alerts, and log messages on every entry/exit
- ✅ Weekly equity-growth alert with a suggested profit-withdrawal amount

---

## How the Strategy Works

### Entry Logic

On every new M1 bar close (per symbol), the EA checks all six timeframes (H4 → H1 → M30 → M15 → M5 → M1). A timeframe is considered **bullish** when, on the last confirmed bar:

| Level | Price condition | Chikou (lagging span) condition |
|-------|-----------------|----------------------------------|
| Tenkan-sen | Price > Tenkan | Chikou > Tenkan at its plotted position |
| Kijun-sen | Price > Kijun | Chikou > Kijun at its plotted position |
| Kumo (cloud) | Price above cloud top | Chikou above cloud top at its plotted position |
| Price action | — | Chikou above the high of the candle at its plotted position |

**Bearish** is the exact mirror (price and Chikou below every level). A trade only opens when **all six timeframes agree** on the same direction, no position is currently open on that symbol, the current spread is within `InpMaxSpreadPoints`, and the PO3 location filters (below) approve.

### PO3 Dealing Ranges

The EA overlays a fixed grid of **power-of-three price levels** (the PO3 dealing-range concept by Hopiplaka): every multiple of `3^n × InpPO3Unit`. On gold with `InpPO3Unit = 1.0` the base grid (`3^4 = 81`) is …3888, 3969, 4050, 4131…; a level whose multiple carries a higher power of 3 outranks its neighbours (3888 = 16 × 3⁵ is a 243-grade level, 4374 = 2 × 3⁷ a 2187-grade one). The dealing range containing price is `floor(price / step) × step` to that plus `step`; its midpoint is **equilibrium**, the lower half **discount**, the upper half **premium**. Ichimoku decides *when* to trade — PO3 decides *whether the location is worth it* and *how far to hold*:

- **Bias filter** (`InpPO3BiasFilter`): if the recent H4 extreme tagged or raided a major level (`3^InpPO3BiasPower`, default 729-grade) and price was rejected away from it, entries *against* that rejection are blocked until price reclaims the level or an opposite-side tag supersedes it.
- **Room filter** (`InpPO3RoomFilter`): an entry is skipped when the first strong level (`3^InpPO3StrongPower`, default 243-grade) ahead in the trade direction is closer than `InpPO3MinRR ×` the ATR stop distance — no buying into a ceiling, no selling into a floor.
- **Tiered take-profits**: half of each order batch targets **TP1**, the nearest base rung worth at least `InpPO3MinRR` R; the other half targets **TP2**, the nearest strong level beyond TP1. Both are front-run by `InpPO3BufferATR × ATR(M15)` since price often stalls just short of a level. A tier with no qualifying level within `InpPO3MaxRR` R gets no TP — those orders stay runners managed by the Kijun exit.

Entry alerts include the PO3 context, e.g. `PO3 243[3888-4131] 39% discount | TP1 3890.12 TP2 runner`. For non-gold symbols set `InpPO3Unit` to the instrument's convention (e.g. `0.0001` for 5-digit FX pairs so a 243 range spans 0.0243; `0.01` for a cents-based intraday grid on metals).

### Exit Logic

Orders that reached their PO3 take-profit close there. Everything remaining is closed when the M15 close crosses the M15 Kijun-sen against the trade's direction:
- **Long** closes when the M15 close ends *below* the M15 Kijun.
- **Short** closes when the M15 close ends *above* the M15 Kijun.

Independently of that signal exit, every position carries an **ATR(M15) × multiplier** stop loss to cap losses from fast adverse moves between M15 closes.

### Risk Protection

- `InpUseStopLoss` (default `true`) attaches a stop loss to every order, sized as `ATR(M15, InpATRPeriod) × InpATRMultiplier`, widened automatically if it's tighter than the broker's minimum stop distance.
- If the ATR value can't be read for any reason, the EA **skips the entry entirely** rather than opening an unprotected position.
- `InpMaxSpreadPoints` skips entries when the live spread is too wide (set to `0` to disable).

### Equity-Based Position Sizing

`GetEquityRisk()` determines how many orders to open and at what lot size, based on current account equity:

| Equity | Orders | Lot size (each) |
|--------|--------|------------------|
| ≤ $30 | 2 | 0.10 |
| ≤ $50 | 2 | 0.10 |
| ≤ $70 | 4 | 0.10 |
| ≤ $100 | 4 | 0.10 |
| ≤ $130 | 6 | 0.10 |
| ≤ $150 | 8 | 0.10 |
| ≤ $170 | 10 | 0.10 |
| ≤ $200 | 6 | 0.20 |
| ≤ $300 | 4 | 0.30 |
| ≤ $400 | 6 | 0.30 |
| ≤ $500 | 6 | 0.30 |
| ≤ $600 | 8 | 0.30 |
| ≤ $1000 | 4 | 0.50 |
| ≤ $3000 | 4 | 0.30 |
| ≤ $5000 | 4 | 0.20 |
| ≤ $8000 | 4 | 0.10 |
| > $8000 | 2 | dynamic (see below) |

> Tune this table in `GetEquityRisk()` to fit your own account size and risk tolerance — the defaults are unlikely to be right for you as-is.

Above $8000, lot size is no longer fixed — it's computed by `RiskBasedLots()` so that if the ATR stop loss is hit on both orders, the combined loss is `InpHighEquityRiskPct`% of equity (1% by default). It uses the ATR(M15) stop distance and the symbol's tick value/size to size the position, then rounds down to the broker's lot step and clamps to the symbol's min/max volume. If the ATR value or tick data aren't available (or `InpUseStopLoss` is off), it falls back to a fixed 0.10 lots.

If a batch of orders is only partially filled (e.g. the broker runs out of margin partway through), the EA still tracks the position and exit logic correctly for whatever did open.

### Weekly Equity Alert

Every `InpCheckDay` (default Friday), the EA compares current equity to a stored baseline. If profit since the baseline exceeds `InpMinProfitTrigger`, it alerts you with a suggested withdrawal amount (`InpWithdrawProfitPct`% of the profit) — a simple nudge to bank gains periodically. This is informational only; it does **not** withdraw funds automatically.

---

## Companion: H1 Reversion EA (`ichimoku-H1-M1-reversion-ea.mq5`)

A separate, standalone EA that trades the **opposite** edge to the trend/alignment builds — mean reversion back to a flat H1 Kijun, grounded in Ichimoku *time theory*. It reuses the same infrastructure (symbol parsing, equity-scaled sizing, state recovery, alerts, weekly equity alert) but replaces the entry/exit entirely. Run it on its own chart/instance — it uses its own magic number (`20260722`) and is intentionally not mixed with the alignment logic on the same symbol (the two would fight each other).

### The idea

After price has stayed **off the H1 Kijun for one of the Ichimoku time cycles** (9, 17, 26, or 33 bars, each ± `InpTimeTol`) and the **Kijun is flat**, an extended move is "due" to snap back to the Kijun. The Kijun becomes a magnet; the trade is taken *toward* it.

### Entry

On each new M1 bar, per symbol, a reversion trade opens when **all** of these hold:

1. **Extension** — the last H1 close is at least `InpFarATRMult × ATR(H1)` away from the Kijun. Above the Kijun ⇒ **sell** back down; below ⇒ **buy** back up.
2. **Time theory** — the number of consecutive H1 candles since the last Kijun touch lands on an **Ichimoku time cycle** — `InpTimeCycles` (default `9,17,26,33`) each within ± `InpTimeTol`. A "touch" = the Kijun falling within a candle's high–low range; the count resets to 0 on any touch, so a streak that falls *between* cycles (e.g. 13 or 30 bars) does **not** qualify.
3. **Flat Kijun** — the Kijun's move over the last `InpFlatBars` H1 bars is ≤ `InpFlatATRMult × ATR(H1)`.
4. **A trigger fires** (either one, both configurable):
   - **M5 Kijun cross** (`InpUseM5Cross`) — a *fresh* M5 close cross of the M5 Kijun in the reversion direction (the H1 "breakout close" confirmation on the lower timeframe).
   - **Rejection candle** (`InpUseRejection`) — the last closed H1 candle is a long-wicked, small-body candle (wick ≥ `InpRejWickFrac` of range, body ≤ `InpRejBodyFrac` of range) whose wick **raids beyond a prior fractal swing high/low** from the last `InpRejLookback` bars (default 500) and closes back inside it. With `InpRequireUnraided` (default on) the raided swing must still hold **resting liquidity** — nothing has exceeded it since it formed — so the trade fires on a genuine liquidity grab, not a level that was already run. `InpSwingWing` sets the fractal half-width (bars each side that define a swing point).

### Exit

Exits are **broker-managed** via each order's attached SL and TP:

- **Stop loss** — the current H1 **swing high** (for a sell) or **swing low** (for a buy) over `InpSwingLookback` bars, padded by `InpSLBufferATR × ATR(H1)`, widened to the broker's minimum stop distance if needed.
- **Take profit** — the **H1 Kijun** (the reversion target), fixed at entry. A setup whose Kijun is closer than the broker's minimum stop distance is skipped.

### Risk

Identical equity-scaled sizing to the breakout/alignment EAs — `GetEquityRisk()` picks the order count and lot size from account equity, and above $8000 `RiskBasedLots()` sizes so the swing stop risks `InpHighEquityRiskPct`% of equity across the batch.

### Reversion inputs

| Parameter | Default | Description |
|-----------|---------|-------------|
| `InpTimeCycles` | `9,17,26,33` | Ichimoku time cycles (bars since last Kijun touch) that qualify |
| `InpTimeTol` | 2 | ± tolerance applied to each time cycle |
| `InpFarATRMult` | 2.0 | Price must be ≥ this × ATR(H1) from the Kijun to be "far" |
| `InpFlatBars` | 5 | H1 bars over which the Kijun slope is measured |
| `InpFlatATRMult` | 0.25 | Kijun is "flat" if its move over `InpFlatBars` ≤ this × ATR(H1) |
| `InpSwingLookback` | 10 | H1 bars used for the swing-based stop loss |
| `InpSLBufferATR` | 0.10 | Extra SL padding beyond the swing = this × ATR(H1) |
| `InpUseM5Cross` | `true` | Enable the fresh-M5-Kijun-cross trigger |
| `InpUseRejection` | `true` | Enable the swing-liquidity rejection-candle trigger |
| `InpRejWickFrac` | 0.55 | Rejection wick ≥ this fraction of the H1 candle range |
| `InpRejBodyFrac` | 0.35 | Rejection body ≤ this fraction of the H1 candle range |
| `InpRejLookback` | 500 | H1 bars scanned for prior swing highs/lows to raid |
| `InpSwingWing` | 2 | Fractal half-width for a swing point (bars each side) |
| `InpRequireUnraided` | `true` | Only count swings whose liquidity is not yet raided |
| `InpATRPeriod` | 14 | ATR period (computed on H1) for distance/flatness/buffer |
| `InpMaxSpreadPoints` | 60 | Max spread (points) to allow an entry; `0` disables |
| `InpHighEquityRiskPct` | 1.0 | % of equity risked per trade once equity > $8000 |

Installation and the equity/alert inputs are the same as the main EA below — just compile and attach `ichimoku-H1-M1-reversion-ea.mq5` instead of (or on a separate instance from) the alignment build.

---

## Getting Started

### Requirements

- [MetaTrader 5](https://www.metatrader5.com/) terminal
- A broker account (demo strongly recommended for testing) with the symbol(s) you intend to trade available

### Installation

1. Download `ichimoku-H4-M1-po3-ea.mq5` from this repository (the PO3 build documented here). The pre-PO3 build is preserved as `ichimoku-H4-M1-ea.mq5` for reference.
2. Open MetaTrader 5 → **File → Open Data Folder**.
3. Copy the file into `MQL5/Experts/`.
4. In MT5, open **Navigator → Expert Advisors**, right-click and **Refresh**, or restart MT5.
5. Compile it: open the file in **MetaEditor** (F4 in MT5) and press **Compile** (F7). Confirm there are no errors.
6. Drag the EA onto a chart of the symbol you configured (e.g. `GOLDm#`). The EA manages all symbols in its `Symbols` input internally, so the chart it's attached to is just an anchor — one instance is enough.
7. Make sure **AutoTrading** is enabled (toolbar button) and, in the EA's **Common** tab, that "Allow live trading" and "Allow DLL imports" (if prompted) are checked as needed.
8. Enable **Allow WebRequest**/notifications if you want push alerts — set this up under **Tools → Options → Notifications** with your MetaQuotes ID.

### Recommended First Steps

- Run it in the **Strategy Tester** first (MT5 supports multi-symbol/multi-timeframe testing) to see how the alignment logic behaves historically on your symbol.
- Then run it on a **demo account** for at least a few weeks before considering live capital.
- Review and adjust the equity/lot-size table (`GetEquityRisk()`) — the shipped values were tuned for a specific small account and are almost certainly not appropriate for your balance or risk appetite.

---

## Configuration (Inputs)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `Symbols` | `GOLDm#` | Comma-separated list of symbols to watch (up to 60) |
| `Tenkan` | 9 | Ichimoku Tenkan-sen period |
| `Kijun` | 26 | Ichimoku Kijun-sen period |
| `SenkouB` | 52 | Ichimoku Senkou Span B period |
| `Slippage` | 30 | Maximum allowed slippage, in points |
| `InpUseStopLoss` | `true` | Attach an ATR-based stop loss to every entry |
| `InpATRPeriod` | 14 | ATR period, computed on M15 |
| `InpATRMultiplier` | 3.0 | Stop distance = ATR × multiplier |
| `InpMaxSpreadPoints` | 60 | Max spread (points) to allow an entry; `0` disables the filter |
| `InpHighEquityRiskPct` | 1.0 | % of equity risked per trade once equity exceeds $8000 (see [Equity-Based Position Sizing](#equity-based-position-sizing)) |
| `InpUsePO3` | `true` | Use PO3 dealing-range levels for take-profits and entry filters |
| `InpPO3Unit` | 1.0 | Price per PO3 unit (1.0 = whole dollars on gold; 0.0001 for 5-digit FX) |
| `InpPO3BasePower` | 4 | Base rung = 3^power units (4 → 81) |
| `InpPO3StrongPower` | 5 | Strong level = 3^power units (5 → 243) |
| `InpPO3MinRR` | 1.5 | Minimum reward:risk for a level to qualify as a TP (also the room-filter threshold) |
| `InpPO3MaxRR` | 8.0 | Levels beyond this R-multiple are ignored (order stays a runner) |
| `InpPO3BufferATR` | 0.25 | Front-run TP buffer = ATR(M15) × this |
| `InpPO3RoomFilter` | `true` | Skip entries without `MinRR` room to the next strong level |
| `InpPO3BiasFilter` | `true` | Block entries against a recent rejection off a major level |
| `InpPO3BiasPower` | 6 | Major level for the bias filter = 3^power units (6 → 729) |
| `InpPO3BiasBars` | 180 | H4 bars scanned for a major-level rejection |
| `InpPO3BiasTolFrac` | 0.4 | Rejection tag tolerance, as a fraction of the base rung |
| `InpMinProfitTrigger` | 5.0 | Minimum profit above baseline equity to trigger the weekly alert |
| `InpWithdrawProfitPct` | 50.0 | Suggested withdrawal as a percentage of profit above baseline |
| `InpCheckDay` | Friday | Day of week the equity alert is evaluated |
| `InpResetBaseline` | `false` | Set to `true` once to reset the equity baseline to current equity |
| `InpSendPush` | `true` | Send push notifications for alerts (entries, exits, equity alert) |

---

## Technical Notes

- **Magic number:** `20260501` — used to identify and manage only this EA's positions, so it won't interfere with other EAs or manual trades on the same account.
- **State recovery:** on every tick, `SyncStateFromPositions()` rebuilds per-symbol direction state from currently open positions filtered by magic number. This means the EA recovers correctly after a terminal restart, VPS reboot, or a position closed manually/by stop loss — no stale state is left behind.
- **Per-symbol M1 gating:** each symbol only re-evaluates entry/exit logic once per newly closed M1 bar for that symbol, avoiding redundant checks on every tick.
- **Chikou Span handling:** the Chikou value is read directly from `close[1]` in price data rather than the Ichimoku buffer, avoiding an offset bug where reading Chikou from the indicator buffer silently degrades it into a lagged copy of the price check. See inline comments in `CheckAlign()` for the full offset derivation.

---

## Feedback & Contributing

This project is shared for free so others can learn from it, use it, and make it better. If you:

- **Find a bug** — please open an [issue](../../issues) with as much detail as you can (symbol, timeframe, broker, terminal logs).
- **Have an improvement idea** (better risk sizing, additional filters, alerting, etc.) — open an issue to discuss, or submit a pull request.
- **Just want to share results** — feedback from live/demo testing on different symbols and brokers is genuinely useful and welcome.

---

## License

Released for free personal and educational use. No warranty is provided — see the [Disclaimer](#️-disclaimer) above.
