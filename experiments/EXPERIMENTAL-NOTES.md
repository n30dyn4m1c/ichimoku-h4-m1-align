# Experimental EAs

Strategies here are **experimental** — newer, less battle-tested than the two
main alignment EAs, and shipped for research and demo testing. Backtest and
forward-test on a demo account before risking capital. See the top-level
[Disclaimer](../README.md#️-disclaimer).

All experimental EA files are prefixed `experimental-` so they're easy to
tell apart from the two main builds at a glance. The MS-W1-D1 build (section
6) is an exception: it lives in the main README table but is new and
unbacktested, so it's documented and tracked here alongside the
experimental builds until it has earned main-build status.

> **Promoted, 2026-08-18.** The **H1-bias bottom-up stack** (section 20) is no
> longer only an experiment — it is now the code behind both main builds,
> `ichimoku-h4-m1-vps-ea.mq5` (magic `20260850`) and
> `ichimoku-h4-m1-mt5pc-ea.mq5` (magic `20260852`). The top-down alignment
> builds it replaced are in [`archives/`](../archives/). The experimental
> file stays here as the reference copy and as the parent of the D1-ladder
> fork (section 21); the main builds are where changes to the live strategy
> now belong.

> **Promoted, 2026-08-20.** The **M1-strict cloud-bias build** (section 26) is
> now the code behind both main builds, `ichimoku-h4-m1-vps-ea.mq5` (magic
> `20260858`) and `ichimoku-h4-m1-mt5pc-ea.mq5` (magic `20260860`) — the most
> profitable iteration of the cloud-bias experiment so far (user report
> 2026-08-20, $100 → $14000 on Jan–Aug 2026 data). The bottom-up bias-stack
> builds it replaced are in [`archives/`](../archives/) as the
> `-archived20260820` pair. The experimental file stays here as the
> reference copy.

---

## 1. H4-M1 PO3 Alignment EA

**File:** `experimental-h4-m1-po3-ea.mq5`
**Magic number:** `20260502`

The same 6-timeframe (H4→M1) Ichimoku alignment entry as the main
[H4-M1 EA](../README.md#entry-logic), extended with **PO3
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
alert) are identical to the [main H4-M1 EA](../README.md#configuration-inputs).

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
EAs — see the [README](../README.md#configuration-inputs).

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
same rule table as the main EAs (see [README](../README.md#entry-logic)) — plus
a breakout-strength buffer: the close must clear the cloud by at least
`InpMinBreakoutATR × ATR(tf)` on that timeframe (each of M5 and M1 uses its
own ATR), not merely sit on the other side of it. Set `InpMinBreakoutATR = 0`
to disable the buffer and accept a bare cloud break. If the buffer is
enabled but the ATR value isn't available, the signal is skipped entirely
rather than trading unfiltered. A trade opens only when **both M5 and M1**
agree on direction and no position is already open on that symbol.

### Exit logic

Every position carries an `ATR(M1) × InpATRMultiplier` stop loss (note: ATR
is computed on **M1** here, not M15 as in the main EAs). Once a trade is in
profit by at least `InpTrailActivateATR × ATR(M5)`, an **ATR chandelier
trailing stop** takes over: the stop is re-computed every new M1 bar as
`highest high since entry − InpTrailATR × ATR(M5)` for longs (`lowest low +
InpTrailATR × ATR(M5)` for shorts), using the extreme of the M5 bar that is
still forming so a peak is locked in before it retraces. The trail only ever
tightens and never sits inside the broker's minimum stop distance. Its
behavior is set by `InpTrailMode`: `0` disables the trail entirely (the
original Kijun-only exit), `1` trails every profitable trade, and `2`
(default) trails only when the market is choppy — ADX(M5) below
`InpChopADXLevel` (default 22) — standing down in trending markets so the M5
kijun-cross close rides the trend. The M5 kijun-cross close remains as the
final fallback exit for trades that never arm the trail.

### Risk protection & equity sizing

Identical `InpUseStopLoss` / `InpMaxSpreadPoints` / `InpHighEquityRiskPct`
risk protection and the same `GetEquityRisk()` equity-tiered position sizing
as the main EAs — see [README](../README.md#equity-based-position-sizing).

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
| `InpTrailMode` | `TRAIL_CHOPPY` | 0 = off, 1 = always, 2 = choppy-only via ADX(M5) |
| `InpTrailATR` | 2.0 | Chandelier trail distance = ATR(M5) × multiplier |
| `InpTrailActivateATR` | 1.0 | Arm the trail once profit ≥ ATR(M5) × multiplier |
| `InpADXPeriod` | 14 | ADX period for choppy-market detection (M5) |
| `InpChopADXLevel` | 22.0 | ADX below this = choppy → trail on in auto mode |

The equity/alert inputs (`InpMinProfitTrigger`, `InpWithdrawProfitPct`,
`InpCheckDay`, `InpResetBaseline`, `InpSendPush`) are the same as the main
EAs — see the [README](../README.md#configuration-inputs).

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

A shorter-anchor clone of the main [H1-M1 alignment EA](../README.md#entry-logic).
It runs the **exact same** 4-of-4 Ichimoku alignment entry and M5 Kijun exit,
but drops the top timeframe: instead of aligning **H1→M1** it aligns
**M30→M1**. This is a **trend/breakout alignment** build (all timeframes must
agree in one direction) — *not* a reversion EA.

### Entry logic

Runs on every new M1 bar close, per symbol. `CheckAlign()` on each of **M30,
M15, M5, M1** requires price *and* Chikou above/below Tenkan, Kijun, and the
cloud — the same rule table as the main EAs (see
[README](../README.md#entry-logic)). A trade opens only when **all four
timeframes** agree on direction and no position is already open on that symbol.
Because the highest anchor is M30 rather than H1, setups form and clear faster
than the main H1-M1 build.

### Exit logic

Every position carries an `ATR(M15) × InpATRMultiplier` stop loss. Once a
trade is in profit by at least `InpTrailActivateATR × ATR(M5)`, an **ATR
chandelier trailing stop** takes over: the stop is re-computed every new M1
bar as `highest high since entry − InpTrailATR × ATR(M5)` for longs (`lowest
low + InpTrailATR × ATR(M5)` for shorts), using the extreme of the M5 bar
that is still forming so a peak is locked in before it retraces. The trail
only ever tightens and never sits inside the broker's minimum stop distance.
Its behavior is set by `InpTrailMode`: `0` disables the trail entirely (the
original Kijun-only exit), `1` trails every profitable trade, and `2`
(default) trails only when the market is choppy — ADX(M5) below
`InpChopADXLevel` (default 22) — standing down in trending markets so the M5
kijun-cross close rides the trend. The M5 kijun-cross close remains as the
final fallback exit for trades that never arm the trail.

### Risk protection & equity sizing

Identical `InpUseStopLoss` / `InpMaxSpreadPoints` / `InpHighEquityRiskPct`
risk protection and the same `GetEquityRisk()` equity-tiered position sizing
as the main EAs — see [README](../README.md#equity-based-position-sizing). ATR is
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
| `InpTrailMode` | `TRAIL_CHOPPY` | 0 = off, 1 = always, 2 = choppy-only via ADX(M5) |
| `InpTrailATR` | 2.0 | Chandelier trail distance = ATR(M5) × multiplier |
| `InpTrailActivateATR` | 1.0 | Arm the trail once profit ≥ ATR(M5) × multiplier |
| `InpADXPeriod` | 14 | ADX period for choppy-market detection (M5) |
| `InpChopADXLevel` | 22.0 | ADX below this = choppy → trail on in auto mode |

The equity/alert inputs (`InpMinProfitTrigger`, `InpWithdrawProfitPct`,
`InpCheckDay`, `InpResetBaseline`, `InpSendPush`) are the same as the main
EAs — see the [README](../README.md#configuration-inputs).

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

---

## 5. H4-M15 Alignment EA

**File:** `experimental-h4-m15-align-ea.mq5`
**Magic number:** `20260724`

A trimmed clone of the main [H4-M1 EA](../README.md#entry-logic) that keeps the
same H4 top anchor but stops the alignment at **M15** — it aligns **H4, H1,
M30, M15** and **disregards M5 and M1**. The idea is to keep the multi-hour
trend context of the H4-M1 build while cutting out the two lowest, noisiest
timeframes, so entries fire on a cleaner 4-timeframe agreement rather than
waiting for a full 6-timeframe stack down to M1.

### Entry logic

Runs on every new **M15** bar close, per symbol. `CheckAlign()` on each of
**H4, H1, M30, M15** requires price *and* Chikou above/below Tenkan, Kijun,
and the cloud — the same rule table as the main EAs (see
[README](../README.md#entry-logic)). A trade opens only when **all four
timeframes** agree on direction and no position is already open on that
symbol. Because M5 and M1 no longer have to line up, setups clear the entry
filter sooner than the full H4-M1 stack.

### Exit logic

Identical to the H4-M1 EA: all positions close when the **M15 close crosses
the M15 Kijun-sen** against the trade's direction (long closes below the M15
Kijun, short closes above it). Independently, every position carries an
`ATR(M15) × InpATRMultiplier` stop loss — the **same SL logic** as the main
H4-M1 build.

### Risk protection & equity sizing

**Same risk as the H4-M1 EA** — identical `InpUseStopLoss` /
`InpMaxSpreadPoints` / `InpHighEquityRiskPct` risk protection and the same
`GetEquityRisk()` equity-tiered position sizing (see
[README](../README.md#equity-based-position-sizing)). ATR is computed on **M15**,
exactly as in the H4-M1 EA.

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
EAs — see the [README](../README.md#configuration-inputs).

### Technical notes

- **Magic number:** `20260724` — independent from the other EAs, so it can run alongside them (including the base H4-M1 EA) without interfering.
- **State recovery:** `SyncStateFromPositions()` rebuilds per-symbol direction state from open positions filtered by magic number on every tick, same as the main EAs.
- **Per-symbol M15 gating:** each symbol only re-evaluates entry/exit logic once per newly closed **M15** bar (the lowest timeframe in the alignment set, vs. M1 in the H4-M1 EA); the weekly equity alert is still gated on a new **H4** bar.

### Status & caveats

- Fewer timeframes to satisfy than the main H4-M1 EA (4 vs. 6) and a
  coarser entry cadence (M15 bars vs. M1) — expect somewhat earlier, more
  frequent entries, without the fine M5/M1 timing confirmation.
- Not yet extensively backtested here — run it in the Strategy Tester and on
  demo before considering live capital.

---

## 6. MS-W1-D1 Alignment EA (and companion Python monitor)

**File:** `ichimoku-ms-w1-d1-ea.mq5`
**Magic number:** `20260806`

The slowest, rarest member of the family. Instead of aligning down to M1, it
requires **only three timeframes — MS (monthly) → W1 (weekly) → D1 (daily),
highest to lowest** — to agree. It targets multi-week/month trend trades, so
lower timeframes (H4 down to M1) are deliberately dropped: they would veto
almost every valid signal. Expect a handful of signals per year per symbol.

Because the signal is so rare, the companion **Python monitor** below is the
recommended way to watch for it (no VPS, no chart, no EA running) — use the EA
itself for backtesting in the Strategy Tester and for automated execution once
you trust the signal.

### Entry logic

`CheckAlign()` on each of MS, W1, and D1 requires price *and* Chikou above/
below Tenkan, Kijun, and the cloud — the same rule table as the main EAs (see
[README](../README.md#entry-logic)). A trade opens only when **all three
timeframes** agree on direction, no position is open on the symbol, and the
live spread passes `InpMaxSpreadPoints`. The stack and gating:

| Index | Timeframe | Role |
|-------|-----------|------|
| 0 | MS (PERIOD_MN1) | Highest — trend anchor |
| 1 | W1 | Intermediate |
| 2 | D1 | Lowest — bar-gating and exit reference (default) |

### Exit logic

All positions close when the close crosses the Kijun-sen **against** the trade
direction on `InpExitTF` (default **D1**; set it to **W1** to give trends more
room). Independently, every position carries an
`ATR(InpATRTF) × InpATRMultiplier` stop loss — `InpATRTF` defaults to **D1**
(an M15 stop is meaningless for a multi-week hold).

### Inputs

| Parameter | Default | Description |
|-----------|---------|--------------|
| `Symbols` | `GOLDm#` | Comma-separated list of symbols to watch (up to 60) |
| `Tenkan` / `Kijun` / `SenkouB` | 9 / 26 / 52 | Ichimoku periods |
| `Slippage` | 30 | Maximum allowed slippage, in points |
| `InpUseStopLoss` | `true` | Attach an ATR-based stop loss to every entry |
| `InpATRPeriod` | 14 | ATR period, computed on `InpATRTF` |
| `InpATRTF` | `PERIOD_D1` | ATR timeframe for the stop distance |
| `InpATRMultiplier` | 3.0 | Stop distance = ATR × multiplier |
| `InpExitTF` | `PERIOD_D1` | Exit when close crosses kijun on this TF (D1 or W1) |
| `InpMaxSpreadPoints` | 60 | Max spread (points) to allow an entry; `0` disables |
| `InpHighEquityRiskPct` | 1.0 | % of equity risked per trade once equity exceeds $8000 |
| `InpReentryCooldownSec` | 0 | Min seconds after an exit before re-entering the same symbol |

The equity/alert inputs (`InpMinProfitTrigger`, `InpWithdrawProfitPct`,
`InpCheckDay`, `InpResetBaseline`, `InpSendPush`) are the same as the main
EAs — see the [README](../README.md#configuration-inputs).

### Technical notes

- **Magic number:** `20260806` — independent from the other EAs.
- **State recovery:** `SyncStateFromPositions()` rebuilds per-symbol direction
  state from open positions filtered by magic number on every tick, same as
  the main EAs.
- **Per-symbol D1 gating:** each symbol only re-evaluates entry/exit logic
  once per newly closed **D1** bar (the lowest timeframe in the alignment
  set); the weekly equity alert is gated on a new D1 bar.
- **Backtesting:** test per-symbol in the Strategy Tester (set `Symbols` to a
  single symbol). Verify the monitor and EA agree on historical signals before
  trusting either.

### Status & caveats

- Very rare signals by design — a few per year per symbol. Do not judge it by
  trade count; the edge is a small number of large multi-week/month winners.
- The strict chikou condition (chikou must clear the reference candle's
  high/low 26 bars back) filters heavily even during clean trends — expect
  the monitor to read unaligned on many days where price looks "obviously"
  trending.
- ATR computed on D1 by default; if backtests show stops being hit in normal
  pullbacks, raise `InpATRMultiplier` before loosening the exit timeframe.

### Companion monitor (Python + GitHub Actions, no VPS)

A daily, free monitor that computes the *exact same* MS→W1→D1 alignment from
independent daily OHLC data and pushes a **Telegram** message when it fires —
no VPS, no chart, no EA needed. Located in `utilities/monitor/`, documented in the
[README](../README.md#ms-w1-d1-signal-monitor-python--github-actions).

- **Symbols:** BTC/USD, ETH/USD, XAUUSD, XAGUSD, US100, US30, EURUSD,
  GBPUSD, USDJPY, AUDUSD, USDCAD (edit `utilities/monitor/config.py`). The FX list is
  limited to common trending majors — high-volatility crosses like GBPJPY are
  deliberately excluded.
- **Data:** Yahoo Finance daily bars via `yfinance`; metals use the COMEX
  futures (`GC=F`, `SI=F`) as proxies for the XM spot symbols because Yahoo's
  spot symbols are delisted.
- **Logic:** `utilities/monitor/ichimoku.py` is a faithful port of `CheckAlign()` in
  the EA, including the chikou-offset handling — so the monitor and EA should
  agree on the signal.
- **Dedupe:** `state/state.json` remembers the last notified direction per
  symbol, so a signal that persists for weeks won't spam you daily. It only
  notifies on *new* alignments, direction flips, and clears.
- **Scheduling:** `.github/workflows/ms-w1-d1-monitor.yml` runs it daily at
  22:30 UTC on GitHub Actions for free, persisting the dedupe state between
  runs as a workflow artifact. Needs `TELEGRAM_BOT_TOKEN` and
  `TELEGRAM_CHAT_ID` secrets.
- **Status:** the Python port was verified against real data (it correctly
  flags fully-aligned trends and clears partial ones) but has not yet been
  cross-checked against the EA's backtest output — validate both before
  relying on either for execution decisions.

---

## 7. H4-M1 Kijun-Pullback EA (breakout exhaustion study)

**File:** `experimental-h4-m1-pullback-ea.mq5`
**Magic number:** `20260807` (independent of every other EA)

A fork of the main H4-M1 Alignment EA that adds a **pullback entry**: instead
of waiting for a full 6-TF re-alignment to re-enter after an exit, it buys
the trend's retracement to the **H4 Kijun** while the higher timeframes are
still aligned — trading WITH the trend, never against it.

### The study that motivated it

Empirical analysis on 2 years of hourly gold (`GC=F` from Yahoo, resampled to
H4 — a proxy for `GOLDm#`), using a faithful port of `CheckAlign()`:

| Finding (124 fresh H4 bullish episodes) | Rate |
|---|---|
| Retraced to touch the H4 Kijun | **96.8%** (median ~1.3 days) |
| Touched the H1 Kijun first | 100% (72% touch H1 Kijun before H4) |
| Touched the H4 cloud top / bottom | 66.9% / 41.9% |
| Entered the H4 cloud | 21.1% |
| Made a new high after the retrace | **95.2%** |

The retracement to the Kijun is the **rule, not the exception** — and it is
overwhelmingly a **continuation dip**, not a reversal. Key condition-split
results for buying the pullback (SL = touch-bar low − 0.1 ATR, TP = breakout
high):

| Condition | Win rate |
|---|---|
| All pullback buys | 51.7% |
| **Touch bar closes back above the H4 Kijun** | **61.6%** (vs 26.5% when it closes below) |
| Breakout extension ≥ 2 ATR(H4) | 60.5% (vs 47.6%) |
| Kijun flat | 59.6% (vs 45.6%) |
| ADX(H4) ≥ 30 | 53.4% (vs 48.9%) |

**Fading the breakout back to the Kijun (counter-trend) won 0/13** on the same
data — even conditioned on high ADX or large extension. This EA therefore
only enters WITH the trend; the counter-trend fade idea lives (conservatively,
with more gates) in the H1-M1 Reversion EA (section 2).

Caveat: only the H4 anchor level is reproducible from Yahoo 1h data — the
full 6-TF stack cannot be. The MT5 Strategy Tester on the real EA is the
definitive test of these filters at the stack level.

### Entry logic

Three modes via `InpEntryMode`:

| Mode | Behavior |
|------|----------|
| `ENTRY_BREAKOUT` (0) | Identical to the main H4-M1 EA — full 6-TF alignment only |
| `ENTRY_PULLBACK` (1, default) | H4 Kijun bounce entries only |
| `ENTRY_BOTH` (2) | Full alignment first, pullback if it doesn't fire |

**Pullback setup** — all gates must pass (checked per new M1 bar, per symbol):

1. **Prior breakout:** a full 6-TF alignment signal fired while the symbol was
   flat (memorized with its H4 extension in ATR units). Reset to "none" once a
   position opens, so each pullback needs a fresh breakout.
2. **Trend intact:** the top `InpPullTrendTFs` timeframes (default 2 → H4 + H1)
   are still aligned in the breakout direction.
3. **Retracement:** within the last `InpBounceLookbackH4` closed H4 bars
   (default 3), a bar's range contained the **H4 Kijun** — price actually
   pulled back to it.
4. **Bounce confirmation:** the most recent touch bar closed on the trend side
   of the H4 Kijun (`InpTouchCloseAbove`, default on — the single strongest
   filter in the study: 61.6% vs 26.5%).
5. **Proximity:** price is still on the trend side of the H4 Kijun and within
   `InpMaxEntryDistATR` × ATR(H4) of it (default 1.5 — keeps entries fresh,
   not stale re-touches days later).
6. **Study filters (optional):** breakout extension ≥ `InpMinBreakoutExtATR`
   (default 2.0 ATR; 0 = off) and ADX(H4) ≥ `InpMinADX` (default 30; 0 = off).

Direction always equals the breakout direction (with-trend only). Entries use
the same equity-scaled sizing and ATR(M15) stop as the main EA.

### Exit logic

Identical to the main H4-M1 EA: ATR chandelier trail once in profit
(choppy-only via ADX(M15) by default), M15 Kijun cross as the fallback, and
the ATR(M15) × `InpATRMultiplier` protective stop on every position.

### Pullback inputs

| Parameter | Default | Description |
|-----------|---------|--------------|
| `InpEntryMode` | `ENTRY_PULLBACK` | 0 = breakout only, 1 = pullback only, 2 = both |
| `InpPullTrendTFs` | 2 | Top-N timeframes that must stay aligned (2 = H4+H1, 3 = +M30, …) |
| `InpBounceLookbackH4` | 3 | H4 bars back to search for the Kijun touch |
| `InpTouchCloseAbove` | `true` | Touch bar must close on the trend side of the H4 Kijun |
| `InpMaxEntryDistATR` | 1.5 | Max \|price − H4 Kijun\| for entry (× ATR H4) |
| `InpMinBreakoutExtATR` | 2.0 | Prior breakout must be ≥ this × ATR(H4) extended (0 = off) |
| `InpMinADX` | 30.0 | Min ADX(H4) for a pullback entry (0 = off) |

All other inputs are identical to the main H4-M1 EA (see
[README](../README.md#configuration-inputs)).

### Status & caveats

- **Not yet backtested.** The study numbers above are H4-anchor-only from an
  independent data source; the EA itself has not been run in the Strategy
  Tester. Suggested first pass: compare `ENTRY_PULLBACK` vs `ENTRY_BREAKOUT`
  (mode 0) on the same symbol/period — the breakout mode is the known
  baseline.
- The pullback SL is the ATR(M15) × 3 stop (as shipped) — *not* the tight
  touch-bar-low stop from the study. Expect lower win rate but larger winners
  than the study's headline numbers; test `InpATRMultiplier` if stops sting.
- When `InpMinBreakoutExtATR` blocks an entry, it blocks all pullbacks until a
  *new* full-alignment breakout — a stale, low-extension breakout can idle the
  EA for a long stretch in side-slipping trends.
- `InpTouchCloseAbove = false` is the raw "touch the Kijun" version — the study
  says that halves the win rate (26.5%); leave it on unless you're testing.

## 8. H4-M1 BE30 Alignment EA (break-even stop experiment)

**File:** `experimental-h4-m1-be30-ea.mq5`

A fork of the main H4-M1 Alignment EA that adds one exit-management
experiment: if price reaches a profitable position within `InpBE30Minutes`
of entry, the stop loss is moved **to break even plus a few points** (to
cover the spread) instead of leaving the full ATR(M15) protective stop
exposed. The idea is to cut losers to breakeven early and ride winners —
a cheaper safety net than the chandelier trail, which only arms once
profit reaches 1.0 × ATR(M15).

### Entry logic

Identical to the main H4-M1 EA: H4→M1 price+chikou alignment, spread gate,
same equity-scaled lot sizing, and the ATR(M15) × 3 protective stop on
every position.

### Break-even (BE30) logic

Checked once per new M1 bar while a position is open:

1. **Window:** the trade must turn profitable within `InpBE30Minutes`
   (default 30) of entry. After the window closes without profit, the
   stop stays where it is for that trade — no second chance.
2. **Profitability:** for a long, `bid ≥ average open price + 0.5 ×
   ATR(M15)` (`InpBE30ActivateATR`); mirrored for shorts with `ask`. The
   average open price is volume-weighted across the batch, so a
   multi-fill entry uses its true breakeven point.
3. **Move:** the stop is set to `average open ± InpBE30CoverPoints` points
   (default 15) — break even plus a small buffer to cover the spread.
   The move is tighten-only (never lowers the existing stop) and respects
   the broker's minimum stop distance.

The move is one-shot per trade (`beMoved`); afterwards the chandelier
trail (if enabled) may tighten the stop further as the peak grows. On an
EA restart mid-trade, the window is rebuilt from the position's open time.

### BE30 inputs

| Parameter | Default | Description |
|-----------|---------|--------------|
| `InpBE30Enabled` | `true` | Move SL to break even when profitable in time |
| `InpBE30Minutes` | 30 | Profit window after entry (minutes) |
| `InpBE30ActivateATR` | 0.5 | Min profit to arm BE (× ATR M15) |
| `InpBE30CoverPoints` | 15 | Points beyond break even (covers spread) |

All other inputs are identical to the main H4-M1 EA (see
[README](../README.md#configuration-inputs)).

### Status & caveats

- **Not yet backtested.** Suggested first pass: run the same symbol/period
  with `InpBE30Enabled = true` vs `false` on otherwise identical settings —
  the `false` run is the known H4-M1 baseline.
- With the default `InpTrailMode = TRAIL_CHOPPY`, the chandelier trail can
  tighten stops above the BE30 level once profit grows; BE30 mainly
  protects the stretch between entry and trail activation.
- `InpBE30ActivateATR = 0` arms BE at the first tick price moves past
  entry — expect the stop to trigger on small noise; a small activation
  buffer is what makes the "few points of cover" meaningful.
- Like the trail, BE30 needs the ATR(M15) handle, so it is inactive when
  `InpUseStopLoss = false`.

## 9. H4-M1 BE15 Alignment EA (profit-streak break-even experiment)

**File:** `experimental-h4-m1-be15-ea.mq5`

A fork of the main H4-M1 Alignment EA testing the reverse timing of the
BE30 experiment (section 8): instead of a fixed window from entry, the
stop loss moves to **break even plus a few points** once the trade has
been **in profit continuously for `InpBE15Minutes`** (default 15). A dip
back to break even resets the streak, so only sustained profit time
counts — no credit for a trade that flickered profitable and faded.

### Entry logic

Identical to the main H4-M1 EA: H4→M1 price+chikou alignment, spread gate,
same equity-scaled lot sizing, and the ATR(M15) × 3 protective stop on
every position — plus the optional **kihon suchi time-theory filter**
below.

### Time theory (kihon suchi) filter

At the breakout moment the EA counts, per timeframe, the consecutive
closed bars since the last **Kijun touch** (a candle whose high–low
straddles the Kijun, or slips to the wrong side of it, ends the streak) —
the same count convention as the H1-M1 reversion EA (section 2). The count
is the age of the move on that timeframe.

The check runs as a **nested cascade** — each timeframe must be clear
(count not **exactly** on a kihon suchi number up to 100 —
`9,17,26,33,42,51,65,76,83,97`, no tolerance) before the next is consulted:

1. **H4** — if the count equals a cycle, the breakout is **skipped**
   (`skip entry: H4 time cycle mature`).
2. **H1** — only checked if H4 is clear; same exact-match rule.
3. **M30** — only checked if H1 is clear.
4. **M15** — only checked if M30 is clear.

All four clear ⇒ the move has room to run to the next cycle number
(**continuation**) and the entry proceeds. A mature count anywhere in the
chain blocks the entry. Counts past cycle 100 are always allowed (long
trends don't get starved). This is a filter only — entries are gated,
nothing else changes.

> **Status: experimental — off by default.** `InpUseTimeFilter` ships as
> `false` (no performance edge was seen in A/B runs); flip it on to test.

| Parameter | Default | Description |
|-----------|---------|--------------|
| `InpUseTimeFilter` | `false` | Master switch for the time-theory filter (off by default) |
| `InpTimeCycles` | `9,17,26,33,42,51,65,76,83,97,101,129,172,200,226,257,676` | Kihon suchi cycle list (comma-separated; only cycles ≤ 100 apply) |
| `InpTimeFilterH4` | `true` | Check H4 first (exact match) |
| `InpTimeFilterH1` | `true` | Check H1 next, only if H4 is clear |
| `InpTimeFilterM30` | `true` | Check M30 next, only if H1 is clear |
| `InpTimeFilterM15` | `true` | Check M15 last, only if M30 is clear |

### Break-even (BE15) logic

Checked once per new M1 bar while a position is open:

1. **In profit?** for a long, `bid ≥ average open price + 0.5 × ATR(M15)`
   (`InpBE15ActivateATR`); mirrored for shorts with `ask`. The average
   open price is volume-weighted across the batch.
2. **Streak:** each bar in profit continues the timer; any bar back at or
   below break even resets it to zero. When the streak reaches
   `InpBE15Minutes` the stop moves — even if the trade is no longer at the
   activation buffer at that exact moment, as long as it never dipped
   below break even.
3. **Move:** the stop is set to `average open ± InpBE15CoverPoints` points
   (default 15) — break even plus a small buffer to cover the spread.
   The move is tighten-only and respects the broker's minimum stop
   distance.

The move is one-shot per trade (`beMoved`); afterwards the chandelier
trail (if enabled) may tighten the stop further. On an EA restart
mid-trade the streak starts fresh — how long the trade was already in
profit cannot be recovered.

### BE15 inputs

| Parameter | Default | Description |
|-----------|---------|--------------|
| `InpBE15Enabled` | `true` | Move SL to break even after time in profit |
| `InpBE15Minutes` | 15 | Consecutive minutes in profit required |
| `InpBE15ActivateATR` | 0.5 | Min profit to count as "in profit" (× ATR M15) |
| `InpBE15CoverPoints` | 15 | Points beyond break even (covers spread) |

All other inputs are identical to the main H4-M1 EA (see
[README](../README.md#configuration-inputs)).

### Status & caveats

- **Not yet backtested.** Suggested first pass: run the same symbol/period
  with `InpBE15Enabled = true` vs `false` on otherwise identical settings,
  ideally side-by-side with the BE30 build — the two break-even timings
  (window-from-entry vs continuous-profit-streak) are the variable under
  test.
- The streak resets on any dip below break even, so a trade that keeps
  teasing its entry point may never arm the break-even stop even though
  BE30 (section 8) would have moved it on the first 30-minute profitable
  window.
- With the default `InpTrailMode = TRAIL_CHOPPY`, the chandelier trail can
  tighten stops above the BE15 level once profit grows; BE15 mainly
  protects the stretch between entry and trail activation.
- Like the trail, BE15 needs the ATR(M15) handle, so it is inactive when
  `InpUseStopLoss = false`.

---

## 10. H4-H1 Ignition EA (equivalence-aware compression/breakout)

**File:** `experimental-h4-h1-ignition-ea.mq5`
**Magic number:** `20260821`

A redesign of the multi-timeframe alignment idea based on the Ichimoku
timeframe-equivalence math:

| Law | Identity |
|-----|----------|
| 26/9 = 2.89 | Tenkan of TF X ≈ Kijun of the 2.9x-lower TF (closest standard pair: H1 Kijun ↔ H4 Tenkan) |
| 52/26 = 2 | **Kijun of TF X = cloud Span B of the 2x-lower TF exactly** (H1 Kijun IS the M30 cloud → M30 is redundant and omitted) |

Two structural flaws in the old boolean "all TFs must align" gate motivated
this build: (1) requiring price+chikou alignment on every TF from H4 to M1
guarantees late entries (chikou at 26 bars back is the laggiest element), and
(2) redundant TF checks (H1 Kijun = M30 cloud) measure the same horizon twice
while never measuring the *relationship* between TFs — the compression that
precedes breakouts.

Instead of one alignment gate, the EA uses a state-machine reading:
**compression → ignition → trend → mature** — entering on *ignition* (early,
small stop at the compressed zone), not on full multi-TF confirmation (late).

### Entry engine

Checked once per new closed **M15** bar (all checks on last closed bars of
each TF). Each timeframe has one role and is deliberately asymmetric:

| TF | Role | Check |
|----|------|-------|
| H4 | Trend gate — a REAL breakout | **Full H4 price+chikou breakout** (`InpRequireH4Breakout`, default on): price above/below tenkan, kijun and cloud AND chikou clear above/below price and levels at its plotted position 26 bars back. Disable it (`false`) to fall back to the sticky `InpBiasMode` (0 = kijun+cloud, 1 = kijun+tenkan structure, 2 = kijun only) |
| H1 | Pullback zone + freshness | Price on the trend side of the H1 Kijun and within `InpZoneToleranceATR` × ATR(H1) of the cloud **or** (mode 1, default) the tenkan — catches the shallow pullbacks that never reach the cloud; price far from both = extended = rejected |
| M15 | Ignition timing | Micro-breakout: close through M15 tenkan **and** M15 cloud with momentum (close above prior closed bar); optional M15 chikou confirm (`InpRequireChikou`, default off) |

Plus two cross-TF gates:

- **Compression** (`InpRequireCompression`, default off; threshold 0.35): the
  sister-level coincidence `|H4 Kijun − H1 Span B| < InpCompressionATR ×
  ATR(H1)` — all midpoints converge, i.e. pre-breakout energy. (The observed
  "H4 Kijun = H1 cloud" chart sightings are this coincidence, not an
  identity.) Off by default because it rarely coexists with a fresh H4
  chikou breakout — turn it on to require the rarest, highest-energy setups.
- **Freshness** (`InpFreshnessBars`, default 17): bars since the last H1
  Kijun touch must be ≤ 17 — the move must be young. This is the direct
  answer to "M1 is fully developed and too late": maturity is measured by
  move age, not by line alignment.

### Exit & risk (swing-scale machinery, H4-H1 experimental risk)

- ATR(H1) × 3 protective stop on every position.
- **Risk sizing identical to the H4-M1 VPS build** — the equity-tiered
  ladder (`GetEquityRisk`) with fixed lots up to $8k and
  `RiskBasedLots` at `InpHighEquityRiskPct` (1.0%) of equity above;
  `CapToRisk` by `InpMaxRiskPct`, `CapToMargin` by free margin.
- **ATR(H1) chandelier trail** once profitable (3.0 × ATR(H1) distance,
  armed at 2.0 × ATR(H1) profit; choppy-only via ADX(H1) by default). The
  peak reference is the forming M15 bar.
- **Spike profit lock** (default on): when an M15 bar (forming or last
  closed) moves ≥ 3.0 × ATR(M15) in the trade direction while the trade is
  already locked in ≥ 1.0 × ATR(H1) of profit, the stop slams to just
  0.5 × ATR(H1) behind the spike extreme — sudden peaks are banked before
  the typical post-spike reversal.
- **Cadence:** exit management (trail + spike lock + BE) re-evaluates on
  every new **M1** bar so a spike's peak is locked within a minute;
  entries and the H1-kijun fallback exit run on new **M15** bars.
- **H1 close crossing the H1 Kijun** as the final fallback exit (the M15
  kijun exit of the M1 scalper builds stops out normal swing pullbacks —
  that was the "stopped out too early" cause).
- **BE30 off by default** — its 30-minute profit window was tuned for
  M1-cadence entries; on M15 swings it arms on the first noise tick and
  hands the trade back at breakeven. Flip on only for A/B.
- No Alert popups.

### Ignition inputs

| Parameter | Default | Description |
|-----------|---------|--------------|
| `InpFreshnessBars` | 17 | Max bars since last H1 Kijun touch for entry (young-move gate) |
| `InpZoneToleranceATR` | 1.0 | H1 pullback zone tolerance (× ATR H1) |
| `InpBiasMode` | 1 | H4 bias when `InpRequireH4Breakout=false`: 0 = kijun+cloud, 1 = kijun+tenkan structure, 2 = kijun only |
| `InpRequireH4Breakout` | `true` | Require the full H4 price+chikou breakout (classic alignment condition on the trend TF) |
| `InpZoneMode` | 1 | H1 zone: 0 = cloud pullback only, 1 = cloud OR tenkan pullback |
| `InpRequireCompression` | `false` | Require \|H4 Kijun − H1 Span B\| < threshold (compression) |
| `InpCompressionATR` | 0.35 | Compression threshold (× ATR H1) |
| `InpRequireChikou` | `false` | Require M15 chikou confirmation on the ignition bar |

### Spike profit protection inputs

| Parameter | Default | Description |
|-----------|---------|--------------|
| `InpSpikeLockEnabled` | `true` | Slam SL to just behind sudden spike moves (checked every M1 bar) |
| `InpSpikeATR` | 3.0 | Spike = an M15 bar moved ≥ this × ATR(M15) in the trade direction |
| `InpSpikeProfitATR` | 1.0 | Min locked profit before the spike lock arms (× ATR H1) |
| `InpSpikeBufferATR` | 0.5 | Spike-lock distance behind the spike extreme (× ATR H1) |

All other inputs (Ichimoku periods, risk protection, equity sizing, trail,
BE30) are identical to the H4-M1 VPS build, except ATR is computed on **H1**
(swing scale) and BE30 ships **off**.

### Status & caveats

- **Not yet compiled** (no MetaEditor available during development) — braces/
  parens checked manually only. F7-compile in MetaEditor and fix any warnings
  before the first backtest.
- **Not yet backtested.** Suggested first pass: same symbol/period vs the
  `experimental-h4-h1-align-ea.mq5` baseline — the difference isolates the
  ignition/compression/freshness gate from the full-alignment gate.
- **H4 chikou blocks the first ~26 H4 bars (4.3 days) of a fresh move** — the
  chikou span only confirms after it clears the candle 26 bars back. If that
  starves fresh-breakout entries, A/B with `InpRequireH4Breakout = false` +
  `InpBiasMode = 2` (kijun-only) — the freshness gate still filters lateness.
- Compression (`false` by default) rarely coexists with a fresh H4 chikou
  breakout — it's the "rarest setups only" knob; loosen `InpCompressionATR`
  before switching it on.
- The exit stack is swing-scaled: ATR(H1) stop/trail, H1 kijun fallback,
  BE30 off. If a backtest shows trends being given back, the first knobs are
  `InpTrailATR` (raise to ride) and `InpTrailActivateATR` (raise to hold);
  if small accounts feel the fixed-lot ladder, adjust `InpATRMultiplier`.
- The spike lock banks peaks fast but can also sell the top of a legit
  impulse that keeps running — `InpSpikeBufferATR` and `InpSpikeATR` trade
  give-back vs. early bank. A/B with `InpSpikeLockEnabled = false` to see
  its contribution in isolation.
- Exit management runs every M1 bar, so CPU use is higher than the pure
  M15-cadence build — still trivial for a handful of symbols.

## 11. H4-M1 alignment-filter experiments (timeframe pruning)

**Files:**
- `experimental-h4-m1-no-m30-ea.mq5` — alignment filter: H4/H1/M15/M5/M1 (Magic `20260822`)
- `experimental-h4-m1-no-m30-m1-ea.mq5` — alignment filter: H4/H1/M15/M5 (Magic `20260823`)
- `experimental-h4-m1-no-m30-m5-m1-ea.mq5` — alignment filter: H4/H1/M15 (Magic `20260824`)
- `experimental-h4-m15-vps-ea.mq5` — alignment filter: H4/M15 ONLY (Magic `20260825`)
- `experimental-h4-m1-no-m1-ea.mq5` — alignment filter: H4/H1/M30/M15/M5 (Magic `20260828`)
- `experimental-h1-m1-no-m1-ea.mq5` — H1-VPS fork, filter: H1/M30/M15/M5 (Magic `20260829`)

Five forks of the H4-M1 VPS build plus one of the H1-M1 VPS build testing
how much of the multi-timeframe alignment gate can be pruned before trade
quality changes. Everything else (entries, exit-timeframe kijun cross,
chandelier trail, BE30, risk sizing) is identical to the respective VPS
build; only `tfs[]`, `TF_COUNT`, `IDX_M15`/`IDX_M5` (3 in the no-M1 builds,
2 in the first three, 1 in the H4/M15-only build) and the magic number
differ.

### Rationale (Ichimoku timeframe equivalence)

Every Ichimoku level is the midpoint of the high/low over N bars, so the
26-bar lookback of a higher TF equals the 52-bar cloud Span B of the
2x-lower TF:

| Identity | Horizon |
|----------|---------|
| H1 Kijun = M30 Span B (exact) | ~26h |
| M30 Kijun = M15 Span B (exact) | ~13h |

And chikou on any TF proves only *26 bars of persistence at that scale*:
26 minutes on M1, 2.2h on M5 — it cannot corroborate an H4 breakout whose
own memory is 4.3 days. So M30 re-measures the same horizon as H1 (pure
redundancy), while M5/M1 add entry-timing noise rather than trend
validation. M15 is kept in every build because it is the exit/ATR/ADX
timeframe.

### What each build isolates

1. **no-M30** — removes the one exactly-redundant check (its cloud = H1
   kijun). Expected: near-identical trade frequency/quality vs VPS; cheapest
   way to test the equivalence claim.
2. **no-M30 + no-M1** — also drops the 26-minute persistence gate. Expected:
   earlier entries (timing anchors to M5 instead of M1) and fewer
   noise-blocked signals.
3. **no-M30 + no-M5 + no-M1** — the "validation-only" stack: H4 trend gate,
   H1 day-level confirmation, M15 swing confirmation. Expected: fewest but
   strongest entries — the moments where even the 6.5h envelope is broken.
4. **H4/M15 only** (`experimental-h4-m15-vps-ea.mq5`) — the pure two-TF
   envelope: H4 trend gate + M15 swing/exit TF, with the H1 day-level
   confirmation dropped too. Per the equivalence table, H1 Kijun ≈ M30 Span
   B ≈ 26h — the removed day-scale memory that used to keep entries out of
   H1-level congestion. Expected: the fewest entries of the series and the
   simplest "breakout across two scales" test; worth comparing directly
   against build 3 to isolate what the H1 gate adds on gold.
5. **no-M1** (`experimental-h4-m1-no-m1-ea.mq5`) — keeps the full stack
   minus the innermost 26-minute persistence gate. Expected: earlier
   entries (timing anchors to M5) and fewer noise-blocked signals, without
   losing the M30/H1 redundancy removal that build 1 tests. The same cut on
   the H1-VPS build is `experimental-h1-m1-no-m1-ea.mq5` (filter H1/M30/
   M15/M5) — a mirror test of the same claim at one scale lower.

### Status & caveats

- **Not yet compiled / not yet backtested.** Suggested first pass: same
  symbol/period vs the VPS build (or `experimental-h4-m1-no-m30-ea.mq5` as
  the intermediate baseline) — the delta isolates what each removed TF
  contributed to frequency and win rate.
- The M1 bar gating in `OnTick` is untouched in all six builds — the
  once-per-minute cadence is the timing mechanism, not the filter.
- Total alignment is a multi-scale envelope breakout: the condition exists
  only during momentum bursts and can decay quickly on the lower TFs; trade
  duration is therefore decided by the exits (M15 kijun cross, chandelier),
  not by alignment. If entries look too late even at H4/H1/M15, that is the
  H4 chikou 26-bar lag, not the filter pruning — see the ignition EA
  (section 10) for the early-entry redesign.

---

## 12. Per-Timeframe Breakout EA (tenkan-close exit)

**File:** `experimental-h4-h1-per-timeframe-ea.mq5` (Magic `20260826` H4 / `20260827` H1)

The most stripped-down build in the repo: a **single-timeframe** breakout
experiment. No cross-TF confirmation, no M15 exits, no chandelier trail, no
BE30 — each enabled timeframe opens on its own breakout and closes only by
its tenkan or the ATR stop.

### Rules

- **Entry:** the same price+chikou breakout used as the top gate of the
  alignment stack — price above/below tenkan, kijun, and cloud on the last
  closed bar, with the chikou span clear of price and all three levels at
  its plotted position. No other timeframe is consulted.
- **Exit (managed):** aggressive profit locking — the SL moves to break
  even as soon as the trade is profitable by `InpBEActivateATR` x ATR, then
  a tight chandelier trail (`InpTrailATR` x ATR behind the forming bar's
  peak, armed once profit >= `InpTrailActivateATR` x ATR) locks in the
  breakout spike. Both are per-timeframe.
- **Exit (final):** the next close back on the wrong side of that
  timeframe's tenkan (conversion line) closes everything — a long exits on
  a close below tenkan, a short on a close above it. The ATR-based
  protective stop loss is the only other way out.
- **Choppy filter:** entries are skipped when ADX of that timeframe
  (`InpChopADXPeriod`, read on H4 for H4 trades and H1 for H1 trades) is
  below `InpChopADXLevel` (default 22) — the breakout won't follow through
  without a trend. Unready ADX is treated as choppy, so no trade is ever
  taken on a signal that can't be verified.
- **ATR for the stop is read on the traded timeframe** so the protective
  distance matches the holding scale of the trade.

### Timeframe options

`InpUseH4` / `InpUseH1` enable each timeframe independently; at least one
must be on. Each enabled timeframe monitors itself and fires on its own:
separate state per timeframe per symbol, separate magic numbers (so an H4
exit never touches an H1 position on the same symbol), and its own ATR
stop. H4 trades use the same risk ladder as H1 trades ("same risk" — the
equity-scaled `GetEquityRisk` sizing is shared).

### Base and changes

Forked from the simple `experimental-h4-m15-align-ea.mq5` base (per-symbol
bar gating, equity alert, laddered lots — no cooldown/margin caps). The
exit was swapped from the M15-kijun cross to the tenkan cross, gating moved
to closed bars of each enabled timeframe, ATR moved to the traded
timeframe, and state/ATR/magic/gating became per-timeframe arrays.

### Why it exists

The alignment stack can only enter when *every* scale confirms — a rare,
late condition. This build tests the other extreme: the breakout alone on
one scale at a time as a pure trend-capture, with the tenkan acting as a
trailing exit in price space. H4 vs H1 on the same symbol shows how much of
the edge is the horizon itself (4.3-day memory vs ~26-hour) rather than
lower-TF confirmation.

### Status & caveats

- **Not yet compiled / not yet backtested.** Suggest comparing against the
  VPS build and the H4/M15-only build (section 11, build 4) on the same
  symbol/period.
- Defaults are deliberately aggressive: BE at 0.3 x ATR profit and a 1.0 x
  ATR chandelier (the VPS build uses 0.5/BE30 and 2.0 ATR). Expect frequent
  break-even exits when a breakout stalls — that is the cost of locking
  profit fast. Widen `InpTrailATR` toward 2.0 to give trades room.
- Tenkan exits are slow by design: a long only exits after a full close
  below the conversion line, so givebacks of 1–2 candles' worth of profit
  are expected; the trail/BE stack usually exits earlier.
- A deep adverse move to the protective stop is still an ordinary outcome
  when the trade never reaches the BE/trail arm level — no strategy locks
  profit on a loser.
- With both timeframes enabled, the same symbol can hold an H4 trade and an
  H1 trade simultaneously, in either direction — the laddered lot counts
  from each can stack on one symbol.

> **Removed:** the per-symbol US30, Silver, and BTCUSD variants of the
> H4-H1 swing EA (`experimental-h4-h1-align-us30-ea.mq5`,
> `experimental-h4-h1-align-silver-ea.mq5`,
> `experimental-h4-h1-align-btc-ea.mq5`) were deleted from the repo.
> The symbol-agnostic H4-H1 builds cover those markets through the
> `Symbols` input.


---

## 13. H4-M1 News-Filter EA (high-impact event blackout)

**File:** `experimental-h4-m1-news-filter-ea.mq5`
**Magic number:** `20260832` (independent of every other EA)

A fork of the H4-M1 desktop build (`ichimoku-h4-m1-mt5pc-ea.mq5`, magic
`20260830`) that refuses to hold or open a position around high-impact
news. Every rule of the parent build is unchanged — H4→M1 alignment entry,
ATR stop, chandelier trail, ADX choppy gate, BE30, M15-kijun exit, weekly
equity alert. The only addition is the news blackout.

### Rules

- **Source:** the terminal's built-in MQL5 Economic Calendar
  (`CalendarValueHistory` / `CalendarEventById`). Same feed as the
  Calendar tab in MT5, supplied by MetaQuotes rather than the broker, so
  it works on any MT5 account including XM. No WebRequest permission, no
  DLL, no scraping of Forex Factory.
- **Impact:** `CALENDAR_IMPORTANCE_HIGH` only by default — the calendar's
  equivalent of a Forex Factory red folder. `InpNewsIncludeMedium` adds
  medium impact (orange) as well.
- **Which events count:** those whose currency matches the symbol's base
  or profit currency, plus anything listed in `InpNewsCurrencies`. On
  `GOLDm#` the profit currency is USD, so US releases (NFP, CPI, FOMC)
  qualify; the XAU base matches nothing, which is harmless. Add
  `"EUR,GBP"` to sit out ECB/BoE releases on gold as well.
- **Blackout window:** from `InpNewsBlockBeforeMin` minutes before the
  event (default 60) to `InpNewsBlockAfterMin` minutes after it (default
  5). Open positions on that symbol are closed the moment the window
  opens, and no entry is taken until it closes. Overlapping events extend
  the window to the latest end time.
- **Ordering:** the news check runs before the M15 exit, trail, BE and
  entry checks, so a news exit always wins. A close that fails (requote,
  halt) is retried on the next M1 bar, and the trail/BE keep managing the
  position in the meantime.
- **Alerts:** one print + popup + push per blackout window (event name,
  event time, and when trading resumes), plus a separate alert for the
  positions actually closed.

### Inputs

| Input | Default | Meaning |
|---|---|---|
| `InpNewsFilterEnabled` | `true` | Master switch for the whole filter |
| `InpNewsBlockBeforeMin` | `60` | Flatten and block entries this long before an event |
| `InpNewsBlockAfterMin` | `5` | Resume trading this long after an event |
| `InpNewsIncludeMedium` | `false` | Also block on medium (orange) impact |
| `InpNewsCurrencies` | `""` | Extra currencies to watch, comma-separated |

### Implementation notes

- Calendar times are in **trade-server time**, which is what
  `TimeTradeServer()` returns, so no broker GMT-offset conversion is
  needed. Alert timestamps are labelled `(server)` for that reason.
- The event cache is rebuilt every 15 minutes over a −6h/+36h window and
  filtered per symbol on each M1 bar, so the calendar is not re-queried on
  every bar.
- **Fails open.** If the calendar can't be read (terminal offline,
  calendar disabled), the EA warns once — print, popup and push — and then
  trades normally rather than freezing the account indefinitely.
- Because everything is gated on closed M1 bars, the blackout starts
  within about a minute of the exact `InpNewsBlockBeforeMin` mark. Set 60
  minutes and expect the flatten between T−60 and T−59.

### Status & caveats

- **Not yet compiled / not yet backtested.**
- **The Strategy Tester has no calendar access**, so a backtest of this
  file trades exactly like the parent build — the blackout never triggers
  and the results say nothing about the filter. Forward-testing on a demo
  account is the only way to see it work; watch the Experts log for the
  blackout lines around a scheduled release.
- **Check the calendar before running this on a VPS.** MetaTrader VPS
  runs a stripped terminal, and calendar availability there should be
  verified on a demo account first — a fail-open filter on a VPS that
  can't read the calendar is a filter that never fires. The one-shot
  "calendar unavailable" push exists to make that obvious.
- Flattening an hour ahead of every red-folder release cuts trades that
  would have run through the news profitably; on a USD-heavy symbol like
  gold it also removes a large share of the week's trading hours. The
  point of the experiment is to measure that trade-off against the parent
  build over the same period.
- The filter never *blocks* an exit: stops, trail, BE and the M15-kijun
  exit all keep working normally outside the window.

---

## 14. Structure-Map EA (price-action bounce reader)

**File:** `experimental-structure-map-ea.mq5`
**Magic number:** `20260834`

Every other build in this repo asks one boolean question — *are the
timeframes aligned?* — and trades the answer. This one asks a different
question: **where is price, relative to everything, and what is the obvious
next move?** It reads the chart instead of gating on it. There is no
breakout-alignment requirement anywhere in the entry path.

The trade it looks for is the continuation bounce: price is in an
established structure, pulls back into an Ichimoku level (kijun, tenkan, or
a cloud edge), rejects it, and resumes. Bouncing off the cloud to resume the
trend, bouncing off the kijun to resume the trend — that is the whole thesis.

### The three readings

**1. The structure map (where price is).** On each of up to **six**
timeframe slots, running highest to lowest (H4 / H1 / M15 / M5 by default,
with two spare slots off), the EA records, on the last closed bar:

| Recorded | Meaning |
|---|---|
| Cloud side | above / inside / below the kumo |
| Cloud thickness | in ATR — a thin cloud is a weak floor |
| Future twist | span A vs span B projected 26 bars ahead, computed from the tenkan/kijun midpoint and the 52-bar midpoint rather than read off a plotted buffer |
| Tenkan/kijun state | which is on top |
| Distance to kijun / tenkan / cloud edge | signed, in ATR — the "how extended is it" measure |
| Kijun slope + flat flag | slope over `InpSlopeBars` in ATR; flat = balance, and a flat kijun is graded as a stronger level |
| Chikou free space | the close plotted 26 bars back, clear above / clear below / tangled in the candle there |
| Swing structure | higher highs + higher lows, lower highs + lower lows, or mixed |
| Legs | the last completed impulse in ATR, the leg in progress, and the retracement fraction between them |

Each timeframe's reading is scored into a single number in −1…+1 from eight
signed components (cloud side ±2, structure ±2, chikou ±1.5, price vs kijun
±1.5, tenkan/kijun ±1, twist ±1, price vs tenkan ±0.5, kijun slope ±0.5 —
raw sum ÷ 10). The weighted sum across timeframes (`InpW1`…`InpW6`,
default 3 / 2 / 1.5 / 0.5 / 0 / 0) is the **context score**, −100…+100. Its
sign is the direction the EA thinks price is headed; `InpMinContext`
(default 25) is how convinced it has to be before it will look for a trade
at all.

Any slot can hold any timeframe, so the stack can be anchored as high as
**MN1** — see [Anchoring the stack](#anchoring-the-stack)
below. A slot set to `PERIOD_CURRENT` is switched off entirely: never
mapped, never scored, supplies no levels, allocates no indicator handles.

With `InpLogMap` on (the default) the whole map is printed on every closed
trigger bar whether or not a trade follows, so the reasoning is on the
record:

```
MAP GOLDm# ctx=48.3 | H4[aboveKumo thick1.8 kj0.62 tn0.31 tk+ ch+ tw+ HH/HL leg+2.1 retr0.44 s0.65]
 | H1[aboveKumo thick1.2 kj0.08flat tn-0.12 tk+ ch0 tw+ HH/HL leg-1.3 retr0.51 s0.45] | ...
```

**2. The reaction (what price is doing right now).** Levels are collected
from the top `InpLevelTFs` timeframes (default 2 → H4 and H1): kumo top,
kumo base, kijun, tenkan. Only levels on the correct side qualify — support
below price for a long, resistance above for a short. Within the last
`InpReactionBars` closed trigger-TF bars, a level counts as **reacted off**
when a bar reached into it (within `InpTouchATR × ATR`) **and closed back
out of it** on the trade side. Price must still be on that side and within
`InpMaxEntryDistATR × ATR` of the level, so stale re-touches from hours ago
don't qualify. The strongest level touched wins, graded by type and
timeframe (kumo edge > flat kijun > kijun > tenkan; H4 > H1).

**3. The candle structure (is the bounce real).** At the reaction bar and
the last closed bar: rejection wick (`InpPinWickFrac` / `InpPinBodyFrac`
with the close in the right half), engulfing in the trade direction, a
momentum close beyond the reaction bar's extreme (+1.5 — the strongest
single reading), and a plain directional close (+0.5). The total must reach
`InpMinCandleScore` (default 1.0), so a bare close in the right direction is
never enough on its own.

### Conviction, and what it buys

```
conviction = 0.7 × |context score|
           + level grade bonus      (0…10)
           + candle score bonus     (0…10)
           + retracement bonus      (+10 sane pullback, −10 too deep)
           − lateness penalty       (15 when the move is already extended)
```

Clamped to 0…100. Below `InpMinScore` (55) nothing happens. Between
`InpMinScore` and `InpStrongScore` (75) the equity ladder is halved. At or
above `InpStrongScore` the full ladder goes on.

The retracement term is where the leg map earns its keep: for a long, the
leg in progress on the leg timeframe (`InpLegTFIdx`, default H1) should be
*down* — a pullback — and between `InpMinRetrace` and `InpMaxRetrace`
(0.25–0.90) of the impulse before it. Deeper than that and it stops reading
as a pullback and starts reading as a reversal, so the bonus turns negative.
If the leg is already running in the trade direction and is more than
`InpLateLegATR` (6 ATR) long, the setup is late and takes the penalty.

### The optimal-trade calculation

A setup that passes the read still has to be worth taking:

- **Stop** — behind the reaction extreme by `InpSLBufferATR × ATR`, pushed
  further out to the last trigger-TF swing when `InpSLBeyondSwing` is on.
  Widened to the broker minimum. If the resulting risk exceeds
  `InpMaxRiskATR × ATR` (4) the setup is **rejected** rather than traded with
  a bad stop.
- **Room** — the next structural obstacle ahead (mapped swing extremes and
  cloud edges on the context timeframes). If it sits closer than
  `InpMinRR × risk` (1.5R) the trade is **skipped** — no buying into a
  ceiling, no selling into a floor. Nothing ahead at all is the best case:
  clear air, all runners.
- **Target** — the obstacle front-run by `InpTPBufferATR × ATR`, applied to
  part of the ladder; `InpRunnerFrac` (default half) is left without a take
  profit for the trail to manage. Obstacles beyond `InpMaxRR` (8R) are
  ignored and those orders run free too.

### Anchoring the stack

The six slots take any timeframe, so the read can start anywhere from the
monthly candle down. Three presets, from the mildest anchor to the heaviest.

#### Default — H4 anchor (H4 / H1 / M15 / M5)

What ships. Slots 5–6 off, trigger and exit both on M15, levels from H4 and
H1. Intraday cadence, several setups a week on gold.

#### Daily anchor (D1 / H4 / H1 / M15)

The recommended starting point for a swing configuration, and the setting
where none of the ceilings below bite. It is the default stack shifted up
one scale — same weight shape, same slot roles. **Shipped as its own build**
(`experimental-structure-map-d1-ea.mq5`, section 15) so it can run alongside
the H4 build; the settings below are what that file already defaults to:

| Input | Value | Why |
|---|---|---|
| `InpTF1`…`InpTF4` | D1 / H4 / H1 / M15 | Slots 5–6 stay off; add M5 in slot 5 at weight 0.5 if you want timing texture |
| `InpW1`…`InpW4` | 3 / 2 / 1.5 / 0.5 | Identical shape to the shipped default, one scale higher |
| `InpTrigIdx` | 3 (M15) | Time the entry on M15 |
| `InpExitIdx` | 2 (H1) | Hold on the H1 scale |
| `InpLegTFIdx` | 1 (H4) | Grade the pullback on H4 legs — one slot below the anchor, as in the default |
| `InpLevelTFs` | 2 | Bounce off D1 and H4 structures |
| `InpObstacleTFs` | 3 | Measure room down to H1 |

Three reasons this is the sweet spot:

- **History is a non-issue.** 56 daily bars is under three months. The
  monthly stack's 4.7-year requirement is what makes it fragile on anything
  but gold and the majors; D1 has no such problem.
- **No redundant slots.** The Ichimoku equivalence that makes M30 pointless
  next to H1 (`Kijun of TF X = Span B of the 2× lower TF`, see section 11)
  needs an exactly-2× pair. D1 / H4 / H1 / M15 contains none, so every slot
  measures a genuinely different horizon.
- **The levels are real.** A D1 kijun and a D1 cloud edge are levels that
  get traded by people, not just by this EA — which is the entire premise of
  a bounce strategy.

Two things to retune for the longer hold: `InpReentryCooldownSec` (900s is
15 minutes — for a D1-anchored trade, something on the order of four hours
stops it re-entering the same level minutes after a stop-out), and
`InpExitIdx`. H1 is the recommendation because the M15 kijun cross stops out
normal swing pullbacks — the same "stopped out too early" failure documented
on the ignition EA (section 10), which moved its fallback exit to H1 for
exactly this reason. H4 in slot 1 gives even more room if H1 still proves
tight.

#### Monthly anchor (MN1 / W1 / D1 / H4 / H1 / M15)

The full stack. Recommended preset:

| Input | Value | Why |
|---|---|---|
| `InpTF1`…`InpTF6` | MN1 / W1 / D1 / H4 / H1 / M15 | The full stack, highest to lowest |
| `InpW1`…`InpW6` | 3 / 2.5 / 2 / 1.5 / 1 / 0.5 | Context weight decays down the stack |
| `InpTrigIdx` | 5 (M15) | Time the entry on M15 — the reaction, the candle structure and the entry cadence all read here |
| `InpExitIdx` | 3 (H4) | Hold on the H4 scale — the trail, break even and the kijun-cross exit read here |
| `InpLegTFIdx` | 2 (D1) | Grade the impulse/pullback on daily legs |
| `InpLevelTFs` | 3 | Bounce off MN1 / W1 / D1 structures |
| `InpObstacleTFs` | 4 | Measure room down to H4 |

Two separations make this coherent, and both were added for it:

- **Trigger slot vs exit slot.** `InpTrigIdx` is the *timing* scale — where
  the reaction is detected, where the candle structure is read, and how
  often entries are evaluated. `InpExitIdx` is the *holding* scale — the ATR
  that sizes the trail and the break-even arming, the swings the trail
  follows, and the kijun whose cross closes the trade. They default to the
  same slot (`InpExitIdx = -1`), which is the single-scale behaviour. On a
  monthly-anchored stack they must differ: an M15 kijun cross would close a
  trade that was taken off a weekly level within the hour. The EA refuses to
  start if the exit slot is *faster* than the trigger slot.
- **`InpObstacleTFs`** now sets how far down the stack the target search
  looks, separately from `InpLevelTFs`. With a monthly anchor, obstacles
  drawn only from MN1/W1 sit so far away that every setup clears the
  reward:risk gate and nothing gets filtered — scanning down to H4 restores
  the gate's meaning.

Level grades scale with `InpLevelTFs` rather than with slot capacity, so a
top-slot kumo edge grades the same whether the stack is anchored on H4 or on
MN1, and the conviction arithmetic is unchanged between configurations.

**History is the real constraint.** Each mapped slot needs
`max(SenkouB, Kijun + InpSlopeBars) + 4` bars — 56 at the defaults. On MN1
that is 56 monthly candles, roughly 4.7 years. Brokers usually have it for
gold and the majors, less often for newer symbols. `OnInit` logs a warning
per symbol/slot that is short rather than failing, because history normally
fills in once the terminal finishes downloading; until it does, that symbol
simply produces no signals. If a monthly-anchored build is silent, check the
log for that warning first.

**Indicator handles** are the other ceiling: two per enabled slot per
symbol. A six-slot stack across 60 symbols wants 720 handles, which will run
into the terminal's limit. Keep the symbol list short when running the full
stack — the monthly read is a swing configuration, not a scanner.

### Exits

- **Structure trail** — once profit reaches `InpTrailActivateATR × ATR`, the
  stop follows the most recent confirmed fractal swing on the trigger TF
  (padded by `InpSLBufferATR × ATR`). Tighten-only, broker-minimum aware.
  It arms late on purpose: the entry already carries a tight structural stop,
  and an unarmed trail would drag it into the noise straight away.
- **Break even** — at `InpBEActivateATR × ATR` of profit the stop moves to
  the volume-weighted open ± `InpBECoverPoints`. One-shot, but only marked
  done once the modify actually lands, so a stop blocked by the broker's
  minimum distance is retried.
- **Kijun cross** — a trigger-TF close back across its own kijun closes
  everything.
- **Map flip** (`InpExitOnFlip`, off by default) — the context score itself
  turning against the trade closes it.

### Key inputs

| Group | Parameter | Default | Purpose |
|-------|-----------|---------|---------|
| Map | `InpTF1`…`InpTF6` | H4 / H1 / M15 / M5 / off / off | The mapped timeframe slots, highest to lowest (`PERIOD_CURRENT` = off) |
| Map | `InpW1`…`InpW6` | 3 / 2 / 1.5 / 0.5 / 0 / 0 | Context-score weights (0 = map the slot, don't score it) |
| Map | `InpTrigIdx` | 2 | Trigger slot — reaction, candle structure, entry cadence |
| Map | `InpExitIdx` | −1 | Exit/holding slot — trail, break even, kijun exit (−1 = same as trigger) |
| Map | `InpLegTFIdx` | 1 | Slot whose legs and retracement are graded |
| Map | `InpLevelTFs` | 2 | Bounce levels come from the top N slots |
| Map | `InpObstacleTFs` | 2 | Target obstacles are scanned across the top N slots |
| Map | `InpSwingWing` / `InpLegBars` | 2 / 120 | Fractal half-width and scan depth |
| Reaction | `InpReactionBars` | 3 | Trigger-TF bars searched for the touch |
| Reaction | `InpTouchATR` | 0.25 | How close counts as touching the level |
| Reaction | `InpMaxEntryDistATR` | 1.25 | Freshness — max distance from the level at entry |
| Candles | `InpMinCandleScore` | 1.0 | Minimum price-action score at the level |
| Legs | `InpMinRetrace` / `InpMaxRetrace` | 0.25 / 0.90 | Accepted pullback depth |
| Legs | `InpLateLegATR` | 6.0 | Extension that marks a setup late (0 = off) |
| Score | `InpMinContext` | 25 | Min \|context score\| to look for a trade |
| Score | `InpMinScore` / `InpStrongScore` | 55 / 75 | Trade threshold / full-ladder threshold |
| Score | `InpHTFVetoScore` | 0.10 | How far the top TF may oppose the trade |
| Trade | `InpMaxRiskATR` | 4.0 | Reject setups whose structural stop is too wide |
| Trade | `InpMinRR` / `InpMaxRR` | 1.5 / 8.0 | Room gate / obstacle horizon |
| Trade | `InpRunnerFrac` | 0.50 | Share of the ladder left without a take profit |
| Exit | `InpTrailActivateATR` | 0.5 | Profit needed before the structure trail arms |
| Exit | `InpExitOnFlip` | `false` | Close when the map flips against the trade |

Risk sizing is the same equity ladder as the VPS builds (`GetEquityRisk`,
`RiskBasedLots` above $8k, `CapToRisk`, `CapToMargin`), sized off the
structural stop rather than a fixed ATR multiple.

### Status & caveats

- **Not yet compiled / not yet backtested.** No MetaEditor was available
  during development — braces and call sites were checked mechanically only.
  F7-compile and fix any warnings before the first Strategy-Tester run.
- The natural A/B partner is `experimental-h4-m1-pullback-ea.mq5` (section
  7): both buy the pullback, but the pullback EA requires a prior
  full-alignment breakout to arm and only ever uses the H4 kijun, while this
  one needs no breakout at all and reads every level on both context
  timeframes. Running them on the same symbol/period isolates what the
  breakout precondition is worth.
- **The score weights are hand-set, not fitted.** They encode a view (cloud
  side and swing structure matter most, tenkan least); nothing has measured
  them yet. Treat `InpW1`…`InpW4` and the component weights in `ScoreMap()`
  as the first thing to test, not as settled numbers.
- **The room filter can idle the EA.** In a range, every direction has an
  obstacle within 1.5R, so nothing qualifies — by design, but if trade count
  is near zero that gate is the first suspect. Loosen `InpMinRR` before
  loosening the read.
- `InpLogMap` writes a line per symbol per trigger bar. That is the point of
  the build — the recorded map is the research output — but turn it off for
  a long multi-symbol Strategy Tester run or the log will dominate the run
  time.
- The context score is a *sum*, not a gate: a strong top-slot read can carry
  a neutral middle of the stack. `InpHTFVetoScore` is the only hard
  directional veto, and it only guards the top slot. If entries look like
  they are fighting the intermediate timeframes, raise their weights before
  touching anything else. This matters more the taller the stack: with six
  slots a dominant MN1 reading can outvote four lower ones.
- **A monthly anchor changes what the EA is, not just its settings.** MN1
  and W1 readings move a handful of times a year, so the context score
  becomes near-constant and the trade rate collapses to whatever the D1/H4
  levels produce. That is the intent — swing trades off big structures — but
  it means a monthly-anchored backtest needs years of data to produce a
  meaningful trade count, and the first thing to verify is that the top
  slots are not simply frozen for the whole run.
- Chikou is read here as clear-of-the-candle only (not clear of the levels
  too, as in the alignment builds). It is one weighted component out of
  eight rather than a veto, which is deliberate — the strict chikou test is
  what makes the alignment builds late.

---

## 15. Structure-Map EA — D1 anchor

**File:** `experimental-structure-map-d1-ea.mq5`
**Magic number:** `20260835`

The [Structure-Map EA](#14-structure-map-ea-price-action-bounce-reader)
(section 14) with its stack shifted up one scale: **D1 / H4 / H1 / M15**
instead of H4 / H1 / M15 / M5. It bounces off *daily* structures — the D1
kijun, the D1 cloud edges, the H4 levels beneath them — while still timing
the entry on M15, so the stop stays small even though the level is a daily
one.

**The engine is byte-identical to section 14.** Only the input defaults, the
magic number and the order comments differ, so the two builds run side by
side on one account without colliding. Everything about how the map is
built, how the reaction is detected, how conviction is scored and how the
trade is constructed is documented in section 14 and is not repeated here.

### What differs from the H4 build

| Input | H4 build | D1 build | Why |
|---|---|---|---|
| `InpTF1`…`InpTF4` | H4 / H1 / M15 / M5 | **D1 / H4 / H1 / M15** | The whole stack, one scale up |
| `InpTrigIdx` | 2 (M15) | **3 (M15)** | Same timing scale, different slot number |
| `InpExitIdx` | −1 (= trigger, M15) | **2 (H1)** | Hold on H1 — the M15 kijun cross stops swing pullbacks out too early |
| `InpLegTFIdx` | 1 (H1) | **1 (H4)** | Still one slot below the anchor |
| `InpLevelTFs` | 2 (H4, H1) | **2 (D1, H4)** | Bounce off daily and H4 structures |
| `InpObstacleTFs` | 2 | **3 (down to H1)** | Daily obstacles alone are too far away for the reward:risk gate to filter anything |
| `InpReactionBars` | 3 | **8** | A daily level gets worked for hours, not 45 minutes — the touch window has to be wide enough to still be looking when momentum confirms |
| `InpMaxEntryDistATR` | 1.25 | **1.5** | Slightly looser freshness, since the wider touch window lets price drift further from the level before the entry fires |
| `InpReentryCooldownSec` | 900 (15 min) | **14400 (4 h)** | Stops it re-entering the same daily level minutes after a stop-out |

Weights are unchanged at 3 / 2 / 1.5 / 0.5 — the shape that decays down the
stack is the same, it is just applied one scale higher. Slots 5 and 6 stay
off; put M5 in slot 5 at weight 0.5 if you want the timing texture back.

### Why the daily anchor is the sensible one

- **History is a non-issue.** A mapped slot needs 56 bars; on D1 that is
  under three months. The MN1 configuration wants 4.7 years, which is what
  makes it fragile on anything but gold and the majors.
- **No redundant slots.** The equivalence that makes M30 pointless next to
  H1 (`Kijun of TF X = Span B of the 2× lower TF`, section 11) needs an
  exactly-2× pair. D1 / H4 / H1 / M15 contains none, so every slot measures
  a genuinely different horizon.
- **The levels are traded by people.** A D1 kijun and a D1 cloud edge are
  levels other participants act on. For a strategy whose entire premise is
  that price reacts at a level, that matters more than the indicator
  arithmetic.

### Status & caveats

- **Not compiled, not backtested** — same as section 14. No MetaEditor was
  available; the fork was verified to differ from the H4 build only in
  inputs, magic number and order comments, and its shipped defaults were
  checked against the `OnInit` validation rules (trigger/exit/leg slots all
  enabled, exit timeframe not faster than the trigger).
- **The obvious A/B is against the H4 build** on the same symbol and period.
  Both engines are identical, so the entire difference in results is the
  anchor scale — which is the cleanest experiment in this repo, since
  nothing else varies.
- **`InpReactionBars = 8` is a judgement call, not a measurement.** Eight
  M15 bars is two hours of touch window. Daily levels can be worked for a
  full session; if the trade count comes back low, this is the first input
  to widen, before touching the score weights or `InpMinRR`.
- **Expect far fewer trades than the H4 build.** Daily structures are
  touched a handful of times a month, not several times a week. Do not read
  a low trade count as a broken configuration until the map log has been
  checked — with `InpLogMap` on, a run that never produced a setup still
  shows exactly which gate was never passed.
- The score weights remain hand-set rather than fitted, exactly as in
  section 14, and shifting the stack up a scale does not make them any more
  measured.

---

## 16. Karen Peloille Multi-Timeframe EAs (her strategies, made mechanical)

**Files:** `experimental-karen-multitf-ea.mq5`, `experimental-karen-vst-ea.mq5`,
`experimental-karen-kijun-retest-ea.mq5`, `experimental-karen-countertrend-ea.mq5`,
`experimental-karen-candle3-ea.mq5`
**Magic numbers:** `20260840` … `20260844` (one per build — all five can run
side by side on one account, even on the same symbol)

A family of experimental EAs implementing the trading system described by
Karen Peloille in *Trading with Ichimoku: A Practical Guide* (ch. 3-4) and her
article *Trader avec Ichimoku: 3 techniques* (karenpeloille.com). Her system is
discretionary; these builds are a faithful, mechanical approximation for
backtesting on `GOLDm#`.

### Her strategies and which EA implements what

| Strategy (book source) | Rule summary | EA |
|---|---|---|
| **Kijun-break trend continuation** (ch. 4, "Trading with Ichimoku as the only indicator") | 3 time frames per trade: ANALYSIS (prices vs cloud = market state), STRATEGY (Kijun break = the signal, LS validates), MANAGEMENT (entry/exit timing). Pullback to the Tenkan, bounce entry. Exit on Tenkan cross; optional target at the nearest qualifying level with her 1:3 RR gate | `experimental-karen-multitf-ea.mq5` (D1→H4→H1, her "medium term" table) |
| **VST — very short term** (ch. 4, table of horizons) | Same engine on her "short term" table: 60 / 15 / 5 minutes, gated on M5 closes ("always wait for the current candlestick to close") | `experimental-karen-vst-ea.mq5` (H1→M15→M5) |
| **Kijun retest** (ch. 4, EURAUD "Dynamic Market Reading") | Deeper pullback: "A sell trade is initiated on the first red candlestick whose shadow tested the Kijun and validated" — wick test of the Kijun (not the Tenkan), bounce bar closes back above it | `experimental-karen-kijun-retest-ea.mq5` (D1→H4→H1) |
| **Counter-trend at the SSB** (ch. 4 AUDNZD/NZDUSD; article Technique A) | Strong trend on D1, trend confirmed on H4 (beyond its cloud), the correction is faded at the H4 cloud edge — "entrer une position vendeuse sur le niveau de cette SSB". Stop beyond the SSB ("place au-dessus de la SSB"), target the nearest qualifying level, her "fall as far as the 240-minute Kijun" | `experimental-karen-countertrend-ea.mq5` (D1→H4→H1) |
| **3-candle impulse** (ch. 4, "Dynamic Market Reading") | Trends move in impulses of three candles. H4 Kijun break starts the run; on H1 count directional progress candles (Dojis/tests ignored, a close through the Kijun ends the run). Enter at the 2nd candle ("the trader will prefer to take the second candlestick, the first giving the signal and the third being able to reject it"), exit at the 3rd ("the position is unwound as soon as the shadow is formed on the third red candlestick") | `experimental-karen-candle3-ea.mq5` (D1→H4→H1) |

What she says about her own method, worth remembering while testing these:

- "Kijun breaks are what provide trading signals" — not Tenkan/Kijun crossovers,
  which she dismisses as "much too late" (ch. 1).
- The Lagging Span validates every break: "a sell signal validated by the
  Lagging Span in both time frames". All builds gate on the chikou side of the
  strategy-TF Kijun by default.
- "Time frames of 240-minute and 15-minute are of prime importance in
  Ichimoku" — the H4 and M15 slots of these builds carry the signal.
- Stops are technical, tight at entry (the broken Kijun), wider mid-trade
  (SSB), Tenkan at the end: "the position will be closed once the Tenkan is
  broken". The builds approximate this with the entry-TF Tenkan cross exit
  (default), ATR hard stop, chandelier trail and BE30.
- "I personally take only trades with a risk reward ratio of 1:3" — the
  cloud-edge/Kijun target and `InpMinRR` gate implement this.
- "Never pre-empt entry strategies... wait for signals to be confirmed even if
  this means giving up a few extra points" — all entries act on closed bars of
  the management TF.

### Shared engine

All five builds reuse the risk and management machinery of the H4-M1 VPS build
verbatim: equity-tiered ladder sizing, `CapToRisk`, `CapToMargin`, spread
filter, re-entry cooldown, verified closes, ATR-based hard stop on every order,
chandelier trail (ADX choppy filter), BE30 break-even, once-per-minute gating
and push notifications. Only the entry logic, time frames, magic numbers and
order comments differ between them.

### Chikou reading

Identical to the alignment builds: the chikou value is the close of the
reference bar read directly from rates, compared against the Kijun at its
plotted position (`chShift = 1 + Kijun`).

### Karen input table (multi-TF build; the forks share the same shapes)

| Parameter | Default | Description |
|-----------|---------|--------------|
| `InpAnalysisTF` | D1 (VST: H1) | Analysis screen — prices vs cloud, LS optional |
| `InpSignalTF` | H4 (VST: M15) | Strategy screen — the Kijun break + LS validation |
| `InpEntryTF` | H1 (VST: M5) | Management screen — pullback entry, Tenkan exit, stop anchor |
| `InpSignalCloud` | `true` | Strategy-TF close must be on the trade side of its cloud |
| `InpSignalChikou` | `true` | Strategy-TF LS on the trade side of its Kijun |
| `InpAnalysisChikou` | `true` | Analysis-TF LS on the trade side of its Kijun |
| `InpPullbackBars` | 6 | Management-TF bars back to find the Tenkan/Kijun wick test |
| `InpBounceCandle` | `true` | Bounce bar must close in the trade direction |
| `InpChikouEntry` | `true` | Management-TF LS must confirm too |
| `InpMinRR` | 3.0 (counter-trend: 1.5) | Reward:risk gate to the nearest qualifying level (her 1:3) |
| `InpUseTakeProfit` | `true` | TP at the nearest qualifying level beyond entry: analysis-TF Tenkan/Kijun/cloud edge plus the strategy-TF Kijun, quarter-ATR front-run |
| `InpExitMode` | 0 | 0 = entry-TF Tenkan cross, 1 = entry-TF Kijun cross, 2 = strategy-TF Kijun cross |
| `InpLevelBufferATR` | 0.5 | Counter-trend only: stop distance beyond the touched cloud edge |

Counter-trend specifics: the stop is the larger of ATR×`InpATRMultiplier` and
the distance to the H4 cloud edge plus `InpLevelBufferATR × ATR`; the touch is
read against the *current* cloud edge (the edge moves as the cloud recalculates
— a documented approximation); the target is the nearest qualifying level beyond the entry (analysis-TF Tenkan/Kijun/cloud edge, strategy-TF Kijun).

3-candle specifics: `InpCountEntry` (2) and `InpCountExit` (3) drive entry/exit;
the count scans back up to `Kijun + 6` bars; a stale count (the second impulse
candle not being the last closed bar) never enters; the exit also fires when a
bar closes through the Kijun against the trade or when the strategy-TF close
crosses its Kijun back.

### Status & caveats

- **Not compiled, not backtested** — no MetaEditor was available. Files were
  reviewed for identifier/input consistency across all five builds, but treat
  the first tester run as a compile check.
- These are discretionary rules made mechanical: her actual counting of
  candles, level retests and target choices involve judgment the EAs
  approximate (see the approximations noted above).
- The book's original parameter settings are respected: 9-26-52 on every time
  frame ("Changing the original settings damages Ichimoku's ability to provide
  a precise glimpse of price action").
- She trades currencies with these rules; gold is faster and more volatile.
  Expect `InpPullbackBars`, `InpMinRR` and the exit mode to need tuning on
  `GOLDm#`.
## 17. Kumo Breakout EA (flat-kijun filter)

**File:** `experimental-kumo-breakout-ea.mq5` (Magic `20260845`)

A single-timeframe (M1) breakout experiment: price and the chikou span both
must break out of the cloud, the kumo twist must agree, and — the point of
the build — the kijun must be sloping before a trade opens. It directly
tests the concern that breakouts are preceded by flat, choppy areas:
**skip and wait** instead of trading through the noise.

### Rules

- **Entry:** on a closed M1 bar, VPS-style alignment plus breakout: the
  close must be above tenkan, kijun and the cloud top (long) or below
  all three (short), *and* the chikou span must be clear of tenkan,
  kijun and the cloud at its plotted position (`chShift = 1 + Kijun`),
  *and* the kumo twist must agree (Span A above Span B for longs, below
  for shorts). Entry fires while the breakout state holds — if the
  flat-kijun filter blocks the first bar of a breakout, the EA waits and
  enters later in the same move once the kijun angles.
- **Flat-kijun filter:** before opening, the kijun's slope over
  `InpFlatBars` (default 10) M1 bars is checked against `InpFlatATRMult`
  (default 0.15) x ATR(M1). A flat kijun — a move within that threshold —
  skips the trade and waits. Unreadable values count as flat (conservative).
- **Thick-cloud filter:** the cloud itself must be thick — Span A and
  Span B at least `InpMinCloudATR` (default 0.5) x ATR(M1) apart. A thin,
  narrowing cloud is the consolidation the build is designed to avoid, so
  a breakout through it skips and waits until the cloud widens.
  Unreadable values count as thin (conservative).
- **Future-cloud angle:** the cloud drawn Kijun bars ahead of price must
  also be angled in the trade direction — from the last closed bar out to
  the far end of the drawn cloud, both spans must rise (long) or fall
  (short) by more than `InpFlatATRMult` x ATR(M1). A cloud that flattens
  or tilts against the breakout blocks the entry. Unreadable values count
  as not angled (conservative).
- **ADX(51) filters — key levels 9, 17, 26:** at the breakout, the
  directional index in the trade direction must sit in the window
  **(17, 26]** — a buy needs 17 < +DI <= 26, a sell 17 < -DI <= 26.
  Below 17 the breakout is too weak, above 26 it is overextended —
  either way, no trade. The trade-direction DI must also **dominate**
  the other DI (+DI > -DI for a buy, -DI > +DI for a sell) so the
  cross-back exit is well defined. And the +DI/-DI lines must have
  crossed **exactly once** over the last **9** periods: no crossover
  = no setup (the lines haven't just turned), more than one =
  consolidation — either way, no trade. Unreadable values block the
  entry (conservative).
- **Angled kijun:** the kijun must also be angled *in the breakout
  direction* — rising for a long, falling for a short — so the cross fires
  with the trend, not against it.
- **Exit:** close when the trade-direction DI crosses back over the
  other DI line — a long exits on the closed bar where +DI crossed
  below -DI, a short where -DI crossed below +DI. Because entry
  requires the DI to dominate, the cross back is always still ahead of
  the trade. The ATR(M1) stop loss is the only other way out.
- **Risk:** one fixed position of `InpFixedLots` (default 0.10) by
  default — flip `InpUseFixedLots` off to get the H4-M1 VPS equity-tiered
  ladder sizing, `CapToRisk` and `CapToMargin`. Either way: ATR(M1) stop
  loss on every order, spread filter, re-entry cooldown, verified
  closes, once-per-minute gating, no Alert popups (Print + push only).
- **Logging:** skipped entries are journaled with the reason (`InpLogSkips`,
  default on) so the "waiting" behavior is visible — e.g. *kumo breakout but
  kijun flat — skipping and waiting*.

### Flat-kijun filter meaning

The kijun counts as flat when its move over `InpFlatBars` bars is <=
`InpFlatATRMult` x ATR(M1) — the same measure as the reversion build
(section 2) and the structure-map builds (sections 14-15). On M1 gold,
`InpFlatBars = 10` and `InpFlatATRMult = 0.15` means roughly: the kijun may
not have moved more than a bar-and-a-half of typical M1 range over the last
ten bars.

### Why it exists

The previous discussion: breakouts on M1 are preceded by consolidation —
price inside a narrowing cloud, flat lines, whipsaw. The question this
build answers is whether filtering out flat-kijun breakouts and only
entering when the kijun is angled in the trade direction raises the win
rate enough to pay for the later, higher-risk entries it accepts.

The ADX(51) filters add a second layer to that same concern: the
directional index must be strong (above 17), not overextended (26 cap),
dominant over the other DI, and the +DI/-DI lines must have crossed
exactly once in the last 9 periods — a fresh, clean turn with strength
but no chop. The exit then lets the trade run for as long as the
directional push itself lasts: the position is held until the DI lines
cross back over again — the momentum that opened the trade is the
momentum that closes it.

### Crossover possibilities (three ADX lines, six directed events)

With +DI, -DI and ADX, every pairwise crossover exists in both
directions — six events total:

| Event | Meaning | Used by this EA |
|---|---|---|
| +DI crosses **above** -DI | Buy momentum overtakes sell momentum | **Buy setup** (one such cross in the 9-period window) |
| +DI crosses **below** -DI | Buy momentum lost to sell momentum | **Long exit** (cross back) |
| +DI crosses **above** ADX | Buy momentum stronger than average | — |
| +DI crosses **below** ADX | Buy momentum fading below average | — |
| -DI crosses **above** ADX | Sell momentum stronger than average | — |
| -DI crosses **below** ADX | Sell momentum fading below average | — |

The mirror events for a short are -DI crossing **above** +DI (sell
setup) and -DI crossing **below** +DI (short exit, cross back). The
ADX-line crosses are not used — ADX(51) is roughly the average of the
DIs, so a DI crossing ADX is a lagged echo of the DI/DI cross. The
trade exits on the cross back, or the ATR stop.

### Status & caveats

- **Not yet compiled / not yet backtested.** Treat the first tester run as
  a compile check.
- The flat filter necessarily delays entries — the first bars of a real
  breakout can have a still-flat kijun, and this EA will sit those out. The
  `InpLogSkips` journal shows how often that happens.
- Crossover exits react to the DI lines themselves — a trade is held
  only as long as the directional push holds, so givebacks come from the
  lag between price and the ADX(51) lines, not from waiting for price to
  travel back to a level. The ATR stop is the only other way out.
- Single-timeframe by design — the tradeoff being tested is the flat
  filter itself, not multi-TF agreement. `TF_M1` is a single constant at
  the top of the file if a higher timeframe is ever wanted.

---

## 18. Dual-Mode H4/H1 Kijun-Start EA (VPS merge experiment)

**Files:** `experiments/experimental-h4-m1-kijun-start-vps-ea.mq5` (the
experiment), promoted on 2026-08-14 to **`ichimoku-h4-m1-vps-ea.mq5`** — the
single production VPS file replacing both former VPS builds (originals
archived 2026-08-14 as `archives/ichimoku-h4-m1-vps-ea-archived20260814.mq5`
and `archives/ichimoku-h1-m1-vps-ea-archived20260814.mq5`).
Magic `20260846` = H4 mode, `20260847` = H1 mode.

> **Superseded, 2026-08-18.** This top-down dual-mode build is no longer the
> production VPS EA — the H1-bias bottom-up stack (section 20) took over the
> `ichimoku-h4-m1-vps-ea.mq5` / `ichimoku-h4-m1-mt5pc-ea.mq5` filenames. The
> dual-mode files it describes are archived as
> `archives/ichimoku-h4-m1-vps-ea-archived20260818.mq5` and
> `archives/ichimoku-h4-m1-mt5pc-ea-archived20260818.mq5`; the notes below
> describe them as they were.

A single file that merges **both live VPS builds** — `ichimoku-h4-m1-vps-ea.mq5`
and `ichimoku-h1-m1-vps-ea.mq5` — selected with `InpTopTF`:

| Mode | Stack | Kijun exit TF | Filter/cloud TFs | Magic |
|------|-------|---------------|------------------|-------|
| `TOP_H4` (0) | H4→M1 (6 TFs) | M15 kijun cross | M15 kijun-start; cloud bias H4 + M15 | `20260846` |
| `TOP_H1` (1) | H1→M1 (5 TFs) | M5 kijun cross | M5 kijun-start; cloud bias H1 + M5 | `20260847` |

Each mode is byte-identical to its live VPS build for entry, exit, trail,
BE30 and risk — including the mode's own equity ladder (the H1 VPS uses
smaller order batches than the H4 VPS) — with **two extra entry gates**
applied after the full stack alignment fires:

1. **Kijun-start** — the last 3 values of the kijun on the filter TF:
   - **Flat kijun → no entry.** If all three values sit within the
     flatness tolerance of each other, the kijun is flat and the entry is
     skipped entirely. Tolerance: `InpKijunFlatPoints` (default 30 points,
     M15 kijun in H4 mode) or `InpM5KijunFlatPoints` (default 10 points,
     M5 kijun in H1 mode).
   - **Starting to move + angle in the trade direction → entry.** The kijun
     must have *broken out* of the flat tolerance with its newest value
     angled with the trade: rising for a long, falling for a short. A kijun
     moving against the trade, or one whose values are unavailable, also
     blocks the entry.
2. **Cloud bias** — the cloud must carry the trade's bias on both the top
   timeframe and the filter timeframe: **Span A above Span B** (bullish
   cloud) for a long, **Span A below Span B** (bearish cloud) for a short,
   at both the last closed bar and the far end of the future-cloud window
   (shift `1 − Kijun`). A buy never opens under a red cloud.

The cloud-bias condition is inspired by the Kumo breakout EA (section
17) — its alignment check also requires the kumo twist. The kumo build's
*thick-cloud* and *future-cloud angle* requirements were deliberately
**not** ported; the bias alone is the gate.

| Parameter | Default | Description |
|-----------|---------|--------------|
| `InpTopTF` | `TOP_H4` | 0 = H4 stack (H4→M1), 1 = H1 stack (H1→M1) |
| `InpKijunStartEnabled` | `true` | Master switch for the kijun-start filter |
| `InpKijunFlatPoints` | 30 | H4 mode: flatness tolerance (points) for the M15 kijun (3 values within this = flat) |
| `InpM5KijunFlatPoints` | 10 | H1 mode: flatness tolerance (points) for the M5 kijun (3 values within this = flat) |
| `InpCloudBiasEnabled` | `true` | Master switch for the cloud bias filter |

On gold (`GOLDm#`, 1 point = 0.01), 30 points is a third of a dollar —
small enough that a genuinely flat M15 kijun is still caught, large
enough to ignore rounding noise. 10 points is a tenth of a dollar for the
faster-moving M5 kijun.

### Status & caveats

- **Not yet backtested.** Suggested first pass: per mode, run the same
  symbol/period with the filter groups on vs off to isolate each one's
  effect — `InpKijunStartEnabled = false` + `InpCloudBiasEnabled = false`
  is exactly the known VPS baseline for that mode.
- The two modes use distinct magic numbers (`20260846` / `20260847`), so
  an H4-mode and an H1-mode instance can run on the same account/symbol
  without colliding. Note: the archived live VPS EAs used `20260815` (H4)
  and `20260814` (H1) — when replacing a live EA, either close its open
  positions first or point this build's magic at the live values so it
  adopts them.
- The filters necessarily delay entries: the first bar of a real move can
  still have a flat kijun, and this build will sit those signals out until
  the kijun angles and the clouds carry the right bias.
- Only the newest kijun leg (`shift 1` vs `shift 2`) is required to point
  with the trade; the older leg may be flat or already moving — i.e. both
  a *starting* move and a *continuing* one qualify, so long as the whole
  three-value shape is not flat. Tighten to "older two flat, newest
  breaking out" by editing `CheckKijunStart()` if backtests show entries
  too late in the move.

---

## 19. Bottom-Up Stack EA (per-level chain alignment, five tiers)

**File:** `experimental-bottomup-stack-ea.mq5`
**Snapshot:** `experimental-bottomup-stack-ea-very-profitable.mq5` — a saved
checkpoint (touch-only kumo exit, no H4 overextension filter, no ADX trend
filter; see below)
**Magic number:** `20260848` — fresh, distinct from every other build

A structural departure from the single-alignment-gate EAs: instead of one
boolean "all TFs aligned" check that opens one trade, this build treats the
6-TF stack (M1→H4) as five nested tiers and opens a trade at **whichever
tier the alignment currently reaches**, bottom-up:

| Tier | Requires aligned | Opens on |
|------|-------------------|----------|
| M5  | M1 + M5 | M5 |
| M15 | M1 + M5 + M15 | M15 |
| M30 | M1 + M5 + M15 + M30 | M30 |
| H1  | M1 … H1 | H1 |
| H4  | M1 … H4 | H4 |

M1 alone never trades — it's only the base of the chain. `ChainAligned()`
walks the stack from M1 upward and returns the common direction only if
every timeframe up to the tier agrees; a single mismatched TF breaks the
chain for that tier (and every tier above it, since they include it).

### Entry filters (checked before a tier is allowed to open)

- **Cloud bias** (`InpCloudBiasEnabled`, default on) — Span A vs Span B must
  carry the trade's bias, checked at the last closed bar and the far end of
  the future-cloud window, on the tier TF **and** the TF directly below it.
- **H4 bias** (`InpH4Bias`, default on) — H4 is the bias for the *entire*
  stack: H4 bullish allows buys only (a lower-TF sell is just a pullback),
  H4 bearish allows sells only, H4 unaligned blocks every tier, including M5.
- **D1 filter, H4 tier only** (`InpD1Filter`, default on) — the H4 tier also
  needs D1 to carry the same bias; D1 closed inside its own cloud blocks new
  H4 trades (lower tiers are unaffected).
- **H4 overextension filter, H1/H4 tiers only** (`H4Overextended()`) — three
  independent H4-only measures, any one of which blocks new H1/H4 entries
  (M5/M15/M30 may still trade):
  1. **Distance** (`InpOverextDistATR`, default 3.0): last closed H4 close is
     ≥ this × ATR(H4) from tenkan, kijun, *or* the cloud edge (worst-case of
     the three).
  2. **Huge candles** (`InpOverextCandleATR`, default 2.5): the max range of
     the last 3 closed H4 bars is ≥ this × ATR(H4) — the trending candles
     have gotten enormous.
  3. **No touch** (`InpOverextNoTouch`, default 26 bars): no H4 candle in the
     lookback window has touched tenkan, kijun, or the cloud — price has run
     away from every pullback reference.
  Any sub-check set to `0` is disabled; unreadable data is treated as "not
  overextended" (allows entry).
- **Trend strength** (`InpTrendADX`, default on) — H4 ADX must be ≥
  `InpTrendADXLevel` (default 25) for *any* tier to open; a flat/choppy H4
  blocks the whole stack, not just H1/H4.

### Entry consolidation (one position per symbol)

When several tiers align at the same moment, only the **largest** (highest
TF) tier opens — any smaller tier already running on the symbol is closed
first (`superseded by <TF>`). So at most one position runs per symbol at a
time, always the highest tier the chain currently reaches.

### Exit logic

Two independently-configurable layers:

- **Cloud exit** (`InpKumoExit`) — the trade's main exit, evaluated once per
  closed M1 bar:
  - `KUMO_TOUCH` (0, default): exits the instant price **touches** the tier
    TF's cloud edge intra-bar — fast, but a normal trend pullback that
    grazes the cloud cuts the trade short.
  - `KUMO_CLOSE` (1): waits for the tier TF bar to **close** inside (or
    beyond) the cloud — rides trends further, added after the touch-only
    snapshot below.
- **Rejection candle exit** (`InpRejectionExit`, default **off**) — closes a
  trade when a very strong rejection candle forms against it on the tier TF:
  all four conditions must hold — opposing body, sweeps the swing extreme of
  the last `InpRejSwingBars` bars, wick ≥ `InpRejWickPct` of the range, close
  in the outer `InpRejClosePct` of the range.
- **Profit protection** (always on, once a trade is green): break-even once
  profit ≥ `InpBEProfitATR` × ATR (or the tighter `InpBEProfitH1H4` for the
  H1/H4 tiers), then an ATR chandelier trail behind the peak — H1/H4 arm at
  `InpTrailActivateATR` × ATR, M5/M15/M30 only arm on a spike
  (`InpSpikeLockATR` × ATR). Both are tighten-only and use each level's own
  TF for ATR.
- **No entry stop loss.** The trade runs naked until an exit fires; the BE/
  trail layer is the only protection until then.

### Risk sizing — three equity tiers, de-risking as the account grows

Every trade risks a fixed % of **actual equity at entry** against a
reference distance of `ATR(level TF) × InpRiskATRMult` (sizing basis only —
no stop is attached at that distance). The % drops as equity grows:

| Regime | Equity | M5 | M15 | M30 | H1 | H4 |
|--------|--------|----|-----|-----|----|----|
| Tier 1 (full) | < `InpRiskTier2At` ($7000) | 1% | 1% | 5% | 10% | 20% |
| Tier 2 (half) | $7000–$13000 | 0.5% | 0.5% | 2.5% | 5% | 10% |
| Tier 3 (tiny) | ≥ `InpRiskTier3At` ($13000) | 0.1% | 0.1% | 0.2% | 1% | 2% |

Falls back to `InpFixedLots` when ATR/tick sizing data is unavailable; every
order is capped to free margin so it fills fully.

### The "very-profitable" snapshot

`experimental-bottomup-stack-ea-very-profitable.mq5` was saved (commit
`5fdd401`) as a checkpoint of a run described as very profitable, before the
H4 overextension filter, ADX trend-strength filter, and `KUMO_CLOSE` exit
mode were added — it has `InpKumoExit` hard-coded to touch-only, the D1
filter and 3-tier risk regime already in place, and no
`H4Overextended()`/`H4TrendOK()` gates at all. Useful as an A/B baseline
against the current file to see what those three additions changed.

### Status & caveats

- **Not yet backtested.** No F7 compile/Strategy Tester run recorded in this
  repo — the "very-profitable" label describes a prior manual/demo run, not
  a reproduced backtest artifact.
- **No entry stop loss** — every position is naked until BE arms; a fast
  adverse move right after entry has nothing to catch it before the cloud
  exit or a manual close.
- **Overextension and ADX filters are new and unvalidated** — compare
  against the `-very-profitable` snapshot (which lacks both) to see whether
  they help or just reduce trade count.
- **`KUMO_TOUCH` is the default** even though `KUMO_CLOSE` was added to let
  trends run further — hasn't been A/B'd yet; flip `InpKumoExit` to compare.
- Five tiers × per-symbol state means CPU/array usage scales with
  `symsCount × LEVELS` — trivial for a handful of symbols, worth checking
  before scaling `Symbols` up toward `MAX_SYMS` (60).

---

## 20. Bottom-Up Stack EA — H1 Bias variant *(promoted to the main builds)*

**File:** `experimental-bottomup-stack-h1-bias-ea.mq5`
**Forked from:** `experimental-bottomup-stack-ea-very-profitable.mq5` (the
"very profitable" snapshot running on the VPS — section 19)
**Magic number:** `20260850`

> **Status: promoted, 2026-08-18.** This variant is now the production
> strategy. Its code was copied to `ichimoku-h4-m1-vps-ea.mq5` (VPS, magic
> `20260850` carried over so positions it already opened keep being managed)
> and to `ichimoku-h4-m1-mt5pc-ea.mq5` (desktop, magic `20260852`, plus
> `Alert()` popups on every entry/exit and the weekly equity reminder). The
> top-down alignment builds that previously held those filenames were
> archived as `archives/ichimoku-h4-m1-vps-ea-archived20260818.mq5` and
> `archives/ichimoku-h4-m1-mt5pc-ea-archived20260818.mq5`. The write-up below
> describes the strategy as it was developed here; the main
> [README](../README.md#how-the-strategy-works) now documents it as the
> shipped behaviour. Edit the root files, not this one, for live changes.

A single-change fork of the very-profitable snapshot. Everything else — the
five-tier bottom-up chain, the touch-only kumo exit, the cloud bias gate, the
3-tier equity risk regime, the BE/chandelier protection layer, no entry stop
loss — is byte-for-byte the snapshot. The one addition is a **second, smaller
directional bias on H1**, so that an undecided H4 no longer freezes the whole
stack.

### The problem it addresses

In the snapshot, `InpH4Bias` makes H4 the bias for *every* tier: H4 bullish
allows buys only, H4 bearish sells only, and **H4 unaligned blocks all five
tiers, M5 included**. H4 spends a large share of the time neither above nor
below its own tenkan/kijun/cloud (or with the chikou disagreeing), and during
those stretches a perfectly clean M1→M30 chain produces no trade at all.

### What the H1 bias does

When H4 offers no direction, the lower tiers may fall back on H1: a tier at or
below `InpH1BiasMaxTier` opens if **H1 itself is aligned** with the trade —
the same price + chikou vs tenkan/kijun/cloud test the H4 bias uses, one
timeframe down. The H4 bias is untouched as the primary path, and the D1
filter on the H4 tier is untouched as well.

Resolution order in `EntryBiasOK()`, evaluated after the chain and cloud-bias
checks the snapshot already ran:

| H4 state | Tier ≤ `InpH1BiasMaxTier` | Tier above it (H1/H4) |
|----------|---------------------------|------------------------|
| Aligned **with** the trade | opens (logged `bias H4`) | opens (logged `bias H4`) |
| **Flat** (unaligned / in its cloud) | opens **if H1 is aligned** (logged `bias H1`) — **new** | blocked, as before |
| Aligned **against** the trade | blocked, unless `H1BIAS_ALWAYS` (then logged `bias H1x`) | blocked, as before |

The H4 tier can never use the stand-in — it always needs H4 *and* D1 itself.

### New inputs

| Input | Default | Meaning |
|-------|---------|---------|
| `InpH1BiasMode` | `H1BIAS_FLAT_H4` (1) | `0` = off (identical to the snapshot), `1` = stand in only while H4 is flat, `2` = stand in even against an aligned H4 (counter-H4 on the lower tiers) |
| `InpH1BiasMaxTier` | `H1TIER_M30` (2) | Highest tier allowed to enter on the H1 bias — `0` M5, `1` M15, `2` M30, `3` H1. The H4 tier is deliberately not an option |
| `InpH1BiasCloudCheck` | `true` | Also require the H1 kumo (Span A vs Span B, now and at the far end of the future cloud) to carry the trade's bias |

Setting `InpH1BiasMode = H1BIAS_OFF` reduces the build exactly to the
snapshot's entry behaviour — that's the A/B baseline switch.

Every entry now logs which bias authorised it (`… (bottom-up, bias H4)` /
`bias H1` / `bias H1x`), so the journal separates the new H1-bias trades from
the H4 ones without having to reconstruct the H4 state after the fact.

### Note on `InpH1BiasMaxTier = H1TIER_H1`

At the H1 tier the chain check already requires M1…H1 aligned, so the H1 bias
is trivially satisfied there. Opening that tier up therefore means "the H1
tier trades whenever its chain aligns and H4 isn't opposed" — a much larger
loosening than the M5/M15/M30 default, and the H1 tier carries tier-1 risk of
10% equity. Treat it as a separate experiment, not a default.

### Status & caveats

- **Not backtested when it was promoted.** No F7 compile or Strategy Tester
  run is recorded in this repo for it; it went live on the strength of the
  snapshot's forward results plus the reasoning above. Compile and test any
  further change before it reaches the account.
- **More trades means more of everything**, including drawdown. The tiers
  this opens up are exactly the ones the H4 bias was suppressing, and they
  run with the snapshot's risk table (M5/M15 1%, M30 5% of equity in tier 1)
  and **no entry stop loss**. A/B it against `InpH1BiasMode = H1BIAS_OFF` on
  the same period before judging it.
- **A flat H4 is not the same as a safe H4.** H4 unaligned often means a
  range or a turn; the H1 stand-in deliberately trades into that, relying on
  the touch-only kumo exit to cut losers fast.
- **`H1BIAS_ALWAYS` is genuinely counter-trend** on the lower tiers — the H4
  bias exists precisely to stop those entries. Off by default for that reason.
- Trade count still passes through entry consolidation: when H4 later aligns
  and the H4 tier opens, any lower tier opened on the H1 bias is closed and
  superseded, exactly as before.

---

## 21. Bottom-Up Stack EA — D1..M1 stack with a bias ladder

**File:** `experimental-bottomup-stack-d1-ladder-ea.mq5`
**Forked from:** `experimental-bottomup-stack-h1-bias-ea.mq5` (section 20),
which is left untouched
**Magic number:** `20260851` — fresh, so it runs alongside the live builds
(VPS `20260850`, desktop `20260852`), the snapshot (`20260848`) and the
archived top-down builds (`20260846`/`20260847`, `20260830`/`20260831`)

Takes the H1-bias build and changes the stack's top end and how entries are
qualified. Everything else — the bottom-up chain, the touch-only kumo exit,
the cloud bias gate, the equity risk regime, the BE/chandelier protection
layer, no entry stop loss — is unchanged. Three additions:

1. a **D1 tier** on top of H4, so the full M1…D1 chain is tradable;
2. a **flat-kijun filter on every timeframe**, so a breakout over a stalled
   kijun is not an alignment at all; and
3. a **bias ladder** — D1 → H4 → H1 — in which a *flat* step stands aside and
   hands the tiers below to the next step down, while an *opposed* step still
   blocks.

### The six tiers

| Tier | Chain required | Bias above it |
|------|----------------|---------------|
| M5 | M1 + M5 | H4, or H1 as stand-in |
| M15 | M1 … M15 | H4, or H1 as stand-in |
| M30 | M1 … M30 | H4, or H1 as stand-in (default `InpH1BiasMaxTier`) |
| H1 | M1 … H1 | H4 (stand-in only if `InpH1BiasMaxTier = H1TIER_H1`) |
| H4 | M1 … H4 | the D1 step (`InpD1Filter`) |
| **D1** | **M1 … D1** | **none — its own chain is the bias** |

Consolidation is unchanged: when several tiers align at once only the largest
opens, and smaller tiers already running on the symbol are closed first. D1
now sits at the top of that ordering, so an aligning D1 tier supersedes a
running H4 trade.

The D1 tier inherits the H1/H4 branch of the protection layer (`lvl >= 3`):
the tighter `InpBEProfitH1H4` break-even and the `InpTrailActivateATR`
chandelier trail, both measured against ATR(D1). Its exit is the same
touch-only kumo exit, on the D1 cloud.

### Flat-kijun filter — inside the alignment test

`CheckAlign()` requires the timeframe's own kijun to be sloping the same way
as the breakout. The test compares **two values** — the last two closed bars —
and flat means they are the *same*:

```
kijun[1] > kijun[2]  → rising     (+1)
kijun[1] < kijun[2]  → falling    (−1)
kijun[1] = kijun[2]  → FLAT        (0)   → that TF is not aligned, either way
```

No ATR tolerance: the kijun is the midpoint of its own `Kijun`-period high/low
range, so an unchanged kijun means that range has not moved at all and price
is merely rotating inside it. The comparison is exact — the epsilon in the
code is `SYMBOL_POINT × 0.01`, there to absorb float noise, not to act as a
tolerance band. `InpKijunFlatBars` sets the gap between the two values read
(default `1` = the last two closed bars); raising it compares further back.

Because the requirement lives inside `CheckAlign()`, it applies **everywhere
that function is used**: every rung of a tier's chain (M1 included) and every
step of the bias ladder. There is no separate bias-only guard.

| Input | Default | Meaning |
|-------|---------|---------|
| `InpKijunFlatGuard` | `true` | Require a sloping kijun on every TF. `false` restores the pure price+chikou test — i.e. section 20's entry behaviour |
| `InpKijunFlatBars` | `1` | Gap between the two kijun values compared — `1` is the last two closed bars (clamped to ≥ 1) |

The per-level `atr[]` and the separate `ichD1[]` daily handle of section 20
collapsed into one per-TF array (`atrTF[sym][tf]`, `InpATRPeriod`) when D1
joined the stack. ATR plays no part in the flat test, so the M1 slot is unused
and stays `INVALID_HANDLE`; ATR is still what risk sizing, the break-even and
the trail measure against, per tier TF.

### The bias ladder

Each step gates the tiers below it. The key property: **flat is not a veto,
it is a hand-off.**

| Step | Aligned with the trade | Flat (no breakout, or flat kijun) | Aligned against |
|------|------------------------|-----------------------------------|-----------------|
| D1 | authorises the H4 tier (logged `bias D1`) | no D1-tier trade; the H4 tier stands on H4 itself | blocks the H4 tier |
| H4 | authorises every tier below (logged `bias H4`) | no H4-tier trade; tiers ≤ `InpH1BiasMaxTier` may open on H1 | blocks, unless `H1BIAS_ALWAYS` |
| H1 | authorises the stand-in (logged `bias H1`) | nothing opens on the stand-in | no stand-in |

So a flat daily stops daily trades without freezing H4; a flat H4 stops H4
trades without freezing M5–M30; and since the flat-kijun filter is part of
alignment, "flat" now includes "broke out but the kijun has stalled".

`InpD1Filter` became a three-way mode for the daily step:

| Value | Behaviour |
|-------|-----------|
| `D1F_OFF` (0) | no daily step at all |
| `D1F_NOT_OPPOSED` (1, default) | only an opposed D1 blocks the H4 tier; a flat D1 stands aside |
| `D1F_REQUIRED` (2) | D1 must itself carry the trade — section 20's strict filter |

`InpH1BiasMode` / `InpH1BiasMaxTier` / `InpH1BiasCloudCheck` are unchanged
from section 20, and the H4 and D1 tiers still never use the stand-in.

Every entry logs the step that authorised it — `… (bottom-up, bias D1)` /
`bias H4` / `bias H1` / `bias H1x` — so the journal separates ladder levels
without reconstructing state after the fact.

### Risk for the D1 tier

`InpRiskPctD1` = **20 / 10 / 2** across the three equity regimes — the same
row as H4, deliberately *not* the next doubling the lower ladder implies
(1, 1, 5, 10, 20 → 40 would be reckless on a build with no entry stop loss).
Treat it as a starting point to tune, not a validated number.

### Status & caveats

- **Not backtested, not compiled here.** No F7 compile or Strategy Tester run
  is recorded in this repo. Compile and test before this goes near an account.
- **Trade count drops.** Every rung of every chain now needs a moving kijun,
  M1 included. The D1 tier in particular needs all seven timeframes aligned
  *and* sloping at once — expect it to fire rarely, which is the point, but
  verify it fires at all over your test window before concluding the wiring
  works.
- **The ladder cuts both ways.** `D1F_NOT_OPPOSED` *loosens* the H4 tier
  relative to section 20's strict D1 filter (a flat daily no longer blocks
  it), while the flat-kijun filter tightens everything. A/B those two
  separately — `InpD1Filter = D1F_REQUIRED` and `InpKijunFlatGuard = false` —
  or the effects will be impossible to attribute.
- **The flat test is exact, so it is strict on the fast timeframes.** One
  point of movement between the last two M1 kijun values counts as "sloping".
  That makes the filter mostly a *stall* detector — it removes the dead-flat
  kijun of a tight range, not the shallow drift of a weak trend. If the intent
  is to demand real slope, raise `InpKijunFlatBars` so the two values sit
  further apart.
- **A flat H4 is still not a safe H4.** The H1 stand-in deliberately trades
  into an undecided daily/4-hour picture, relying on the touch-only kumo exit
  to cut losers fast.
- **No entry stop loss** — every position is naked until BE arms, and the D1
  tier carries 20% of equity in the tier-1 regime.
- **Section 20's `.set` files will not load here**: `InpD1Filter` is an enum
  rather than a `bool`, and the risk inputs gained a D1 row.

---

## 22. Bottom-Up Stack EA — standard-account build ($100 start)

**File:** `experimental-bottomup-stack-standard-account-ea.mq5`
**Forked from:** `experimental-bottomup-stack-h1-bias-ea.mq5` (the H1-bias
variant, magic `20260850` — the version currently deployed), which is left
untouched. That parent's executable code is identical to the live VPS build
`ichimoku-h4-m1-vps-ea.mq5` apart from one input-group label, so this fork
carries the same strategy either way.
**Magic number:** `20260854` — fresh, so a standard-account instance never
adopts or manages positions belonging to the H1-bias parent / VPS build
(`20260850`), the desktop build (`20260852`), the D1-ladder fork
(`20260851`) or anything archived

The same strategy re-scaled for a **standard (full-size) account funded with
about $100**. The trading logic is byte-for-byte the parent's — bottom-up
chain alignment, H4 bias with the H1 stand-in, D1 filter on the H4 tier,
touch-only kumo exit, BE + chandelier protection, no entry stop loss. **Only
the money management differs.** `diff` the two files and every hunk should
land in the risk inputs, the sizing functions, or the entry call site.

### Why a separate build at all

On a standard account the smallest lot the broker accepts (0.01) is a
hundred times the exposure of the same number on a cent-sized account. On
gold, 0.01 lot = 1 oz ≈ $1 of P/L per $1 of price.

The parent's sizing ends with `MathMax(lotMin, MathMin(lotMax, lots))`.
Whenever the risk-correct size falls below the broker minimum, that line
silently rounds the order **up** and the trade risks whatever the minimum lot
happens to risk — not what its tier asked for. On a cent-sized account the
minimum is tiny and the rounding is harmless. On a $100 standard account it
is the *dominant* risk: an H4 trade against a reference distance of
ATR(H4) × 2 (≈ $50 of gold) risks ≈ $50 at 0.01 lot, half the account, no
matter what percentage is configured.

### What changed

1. **Every risk percentage is exactly a quarter of the parent's**, in the
   same three-tier de-risking shape:

   | Regime | Equity | M5 | M15 | M30 | H1 | H4 |
   |--------|--------|----|-----|-----|----|----|
   | Tier 1 (full) | < `InpRiskTier2At` ($700) | 0.25% | 0.25% | 1.25% | 2.5% | 5% |
   | Tier 2 (half) | $700–$1300 | 0.125% | 0.125% | 0.625% | 1.25% | 2.5% |
   | Tier 3 (tiny) | ≥ `InpRiskTier3At` ($1300) | 0.025% | 0.025% | 0.05% | 0.25% | 0.5% |

   That is the parent's ladder (1/1/5/10/20 → 0.5/0.5/2.5/5/10 →
   0.1/0.1/0.2/1/2) divided by four throughout.

2. **Equity thresholds scaled to the smaller start** — $700 and $1300,
   i.e. the parent's 7000/13000 in the same ratio against a $100 account,
   so the de-risking still triggers after a 7× and a 13× rather than after a
   gain the account can never reach.

3. **Minimum-lot honesty gate** (`InpMinLotMaxRiskPct`, default 10%) — the
   substantive change. When the risk-correct size rounds below `InpMinLots`
   (0.01), `SizedLots()` prices what that minimum lot would actually risk
   over the reference distance and **skips the entry** when it exceeds
   `InpMinLotMaxRiskPct` of equity. Set it to 0 to refuse every minimum-lot
   trade outright; raise it to re-enable the parent's round-up knowingly.

4. **No silent fixed-lot fallback** — `InpFixedLots` defaults to 0, so a
   trade whose ATR/tick sizing data is unavailable is skipped rather than
   sent at an arbitrary size. Set it to 0.01 to restore a fallback.

5. **Margin cap skips instead of clamping up** — an order the free margin
   cannot carry at the minimum lot is skipped, where the parent clamped
   `maxLots` back up to `lotMin` and sent it anyway.

6. **Sizing now runs before the supersede-close.** In the parent the
   entry consolidation closes every smaller running tier and *then* sizes the
   winner. With the gate in place a blocked higher tier would kill a
   perfectly good M5 trade and open nothing, so `SizedLots()` is called
   first and a zero result skips the whole consolidation. The margin cap
   still runs after the closes, when their margin has been released.

Skips are logged to the journal, throttled to one line per symbol/level per
hour so a tier that stays aligned and blocked for hours does not flood it.

### What this actually does at $100 — read this before deploying

Modelled on gold with typical ATR (M5 $2, M15 $4, M30 $6, H1 $10, H4 $25)
and the default 10% cap:

| Equity | M5 | M15 | M30 | H1 | H4 |
|--------|----|-----|-----|----|----|
| $100 | 0.01 (4% risk) | 0.01 (8%) | **skip** (12%) | **skip** (20%) | **skip** (50%) |
| $700 | 0.01 (0.6%) | 0.01 (1.1%) | 0.01 (1.7%) | 0.01 (2.9%) | 0.01 (7.1%) |
| $1300+ | 0.01 (0.3%) | 0.01 (0.6%) | 0.01 (0.9%) | 0.01 (1.5%) | 0.01 (3.8%) |

Two things follow, and neither is a bug:

- **At $100 only the fast tiers can trade.** M30/H1/H4 stay blocked until
  equity is large enough that a minimum lot is a sane fraction of it, then
  unlock on their own. That is the intended behaviour of the gate — the
  alternative is an H4 trade risking half the account.
- **The risk percentages are not the binding constraint at this size.** Every
  trade is 0.01 lot because the risk-correct size is far below it; the
  percentages only start to govern lot size once equity reaches roughly
  $10k–$20k on gold. Below that, what actually controls risk per trade is
  `InpMinLotMaxRiskPct` and the ATR of the tier. Tune that input, not the
  risk table, while the account is small.

### Status & caveats

- **Not compiled, not backtested here.** No F7 compile or Strategy Tester run
  is recorded in this repo. Compile and demo-test before this touches money.
- **The tier thresholds are a judgement call.** $700/$1300 preserve the
  parent's 7000:13000 ratio against a $100 start, but they de-risk the account
  at roughly the point where the risk table would otherwise have started to
  bind, keeping it inert for longer. Leaving them at 7000/13000 is a
  defensible alternative and a one-input change.
- **The 10% default cap is not a validated number**, it is a starting point
  chosen so the fast tiers can trade at $100 while the big ones cannot. It
  is still a 10%-of-equity loss per trade in the worst case, on a build with
  **no entry stop loss** — the reference distance is a sizing basis, not a
  stop, and a gap can exceed it.
- **`.set` files from the parent will not load here** — `InpFixedLots`
  changed meaning and `InpMinLots` / `InpMinLotMaxRiskPct` are new.
- **Cent-account instances must not run this file**, and vice versa: the
  magic numbers differ deliberately so the two never manage each other's
  positions.

---

## 23. Bottom-Up Stack EA — M1 as a tradable tier

**File:** `experimental-bottomup-stack-m1-tier-ea.mq5`
**Forked from:** `experimental-bottomup-stack-h1-bias-ea.mq5` (section 20 —
the build promoted to the VPS and desktop EAs), which is left untouched
**Magic number:** `20260856` — fresh, so this fork never adopts or manages
positions belonging to the VPS build (`20260850`), the desktop build
(`20260852`), the D1-ladder fork (`20260851`) or the standard-account build
(`20260854`)

One change to the promoted build: **M1 trades**. Everything else — the
per-TF alignment test, the per-tier kumo-touch exit, the H4 bias with its H1
stand-in, the D1 filter on the H4 tier, entry consolidation, the 3-tier
equity risk regime, the BE/chandelier protection layer, no entry stop loss —
is the parent's.

### M1 as a tier

In the parent, M1 is the foot of every chain and never opens anything: the
header says so outright, *"M1 alone never trades — it is only the start of
the stack."* Here it becomes a sixth tier. `LEVELS` goes from 5 to 6 and a
tier's index is now its own index in `tfs[]` rather than one above it, so
tier 0 is M1 and its chain check (`ChainAligned(s, 0)`) is simply M1 aligned
on its own — a chain of one.

Everything that was keyed to the tier index moved with it:

| | Parent | This build |
|---|---|---|
| Tier → TF (entry, ATR, exit cloud, rejection candle) | `tfs[lvl + 1]` | `tfs[lvl]` |
| Cloud bias pair | TF `lvl` and TF `lvl + 1` | TF `lvl - 1` and TF `lvl` (the M1 tier has nothing below it, so only the M1 cloud is checked) |
| Tighter BE / full chandelier | `lvl >= 3` (H1, H4) | `lvl >= 4` (H1, H4 — same two tiers) |
| `ENUM_H1_BIAS_TIER` | `0` M5 … `3` H1 | `0` M1, `1` M5, `2` M15, `3` M30, `4` H1 |

`InpH1BiasMaxTier` still defaults to `H1TIER_M30`, which is now the value
`3` rather than `2` — **a `.set` file from the parent build will not carry
over correctly**, because the same stored number means a different tier.

The M1 tier gets its own risk row, half of M5 in each regime — `InpRiskPctM1`
0.5% (tier 1), `InpRiskPctM1_T2` 0.25%, `InpRiskPctM1_T3` 0.05% — sized like
every other tier against ATR(M1) × `InpRiskATRMult`. Half of M5 is a
judgement call, not a tested number: M1 is the noisiest tier and the one that
will fire most often, so it starts smaller than the tier above it.

### Exits are unchanged — each tier on its own cloud

The parent's exit rule carries over exactly: a trade is closed when price
**touches** the edge of the cloud on the tier's **own** timeframe — the M1
tier on the M1 cloud, M5 on the M5 cloud, M15 on M15, up to H4 on the H4
cloud. No wait for a candle to close inside the kumo, checked on every closed
M1 bar. An H4 trade still runs until the H4 cloud is reached; only the new M1
tier exits on the fastest kumo, because that is its own.

Two consequences for the M1 tier fall out of the entry rule rather than being
coded:

- **An M1 trade can never open already touching its exit.** Entry requires M1
  aligned, which means price is clear of the M1 cloud in the trade's
  direction.
- **The M1 tier cannot immediately re-open after exiting.** Price touching
  the M1 cloud breaks M1's alignment, and M1 alignment is the foot of every
  chain — so same-bar churn is self-limiting. It resumes as soon as price
  clears the M1 cloud again, which on M1 can be within a few bars.

### New inputs

| Input | Default | Meaning |
|-------|---------|---------|
| `InpRiskPctM1` | `0.5` | M1 tier risk, % of equity, regime 1 (< `InpRiskTier2At`) |
| `InpRiskPctM1_T2` | `0.25` | M1 tier risk, half regime |
| `InpRiskPctM1_T3` | `0.05` | M1 tier risk, tiny regime |
| `InpH1BiasMaxTier` | `H1TIER_M30` (now `3`) | Same default tier as the parent, different stored value — see above |

### Status & caveats

- **Not compiled, not backtested here.** No F7 compile or Strategy Tester run
  is recorded in this repo for it. Compile and demo-test before it touches
  money.
- **The M1 tier fires on the loosest condition in the family** — one
  timeframe aligned, plus the M1 cloud bias and whichever bias (H4 or the H1
  stand-in) authorises it. Expect a much higher trade count than the parent
  and a much lower average hold, with commission and spread mattering
  proportionally more; `InpMaxSpreadPoints` is doing real work here.
- **BE and the chandelier trail rarely get a chance on the M1 tier.** They
  arm off ATR of the tier's own TF, and ATR(M1) thresholds sit inside the
  broker's minimum stop distance on many symbols; the M1 kumo touch will
  usually fire first.
- **Entry consolidation still applies**, so the M1 tier is superseded and
  closed the moment a larger tier aligns — it is the tier of last resort, not
  an extra position alongside the others.
- **Setting `InpRiskPctM1` to 0 does not disable the tier**, it falls back to
  `InpFixedLots` (`LevelRiskPct` → `RiskLots`), same as every other tier in
  this family. To run the parent's behaviour, run the parent.

---

## 24. Bottom-Up Stack EA — REFINED experiment (consolidation hardening)

**File:** `experimental-bottomup-stack-refined-ea.mq5`
**Forked from:** `ichimoku-h4-m1-vps-ea.mq5` (the live VPS build, magic
`20260850`), which is left untouched. The parent's executable code is
byte-for-byte the VPS build; every change below is additive and marked
`(REFINED)` in the code.
**Magic number:** `20260857` — fresh, so this experiment never adopts or
manages positions belonging to the live builds (`20260850` VPS, `20260852`
desktop) or any other fork.

### What changed (all in one build, each toggleable)

1. **Per-tier cloud exit modes** (`InpKumoCloseFrom`, default `KUMO_CLOSE_M30`):
   tiers at/above the setting (M30, H1, H4 by default) exit when the tier TF
   bar **closes** inside the cloud; M5/M15 keep the touch exit. `0` = touch
   everywhere (parent behaviour). Trend-profit experiment — lets H1/H4 runs
   survive pullbacks that only graze the kumo.
2. **Bias kijun-slope stall filter** (`InpKijunFlatGuard`, default on, with
   `InpKijunFlatBars`): the D1, H4 and H1 *bias* timeframes additionally need
   a SLOPING kijun (last two values differ) to authorise entries. Unlike the
   D1-ladder fork (section 21), the guard is NOT inside `CheckAlign` — the
   lower-TF chain/breakout triggers keep the pure price + chikou test. A
   price-aligned but kijun-stalled H4 counts as FLAT, so the H1 stand-in may
   cover the lower tiers. Consolidation experiment — dead-flat kijuns are the
   stall signature of a range.
3. **High-water-mark risk regime**: `LevelRiskPct()` now picks the tier from
   `max(current equity, peak equity)`, the peak stored in a terminal global
   variable (`EA_Refined_PeakEq_<login>`) and ratcheted once per minute. The
   regime de-risks one-way: a drawdown can never re-arm the full-risk tier
   (H4 20% / H1 10% / M30 5%). `InpResetPeakEquity` = true once re-baselines.
   Pure downside protection — in a trend the peak only ratchets up, so the
   regime path is unchanged.
4. **Daily loss circuit breaker** (`InpDailyLossLimitPct`, default 10%):
   once the day loses that % of its start equity (day anchor in GVs), NEW
   entries stop until the next day. Open positions are still managed and
   exited; only entries are blocked. Announced once per day via push.
5. **News blackout** (ported from the windows-laptop build): MT5 Economic
   Calendar high-impact events — flatten
   `InpNewsBlockBeforeMin` (60) before, block entries until
   `InpNewsBlockAfterMin` (5) after. Fails OPEN when the calendar is
   unavailable; the Strategy Tester has no calendar, so backtests trade as
   if no news existed.
6. **Disaster stop** (`InpDisasterStopATR`, default 4.0, 0 = off): a wide
   entry SL at 4 x ATR(level TF) attached at entry, replacing the fully
   naked entry when enabled; only ever tightens afterwards via BE/chandelier.
   Skips the SL (naked entry) if data is unavailable or the stop sits inside
   the broker minimum distance.
7. **Cloud bias gate — far-end only** (`CloudBiasOK` rewritten): the gate
   now reads ONLY the projected kumo 26 bars ahead (shift `1 - Kijun` on
   Span A / Span B) and requires the twist there alone — Span A above Span
   B for a long, below for a short. The cloud under current price is
   deliberately NOT required to agree; price + chikou vs the kumo remains
   the alignment test's job. Applies to the tier TF pair (level TF + the
   TF below it) and to the H1 stand-in cloud confirmation. Design decision
   by the owner: the future cloud is the only cloud that matters for the
   bias.

### A/B switches

- `InpKijunFlatGuard = false` restores the parent's bias tests.
- `InpKumoCloseFrom = KUMO_CLOSE_OFF` restores the touch-only exit.
- `InpDisasterStopATR = 0` restores naked entries.
- `InpDailyLossLimitPct = 0` disables the daily breaker.
- `InpNewsFilterEnabled = false` disables the news blackout.
- The far-end-only cloud gate cannot be switched off in this build (it is
  the owner's design decision); the parent's near+far twist is the
  baseline to A/B against.
- The HWM regime cannot be switched off (it is the point of the build);
  `InpResetPeakEquity` re-baselines it.

### Status & caveats

- **Not compiled, not backtested here.** No F7 compile or Strategy Tester
  run is recorded in this repo. Compile and test before this goes near an
  account.
- **The stack still runs** — one position per level per symbol, so a full
  H4+H1+M30+M15+M5 stack can be open at once (tier 1 = 37% of equity at
  risk on one symbol). This is the parent's actual behaviour; the parent's
  header claimed one position per symbol, which this build's header
  corrects. No per-symbol total-risk cap was added — not requested.
- **The daily breaker and HWM use terminal global variables**: in the
  Strategy Tester they persist per test run; on live accounts they survive
  restarts and recompiles. If a backtest run carries over a peak from a
  previous run, reset via `InpResetPeakEquity` or clear the terminal GVs.
- **KUMO_CLOSE on M30+ changes the exit lag structure**: the exit now waits
  for a tier-TF close, so an M30 trade can ride a pullback up to the M30
  bar close. Expect fewer, larger exits on the upper tiers; A/B against
  `KUMO_CLOSE_OFF` on both the 2026 trend window and a range window.

---

## 25. Bottom-Up Stack EA — new kumo-breakout definition (M1..D1), M30 bias, tenkan-close exits

**File:** `experimental-bottomup-stack-m30-bias-ea-third-most-profitable.mq5`
**Rank:** third most profitable build in the family so far (user report,
2026-08-20) — behind the m1-strict and m1m5-strict cloud-bias builds
(1st and 2nd, sections 26 and 27)
**Forked from:** `ichimoku-h4-m1-vps-ea.mq5` (the live VPS build, magic
`20260850`), which is left untouched
**Magic number:** `20260855` — fresh, so this experiment never adopts or
manages positions belonging to the live builds (`20260850` VPS, `20260852`
desktop) or any other fork

Two changes to the promoted build; everything else is byte-for-byte the
parent's.

1. **New kumo-breakout definition, all timeframes M1..D1 (fundamental).**
   The per-TF test behind the entry chains (`CheckAlign`, on M1/M5/M15/
   M30/H1/H4), the H4 and H1 biases (they call the same test), the D1
   filter (`DailyAlign`) and the M30 gate now defines a valid kumo
   breakout as exactly:
   - **price** beyond the kumo — the last closed bar's close above the
     cloud's upper edge (bullish) / below the lower edge (bearish),
   - **chikou** beyond the kumo — the chikou span (that same close
     plotted Kijun bars back) beyond the cloud at its own position,
   - **the twist** — tenkan > kijun (bullish) / tenkan < kijun
     (bearish) on the last closed bar.
   The old per-line conditions are gone: price no longer has to sit above
   tenkan and kijun individually, and the chikou no longer has to clear
   the prior high/low or the tenkan/kijun at its shift. One definition
   everywhere, from the M1 foot of the chain to the D1 filter.

2. **The M30 bias — a last-resort stand-in.** The parent's bias stack is
   untouched: H4 is the primary bias for every tier, and the H1 stand-in
   covers the tiers at or below `InpH1BiasMaxTier` when H4 is flat. The
   M30 bias adds a third rung below H1: when there is **no H4 bias and no
   H1 bias** (H4 flat and H1 flat), the **M5 and M15 tiers only** may
   still open provided M30 shows the valid kumo breakout of change 1
   (`M30BreakoutOK` is now just `CheckAlign(IDX_M30) == dir` — the M30
   gate inherited the new definition, twist included). The M30 bias never
   stands in against an aligned H4 or an aligned H1, and never opens the
   M30/H1/H4 tiers — only the m1-m5 and m1-m5-15 chains.

3. **Tenkan-close exits for M30-authorised trades.** A trade opened under
   the M30 bias closes when a **candle CLOSES BEYOND** the highest
   timeframe's **tenkan sen** — not on a mere touch: the M5 tier exits on
   the last closed M5 candle closing below the M5 tenkan (long) or above
   it (short), the M15 tier on the M15 candle doing the same. Strict
   inequalities, no wait beyond the tier-TF candle close, checked every
   closed M1 bar so the exit fires within a minute of the close.
   Parent-authorised trades (H4/H1) keep the parent's kumo-touch exit
   unchanged. The position comment carries the exit mode so it survives a
   restart: M30-bias trades get a "T" suffix ("Exp Buy M5T"), parent
   trades keep the plain comment ("Exp Buy M5"), and
   `SyncStateFromPositions` restores the mode on restart.

### New inputs

| Input | Default | Meaning |
|-------|---------|---------|
| `InpM30Bias` | `true` | When H4 and H1 are both flat, the M5/M15 tiers may open on M30's valid kumo breakout (price + chikou beyond kumo + tenkan > kijun); these trades exit on the highest-TF tenkan sen instead of the cloud |

All other inputs are the parent's, unchanged — **`.set` files from the
parent load cleanly**; only `InpM30Bias` is added (defaults to true, so a
parent `.set` behaves as the new build with the M30 fallback enabled).

### Status & caveats

- **Not compiled, not backtested here.** No F7 compile or Strategy Tester
  run is recorded in this repo. Compile and demo-test before it touches
  money.
- **The new breakout definition changes EVERYTHING, not just M30.** Entry
  chains and the H4/H1 biases are stricter on the twist (a flat or
  counter-twisted tenkan/kijun blocks a breakout even with price and
  chikou beyond the kumo) but looser on the lines (price/chikou no longer
  need to clear tenkan and kijun individually). The net effect on trade
  count is unknown until backtested — that is the experiment.
- **The M30 bias only fires when the higher biases are silent** — H4 flat
  and H1 flat. That is the point: it is a last-resort directional gate
  for the two smallest chains, not an override. An aligned H4 (or H1)
  always takes precedence and the M30 path is skipped.
- **Tenkan-close exits are still faster than cloud exits.** Entry
  requires price clear of the kumo on the tier TF, but the tenkan is a
  fast line — an M30-bias trade can be closed by a pullback that closes
  beyond the tenkan while the cloud exit would have ridden it through.
  That is the experiment: tighter exits against the M30 breakout
  direction, requiring a full tier-TF candle close (not just a touch) so
  brief wicks through the tenkan do not stop the trade.
- **Only M30-authorised trades exit on the tenkan.** H4/H1-authorised
  trades on the same levels keep the parent's kumo exit — the exit mode
  is fixed at entry and carried in the position comment ("T" suffix).

## 26. Bottom-Up Stack EA — M1-strict cloud bias (M1 current+future, M5+ future only)

> **PROMOTED 2026-08-20** — this build is now the code behind the main VPS
> and desktop EAs at the repo root (magics `20260858` / `20260860`); the
> file here is the experimental reference.

**File:** `experimental-bottomup-stack-m1-strict-cloud-bias-ea-most-profitable.mq5`
**Forked from:** `ichimoku-h4-m1-vps-ea.mq5` (the live VPS build, magic
`20260850`), which is left untouched
**Magic number:** `20260858` — carried over from the cloud-gate fork it
supersedes (earlier iterations are documented below), so positions those
versions already opened keep being managed. It never touches positions of
the retired builds (`20260850` VPS, `20260852` desktop) or any other fork

This is the **third iteration** of the cloud-bias experiment. The first
iteration (far-end-only check on every timeframe) traded much better than
the parent; the second (strict M1+M5 gate on the M5 tier only, M15+
cloud-free) was built to choke off the flood of small M5-tier trades. This
iteration reconciles both: the gate applies to **every tier again** (tier
TF + the TF directly below it, exactly like the parent and the first
iteration), with a **per-timeframe rule**:

> **User report (2026-08-20): most profitable version of the EA so far in
> all iterations** — hence the `-most-profitable` suffix on the file name.
> Backtest result reported by the user on Jan–Aug 2026 data: **$100 → $14000**.

- **M1 — the full parent check.** **Both** the current cloud (last closed
  bar) **and** the future cloud (far end, bar `Kijun` ahead) must be
  twisted the trade's way (Span A > Span B for a long, Span A < Span B
  for a short). M1 only appears as the TF below the M5 tier, so this is
  the strictness that keeps the smallest tier in check.
- **M5 and above — future-only.** The **current** cloud may be any value,
  bullish or bearish; only the **future** cloud must be in the trade's
  direction. Applied to M5, M15, M30, H1 and H4 wherever the gate touches
  them — the early-breakout behaviour of the well-performing first
  iteration.

So per tier: the **M5 tier** needs M1 current+future and M5 future; the
**M15 tier** needs M5 future and M15 future; **M30** needs M15 future and
M30 future; **H1** needs M30 future and H1 future; **H4** needs H1 future
and H4 future. `InpCloudBiasEnabled` (default `true`) still switches the
whole gate; `false` opens everything cloud-free.

The H1 stand-in bias keeps its optional cloud confirmation
(`InpH1BiasCloudCheck`, default `true`) — the same **future-only** check
on the H1 kumo (`CloudBiasFarOK`), now naturally consistent with the M5+
rule. Turn the input off to drop it.

### New inputs

None. All inputs are the parent's, unchanged — **`.set` files from the
parent load cleanly.**

### Status & caveats

- **Not compiled, not backtested here.** No F7 compile or Strategy Tester
  run is recorded in this repo. Compile and demo-test before it touches
  money.
- **M1 strictness is the only small-tier brake.** The M5 tier is gated by
  the full M1 check (current+future) plus the M5 future cloud. M1 clouds
  twist often, so this is a mild brake compared with iteration 2 — "to
  start off" per the user, with more strictness (e.g. M5 current too)
  available as a follow-up if M5-tier trades still over-fire.
- **M15+ tiers are back to future-only, not free.** The gate applies to
  every tier again; an M15+ entry needs the future clouds of its two TFs
  in the trade's direction — the exact behaviour of the first iteration
  the user reported as performing much better.
- **Magic `20260858` shared with the superseded forks** — deliberate, so
  open positions from the earlier iterations keep being managed after the
  file swap. Do not run two of these files on the same account at once.
- If the test proves out, promote the change into the VPS and desktop
  builds together (per AGENTS.md the two production files must stay in
  step).

---

### Earlier iterations (superseded 2026-08-20)

**Iteration 2 — M1/M5 cloud gate.** File
`experimental-bottomup-stack-m1m5-cloud-gate-ea.mq5` (replaced by
`experimental-bottomup-stack-m1-strict-cloud-bias-ea-most-profitable.mq5` above; magic
`20260858` carried over). The gate applied **only** to the M5 tier, where
M1 and M5 both needed the full parent check (current AND future twisted
the trade's way); the M15 tier and above were **completely cloud-free**.
Built to prevent small M5-tier trades; superseded by the M1-strict rule
above before the user tested it further.

**Iteration 1 — future-cloud bias.** File
`experimental-bottomup-stack-future-cloud-bias-ea.mq5` (replaced by
iteration 2; magic `20260858` carried over). `CloudBiasOK` checked
**only** the far end of the future-cloud window (Span A/Span B at shift
`1 - Kijun`) on every timeframe: the immediate cloud at the last closed
bar may be anything — same direction as the future cloud or the opposite.
The parent required the cloud twisted the trade's way at **both** the
last closed bar and the far end, which effectively waited for the kumo
twist to cover the whole future window before an early breakout could
enter.

User feedback on iteration 1: **"performs much better"**, but too many
small M5-tier trades — which motivated the later iterations. Its relaxed
far-only check is exactly what the current build applies to every M5+
timeframe (`CloudBiasFarOK`).

## 27. Bottom-Up Stack EA — M1/M5-strict cloud bias (M5 joins the full check)

**File:** `experimental-bottomup-stack-m1m5-strict-cloud-bias-ea-second-most-profitable.mq5`
**Forked from:** `experimental-bottomup-stack-m1-strict-cloud-bias-ea-most-profitable.mq5`
(the third-iteration fork, magic `20260858`), which is left untouched —
it stays in the repo as the most-profitable benchmark
**Magic number:** `20260858` — carried over again, so positions opened by
the earlier forks keep being managed when this file is swapped in. It
never touches positions of the live builds (`20260850` VPS, `20260852`
desktop); do not run it and the most-profitable file on the same account
at once

> **User report (2026-08-20): second most profitable version of the EA
> so far** — hence the `-second-most-profitable` suffix on the file name,
> runner-up to the m1-strict most-profitable build ($100 → $14000 on
> Jan–Aug 2026 data).

Fourth iteration of the cloud-bias experiment. The user reported the
third iteration (M1 strict, M5+ future-only) as **the most profitable so
far — $100 → $14000 on Jan–Aug 2026 data** — and asked to extend the same
full condition to M5 as well, with M15 upward unchanged.

**The per-TF rule is now:**

- **M1 and M5 — the full parent check.** **Both** the current cloud (last
  closed bar) **and** the future cloud (far end, bar `Kijun` ahead) must
  be twisted the trade's way (Span A > Span B for a long, Span A < Span B
  for a short).
- **M15 and above — future-only (unchanged).** The current cloud may be
  any value, bullish or bearish; only the future cloud must be in the
  trade's direction.

The gate applies to every tier (tier TF + the TF directly below it),
judged per-TF via the new `CloudBiasTFOK()` helper (`IDX_M15` marks the
cut: `tfIdx >= IDX_M15` → future-only, else full check). So per tier:

| Tier | Cloud requirements |
|------|--------------------|
| M5   | M1 current+future **+** M5 current+future |
| M15  | M5 current+future **+** M15 future |
| M30  | M15 future + M30 future |
| H1   | M30 future + H1 future |
| H4   | H1 future + H4 future |

Note the consequence: because the gate also checks the TF directly below
a tier, the **M15 tier now needs the M5 cloud fully twisted** (current +
future) — the M15 *timeframe's own* condition is unchanged, but M15-tier
entries got stricter via their M5-below component. M30/H1/H4 are
untouched.

The H1 stand-in bias keeps its optional future-only cloud confirmation
(`InpH1BiasCloudCheck`, default `true`) — H1 is M15+, so it falls under
the unchanged M15+ rule. Turn the input off to drop it.

### New inputs

None. All inputs are the parent's, unchanged — **`.set` files from the
parent load cleanly.**

### Status & caveats

- **Not compiled, not backtested here.** No F7 compile or Strategy Tester
  run is recorded in this repo. Compile and demo-test before it touches
  money.
- **The experiment: does M5 strictness beat the most-profitable build?**
  This version trades fewer, higher-quality entries on the M5 and M15
  tiers (both now need the M5 cloud fully twisted). The M5 tier needs
  M1+M5 both current and future — the strictest small-tier gate of any
  iteration. Whether the fewer trades outweigh the lost early entries is
  the test; the third iteration is the benchmark at $100 → $14000.
- **M15-tier entries are also affected** (via the M5-below check), M30+
  exactly as the third iteration. If the M15 tier should keep the relaxed
  M5 check, say so and the tier can be excluded from the M5 strictness.
- **Magic `20260858` shared with the whole fork lineage** — deliberate, so
  open positions keep being managed across file swaps. Do not run two of
  these files on the same account at once.
- If the test proves out, promote the change into the VPS and desktop
  builds together (per AGENTS.md the two production files must stay in
  step).

## 28. Bottom-Up Stack EA — M1/M5/M15-strict cloud bias (M15 joins the full check)

**File:** `experimental-bottomup-stack-m1m5m15-strict-cloud-bias-ea.mq5`
**Forked from:**
`experimental-bottomup-stack-m1m5-strict-cloud-bias-ea-second-most-profitable.mq5`
(fourth iteration, magic `20260858`), which is left untouched — it stays
in the repo as the second-most-profitable build; the m1-strict build
remains the most-profitable benchmark ($100 → $14000 on Jan–Aug 2026
data, user report)
**Magic number:** `20260858` — carried over again, so positions opened by
the earlier forks keep being managed when this file is swapped in. It
never touches positions of the live builds (`20260850` VPS, `20260852`
desktop); do not run two of the lineage files on the same account at once

Fifth iteration of the cloud-bias experiment. The user reported the
fourth iteration (M1+M5 strict, M15+ future-only) as **the second most
profitable so far** and asked to extend the same full condition to M15
as well, with M30 upward unchanged.

**The per-TF rule is now:**

- **M1, M5 and M15 — the full parent check.** **Both** the current cloud
  (last closed bar) **and** the future cloud (far end, bar `Kijun` ahead)
  must be twisted the trade's way (Span A > Span B for a long, Span A <
  Span B for a short).
- **M30 and above — future-only (unchanged).** The current cloud may be
  any value, bullish or bearish; only the future cloud must be in the
  trade's direction.

The gate applies to every tier (tier TF + the TF directly below it),
judged per-TF via `CloudBiasTFOK()` (the cut moved from `IDX_M15` to
`IDX_M30`: `tfIdx >= IDX_M30` → future-only, else full check). So per
tier:

| Tier | Cloud requirements |
|------|--------------------|
| M5   | M1 current+future **+** M5 current+future |
| M15  | M5 current+future **+** M15 current+future |
| M30  | M15 current+future **+** M30 future |
| H1   | M30 future + H1 future |
| H4   | H1 future + H4 future |

Note the consequence: because the gate also checks the TF directly below
a tier, the **M30 tier now needs the M15 cloud fully twisted** (current +
future) — the M30 *timeframe's own* condition is unchanged, but M30-tier
entries got stricter via their M15-below component. H1/H4 are untouched.

The H1 stand-in bias keeps its optional future-only cloud confirmation
(`InpH1BiasCloudCheck`, default `true`) — H1 is M30+, so it falls under
the unchanged M30+ rule. Turn the input off to drop it.

### New inputs

None. All inputs are the parent's, unchanged — **`.set` files from the
parent load cleanly.**

### Status & caveats

- **Not compiled, not backtested here.** No F7 compile or Strategy Tester
  run is recorded in this repo. Compile and demo-test before it touches
  money.
- **The experiment: does M15 strictness beat the second-most-profitable
  build?** This version trades fewer, higher-quality entries on the M5,
  M15 and M30 tiers (all three now involve the full M15 check). Whether
  the fewer trades outweigh the lost early entries is the test; the
  benchmarks are the third iteration ($100 → $14000) and the fourth
  (second most profitable).
- **M30-tier entries are also affected** (via the M15-below check), H1/H4
  exactly as the fourth iteration. If the M30 tier should keep the
  relaxed M15 check, say so and the tier can be excluded from the M15
  strictness.
- **Magic `20260858` shared with the whole fork lineage** — deliberate, so
  open positions keep being managed across file swaps. Do not run two of
  these files on the same account at once.

---

## 29. Bottom-Up Stack EA — M1/M5/M15/M30-strict cloud bias (M30 joins the full check)

**File:** `experimental-bottomup-stack-m1m5m15m30-strict-cloud-bias-ea.mq5`
**Forked from:** `experimental-bottomup-stack-m30-bias-ea-third-most-
profitable.mq5` (section 25 — the M30-bias build ranked third most
profitable, magic `20260855`), which is left untouched
**Magic number:** `20260859` — fresh, so this build never adopts or manages
positions belonging to any other file (the strict-lineage forks share
`20260858`; the parent runs `20260855`)

Sixth iteration of the cloud-bias experiment, and the first one built on
top of the third-most-profitable M30-bias build rather than the live VPS
build — so it inherits, unchanged, the new kumo-breakout definition
(price + chikou beyond the kumo + tenkan/kijun twist on every timeframe
M1..D1), the M30 last-resort bias (only when H4 and H1 are both flat; only
the m1-m5 and m1-m5-15 chains open under it) and the tenkan-close exits
for M30-authorised trades.

The experimental change extends the strict cloud-bias rule from M15 to
**M30**: the cloud-bias gate now waits for **BOTH cloud positions to
agree** on every timeframe from M1 to M30 — the Span A/B twist must hold
at the current bar (last closed bar) AND at the far end of the future
cloud (Kijun bars ahead). For H1 and H4 it just looks at the **future
cloud** — the far-end twist only; their current cloud may be any value.
The H1 stand-in's optional cloud confirmation (`InpH1BiasCloudCheck`)
follows the same rule (H1 → future only).

Per-tier cloud requirements (`LevelCloudBiasOK` via `CloudBiasTFOK`):

| Tier | Cloud requirements |
|------|--------------------|
| M5   | M1 current+future **+** M5 current+future |
| M15  | M5 current+future **+** M15 current+future |
| M30  | M15 current+future **+** M30 current+future |
| H1   | M30 current+future + H1 future |
| H4   | H1 future + H4 future |

Note the consequence: because the gate also checks the TF directly below
a tier, the **H1 tier now needs the M30 cloud fully twisted** (current +
future) — M30-tier entries already got this via their own check; H1-tier
entries now do too. H4 is untouched (future only for both H1 and H4).

### New inputs

None — all inputs are the parent build's, unchanged. **`.set` files from
the third-most-profitable parent load cleanly.**

### Status & caveats

- **Not compiled, not backtested here.** No F7 compile or Strategy Tester
  run is recorded in this repo. Compile and demo-test before it touches
  money.
- **The experiment: does M30 strictness beat the third-most-profitable
  build?** The M5, M15 and M30 tiers all now require both cloud positions
  to agree; only H1/H4 keep the future-only rule. Whether fewer,
  higher-quality entries beat the parent is the test.
- **The M30 bias path is fully strict** — M30-bias entries are M5/M15
  tiers, whose cloud pairs (M1/M5 and M5/M15) are all current+future.
- **Magic `20260859` is fresh and unique** — safe to run alongside the
  strict lineage (`20260858`), the third-most-profitable parent
  (`20260855`) and the live builds (`20260850`/`20260852`).
- If the test proves out, promote the change into the VPS and desktop
  builds together (per AGENTS.md the two production files must stay in
  step).

---

## 30. Bottom-Up Stack EA — STANDARD-ACCOUNT build ($100), M1/M5/M15-strict cloud + hard stop + circuit breakers

**File:**
`experimental-bottomup-stack-standard-account-m1m5m15-cloud-ea.mq5`
**Forked from:** the LIVE VPS build `ichimoku-h4-m1-vps-ea.mq5` (magic
`20260858`, the M1-strict cloud-bias build), which is untouched — as is the
desktop twin. This is the first standard-account fork taken from the
current live logic; the earlier one (section 22, magic `20260854`) was
forked from the retired H1-bias parent and does **not** carry the
cloud-bias rule.
**Magic number:** `20260862` — fresh, so a standard-account instance never
adopts or manages positions belonging to the live VPS build (`20260858`),
the desktop twin (`20260860`), the earlier standard-account fork
(`20260854`) or anything else in the lineage.

The live strategy re-scaled for a **standard (full-size) account funded
with about $100**, replacing the XM Ultra Low **Micro** account it runs on
today. Unlike section 22 this is not a money-management-only fork: the
entry gate is tightened as well, at the user's request, because the risk
work below cuts the tradable universe down and the trades that survive
should be the best ones available.

### Why a standard account changes everything

On a **micro** gold symbol one lot is 10 oz, so the 0.01 minimum is 0.1 oz
and moves about **$0.10** per $1 of gold. On a **standard** gold symbol one
lot is 100 oz: the same 0.01 minimum is 1 oz and moves about **$1.00** per
$1 of gold — **ten times the exposure for the identical number in the
volume box**, and the smallest trade the broker will accept.

Two consequences, both invisible on the micro account:

1. **The parent's risk table stops meaning anything.** Its sizing ends
   with `MathMax(lotMin, lots)`, so any risk-correct size below 0.01 is
   silently rounded **up**. Below roughly $10k of equity every single trade
   is a minimum-lot trade whose real risk is set by the broker's lot floor,
   not by the percentage configured.
2. **The parent has no entry stop at all.** The trade runs to the
   kumo-touch exit, and that exit is only evaluated on closed M1 bars. A
   news spike moving gold $25 inside one minute costs $25 at 0.01 standard
   lot — a quarter of a $100 account — and there is no smaller size to fall
   back on.

### What changed — trade quality

1. **Strict cloud on M1, M5 and M15.** The live build requires the cloud
   twist (Span A vs Span B) to agree at **both** the current bar and the
   far end of the future cloud on **M1 only**; M5 and above are
   future-cloud-only. Here the full check reaches **M1, M5 and M15**, with
   M30 upward left future-only — the rule from section 28. Per tier:

   | Tier | Cloud requirements |
   |------|--------------------|
   | M5   | M1 current+future **+** M5 current+future |
   | M15  | M5 current+future **+** M15 current+future |
   | M30  | M15 current+future **+** M30 future |
   | H1   | M30 future + H1 future |
   | H4   | H1 future + H4 future |

   The cut is now an input, `InpStrictCloudUpTo` (`STRICTCLOUD_M1` /
   `_M5` / `_M15` / `_M30`, default `_M15`), so it can be walked back to
   the live build's rule without editing code. `CloudBiasTFOK()` replaces
   the hard-coded M1-versus-the-rest split in `LevelCloudBiasOK()`.
2. **Spread ceiling 60 → 35 points.**
3. **Post-loss cooldown** (`InpLossCooldownMin`, 60 min). Not cosmetic —
   see the hard stop below.

### What changed — risk

4. **Hard stop loss at entry** (`InpUseHardStop`, `InpStopLossATR` = 2.0 ×
   ATR of the tier TF, floored at 1.5 × the broker's stops level). The
   single most important change. **2.0 × ATR is deliberately the same
   distance the parent already used as its sizing "reference distance"** —
   the room it implicitly treated the trade as working within. This build
   makes that distance real and attaches it to the order.
5. **Risk is priced against that real stop.** The sizing distance **is**
   the stop distance, so a tier's risk % is money genuinely at risk rather
   than a notional figure. `InpRiskATRMult` is gone; `InpStopLossATR`
   replaces it.
6. **Hard per-trade ceiling** (`InpMaxRiskPerTradePct`, 5%). No entry may
   risk more than this at its stop. When even the 0.01 minimum lot would
   exceed it, `SizedLots()` **skips** the entry instead of rounding up —
   so tiers unlock one at a time as equity grows.
7. **Risk ladder re-cut**, because the percentages now bind on real money:

   | Regime | Equity | M5 | M15 | M30 | H1 | H4 |
   |--------|--------|----|-----|-----|----|----|
   | Tier 1 | < $2000 | 1% | 1.5% | 2% | 2.5% | 3% |
   | Tier 2 | $2000–$10000 | 0.5% | 0.75% | 1% | 1.25% | 1.5% |
   | Tier 3 | ≥ $10000 | 0.25% | 0.375% | 0.5% | 0.625% | 0.75% |

   The parent's 1/1/5/10/20 was sized against a distance nothing enforced;
   20% of equity on one H4 trade **with a real stop** is not survivable at
   this size.
8. **Circuit breakers.** Daily loss limit (`InpDailyLossLimitPct`, 10% of
   the day's opening equity) blocks new entries for the rest of the server
   day; peak-to-trough drawdown limit (`InpMaxDrawdownPct`, 30%) blocks
   them until equity recovers. Both references live in terminal global
   variables keyed by the magic number, so a **VPS restart mid-drawdown
   does not hand the account a fresh budget**. Neither ever abandons an
   open position — exits, break-even and the trail keep running.
   `InpResetBreakers` clears the stored state for one init.
9. **Carried over from section 22:** no silent fixed-lot fallback
   (`InpFixedLots` defaults to 0), the margin cap **skips** instead of
   clamping back up to the minimum, and sizing runs **before** the
   supersede-close so a gated higher tier cannot kill a running lower-tier
   trade and then open nothing.
10. **Startup risk preview.** On the first M1 bar the EA prints, per tier,
    the live ATR, the stop distance, what 0.01 lot would risk in money and
    in % of equity, whether the tier is tradable right now, and the
    approximate equity each blocked tier needs to unlock. It also prints
    the symbol's contract size — the fastest way to catch a micro symbol
    left in the `Symbols` input.

### The cooldown is required, not optional

Adding a hard stop introduces a failure mode the stopless parent does not
have: the stack can be stopped out and then find the **same setup still
aligned** on the very next M1 bar, re-enter, and be stopped again. Every
one of those trades is inside its risk budget, so no per-trade cap catches
it — the account just bleeds. Hence the 60-minute post-loss cooldown per
symbol.

Loss times are read from the **deal history**, not from `ExitLevel()`,
because a stop-out is executed by the server and never passes through the
EA's exit path. Positions closed by the **supersede** rule are excluded
via a ring of position IDs (`MarkLevelSuperseded()` / `WasSuperseded()`) —
a tier closed because a bigger one took over is a position upgrade, not
the losing trade the cooldown exists to follow.

### What this actually does at $100 — read before deploying

Gold on a standard symbol: 0.01 lot ≈ $1 of P/L per $1 of gold, so the
minimum lot's risk in dollars is simply the stop distance in dollars.
With `InpStopLossATR` = 2.0 and the 5% ceiling:

| Tier | Typical ATR | Stop | 0.01 lot risks | Tradable at $100? | Unlocks near |
|------|-------------|------|----------------|-------------------|--------------|
| M5   | $2.0  | $4.00  | $4.00  | **yes** (4%) | — |
| M15  | $4.5  | $9.00  | $9.00  | no (9%) | ~$180 |
| M30  | $6.5  | $13.00 | $13.00 | no (13%) | ~$260 |
| H1   | $11   | $22.00 | $22.00 | no (22%) | ~$440 |
| H4   | $28   | $56.00 | $56.00 | no (56%) | ~$1100 |

Those ATRs are illustrative — the real figures move daily, which is why
item 10 prints the live table. Two things follow, and neither is a bug:

- **At $100 essentially only the M5 tier can trade**, and the higher tiers
  unlock on their own as equity grows. That is the gate working. The
  alternative is an H4 trade risking half the account.
- **The risk percentages are not the binding constraint at this size.**
  Below roughly $300 (M5) to $1200 (H4) every trade is 0.01 lot and what
  governs risk is `InpMaxRiskPerTradePct` and the tier's ATR. **Tune that
  input, not the risk table, while the account is small.**

Combined worst case with the defaults: ≤5% per trade, ≤10% per day, and a
hard halt at 30% off the peak.

### Status & caveats

- **Not compiled, not backtested here.** No F7 compile or Strategy Tester
  run is recorded in this repo. Compile and demo-test on a standard
  account before this touches real money.
- **The hard stop is not a strictly better build.** A stop at 2 × ATR will
  sometimes fire where the kumo-touch exit would have let the trade
  breathe and recover. It trades a slice of the parent's let-it-run edge —
  the edge that produced the $100 → $14000 micro-account report — for a
  bounded worst case. That is the intended bargain at this account size,
  and it is the main thing a backtest should measure. `InpUseHardStop =
  false` reproduces the parent exactly.
- **`Symbols` defaults to `"GOLD#"`, not `"GOLDm#"`.** Confirm the exact
  standard-account symbol in Market Watch. A micro symbol left here makes
  every risk figure tenfold conservative and the account will simply
  under-trade.
- **The tier thresholds ($2000 / $10000) are a judgement call.** They sit
  deliberately above the point where the percentages start to bind
  (~$300–$1200), so the account is not de-risked while the lot floor is
  still doing the governing. Section 22 used $700/$1300 and its own notes
  flag that as debatable for the same reason.
- **The 30% drawdown breaker does not reset itself.** That is deliberate —
  a 30% hole on a $100 account is a decision to make, not a limit to wait
  out. Clear it with one init at `InpResetBreakers = true`, or set
  `InpMaxDrawdownPct = 0` to disable it.
- **Circuit-breaker globals are per-terminal, not per-account.** Run one
  instance of this build per terminal, and use `InpResetBreakers` after
  moving it to a different account or making a deposit.
- **`.set` files from the parent will not load here** — `InpRiskATRMult`
  is gone, `InpFixedLots` changed meaning, and the stop, ceiling, breaker
  and strict-cloud inputs are new.
- **Micro-account instances must not run this file, and vice versa.** The
  magic numbers differ deliberately so the two never manage each other's
  positions.
