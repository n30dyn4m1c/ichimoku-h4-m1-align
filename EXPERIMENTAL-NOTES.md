# Experimental EAs

Strategies here are **experimental** — newer, less battle-tested than the two
main alignment EAs, and shipped for research and demo testing. Backtest and
forward-test on a demo account before risking capital. See the top-level
[Disclaimer](README.md#️-disclaimer).

All experimental EA files are prefixed `experimental-` so they're easy to
tell apart from the two main builds at a glance.

---

## 1. H4-M1 PO3 Alignment EA

**File:** `experimental-h4-m1-po3-ea.mq5`
**Magic number:** `20260502`

The same 6-timeframe (H4→M1) Ichimoku alignment entry as the main
[H4-M1 EA](README.md#entry-logic), extended with **PO3
dealing-range** location filters (the power-of-three price-level concept by
Hopiplaka) for entry gating and tiered take-profits. Ichimoku decides *when*
to trade; PO3 decides *whether the location is worth it* and *how far to
hold*.

### PO3 dealing ranges

A fixed grid of power-of-three price levels: every multiple of `3^n ×
InpPO3Unit`. On gold with `InpPO3Unit = 1.0` the base grid (`3^4 = 81`) is
…3888, 3969, 4050, 4131…; a level whose multiple carries a higher power of 3
outranks its neighbours (3888 = 16 × 3⁵ is a 243-grade level, 4374 = 2 × 3⁷ a
2187-grade one). The dealing range containing price is `floor(price / step)
× step` to that plus `step`; its midpoint is **equilibrium**, the lower half
**discount**, the upper half **premium**.

- **Bias filter** (`InpPO3BiasFilter`): if the recent H4 extreme (`InpPO3BiasBars`
  bars, default 180) tagged or raided a major level (`3^InpPO3BiasPower`,
  default 729-grade, within `InpPO3BiasTolFrac` of the base rung) and price
  was rejected away from it, entries *against* that rejection are blocked
  until price reclaims the level or an opposite-side tag supersedes it.
- **Room filter** (`InpPO3RoomFilter`): an entry is skipped when the first
  strong level (`3^InpPO3StrongPower`, default 243-grade) ahead in the trade
  direction is closer than `InpPO3MinRR ×` the ATR stop distance — no buying
  into a ceiling, no selling into a floor.
- **Tiered take-profits**: half of each order batch targets **TP1**, the
  nearest base rung worth at least `InpPO3MinRR` R; the other half targets
  **TP2**, the nearest strong level beyond TP1. Both are front-run by
  `InpPO3BufferATR × ATR(M15)` since price often stalls just short of a
  level. A tier with no qualifying level within `InpPO3MaxRR` R gets no TP —
  those orders stay runners managed by the M15 Kijun exit.

Entry alerts include the PO3 context, e.g. `PO3 243[3888-4131] 39% discount |
TP1 3890.12 TP2 runner`. For non-gold symbols set `InpPO3Unit` to the
instrument's convention (e.g. `0.0001` for 5-digit FX pairs so a 243 range
spans 0.0243; `0.01` for a cents-based intraday grid on metals).

### Exit logic

Orders that reached their PO3 take-profit close there. Everything remaining
is closed when the M15 close crosses the M15 Kijun-sen against the trade's
direction (long closes below the M15 Kijun, short closes above it).
Independently of that signal exit, every position carries an `ATR(M15) ×
InpATRMultiplier` stop loss.

### PO3 inputs

| Parameter | Default | Description |
|-----------|---------|--------------|
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

All other inputs (Ichimoku periods, risk protection, equity sizing, equity
alert) are identical to the [main H4-M1 EA](README.md#configuration-inputs).

### Status & caveats

- Distinct magic number (`20260502`, vs. `20260501` for the base H4-M1 EA) so
  the two can run on the same account/symbol without colliding.
- The PO3 grid is a fixed, hand-picked price scale — it needs to be tuned per
  instrument (`InpPO3Unit`) and re-checked if a symbol's price range shifts
  materially over time.

---

## 2. H1-M1 Time-Theory Reversion EA

**File:** `experimental-h1-m1-reversion-ea.mq5`
**Magic number:** `20260722` (runs independently of the other EAs)

A **mean-reversion** EA — the logical opposite of the trend/alignment builds. It
fades an over-extended H1 Ichimoku trend back to a flat Kijun, timed by Ichimoku
*time theory* and triggered by lower-timeframe momentum or a liquidity-raid
rejection candle. Run it on its own instance; don't mix it with the alignment
logic on the same symbol (the two would fight each other).

### Core idea

After price has trended away and stayed **off the H1 Kijun for one of the
Ichimoku time cycles** (9, 17, 26 or 33 bars, ±2) while the **Kijun has gone
flat**, the extended move is "due" to snap back. The flat Kijun becomes a magnet;
the trade is taken *toward* it, *against* the prevailing trend.

---

### Entry — all gates must pass (checked per new M1 bar, per symbol)

Evaluated in `CheckReversion()`. The trade bails the moment any gate fails.

| # | Gate | Rule | Input(s) |
|---|------|------|----------|
| 1 | **Extension** | Last H1 close is ≥ `InpFarATRMult × ATR(H1)` from the Kijun. Above ⇒ **sell** back down; below ⇒ **buy** back up (sets direction). | `InpFarATRMult` |
| 2 | **Trend to fade** | The reversion fires only *against* an established H1 Ichimoku trend: a **sell** needs a **bullish** H1 trend (close above the Kumo **and** Tenkan > Kijun); a **buy** needs the bearish mirror. | `InpUseTrendFilter` |
| 3 | **Time theory** | Consecutive H1 candles since the last Kijun touch (the "break away") must equal an Ichimoku cycle — `9, 17, 26, 33` ± tolerance. A "touch" = the Kijun inside a candle's high–low; the count resets to 0 on any touch, so streaks *between* cycles (13, 30, …) don't qualify, and a streak longer than every window is rejected too. | `InpTimeCycles`, `InpTimeTol` |
| 4 | **Flat Kijun** | Kijun's move over the last `InpFlatBars` H1 bars ≤ `InpFlatATRMult × ATR(H1)`. | `InpFlatBars`, `InpFlatATRMult` |
| 5 | **A trigger fires** | Either trigger below (both configurable). | see below |

**Trigger A — M5 Kijun cross** (`InpUseM5Cross`)
A *fresh* M5 close cross of the M5 Kijun in the reversion direction (the H1
"breakout close" confirmation on the lower timeframe). For a sell: the prior
closed M5 bar was at/above the M5 Kijun and the last closed M5 bar is below it.

**Trigger B — Rejection candle raiding liquidity** (`InpUseRejection`)
The last closed H1 candle is a **long-wicked, small-body** candle (wick ≥
`InpRejWickFrac` of range, body ≤ `InpRejBodyFrac`) whose wick **raids an
unliquidated fractal swing** and closes back inside it. Swing liquidity is mapped
across three timeframes, checked **Daily → H4 → H1**; a raid of any one qualifies:

| Timeframe | Bars scanned | Input |
|-----------|--------------|-------|
| Daily | 50 | `InpRaidBarsD1` |
| H4 | 300 | `InpRaidBarsH4` |
| H1 | 500 | `InpRaidBarsH1` |

- A **swing point** is a fractal high/low with `InpSwingWing` lower/higher bars on each side.
- **Raid + reject**: the H1 rejection wick pokes *beyond* the level and the close comes back *inside* it.
- **Unliquidated** (`InpRequireUnraided`, default on): no more-recent closed bar *on that timeframe* has exceeded the level since it formed — the resting liquidity is still there. Set a timeframe's bar count to `0` to disable it.

---

### Exit & stop management

- **Take profit** — the **H1 Kijun** (the reversion target), fixed at entry, attached to the order. A setup whose Kijun is inside the broker's minimum stop distance is skipped.
- **Initial stop (Stage 1)** — the **H1 signal candle's own extreme** (its high for a sell, low for a buy) + `InpSLBufferATR × ATR(H1)`, widened to the broker minimum if needed. A tight stop just past the rejection/raid wick ⇒ **small risk**.
- **M15 Kijun trail (Stage 2)** — once a **closed M15 candle prints clearly beyond the M15 Kijun** in the trade direction ("clearly" = ≥ `InpM15ClearATR × ATR(M15)` past it), the stop is moved to the **M15 Kijun** itself, padded by `InpM15SLBufferATR × ATR(M15)`. It re-evaluates each new M15 bar — following the Kijun as it drifts — **only ever tightens** (a short's stop only moves down, a long's up), and never sits inside the broker minimum.

---

### Risk sizing

Identical equity-scaled sizing to the alignment EAs — `GetEquityRisk()`
picks order count and lot size from account equity; above $8000 `RiskBasedLots()`
sizes so the initial stop risks `InpHighEquityRiskPct`% of equity across the
batch. Because the initial stop is tight, the same % risk buys a larger position
than a wide swing stop would.

---

### Full setup at a glance (sell example)

```
Trend up (price above Kumo, Tenkan > Kijun)
   └─ price ≥ 2·ATR(H1) above a FLAT Kijun
        └─ 9 / 17 / 26 / 33 H1 candles (±2) since last Kijun touch
             └─ trigger: M5 Kijun cross down  OR  H1 rejection candle
                         raiding an unraided D1/H4/H1 swing HIGH
                  └─ SELL
                     • TP  = H1 Kijun
                     • SL  = H1 signal-candle high (tight)
                     • then M15 closes clearly below M15 Kijun
                          → trail SL to the M15 Kijun (padded)
                          → keep tightening each M15 bar as it drifts
```

Buy setups are the exact mirror (downtrend, price below the Kijun, swing lows,
M5 cross up, M15 closes above the M15 Kijun).

---

### Key inputs

| Group | Parameter | Default | Purpose |
|-------|-----------|---------|---------|
| Setup | `InpFarATRMult` | 2.0 | "Far from Kijun" threshold (× ATR H1) |
| Setup | `InpUseTrendFilter` | `true` | Only fade an established H1 Ichimoku trend |
| Setup | `InpTimeCycles` / `InpTimeTol` | `9,17,26,33` / 2 | Ichimoku time cycles (bars since last touch) ± tolerance |
| Setup | `InpFlatBars` / `InpFlatATRMult` | 5 / 0.25 | Flat-Kijun window and tolerance |
| Triggers | `InpUseM5Cross` | `true` | Enable the M5 Kijun-cross trigger |
| Triggers | `InpUseRejection` | `true` | Enable the liquidity-raid rejection trigger |
| Triggers | `InpRejWickFrac` / `InpRejBodyFrac` | 0.55 / 0.35 | Rejection candle wick/body shape |
| Triggers | `InpRaidBarsD1/H4/H1` | 50 / 300 / 500 | Swing-liquidity scan depth per timeframe (0 = off) |
| Triggers | `InpSwingWing` | 2 | Fractal half-width for raid swings |
| Triggers | `InpRequireUnraided` | `true` | Require resting (unliquidated) liquidity |
| Stops | `InpSLBufferATR` | 0.10 | Initial-stop padding (× ATR H1) |
| Stops | `InpM15ClearATR` | 0.1 | "Clearly beyond M15 Kijun" buffer (× ATR M15) |
| Stops | `InpM15SLBufferATR` | 0.1 | Trailed-stop padding beyond the M15 Kijun (× ATR M15) |
| Risk | `InpATRPeriod` | 14 | ATR period (H1 and M15) |
| Risk | `InpMaxSpreadPoints` | 60 | Spread filter (0 = off) |
| Risk | `InpHighEquityRiskPct` | 1.0 | % equity risked per trade above $8000 |

The equity/alert inputs (`InpMinProfitTrigger`, `InpWithdrawProfitPct`,
`InpCheckDay`, `InpResetBaseline`, `InpSendPush`) are the same as the main
EAs — see the [README](README.md#configuration-inputs).

---

### Status & caveats

- **Not yet compiled/backtested here** — needs an F7 compile in MetaEditor and a Strategy-Tester + demo run before live use.
- **"Unliquidated" is judged at each timeframe's own resolution** — a daily level is "untouched" if no later *daily* bar's high exceeded it; an intraday poke within the still-forming daily bar isn't captured at daily resolution.
- **Trend filter vs. flat Kijun** — compatible by design (a strong extension where price ran away and the Kijun flattened underneath), but if live setups get filtered out because the Kijun is still gently sloping, loosen `InpFlatATRMult`.
- **M15 trail** — the Stage-2 stop trails to the **M15 Kijun** (padded), re-evaluated each M15 bar and tightening only; it does not use M15 fractal swings.

---

## 3. M1-M5 Breakout Alignment EA

**File:** `experimental-m1-m5-breakout-ea.mq5`
**Magic number:** `20260717`

A fast, 2-timeframe variant of the alignment idea: instead of requiring
agreement across six timeframes down to H4, it only requires **M5 and M1**
to align, but demands each close clear the cloud by a minimum ATR distance
so marginal breakouts that merely graze the cloud edge don't qualify.
Designed for quicker, more frequent signals than the main EAs at the cost of
a much shorter-term (and noisier) trend anchor.

### Entry logic

Runs on every new M1 bar close, per symbol. `CheckAlign()` on each of M5 and
M1 requires price *and* Chikou above/below Tenkan, Kijun, and the cloud —
same rule table as the main EAs (see [README](README.md#entry-logic)) — plus
a breakout-strength buffer: the close must clear the cloud by at least
`InpMinBreakoutATR × ATR(tf)` on that timeframe (each of M5 and M1 uses its
own ATR), not merely sit on the other side of it. Set `InpMinBreakoutATR = 0`
to disable the buffer and accept a bare cloud break. If the buffer is
enabled but the ATR value isn't available, the signal is skipped entirely
rather than trading unfiltered. A trade opens only when **both M5 and M1**
agree on direction and no position is already open on that symbol.

### Exit logic

All positions close when the M5 close crosses the M5 Kijun-sen against the
trade's direction (long closes below the M5 Kijun, short closes above it).
Independently, every position carries an `ATR(M1) × InpATRMultiplier` stop
loss (note: ATR is computed on **M1** here, not M15 as in the main EAs).

### Risk protection & equity sizing

Identical `InpUseStopLoss` / `InpMaxSpreadPoints` / `InpHighEquityRiskPct`
risk protection and the same `GetEquityRisk()` equity-tiered position sizing
as the main EAs — see [README](README.md#equity-based-position-sizing).

### Inputs

| Parameter | Default | Description |
|-----------|---------|--------------|
| `Symbols` | `GOLDm#` | Comma-separated list of symbols to watch (up to 60) |
| `Tenkan` / `Kijun` / `SenkouB` | 9 / 26 / 52 | Ichimoku periods |
| `Slippage` | 30 | Maximum allowed slippage, in points |
| `InpMinBreakoutATR` | 0.5 | Min close distance beyond the cloud, in ATR multiples per timeframe (`0` = off) |
| `InpUseStopLoss` | `true` | Attach an ATR(M1)-based stop loss to every entry |
| `InpATRPeriod` | 14 | ATR period, computed on M1 |
| `InpATRMultiplier` | 3.0 | Stop distance = ATR(M1) × multiplier |
| `InpMaxSpreadPoints` | 60 | Max spread (points) to allow an entry; `0` disables |
| `InpHighEquityRiskPct` | 1.0 | % of equity risked per trade once equity exceeds $8000 |

The equity/alert inputs (`InpMinProfitTrigger`, `InpWithdrawProfitPct`,
`InpCheckDay`, `InpResetBaseline`, `InpSendPush`) are the same as the main
EAs — see the [README](README.md#configuration-inputs).

### Technical notes

- **Magic number:** `20260717` — independent from the other EAs, so it can run alongside them without interfering.
- **State recovery:** `SyncStateFromPositions()` rebuilds per-symbol direction state from open positions filtered by magic number on every tick, same as the main EAs.
- **Per-symbol M1 gating:** each symbol only re-evaluates entry/exit logic once per newly closed M1 bar.

### Status & caveats

- Shortest-timeframe anchor of all the EAs in this repo (M5, vs. H1 or H4 for
  the others) — expect more signals, more noise, and a stop/exit cadence
  tuned for fast moves rather than sustained trends.
- Not yet extensively backtested here — run it in the Strategy Tester and on
  demo before considering live capital.

---

## 4. M30-M1 Breakout Alignment EA

**File:** `experimental-m30-m1-breakout-ea.mq5`
**Magic number:** `20260723`

A shorter-anchor clone of the main [H1-M1 alignment EA](README.md#entry-logic).
It runs the **exact same** 4-of-4 Ichimoku alignment entry and M5 Kijun exit,
but drops the top timeframe: instead of aligning **H1→M1** it aligns
**M30→M1**. This is a **trend/breakout alignment** build (all timeframes must
agree in one direction) — *not* a reversion EA.

### Entry logic

Runs on every new M1 bar close, per symbol. `CheckAlign()` on each of **M30,
M15, M5, M1** requires price *and* Chikou above/below Tenkan, Kijun, and the
cloud — the same rule table as the main EAs (see
[README](README.md#entry-logic)). A trade opens only when **all four
timeframes** agree on direction and no position is already open on that symbol.
Because the highest anchor is M30 rather than H1, setups form and clear faster
than the main H1-M1 build.

### Exit logic

All positions close when the **M5 close crosses the M5 Kijun-sen** against the
trade's direction (long closes below the M5 Kijun, short closes above it) —
identical to the H1-M1 EA's exit. Independently, every position carries an
`ATR(M15) × InpATRMultiplier` stop loss.

### Risk protection & equity sizing

Identical `InpUseStopLoss` / `InpMaxSpreadPoints` / `InpHighEquityRiskPct`
risk protection and the same `GetEquityRisk()` equity-tiered position sizing
as the main EAs — see [README](README.md#equity-based-position-sizing). ATR is
computed on **M15** (as in the H1-M1 EA), not M1.

### Inputs

| Parameter | Default | Description |
|-----------|---------|--------------|
| `Symbols` | `GOLDm#` | Comma-separated list of symbols to watch (up to 60) |
| `Tenkan` / `Kijun` / `SenkouB` | 9 / 26 / 52 | Ichimoku periods |
| `Slippage` | 30 | Maximum allowed slippage, in points |
| `InpUseStopLoss` | `true` | Attach an ATR(M15)-based stop loss to every entry |
| `InpATRPeriod` | 14 | ATR period, computed on M15 |
| `InpATRMultiplier` | 3.0 | Stop distance = ATR(M15) × multiplier |
| `InpMaxSpreadPoints` | 60 | Max spread (points) to allow an entry; `0` disables |
| `InpHighEquityRiskPct` | 1.0 | % of equity risked per trade once equity exceeds $8000 |

The equity/alert inputs (`InpMinProfitTrigger`, `InpWithdrawProfitPct`,
`InpCheckDay`, `InpResetBaseline`, `InpSendPush`) are the same as the main
EAs — see the [README](README.md#configuration-inputs).

### Technical notes

- **Magic number:** `20260723` — independent from the other EAs, so it can run alongside them without interfering.
- **State recovery:** `SyncStateFromPositions()` rebuilds per-symbol direction state from open positions filtered by magic number on every tick, same as the main EAs.
- **Per-symbol M1 gating:** each symbol only re-evaluates entry/exit logic once per newly closed M1 bar; the weekly equity alert is gated on a new **M30** bar (the highest timeframe present).

### Status & caveats

- Shorter trend anchor than the main H1-M1 EA (M30 vs. H1) — expect more
  frequent signals and a faster exit cadence, at the cost of a noisier
  top-timeframe trend filter.
- Not yet extensively backtested here — run it in the Strategy Tester and on
  demo before considering live capital.
