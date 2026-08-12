# Ichimoku Alignment EAs

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-MetaTrader%205-blue.svg)](https://www.metatrader5.com/)
[![Language](https://img.shields.io/badge/Language-MQL5-orange.svg)](https://www.mql5.com/)
[![Strategy](https://img.shields.io/badge/Strategy-Ichimoku%20Alignment-green.svg)](https://github.com/n30dyn4m1c/ichimoku-h4-m1-align)

**MetaTrader 5 Expert Advisors for multi-timeframe Ichimoku Kinko Hyo alignment with ATR risk protection and equity-scaled position sizing.**

Free MetaTrader 5 Expert Advisors that trade multi-timeframe Ichimoku Kinko
Hyo alignment, with built-in ATR-based risk protection and equity-scaled
position sizing. Four main builds are included at the repo root — two VPS
deployment variants and their MT5 desktop counterparts (identical logic with
terminal alerts restored):

| EA | File | Timeframes | Exit signal | Magic |
|----|------|------------|-------------|-------|
| **H4-M1 VPS Deployment** | `ichimoku-h4-m1-vps-ea.mq5` | H4 → M1 (6 TFs) | M15 Kijun cross | `20260815` |
| **H1-M1 VPS Deployment** | `ichimoku-h1-m1-vps-ea.mq5` | H1 → M1 (5 TFs) | M5 Kijun cross | `20260814` |
| **H4-M1 MT5 Desktop** | `ichimoku-h4-m1-mt5pc-ea.mq5` | H4 → M1 (6 TFs) | M15 Kijun cross | `20260830` |
| **H1-M1 MT5 Desktop** | `ichimoku-h1-m1-mt5pc-ea.mq5` | H1 → M1 (5 TFs) | M5 Kijun cross | `20260831` |

All builds share the same entry rules, risk protection, and equity-sizing
logic — they differ only in which timeframes must agree, which lower
timeframe's Kijun triggers the exit, and whether they're tuned for unattended
VPS use. Every build carries its own magic number, so all four can run on the
same account, even on the same symbol, without interfering with each other.
See [VPS Deployment Builds](#vps-deployment-builds) for what the VPS variants
add on top.

**Repository layout:**

- `ichimoku-h4-m1-vps-ea.mq5`, `ichimoku-h1-m1-vps-ea.mq5` — the live VPS builds (do not modify; see AGENTS.md)
- `ichimoku-h4-m1-mt5pc-ea.mq5`, `ichimoku-h1-m1-mt5pc-ea.mq5` — MT5 desktop copies with alerts
- `archives/` — older standard builds and archived versions
- `experiments/` — experimental EAs, the MS-W1-D1 build, and [EXPERIMENTAL-NOTES.md](experiments/EXPERIMENTAL-NOTES.md)
- `utilities/` — deployment scripts and the Python monitor

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
- ✅ Weekly equity-growth alert with a suggested profit-withdrawal amount (MT5 desktop builds only)
- ✅ VPS deployment builds — once-per-minute gating, push alerts, risk/margin-capped sizing, and a re-entry cooldown (see below)

---

## VPS Deployment Builds

The `ichimoku-h4-m1-vps-ea.mq5` and `ichimoku-h1-m1-vps-ea.mq5` files are
deployment-oriented variants tuned for running unattended on a cheap VPS.
Their trading logic is identical to the desktop builds — same entry/exit
rules and risk protection — but they add several layers of hardening and
differ from the desktop builds in a few practical ways:

- **Once-per-minute gating.** `OnTick()` returns immediately unless a new
  closed M1 bar has appeared (`lastMinuteKey = TimeCurrent() / 60`), so the
  EA does almost no work between bars and burns negligible CPU/network on a
  24/7 VPS. The desktop MT5PC copies keep the same gating, so behavior is
  identical — only the alerts differ.
- **No equity alert, push-only notifications.** The weekly equity-growth /
  profit-withdrawal reminder (`InpMinProfitTrigger`, `InpWithdrawProfitPct`,
  `InpCheckDay`, `InpResetBaseline`) and the `InpSendPush` toggle are removed
  entirely. Every entry/exit sends a `SendNotification` push and a journal
  `Print`; the terminal `Alert()` popups are dropped to keep the VPS session
  quiet. The `*-mt5pc-ea.mq5` desktop copies restore both the `Alert()`
  popups and the weekly equity alert.
- **Re-entry cooldown.** `InpReentryCooldownSec` (default `0`) adds a minimum
  wait in seconds after an exit before the same symbol can be re-entered —
  handy for stopping the EA from instantly flip-flopping right after a
  stop-out. Off by default to match the standard builds' behavior.
- **Capped ladder sizing.** The equity-tiered order ladder is scaled down by
  two extra guards before any order is sent: `CapToRisk()` limits the worst
  case — the initial ATR stop being hit on *every* order — to
  `InpMaxRiskPct`% of equity (default `0` = no cap, matching the standard
  builds), and `CapToMargin()` uses `OrderCalcMargin` so the ladder always
  fits the free margin instead of silently partial-filling.
- **Verified exits.** `ClosePositions()` re-scans after closing and only
  clears the symbol's state when zero positions remain — a failed close
  (requote, market halt) is retried on the next M1 bar instead of allowing a
  fresh entry to stack on top of a live position.
- **Quiet, efficient operation.** Failed orders/modifies log their broker
  retcode, time-filter skip lines are deduplicated to one per episode (not
  one per minute), duplicate symbols in the watch list are ignored, and the
  trailing stop skips microscopic improvements (less than 0.3×ATR) to cut
  broker request volume.

The VPS builds carry their own magic numbers (`20260815` for H4-M1,
`20260814` for H1-M1), so they can run alongside the desktop builds and
each other on the same account. The [kihon suchi time-theory filter](#time-theory-filter-kihon-suchi)
code has been removed from the VPS builds entirely (no edge in A/B runs);
it lives only in the standard/experimental builds for testing.

### MT5 desktop builds (`*-mt5pc-ea.mq5`)

`ichimoku-h4-m1-mt5pc-ea.mq5` and `ichimoku-h1-m1-mt5pc-ea.mq5` are
byte-for-byte copies of the VPS builds' logic (same gating, exits, trail,
BE30, risk caps) with the desktop conveniences restored: `Alert()` popups on
every entry/exit and the weekly equity-withdrawal alert with its
`InpMinProfitTrigger` / `InpWithdrawProfitPct` / `InpCheckDay` /
`InpResetBaseline` / `InpSendPush` inputs. Use these on a normal
always-on desktop or laptop; use the VPS builds on the VPS.

### Deploying the VPS builds (`utilities/deploy.sh`)

`utilities/deploy.sh` downloads the two VPS EAs straight into the local MT5
`MQL5/Experts` folder — no copy-paste or clipboard needed (handy over VNC
where clipboard sync is flaky). Run it on the machine that runs MT5 (the
VPS):

```bash
# install once
curl -fsSL -o deploy.sh \
  https://raw.githubusercontent.com/n30dyn4m1c/ichimoku-h4-m1-align/master/utilities/deploy.sh
chmod +x deploy.sh

# every update — one command
./deploy.sh
```

- It auto-detects the MT5 Experts folder (searches under `$HOME` for
  `MQL5/Experts`, e.g. the Wine path `/home/neo/.wine/drive_c/Program
  Files/XM Global MT5/MQL5/Experts`). If detection fails or you have
  several terminals, point it at the right one:
  `MT5_DATA=/path/to/MQL5/Experts ./deploy.sh`.
- Optional branch argument: `./deploy.sh <branch>` downloads from that
  branch instead of `master`.
- After it finishes: in MetaEditor refresh the Navigator, press **F7** to
  compile both files, then remove and re-attach (or restart MT5) so the
  running EAs pick up the new `.ex5` builds.

#### Auto-deploy on push (`utilities/auto-deploy.sh`)

`deploy.sh` itself is manual — the VPS only knows about a push when you
run it. `utilities/auto-deploy.sh` turns that into a cron poll: it asks the
GitHub API for the latest commit SHA of the branch and runs `deploy.sh` only
when the SHA changes, so unchanged polls do nothing (no re-downloads).
It needs `deploy.sh` next to it.

```bash
# cron: poll every 5 minutes, deploy only when the repo changed
crontab -e
*/5 * * * * /home/neo/utilities/auto-deploy.sh >> /home/neo/auto-deploy.log 2>&1
```

Cron runs with a minimal environment — `curl`, `grep`, and `cut` are all
you need, and the scripts use absolute paths internally. Poll a specific
branch with `/home/neo/utilities/auto-deploy.sh <branch>`. The last-deployed
SHA is stored in `/tmp/last_deploy_sha` (override with `STATE_FILE=`).

> The compiled `.ex5` still needs the manual F7 + re-attach/restart step
> in MetaEditor — auto-deploy only drops the updated source into
> `MQL5/Experts/`; it cannot reload a running EA.

---

## MS-W1-D1 Alignment Build

`experiments/ichimoku-ms-w1-d1-ea.mq5` is a much slower, rarer variant aimed
at multi-week/month trend trades. Its alignment stack is only **MS → W1 → D1**
(monthly → weekly → daily, 3 timeframes from highest to lowest) — the full M1
stack is dropped because lower timeframes would veto almost every valid
signal. Key differences from the H4/H1 builds:

- **Entry:** all of MS, W1, and D1 must align (price + chikou vs tenkan,
  kijun, and cloud) on the last closed bar of each timeframe.
- **Exit:** `InpExitTF` Kijun cross against the trade direction (default D1;
  try W1 if you want to give trends more room). An ATR-based stop is computed
  on `InpATRTF` (default D1) rather than M15 — an M15 stop is meaningless for
  a multi-week hold.
- **Cadence:** gated once per new D1 bar close, so it's cheap to run and
  needs almost no attention.

Expect a handful of signals per year per symbol. Because it's so rare, the
**Python monitor** below is the recommended way to watch for the signal
instead of running the EA on a VPS; use the EA itself for backtesting
(Strategy Tester) and for automated execution once you trust the signal.

---

## MS-W1-D1 Signal Monitor (Python + GitHub Actions)

A daily, free monitor that computes the *exact same* MS→W1→D1 alignment from
independent daily OHLC data and pushes a Telegram message when it fires — no
VPS, no chart, no EA needed. Located in [`utilities/monitor/`](utilities/monitor/).

- **Symbols:** BTC/USD, ETH/USD, XAUUSD, XAGUSD, US100, US30, EURUSD,
  GBPUSD, USDJPY, AUDUSD, USDCAD — the FX list is limited to common trending
  majors (high-volatility crosses like GBPJPY are excluded; edit
  `utilities/monitor/config.py`).
- **Data:** Yahoo Finance daily bars via `yfinance`. Metals use the COMEX
  futures (`GC=F`, `SI=F`) as proxies for the XM spot symbols.
- **Logic:** `utilities/monitor/ichimoku.py` is a faithful port of
  `CheckAlign()` in
  the EA, including the chikou-offset handling — so the monitor and EA
  should agree on the signal. The Senkou (cloud) values are read at the same
  offsets the EA uses: the price-side cloud is the Senkou value computed
  Kijun rows before the last closed bar, and the cloud at the chikou's
  plotted position sits another Kijun rows further back (see the offset
  table below). Because of that chikou-side cloud read, a timeframe needs
  at least `SENKOU_B + 2 × KIJUN + 1` bars (105 for the default periods)
  before it can be evaluated — `HISTORY = "max"` in
  `utilities/monitor/config.py`
  covers that for every symbol on Yahoo.
- **Dedupe:** `state/state.json` remembers the last notified direction per
  symbol, so a signal that persists for weeks won't spam you daily. It only
  notifies on *new* alignments, direction flips, and clears.

### Run it

```bash
pip install -r utilities/monitor/requirements.txt
export TELEGRAM_BOT_TOKEN=...   # from @BotFather
export TELEGRAM_CHAT_ID=...     # your chat id
python utilities/monitor/monitor.py
```

### Or schedule it free on GitHub Actions

1. Push this repo to GitHub.
2. In repo **Settings → Secrets and variables → Actions**, add
   `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID`.
3. The workflow `.github/workflows/ms-w1-d1-monitor.yml` runs it daily at
   22:30 UTC automatically (also triggered manually via
   **Actions → MS-W1-D1 Ichimoku Monitor → Run workflow**).

The workflow persists the dedupe state between runs as a workflow artifact,
so the "only notify on change" behavior works across the ephemeral runners.

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

The Python monitor maps the same table onto its oldest→newest rows: row
`n-1` is bar 1, the price-side cloud is read at row `n-1-Kijun`, and the
chikou-side cloud at row `n-1-2×Kijun`.

### Time Theory Filter (Kihon Suchi)

> **Status: experimental — off by default.** The filter showed no performance
> edge in live/backtest A/B runs (entries were blocked without improving win
> quality), so all builds ship with `InpUseTimeFilter = false`. It remains
> available for testing: flip the input on to re-enable it and A/B it against
> the off setting on the same symbol/period before trusting it.

Both H4/H1 builds include an optional Ichimoku time-theory filter
(`InpUseTimeFilter`, default off): before entering on an aligned breakout,
the EA counts how many candles the current move has already printed on each
timeframe since the last touch of the Kijun-sen. If that count **exactly
equals** one of the kihon suchi cycle numbers — the classic
9 / 17 / 26 / 33 / 42 / 51 / 65 / 76 / 83 / 97 — the move is considered
"mature" and the breakout is skipped as low probability; between cycles
there is room for the move to continue to the next number.

- **Count definition:** consecutive closed bars whose whole range stayed on
  the move's side of the Kijun (above it for a long, below for a short); the
  first touch or side violation stops the count.
- **Cascade:** the anchor timeframe is checked first (H4 on the H4-M1 build,
  H1 on the H1-M1 build), then the next lower one, and so on down to the exit
  timeframe (M15 for H4-M1, M5 for H1-M1). A mature count anywhere in the
  chain blocks the entry. Each timeframe's check is gated by its own input
  flag (`InpTimeFilterH4` / `InpTimeFilterH1` / `InpTimeFilterM30` /
  `InpTimeFilterM15` / `InpTimeFilterM5`).
- **Cycle cap:** cycle numbers above 100 (`KIHON_MAX_CYCLE`) are ignored on
  every build — the classic 101 / 129 / 172 / 200 / 226 / 257 / 676 numbers in
  the default `InpTimeCycles` list are simply inert.
- **Testing note:** exact-match, no tolerance; consider adding ±1–2 bar
  tolerance and/or anchor-timeframe-only checks as test variants (the H1-M1
  reversion EA uses ±2).

### Exit Logic

- **H4-M1 build:** once the trade is in profit by at least
  `InpTrailActivateATR × ATR(M15)`, an **ATR chandelier trailing stop** takes
  over: the stop is re-computed on every new M1 bar as *highest high since
  entry − InpTrailATR × ATR(M15)* for longs (*lowest low + InpTrailATR ×
  ATR(M15)* for shorts), tracking the extreme of the M15 bar that is still
  forming so a peak is locked in before it retraces. It only ever tightens and
  never sits inside the broker's minimum stop distance. The **M15 Kijun-sen
  cross** against the trade direction remains as the final fallback exit for
  trades that never arm the trail.
- **H1-M1 build:** identical chandelier trail, but referenced to the **M5**
  bar extremes and `ATR(M5)`, with the **M5 Kijun-sen cross** as the fallback.

The trail's behavior is controlled by `InpTrailMode`:

| Mode | Value | Behavior |
|------|-------|----------|
| `TRAIL_OFF` | 0 | No trail — original Kijun-cross exit only |
| `TRAIL_ALWAYS` | 1 | Trail every profitable trade |
| `TRAIL_CHOPPY` | 2 (default) | Trail only when the market is choppy: ADX on the exit timeframe (M15 for H4-M1, M5 for H1-M1) below `InpChopADXLevel` (default 22) means no trend, so the trail is allowed; when ADX shows a trending market, the trail stands down and the Kijun-cross exit rides the trend. An already-armed trail stop stays in place when the regime flips to trending — it simply stops tightening and the Kijun exit takes over.

Independently of the trail and signal exit, every position carries an
**ATR(M15) × multiplier** stop loss to cap losses from fast adverse moves
between M15 closes.

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

The VPS builds add two more caps before the ladder is sent: `CapToRisk()` keeps the worst-case loss (the initial ATR stop hit on every order) at or below `InpMaxRiskPct`% of equity, and `CapToMargin()` shrinks the ladder until it fits the free margin so partial fills are the exception rather than the rule — see [VPS Deployment Builds](#vps-deployment-builds).

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

1. Download the build you want from this repository. For hands-on desktop trading use `ichimoku-h4-m1-mt5pc-ea.mq5` and/or `ichimoku-h1-m1-mt5pc-ea.mq5` (distinct magic numbers — you can run both). For unattended 24/7 deployment use the corresponding `ichimoku-h4-m1-vps-ea.mq5` / `ichimoku-h1-m1-vps-ea.mq5` variants instead or alongside them — all four builds can share one account — see [VPS Deployment Builds](#vps-deployment-builds).
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

The main builds share the same input set:

| Parameter | Default | Description |
|-----------|---------|--------------|
| `Symbols` | `GOLDm#` | Comma-separated list of symbols to watch (up to 60) |
| `Tenkan` | 9 | Ichimoku Tenkan-sen period |
| `Kijun` | 26 | Ichimoku Kijun-sen period |
| `SenkouB` | 52 | Ichimoku Senkou Span B period |
| `Slippage` | 30 | Maximum allowed slippage, in points |
| `InpUseStopLoss` | `true` | Attach an ATR-based stop loss to every entry |
| `InpATRPeriod` | 14 | ATR period, computed on M15 (on `InpATRTF` for the MS-W1-D1 build) |
| `InpATRMultiplier` | 3.0 | Stop distance = ATR × multiplier |
| `InpMaxSpreadPoints` | 60 | Max spread (points) to allow an entry; `0` disables the filter |
| `InpHighEquityRiskPct` | 1.0 | % of equity risked per trade once equity exceeds $8000 (see [Equity-Based Position Sizing](#equity-based-position-sizing)) |
| `InpMinProfitTrigger` | 5.0 | Minimum profit above baseline equity to trigger the weekly alert (MT5 desktop builds) |
| `InpWithdrawProfitPct` | 50.0 | Suggested withdrawal as a percentage of profit above baseline (MT5 desktop builds) |
| `InpCheckDay` | Friday | Day of week the equity alert is evaluated (MT5 desktop builds) |
| `InpResetBaseline` | `false` | Set to `true` once to reset the equity baseline to current equity (MT5 desktop builds) |
| `InpSendPush` | `true` | Send push notifications for alerts (entries, exits, equity alert) |
| `InpReentryCooldownSec` | 0 | Cooldown (seconds) after an exit before re-entering the same symbol — `0` disables (VPS builds) |
| `InpMaxRiskPct` | 0.0 | Cap the worst-case ladder loss (initial ATR stop hit on every order) as % of equity — `0` disables (VPS builds) |
| `InpTrailMode` | `TRAIL_CHOPPY` | 0 = off, 1 = always, 2 = choppy-only via ADX |
| `InpTrailATR` | 2.0 | Chandelier trail distance = ATR(M15) × multiplier for H4-M1, ATR(M5) × multiplier for H1-M1 |
| `InpTrailActivateATR` | 1.0 | Arm the trail once profit ≥ trail-timeframe ATR × multiplier |
| `InpADXPeriod` | 14 | ADX period for choppy-market detection (exit timeframe) |
| `InpChopADXLevel` | 22.0 | ADX below this = choppy → trail on in auto mode |
| `InpUseTimeFilter` | `false` | Skip entries when a TF move count exactly equals a kihon suchi cycle (see [Time Theory Filter](#time-theory-filter-kihon-suchi)) |
| `InpTimeCycles` | 9,17,…,676 | Kihon suchi cycle numbers; counts above 100 are ignored |
| `InpTimeFilterH4` / `InpTimeFilterH1` | `true` | Enable the anchor-timeframe cycle check (H4 build / H1 build) |
| `InpTimeFilterM30` / `InpTimeFilterM15` / `InpTimeFilterM5` | `true` | Enable the next cycle checks down the cascade |

> The VPS deployment builds replace the four equity-alert inputs and
> `InpSendPush` with `InpReentryCooldownSec` and `InpMaxRiskPct` instead —
> see [VPS Deployment Builds](#vps-deployment-builds).
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

**MS-W1-D1 Alignment EA:**

| Index | Timeframe | Role |
|-------|-----------|------|
| 0 | MS | Highest — trend anchor |
| 1 | W1 | Intermediate |
| 2 | D1 | Lowest — bar-gating and exit reference (default) |

The VPS deployment builds use exactly the same timeframe stacks as their
standard counterparts.

---

## Technical Notes

- **Magic numbers:** `20260815` (H4-M1 VPS), `20260814` (H1-M1 VPS),
  `20260830` (H4-M1 MT5 desktop), `20260831` (H1-M1 MT5 desktop) — each EA
  only identifies and manages its own positions by its magic
  number, so they won't interfere with other EAs, each other, or manual
  trades on the same account. All four main builds can run together.
- **State recovery:** on every tick, `SyncStateFromPositions()` rebuilds per-symbol direction state from currently open positions filtered by magic number. This means the EA recovers correctly after a terminal restart, VPS reboot, or a position closed manually/by stop loss — no stale state is left behind.
- **Per-symbol M1 gating:** each symbol only re-evaluates entry/exit logic once per newly closed M1 bar for that symbol, avoiding redundant checks on every tick.
- **Chikou Span handling:** the Chikou value is read directly from `close[1]` in price data rather than the Ichimoku buffer, avoiding an offset bug where reading Chikou from the indicator buffer silently degrades it into a lagged copy of the price check. See inline comments in `CheckAlign()` for the full offset derivation.

---

## Experimental EAs

All experimental strategies live in [`experiments/`](experiments/), each
prefixed `experimental-` to keep them clearly separate from the four main
builds at the repo root. The set includes a PO3-enhanced
variant of the H4-M1 alignment EA (`experimental-h4-m1-po3-ea.mq5`), an
Ichimoku time-theory mean-reversion EA (`experimental-h1-m1-reversion-ea.mq5`),
a fast M1-M5 breakout alignment EA (`experimental-m1-m5-breakout-ea.mq5`), a
shorter-anchor M30-M1 breakout alignment clone
(`experimental-m30-m1-breakout-ea.mq5`), an H4-M15 alignment clone that
trims the stack down to M15 (`experimental-h4-m15-align-ea.mq5`), a
Kijun-pullback variant of the H4-M1 build
(`experimental-h4-m1-pullback-ea.mq5`) that re-enters the trend when price
bounces off the H4 Kijun after a full-alignment breakout, two break-even
experiments — `experimental-h4-m1-be30-ea.mq5`, which moves the stop to
break even + a few points (spread cover) when a trade turns profitable
within 30 minutes of entry, and `experimental-h4-m1-be15-ea.mq5`, which
moves the stop to break even after the trade has been in profit
continuously for 15 minutes — plus alignment-filter pruning forks of both
VPS builds, breakout/hold experiments, and the older standard builds moved
to [`archives/`](archives/). They're newer and less battle-tested than the
main builds; see
**[experiments/EXPERIMENTAL-NOTES.md](experiments/EXPERIMENTAL-NOTES.md)**
for the full catalog.

> The per-symbol US30, Silver, and BTCUSD variants of the H4-H1 swing EA
> (`experimental-h4-h1-align-us30-ea.mq5`,
> `experimental-h4-h1-align-silver-ea.mq5`,
> `experimental-h4-h1-align-btc-ea.mq5`) were removed from the repo —
> their per-symbol tuning is superseded by the symbol-agnostic H4-H1
> builds (`experimental-h4-h1-align-ea.mq5`, the ignition EA, and the
> per-timeframe EA), which accept any symbol through the `Symbols` input.

The **MS-W1-D1 build** and its **Python + GitHub Actions monitor** — both new
and unbacktested — are also documented in
**experiments/EXPERIMENTAL-NOTES.md** (section 6) until they've
earned main-build status.

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
