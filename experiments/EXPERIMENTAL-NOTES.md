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
