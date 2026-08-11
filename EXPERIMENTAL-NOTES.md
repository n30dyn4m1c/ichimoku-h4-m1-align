# Experimental EAs

Strategies here are **experimental** — newer, less battle-tested than the two
main alignment EAs, and shipped for research and demo testing. Backtest and
forward-test on a demo account before risking capital. See the top-level
[Disclaimer](README.md#️-disclaimer).

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
| `InpTrailMode` | `TRAIL_CHOPPY` | 0 = off, 1 = always, 2 = choppy-only via ADX(M5) |
| `InpTrailATR` | 2.0 | Chandelier trail distance = ATR(M5) × multiplier |
| `InpTrailActivateATR` | 1.0 | Arm the trail once profit ≥ ATR(M5) × multiplier |
| `InpADXPeriod` | 14 | ADX period for choppy-market detection (M5) |
| `InpChopADXLevel` | 22.0 | ADX below this = choppy → trail on in auto mode |

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
| `InpTrailMode` | `TRAIL_CHOPPY` | 0 = off, 1 = always, 2 = choppy-only via ADX(M5) |
| `InpTrailATR` | 2.0 | Chandelier trail distance = ATR(M5) × multiplier |
| `InpTrailActivateATR` | 1.0 | Arm the trail once profit ≥ ATR(M5) × multiplier |
| `InpADXPeriod` | 14 | ADX period for choppy-market detection (M5) |
| `InpChopADXLevel` | 22.0 | ADX below this = choppy → trail on in auto mode |

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

---

## 5. H4-M15 Alignment EA

**File:** `experimental-h4-m15-align-ea.mq5`
**Magic number:** `20260724`

A trimmed clone of the main [H4-M1 EA](README.md#entry-logic) that keeps the
same H4 top anchor but stops the alignment at **M15** — it aligns **H4, H1,
M30, M15** and **disregards M5 and M1**. The idea is to keep the multi-hour
trend context of the H4-M1 build while cutting out the two lowest, noisiest
timeframes, so entries fire on a cleaner 4-timeframe agreement rather than
waiting for a full 6-timeframe stack down to M1.

### Entry logic

Runs on every new **M15** bar close, per symbol. `CheckAlign()` on each of
**H4, H1, M30, M15** requires price *and* Chikou above/below Tenkan, Kijun,
and the cloud — the same rule table as the main EAs (see
[README](README.md#entry-logic)). A trade opens only when **all four
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
[README](README.md#equity-based-position-sizing)). ATR is computed on **M15**,
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
EAs — see the [README](README.md#configuration-inputs).

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
[README](README.md#entry-logic)). A trade opens only when **all three
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
EAs — see the [README](README.md#configuration-inputs).

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
no VPS, no chart, no EA needed. Located in `monitor/`, documented in the
[README](README.md#ms-w1-d1-signal-monitor-python--github-actions).

- **Symbols:** BTC/USD, ETH/USD, XAUUSD, XAGUSD, US100, US30, EURUSD,
  GBPUSD, USDJPY, AUDUSD, USDCAD (edit `monitor/config.py`). The FX list is
  limited to common trending majors — high-volatility crosses like GBPJPY are
  deliberately excluded.
- **Data:** Yahoo Finance daily bars via `yfinance`; metals use the COMEX
  futures (`GC=F`, `SI=F`) as proxies for the XM spot symbols because Yahoo's
  spot symbols are delisted.
- **Logic:** `monitor/ichimoku.py` is a faithful port of `CheckAlign()` in
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
[README](README.md#configuration-inputs)).

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
[README](README.md#configuration-inputs)).

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
every position.

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
[README](README.md#configuration-inputs)).

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
