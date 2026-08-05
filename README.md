# Ichimoku Alignment EAs

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-MetaTrader%205-blue.svg)](https://www.metatrader5.com/)
[![Language](https://img.shields.io/badge/Language-MQL5-orange.svg)](https://www.mql5.com/)
[![Strategy](https://img.shields.io/badge/Strategy-Ichimoku%20Alignment-green.svg)](https://github.com/n30dyn4m1c/ichimoku-h4-m1-align)

**MetaTrader 5 Expert Advisors for multi-timeframe Ichimoku Kinko Hyo alignment with ATR risk protection and equity-scaled position sizing.**

Free MetaTrader 5 Expert Advisors that trade multi-timeframe Ichimoku Kinko
Hyo alignment, with built-in ATR-based risk protection and equity-scaled
position sizing. Four non-experimental builds are included — two standard and
two VPS deployment variants:

| EA | File | Timeframes | Exit signal | Magic |
|----|------|------------|-------------|-------|
| **H4-M1 Alignment** | `ichimoku-h4-m1-ea.mq5` | H4 → M1 (6 TFs) | M15 Kijun cross | `20260501` |
| **H1-M1 Alignment** | `ichimoku-h1-m1-ea.mq5` | H1 → M1 (5 TFs) | M5 Kijun cross | `20260502` |
| **H4-M1 VPS Deployment** | `ichimoku-h4-m1-vps-ea.mq5` | H4 → M1 (6 TFs) | M15 Kijun cross | `20260501` |
| **H1-M1 VPS Deployment** | `ichimoku-h1-m1-vps-ea.mq5` | H1 → M1 (5 TFs) | M5 Kijun cross | `20260502` |

All four share the same entry rules, risk protection, and equity-sizing
logic — they differ only in which timeframes must agree, which lower
timeframe's Kijun triggers the exit, and whether they're tuned for unattended
VPS use. The two standard builds carry distinct magic numbers so they can run
on the same account (even the same symbol) without interfering with each
other. The VPS builds reuse their anchor's magic number, so treat the standard
and VPS variants of an anchor as alternatives, not companions — see
[VPS Deployment Builds](#vps-deployment-builds).

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

Each EA opens trades on a symbol (defaults to `GOLDm#`, configurable) only
when **every timeframe from its anchor down to M1 agrees** on trend direction
using Ichimoku price *and* Chikou Span confirmation. Positions exit when a
lower-timeframe Kijun-sen is crossed against the trade direction, backstopped
by a hard ATR-based stop loss on every position. Position count and lot size
scale automatically with account equity.

**Highlights:**
- ✅ Multi-timeframe Ichimoku alignment filter (trend + Chikou confirmation) — cuts down on false signals from any single timeframe
- ✅ ATR-based protective stop loss on every trade (respects broker minimum stop distance)
- ✅ Spread filter to avoid entries during wide/illiquid conditions
- ✅ Equity-tiered position sizing (auto-scales lot size and order count as your account grows or shrinks)
- ✅ Multi-symbol support (comma-separated watch list, up to 60 symbols)
- ✅ Crash/restart-safe — rebuilds internal state from open positions on every tick
- ✅ Push notifications, terminal alerts, and log messages on every entry/exit
- ✅ Weekly equity-growth alert with a suggested profit-withdrawal amount (standard builds only)
- ✅ VPS deployment builds — once-per-minute gating, push alerts, and an optional re-entry cooldown (see below)

---

## VPS Deployment Builds

The `ichimoku-h4-m1-vps-ea.mq5` and `ichimoku-h1-m1-vps-ea.mq5` files are
deployment-oriented variants of the two standard builds, tuned for running
unattended on a cheap VPS. Their trading logic is identical — same entry/exit
rules, risk protection, equity sizing, and magic numbers — but they differ in
three practical ways:

- **Once-per-minute gating.** `OnTick()` returns immediately unless a new
  closed M1 bar has appeared (`lastMinuteKey = TimeCurrent() / 60`), so the
  EA does almost no work between bars and burns negligible CPU/network on a
  24/7 VPS. The standard builds evaluate on every tick.
- **No equity alert, push-only notifications.** The weekly equity-growth /
  profit-withdrawal reminder (`InpMinProfitTrigger`, `InpWithdrawProfitPct`,
  `InpCheckDay`, `InpResetBaseline`) and the `InpSendPush` toggle are removed
  entirely. Every entry/exit sends a `SendNotification` push and a journal
  `Print`; the terminal `Alert()` popups are dropped to keep the VPS session
  quiet.
- **Optional re-entry cooldown.** A new `InpReentryCooldownSec` input (default
  `0`) adds a minimum wait in seconds after an exit before the same symbol can
  be re-entered — handy for stopping the EA from instantly flip-flopping right
  after a stop-out.

Because the VPS builds reuse the same magic numbers as their standard
counterparts, run only one variant of each anchor per account/symbol.

---

## How the Strategy Works

### Entry Logic

On every new M1 bar close (per symbol), the EA checks all of its timeframes
(H4 → M1 for the H4-M1 build, H1 → M1 for the H1-M1 build). A timeframe is
considered **bullish** when, on the last confirmed bar:

| Level | Price condition | Chikou (lagging span) condition |
|-------|-----------------|----------------------------------|
| Tenkan-sen | Price > Tenkan | Chikou > Tenkan at its plotted position |
| Kijun-sen | Price > Kijun | Chikou > Kijun at its plotted position |
| Kumo (cloud) | Price above cloud top | Chikou above cloud top at its plotted position |
| Price action | — | Chikou above the high of the candle at its plotted position |

**Bearish** is the exact mirror (price and Chikou below every level). A trade
only opens when **all of its timeframes agree** on the same direction, no
position is currently open on that symbol, and the current spread is within
`InpMaxSpreadPoints`.

`CheckAlign()` uses these `CopyBuffer` offsets to read the alignment:

| Value | Formula | Purpose |
|-------|---------|---------|
| `sh = 1` | — | Last confirmed bar |
| `sh + Kijun` | shift into Senkou buffer | Cloud at bar 1 (Senkou is plotted Kijun bars ahead) |
| `chShift = sh + Kijun` | chikou's chart position for bar 1 | Where bar 1's chikou is plotted — reference candle, Tenkan, and Kijun are read here |
| `chCloud = chShift + Kijun` | shift for cloud at chikou's position | Cloud 52 bars before bar 1 — the cloud chikou "sees" |

The chikou *value* itself is taken directly as `close[1]` from rates (not
from the indicator buffer) — reading Chikou from the indicator buffer at the
`chShift` offset would actually return the close from that many bars ago,
silently reducing the chikou filter to a lagged copy of the price check.

### Exit Logic

- **H4-M1 build:** closes when the M15 close crosses the M15 Kijun-sen against the trade's direction (long closes below the M15 Kijun, short closes above it).
- **H1-M1 build:** closes when the M5 close crosses the M5 Kijun-sen against the trade's direction (long closes below the M5 Kijun, short closes above it).

Independently of that signal exit, every position carries an **ATR(M15) ×
multiplier** stop loss to cap losses from fast adverse moves between M15
closes.

### Risk Protection

- `InpUseStopLoss` (default `true`) attaches a stop loss to every order, sized as `ATR(M15, InpATRPeriod) × InpATRMultiplier`, widened automatically if it's tighter than the broker's minimum stop distance.
- If the ATR value can't be read for any reason, the EA **skips the entry entirely** rather than opening an unprotected position.
- `InpMaxSpreadPoints` skips entries when the live spread is too wide (set to `0` to disable).

### Equity-Based Position Sizing

`GetEquityRisk()` determines how many orders to open and at what lot size, based on current account equity. All counts are even, with the lowest tier opening 2:

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

This feature exists only in the standard builds — the
[VPS deployment builds](#vps-deployment-builds) drop it. Every `InpCheckDay`
(default Friday), the EA compares current equity to a stored baseline. If
profit since the baseline exceeds `InpMinProfitTrigger`, it alerts you with a
suggested withdrawal amount (`InpWithdrawProfitPct`% of the profit) — a simple
nudge to bank gains periodically. This is informational only; it does **not**
withdraw funds automatically.

---

## Getting Started

### Requirements

- [MetaTrader 5](https://www.metatrader5.com/) terminal
- A broker account (demo strongly recommended for testing) with the symbol(s) you intend to trade available

### Installation

1. Download the build you want from this repository. For hands-on trading use `ichimoku-h4-m1-ea.mq5` and/or `ichimoku-h1-m1-ea.mq5` (distinct magic numbers — you can run both). For unattended 24/7 deployment use the corresponding `ichimoku-h4-m1-vps-ea.mq5` / `ichimoku-h1-m1-vps-ea.mq5` variants instead — see [VPS Deployment Builds](#vps-deployment-builds).
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

The standard builds share the same input set:

| Parameter | Default | Description |
|-----------|---------|--------------|
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
| `InpMinProfitTrigger` | 5.0 | Minimum profit above baseline equity to trigger the weekly alert (standard builds) |
| `InpWithdrawProfitPct` | 50.0 | Suggested withdrawal as a percentage of profit above baseline (standard builds) |
| `InpCheckDay` | Friday | Day of week the equity alert is evaluated (standard builds) |
| `InpResetBaseline` | `false` | Set to `true` once to reset the equity baseline to current equity (standard builds) |
| `InpSendPush` | `true` | Send push notifications for alerts (entries, exits, equity alert) |
| `InpReentryCooldownSec` | 0 | Min seconds after an exit before re-entering the same symbol (VPS builds) |

> The VPS deployment builds replace the four equity-alert inputs and
> `InpSendPush` with `InpReentryCooldownSec` instead — see
> [VPS Deployment Builds](#vps-deployment-builds).

## Timeframe Alignment Order

Timeframes are checked highest to lowest — all must agree before entry.

**H4-M1 Alignment EA:**

| Index | Timeframe | Role |
|-------|-----------|------|
| 0 | H4 | Highest — trend anchor |
| 1 | H1 | Intermediate |
| 2 | M30 | Intermediate |
| 3 | M15 | Exit reference |
| 4 | M5 | Fine filter |
| 5 | M1 | Trigger bar |

**H1-M1 Alignment EA:**

| Index | Timeframe | Role |
|-------|-----------|------|
| 0 | H1 | Highest — trend anchor |
| 1 | M30 | Intermediate |
| 2 | M15 | Intermediate |
| 3 | M5 | Exit reference |
| 4 | M1 | Trigger bar |

The VPS deployment builds use exactly the same timeframe stacks as their
standard counterparts.

---

## Technical Notes

- **Magic numbers:** `20260501` (H4-M1 build) and `20260502` (H1-M1 build) — each EA only identifies and manages its own positions by its magic number, so they won't interfere with other EAs, each other, or manual trades on the same account. The VPS deployment builds reuse these same magic numbers, so they should replace (not run alongside) the standard builds.
- **State recovery:** on every tick, `SyncStateFromPositions()` rebuilds per-symbol direction state from currently open positions filtered by magic number. This means the EA recovers correctly after a terminal restart, VPS reboot, or a position closed manually/by stop loss — no stale state is left behind.
- **Per-symbol M1 gating:** each symbol only re-evaluates entry/exit logic once per newly closed M1 bar for that symbol, avoiding redundant checks on every tick.
- **Chikou Span handling:** the Chikou value is read directly from `close[1]` in price data rather than the Ichimoku buffer, avoiding an offset bug where reading Chikou from the indicator buffer silently degrades it into a lagged copy of the price check. See inline comments in `CheckAlign()` for the full offset derivation.

---

## Experimental EAs

This repository also includes five experimental strategies — a PO3-enhanced
variant of the H4-M1 alignment EA (`experimental-h4-m1-po3-ea.mq5`), an
Ichimoku time-theory mean-reversion EA (`experimental-h1-m1-reversion-ea.mq5`),
a fast M1-M5 breakout alignment EA (`experimental-m1-m5-breakout-ea.mq5`), a
shorter-anchor M30-M1 breakout alignment clone
(`experimental-m30-m1-breakout-ea.mq5`), and an H4-M15 alignment clone that
trims the stack down to M15 (`experimental-h4-m15-align-ea.mq5`). They're
newer and less battle-tested than the main builds above; each file is
prefixed `experimental-` to keep it clearly separate. See
**[EXPERIMENTAL-NOTES.md](EXPERIMENTAL-NOTES.md)** for full details on each.

---

## Feedback & Contributing

This project is shared for free so others can learn from it, use it, and make it better. If you:

- **Find a bug** — please open an [issue](../../issues) with as much detail as you can (symbol, timeframe, broker, terminal logs).
- **Have an improvement idea** (better risk sizing, additional filters, alerting, etc.) — open an issue to discuss, or submit a pull request.
- **Just want to share results** — feedback from live/demo testing on different symbols and brokers is genuinely useful and welcome.

---

## License

This project is licensed under the [MIT License](LICENSE).

You are free to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the software, subject to the conditions in the license. The software is provided **as is**, without warranty of any kind — see the [Disclaimer](#️-disclaimer) above and the full text in [LICENSE](LICENSE).
