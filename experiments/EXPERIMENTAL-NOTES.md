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

> **Promoted, 2026-08-18 — since superseded.** The **H1-bias bottom-up
> stack** (section 20) became the code behind both main builds (magics
> `20260850` / `20260852`), replacing the top-down alignment builds now in
> [`archives/`](../archives/). It was itself replaced two days later by the
> M1-strict cloud-bias build below. The experimental file stays here as the
> reference copy and as the parent of the D1-ladder fork (section 21).

> **Promoted, 2026-08-20.** The **M1-strict cloud-bias build** (section 26) is
> now the code behind both main builds, `ichimoku-h4-m1-vps-ea.mq5` (magic
> `20260858`) and `ichimoku-h4-m1-mt5pc-ea.mq5` (magic `20260860`) — the most
> profitable iteration of the cloud-bias experiment so far (user report
> 2026-08-20, $100 → $14000 on Jan–Aug 2026 data). The bottom-up bias-stack
> builds it replaced are in [`archives/`](../archives/) as the
> `-archived20260820` pair. The experimental file stays here as the
> reference copy.

> **Promoted, 2026-08-23.** The **robustness pack** (section 36) — five
> hardening changes, R2 through R6, with no change to the trading logic — is
> now carried by both main builds. The pre-pack versions are in
> [`archives/`](../archives/) as the `-archived20260823` pair. The main
> builds, not the experiments, are where changes to the live strategy belong.

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

**Files:** `experimental-h4-m1-be30-ea.mq5` (Magic `20260811`), and its H1-anchored
sibling `experimental-h1-m1-be30-ea.mq5` (Magic `20260813`), which applies the
identical BE30 rule to the H1-M1 build and differs in nothing else.

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

---

## 31. H4-H1 and D1-H4 swing alignment builds

**Files:**
- `experimental-h4-h1-align-ea.mq5` — H4 anchor, H1 management (Magic `20260817`)
- `experimental-d1-h4-align-ea.mq5` — the same stack one scale up, D1 → H4 (Magic `20260816`)

Top-down alignment on a swing scale: only two timeframes have to agree, so
the trade count is a fraction of the full M1 stack's and each position is
held for days rather than hours. `experimental-h4-h1-align-ea.mq5` is the
baseline the [Ignition EA](#10-h4-h1-ignition-ea-equivalence-aware-compressionbreakout)
(section 10) is measured against — running the two side by side isolates
exactly what the ignition entry engine adds.

The D1-H4 fork changes nothing but the two timeframes and the magic number.
Its reason for existing is the equivalence argument in
[section 11](#11-h4-m1-alignment-filter-experiments-timeframe-pruning): D1
and H4 are not an exact 2× pair, so neither slot is redundant, and the D1
kijun and cloud edges are levels other participants actually trade.

Both are symbol-agnostic — the earlier per-symbol US30 / Silver / BTCUSD
tunings were removed in favour of passing any symbol through `Symbols`.

### Status & caveats

- Far fewer trades than anything else in the repo. Judge them over a year of
  data, not a month.
- The swing scale makes the M15-based ATR stop of the parent builds
  meaningless; both use their own timeframe's ATR.
- Neither has been forward-tested.

---

## 32. Bottom-Up Stack EA — hardening forks of the "very profitable" snapshot

**Files:**
- `experimental-bottomup-stack-ea-very-profitable-windows-laptop.mq5` (Magic `20260850` ⚠️)
- `experimental-bottomup-stack-ea-very-profitable-windows-laptop-minimal.mq5` (Magic `20260852`)
- `experimental-bottomup-stack-ea-very-profitable-windows-laptop-overextension-protection.mq5` (Magic `20260851` ⚠️)
- `experimental-bottomup-stack-office-pc-v2.mq5` (Magic `20260849`)

Four attempts to make the aggressive "very profitable" snapshot
(section 19, magic `20260848`) survivable without giving up the runners that
made it profitable. They are worth reading as a set, because the answer they
converged on is *less* filtering, not more.

| Build | What it adds | Verdict |
|---|---|---|
| **windows-laptop** | Multi-level positions restored (a running H4 no longer blocks the lower tiers), a 4 × ATR disaster stop, and a 30-minute per-tier re-entry cooldown | Fewer trades, lower profit factor than the snapshot |
| **overextension-protection** | The windows-laptop build plus an H4 pullback guard: a turtle-soup sweep check (price runs the recent swing and closes back inside) and a lower-timeframe rejection-candle check, applied to **every** tier | Worse still — the guard cut the entries during stretched moves that produced the biggest winners |
| **minimal** | Written *because* of those two results. Keeps the snapshot's exact trading logic and adds only structural fixes: one position per symbol enforced in both directions, a 4 × ATR disaster stop that can only tighten, and a per-tick kumo-touch exit | The one to A/B against the snapshot |
| **office-pc-v2** | A money-management layer rather than an entry filter: a real SL at entry (`ATR × InpRiskATRMult`), a hard per-trade risk ceiling (`InpMaxRiskPct`, 2%), risk percentages cut to ~1.8% at H4 instead of 20%, equity tiers relative to *starting* equity, drawdown-aware sizing, and a daily-loss circuit breaker | The conservative end of the family |

The lesson the `minimal` build's own header records: **the edge is in trend
continuation.** Entries during stretched moves are where the runners come
from, so an overextension gate that blocks them removes more profit than
drawdown it saves.

⚠️ `windows-laptop` shares magic `20260850` with the H1-bias build
(section 20), and `overextension-protection` shares `20260851` with the
D1-ladder build (section 21). Do not run either pair on one account.

### Status & caveats

- Backtested, not forward-tested, and only on gold.
- `office-pc-v2` supersedes an earlier `experimental-bottomup-stack-office-pc.mq5`
  that was never more than a truncated placeholder; it was deleted from the
  repo rather than left to look like a build.
- The disaster-stop distances here (4 × ATR) predate the production
  robustness pack (section 36), which settled on 8 × ATR.

---

## 33. Bottom-Up Stack EA — intrabar alignment variant

**File:** `experimental-bottomup-stack-ea-very-profitable-intrabar.mq5`
**Magic number:** `20260853`

The "very profitable" snapshot with exactly one change: on **M30, H1, H4 and
D1** the price + chikou alignment is evaluated against the **forming**
candle — current price, tenkan, kijun, cloud and chikou all update intrabar,
sampled once per newly closed M1 bar. M1, M5 and M15 are untouched and still
wait for their candle to close.

The point is latency. A slow timeframe that turns in the first hour of an H4
candle would otherwise not be recognised until the candle closes, by which
time the move it signalled has often already run.

**The fakeout guard is what makes it usable.** A first pass with pure
intrabar evaluation traded blips: live price wicking through the kijun or the
cloud opened positions that the eventual close contradicted. With
`InpIntrabarConfirmClose = true` (the default) the forming candle must
**agree with the last closed candle** of that timeframe, so an intrabar read
can only ever confirm a committed direction, never invent one. Setting it to
`false` restores the blip-prone behaviour.

Everything else — the bottom-up stack, the cloud bias gate, the H4 + D1
bias, kumo-touch exits, break-even, chandelier, the three risk regimes and
entry consolidation — is byte-for-byte the snapshot.

### Status & caveats

- The variable it isolates is clean, which makes it a good A/B, but the
  sampling is still once a minute — this is not a tick-level build.
- Intrabar reads make Strategy Tester results sensitive to the modelling
  mode. Compare against the snapshot under the *same* mode, ideally real
  ticks.
- Untested on anything but gold.

---

## 34. Bottom-Up Stack EA — news blackout

**File:** `experimental-bottomup-stack-news-blackout-vps-ea.mq5`
**Magic number:** `20260854` ⚠️

A fork of the live VPS build that flattens and stands aside around
high-impact releases, using the terminal's **built-in MQL5 Economic
Calendar** — no `WebRequest`, no DLL, no scraping, nothing to keep updated.

- High-impact ("red folder") events on the symbol's own currencies. `GOLDm#`
  picks up USD automatically through its profit currency; add more with
  `InpNewsCurrencies`.
- Open positions on the affected symbol are closed `InpNewsBlockBeforeMin`
  minutes before the release, and no entry is taken until
  `InpNewsBlockAfterMin` minutes after it.
- Medium-impact (orange) events are optional via `InpNewsIncludeMedium`.
- It **fails open**: if the calendar cannot be read, one warning is logged
  and trading continues normally rather than freezing the EA.
- VPS style is preserved — `Print` + `SendNotification`, no `Alert()` popups.

⚠️ It shares magic `20260854` with the standard-account build (section 22).
Do not run both on one account.

### Status & caveats

- **The calendar is empty in the Strategy Tester**, so a backtest of this
  build trades exactly like its parent. The blackout can only be evaluated
  forward, on a demo account. This is the single most important caveat here:
  a backtest cannot tell you whether the filter helps.
- Section 13 is the same idea applied to the top-down H4-M1 build; the
  rationale and the implementation notes there apply.
- Flattening before news is a deliberate choice to accept a known small cost
  (exiting trades that would have survived) against an unknown large one
  (slippage through a stop during a release).

---

## 35. Bottom-Up Stack EA — BTCUSD# test fork

**File:** `experimental-bottomup-stack-m1-strict-cloud-bias-btcusd-ea.mq5`
**Magic number:** `20260861`

The live VPS logic re-tuned for crypto testing. Five changes, all of them
about the instrument rather than the strategy:

1. `Symbols` preset to `BTCUSD#`.
2. **Spread gate disabled** (`InpMaxSpreadPoints = 0`). The 60-point cap
   tuned for `GOLDm#` blocked *every* BTCUSD# entry — a 2-digit BTC spread is
   100+ points.
3. **M1, M5 and M15 all use the full cloud-bias check** (current *and*
   future cloud must agree), where the parent applies the full rule to M1
   only.
4. `InpBECoverPoints` raised 15 → **300** so the break-even stop clears the
   much wider BTC spread instead of sitting inside it.
5. Fresh magic `20260861`, so it can never touch the live build's positions.

### Status & caveats

- **A test fork, not a build.** It exists to find out whether the stack
  transfers to crypto at all; delete it when that question is answered.
- Points 2 and 4 are the two places where a gold-tuned build silently breaks
  on another instrument. Any future symbol fork should start by checking
  exactly those.
- 24/7 markets change what the D1 and H4 biases mean — there is no weekend
  gap and no session structure. Treat the bias results with suspicion.

---

## 36. Bottom-Up Stack EA — robustness pack *(promoted to the main builds)*

**File:** `experimental-bottomup-stack-m1-strict-cloud-bias-robustness-vps-ea.mq5`
**Magic number:** `20260863`

**Promoted 2026-08-23.** Both main builds now carry this pack verbatim; the
pre-pack versions are archived as the `-archived20260823` pair. The file
stays here as the reference copy.

Five hardening changes (review recommendations R2–R6). **No trading logic
changed** — every one of them is about what happens when the broker, the
link or the machine misbehaves.

| | Change | The failure it closes |
|---|---|---|
| **R2** | **Unknown-position guard.** A position carrying the EA's magic whose comment no longer names a tier is logged once per ticket and blocks new entries on that symbol until it is gone | Brokers rewrite or truncate order comments on partial fills and server events. Such a position was invisible to the EA: orphaned from break-even, the trail and the cloud exit, while the EA cheerfully opened duplicates behind it |
| **R3** | **Disaster stop.** Every entry carries a hard SL at `ATR(tier TF) × InpDisasterATRMult` (default 8); a missing stop self-heals in `ManageLevelProtection()` | The build was stopless by design, relying on a kumo-touch exit checked once per M1 bar. A gap, a dead VPS or a broken link had nothing bounding the loss |
| **R4** | **Peak rebuild.** After a restart mid-trade the chandelier references are rebuilt from tier-timeframe history since the position's open time | They used to collapse to the open price, leaving the trail far looser after a restart than before it — silently, at the worst possible moment |
| **R5** | **Order robustness.** `SetTypeFillingBySymbol()` before every order, and the margin cap commits at most `InpMarginUsePct` % of free margin (default 80) | CTrade's FOK default is rejected outright by IOC-only brokers; committing 100% of free margin left nothing against an adverse move |
| **R6** | **Twin rule.** The desktop build carries the identical pack | The two builds drifting apart — see [AGENTS.md](../AGENTS.md) |

**R1 was deliberately not implemented** (user decision): a supersede-invariant
guard that would abort a new entry while an existing higher-tier position
survived its close attempt.

### Status & caveats

- The disaster stop is a **backstop, not a risk budget**. Sizing is measured
  against 2 × ATR while the stop sits at 8 × ATR, so a trade that runs to it
  loses roughly four times the nominal risk percentage. That is the accepted
  bargain: a bounded tail in exchange for never stopping out a trade the
  kumo exit would have managed.
- R2 is conservative on purpose — one unidentifiable position freezes new
  entries for the whole symbol. If that fires often, the cause is the
  broker's comment handling and should be investigated, not tuned around.
- `InpDisasterStopEnabled = false` reproduces the pre-pack behaviour exactly,
  which is the clean A/B.

---

## 37. Bottom-Up Stack EA — market profile layer

**File:** `experimental-bottomup-stack-market-profile-vps-ea.mq5`
**Magic number:** `20260864`

The newest and largest experiment: a fork of the live VPS build (M1-strict
cloud bias + the robustness pack) with a **TPO market profile** measured on
M30 driving the entries.

### The profile engine

Rebuilt on every new M30 bar. Each bar distributes one TPO across the price
buckets its `[low, high]` range covers, weighted by coverage.

- **POC** — the bucket holding the most TPOs, i.e. fair value.
- **Value area** — the tightest range around the POC holding
  `InpMPValuePct` % of all TPOs; `VAH` is its top, `VAL` its bottom.
- **Bucket height** — fixed points via `InpMPBucketPoints`, or adaptive
  `ATR(M30) / 10` when it is `0`, clamped so a profile always spans 8–2000
  buckets.
- **Window** (`InpMPProfileType`) — `0` ROLLING, the last `InpMPBars` M30
  bars (default 48 = one day); `1` SESSIONS, the current session only (Tokyo
  from 00:00, London from 10:00, New York from 16:00 server time, matching
  the MT5 market profile indicator).
- **Daily POC key levels** — the last `InpMPDays` (default 8) *completed*
  days. Peak-prominence analysis can yield up to three significant areas per
  day (multi-distribution days); trend days yield none. Dead days are
  skipped, levels are backfilled at startup, finalised at each server-day
  rollover, and journaled when price crosses one.
- **Shape read** — every completed day is classified `[N]` normal, `[2D]`
  double distribution, `[TU]`/`[TD]` trend up/down.
- **Session stacking** — the last 8 completed sessions. Consecutive value
  areas piling up in one direction (Tokyo flat, London higher, New York
  higher) mean a one-directional auction.

### Entry modes (`InpMPEntryMode`)

| | Mode | Rule |
|---|---|---|
| 0 | OFF | Profile measured and journaled only — the EA trades exactly like its parent |
| 1 | POC side | Longs at/above the POC, shorts at/below — trade with fair value |
| 2 | VA breakout | Longs above VAH, shorts below VAL — expansion |
| 3 | VA reject | The last M30 bar traded beyond a value-area edge and closed back inside |
| 4 | Daily POC | Trade with the primary POC of the most recent day that had a significant one |
| 5 | Stack | Consecutive sessions stacking — enter with the auction on a pullback into the last session's value area |
| 6 | Old POC | The last closed bar touched an old daily POC and closed back on the near side — the level rejected price |
| **7** | **AUTO** *(default)* | Per-bar dispatch, in priority order, with no stale regimes |

**AUTO** is where the work went. When a stack is live
(≥ `InpMPStackMin` sessions), the auction is one-directional and *only*
with-stack trades are allowed: a pullback into the last stacked session's
value area, a quality-filtered extension beyond it, or the rejection of a
fresh old daily POC. With no stack it falls through **MAGNET** (price within
`InpMPAutoNearATR` × ATR(M30) of a fresh daily POC → trade its rejection) →
**BREAKOUT** (price left the value area → trade the expansion, but only while
not overextended and not against the multi-day shape read) → **BALANCE**
(price inside value → fade the edges, filtered to the shape read) →
**DAILY** (fallback while the profile builds). The active environment is
journaled whenever it changes.

### Strategy aim — ride trends, cut losses

- **Ride:** stack and breakout continuations enter *with* the auction, the
  chandelier trail locks profit behind the peak, and the kumo-touch exit
  lets a trend run to its cloud. Keep `InpMPExitVA` and `InpMPExitOldPOC`
  **off** to ride — they are take-profits that cap winners at value and key
  levels, which is right for magnet and balance trades and wrong for trend
  rides.
- **Cut:** every entry carries a stop at `InpDisasterATRMult × ATR`
  (default **2** here, against the live build's 8 — so the risked percentage
  is what is actually at stake), break-even and the trail take over once
  green, `InpCutTimeHours` (default 0 = off) closes a trade that is still
  not green after N hours, and `InpMPShapeBias` (off by default) blocks
  entries against the multi-day shape read.

### Status & caveats

- **Not deployed.** The production VPS file is untouched; magic `20260864`
  shares positions with nothing.
- **The largest surface area of any experiment here** — the profile engine,
  seven entry modes and the AUTO dispatcher are all new code on top of an
  already large build. Most of it has never been exercised in a backtest.
- **AUTO is a dispatcher, not a strategy.** It picks one of four regimes per
  bar; a result that looks good may be one regime carrying three that lose.
  Run modes 1–6 individually before reading anything into mode 7.
- **The 2 × ATR stop is a real change of character**, not just a tighter
  number. The parent's 8 × ATR stop almost never fires; this one will, and
  it will sometimes cut trades the kumo exit would have recovered.
- Session start times are **server time** and are hard defaults
  (`InpMPTokyoStart` / `InpMPLondonStart` / `InpMPNYStart`). Check them
  against your broker's server offset before reading any session result.

---

## 38. Bottom-Up Stack EA — kihon suchi time gate + PO3 level gate + M2 rung

**File:** `experimental-bottomup-stack-kihon-po3-ea.mq5`
**Magic number:** `20260865`

A fork of the live VPS build (M1-strict cloud bias + the robustness pack)
that adds **two gates in front of and behind the structure gate that was
already there**, plus an optional **M2 rung** inside that structure gate. The
parent asked one question before opening a trade — does Ichimoku point a
direction? This build asks three, cheapest first, and any one of them can
veto:

| | Gate | Question | Source |
|---|---|---|---|
| 1 | **TIME** | Is a kihon suchi turn due, within ±2? | `experiments/po3-levels.mq5` |
| 2 | **STRUCTURE** | Does Ichimoku point a direction? | the parent, plus the optional M2 rung |
| 3 | **PRICE** | Is there a PO3 level worth acting on, and room to it? | the PO3 nest |

Gate 1 is market-wide — it is read once per symbol per minute and does not
depend on the tier — so it is the first veto and the alignment work below it
is skipped entirely on the minutes it fails. Gates 2 and 3 are per-tier.

### Gate 1 — the kihon suchi time gate

The Ichimoku basic time numbers, counted in candles from a calendar anchor:
`9, 17, 26` simple and `33, 42, 51, 65, 76, 129, 172, 226, 257` compound.

Counting is **inclusive at both ends** — the candle you start from is candle
1 — which is the whole of the arithmetic: two 17-spans laid end to end do not
make 34, because the last candle of the first span *is* the first candle of
the second, so `17 + 17 - 1 = 33`. Every compound number chains simple spans
that share their turning candle. **26 is the exception**: it does not come out
of that rule (three chained 9s give 25), it is a calendar given — a month of
trading days under the six-day week Japan kept when this was written — and the
rule builds on it.

**The ±2 range** (`InpTimeTol`, default 2) is the point of the gate. A kihon
number is where a move is *due* to change character, not the instant it must,
so the gate measures the signed distance from the count to the **nearest**
number and accepts it either side. Nearest rather than next, because a turn
that was due at 26 is not cancelled by the candle after it — a count two
candles *past* 26 is as much "around 26" as one two candles short. The sign
reads the way the chart does: negative is still short of the number, positive
is just past it.

Because the tolerance is in **candles of that timeframe**, the window scales
itself — ±2 on H4 is ±8 hours, on M15 it is ±30 minutes — and no extra
"sticky" state is needed. The window *is* the tolerance.

**One rule, and it is hardcoded: the daily H1 setup.** Count H1 candles from
the **day** open and open the gate when that count is within `InpTimeTol` of
**9 or of 17**. With `InpTimeTol = 2` that is H1 candles 7–11 and 15–19 of the
daily count: 10 of a day's ~23–24 candles, roughly 40% of the session.
`InpTimeTol = 0` takes only candles 9 and 17 exactly.

**9 and 17 are the reason, and 26 is the trap.** A trading day delivers
~23–24 H1 candles, so 9 and 17 are the only kihon numbers it can reach — 26
needs a longer day than there is. But a nearest-number test does not care that
a number is out of reach; it only measures distance, and 26 sits two candles
past candle 24. So a `{9, 17, 26}` series (which is what "the simple numbers"
would give) reports **"26, offset +2" on the last candle of the day** and opens
the gate on a number the count never reached and never could. The tolerance
that makes the gate useful for 9 and 17 is exactly what makes it fire there.
Measured on a 24-candle day:

| series | candles where the gate opens |
|---|---|
| `{9, 17, 26}` | 7–11, 15–19, **and 24** |
| `{9, 17}` | 7–11 and 15–19 |

So the pair is hardcoded rather than taken as a flag on the shared series.

**There is no ladder any more.** The gate began as a list of `TF:ANCHOR` rungs
judged N-of-M — `H4:W,H1:W,M30:W,M15:W,M2:D` at 2-of-5, then narrowed to a
single H1 rung — which was the right shape while the rungs were being chosen.
The choice has been made, so the ladder string, its parser, the rung arrays,
the N-of-M count and the clamp that guarded it are all gone, along with the
anchor enum, the month/year calendar builder and the multi-anchor selector.
Gate 1 is now one function with one input besides its on/off switch.

That removal also took out gate 1's cost. Each rung meant an anchor lookup and
a `Bars()` window per symbol **per M1 bar** — the heaviest thing gate 1 did,
and the cost that dominated a backtest. One fixed rule is a single window. The
multi-rung version is preserved in **commit `c220059`** if rungs are ever
wanted back.

An unknown count (history still loading, or no D1 bar yet) is **not** a pass.
The gate cannot be evaluated, and an unevaluable filter blocks rather than
waves the trade through — the same stance the cloud gate takes on unreadable
buffers. It clears itself as soon as the history lands.

The day open comes from the **D1 bar itself** rather than from the calendar, so
it follows the broker's own day boundary: on a broker rolling at 00:00 server
that is midnight, on a New York close broker it is not, and the bar knows
which. The counting convention and its arithmetic are ported **verbatim** from
`po3-levels.mq5`, so the EA and the chart cannot disagree about where a count
stands.

Only what this gate needs was carried over from the indicator. The full
twelve-number series, its compound/simple split and the general nearest-number
scan live in `po3-levels.mq5`, which is where they are actually read.

### The M2 rung in the structure stack

M2 joins the alignment stack between M1 and M5 as a **step in the chain, not a
tradable tier** (`InpUseM2`, default on). With it on, the M5 tier needs
M1 + M2 + M5 aligned instead of M1 + M5, and every higher tier inherits M2
because the chain grows through it on the way up. It also joins the cloud gate
beside the M5 tier's existing M1 check.

There is deliberately **no M2 tier**: no risk row, no ATR handle, no exit of
its own, and the level → timeframe mapping is unchanged (levels are still
M5…H4). The stack array simply grows a step, and every level-to-timeframe
lookup now goes through `TfIdxOfLevel()` rather than spelling `+1` at each
site — M2's arrival is exactly the kind of change that leaves one of those
sites behind.

**M1 stays the only timeframe that must fully agree.** M2 is checked *beside*
it, never instead of it, because loosening the rule this build is named for
would be a silent change of character. Whether M2 itself takes the full
current+future check or the M5+ future-only rule is `InpM2CloudFull`
(default: full, since a 2-minute bar is close in character to M1).

**A broker without M2 is not a failure.** M2 is optional and skips itself
rather than blocking: a symbol that refuses an M2 handle at init, or that has
no M2 bars yet, drops the rung with one journal note and runs its chain as
M1 + M5 and up. That matters because `CheckAlign` returns 0 on unreadable
data — an M2 rung *enforced* without an M2 feed would fail every chain check
and stop every entry on the symbol, leaving the EA silent with nothing in the
journal to say why. The rung re-joins automatically if the history arrives.

`InpUseM2 = false` reproduces the parent build exactly, so the two settings
are a clean A/B.

### Gate 3 — the PO3 level gate

`po3-levels.mq5` draws levels at `m × 3ⁿ` and, when several grids land on the
same price, lets the **highest** power own it — *"the higher the power,
stronger the level"*. That rule has a closed form, which is what makes it
cheap enough to run on every entry:

```
strength(R) = 3 ^ v3(R)          v3(R) = how many times R divides by 3
```

Gold at 4374 divides by 3 seven times, so it is a 2187 level — the same answer
the indicator reaches by drawing every ticked grid and letting the strongest
win, and the same label it writes on the line. The EA therefore names levels
exactly as the chart does. The formula was checked against a reproduction of
the indicator's own merge: **222 level assignments, no disagreements.**

Two consequences the gate uses:

1. The levels of power ≥ k are exactly the **multiples of 3^k**, so "the next
   level worth considering" is the next multiple — one division, no grid
   walking. (The next-multiple arithmetic was also checked against the parent
   PO3 build's `PO3NextLevel()`: identical on every case tried.)
2. Its **actual** power may be higher than k — a multiple of 243 that is also
   a multiple of 729 *is* a 729 level — so the EA resolves and journals the
   real power, capped at `InpPO3MaxPower` to match the indicator's top grid.

Gate 3 is a **take profit and a room filter, and nothing else** — it does not
fade levels or trade their breakouts. Structure supplies the direction; PO3
supplies the exit and the veto.

- **ROOM.** Distance to the next level is measured in units of the same
  reference risk the sizing uses — `ATR(tier TF) × InpRiskATRMult` — so "room"
  means room in units of what the trade is actually risking, not in points.
  Closer than `InpPO3MinRR` and price is trading *into* a level: the entry is
  skipped (`InpPO3RoomFilter`, on by default).
- **TARGET.** Inside the band `[InpPO3MinRR, InpPO3MaxRR]` the level becomes
  the trade's take profit, placed `InpPO3BufferATR × ATR` **in front** of it
  so the fill happens before the level can reject price.
- **RUNNER.** Beyond `InpPO3MaxRR` the level is too far to be a target, so the
  trade opens with no TP and is left to the parent's exits (kumo touch, BE,
  chandelier).

A TP the broker would reject (inside its minimum stop distance, or on the
wrong side of entry once the buffer is applied) degrades to a runner rather
than failing the entry — the same way the disaster stop degrades. An
unevaluable gate (ATR not readable) **blocks**, taking the same stance the
cloud gate takes on unreadable buffers.

### Why the level power is per tier

This is the one part of the design that is not obvious, and getting it wrong
disables the upper half of the stack.

The band is measured in each tier's own ATR, and those differ by about an
order of magnitude across the stack — on gold `ATR(M5)` is a couple of dollars
and `ATR(H4)` a few dozen. A single global power cannot serve both ends. With
`ATR` scaled as `sqrt(TF)` from an assumed `ATR(M5)` of `$2.00`, simulating
the share of price positions where the room filter reads "no room":

| Global power 3 (step 27) | M5 | M15 | M30 | H1 | H4 |
|---|---|---|---|---|---|
| **blocked** | 22% | 38% | 54% | **77%** | **100%** |

The H4 tier would never trade again and H1 nearly never. So `InpPO3Power`
takes one power per tier (M5, M15, M30, H1, H4); a single number applies to
every tier. The default `"3,3,4,4,5"` gives, on the same illustration:

| tier | ref risk | step | no room / target / runner |
|---|---|---|---|
| M5 | 4.00 | 27 | 22% / 78% / 0% |
| M15 | 6.93 | 27 | 38% / 62% / 0% |
| M30 | 9.80 | 81 | 18% / 79% / 3% |
| H1 | 13.86 | 81 | 26% / 74% / 0% |
| H4 | 27.71 | 243 | 17% / 74% / 9% |

Those ATRs are an **illustration, not a measurement** — the point is the shape,
not the numbers. The startup read-out prints the step, the next level and the
rr each tier actually sees at the current price, so the powers should be set
from that output rather than from this table.

### Deliberately not implemented — the reaction

A kihon time landing on a strong PO3 level is where a move often **reverses**
and sometimes carries on, and an earlier draft of this file carried fade and
break-and-hold entries for exactly that. They were dropped on the user's
instruction to start simple, and should not be added back without being asked.

Two things are worth reading first, because they say the two outcomes are not
symmetric:

- **§7 measured the analogous fade and it won 0/13.** Fading a breakout back
  to the H4 Kijun — even conditioned on high ADX or a large extension — lost
  every time, while the *same* level-touch entered **with** the trend won
  **61.6%** against 26.5% for the opposite close.
- **§1 already implements the rejection as a directional veto.** `PO3Bias()`
  detects price acting off a major PO3 level and allows only trades *away*
  from it. That is the family's existing answer, and it restricts entries
  rather than generating them.

### Verification performed

There is no MQL5 compiler on this machine, so the build was verified
statically and the numbers were verified independently:

- **Fork integrity.** All 29 parent functions compared after comment and
  whitespace normalisation: **19 identical**, 0 removed. Of the 10 that differ,
  5 change only by the `TfIdxOfLevel()` index remap and nothing else
  (`CloseLevelPositions`, `ExitLevel`, `LevelComment`, `ManageLevelProtection`,
  `SyncStateFromPositions`), and the other 5 are the ones that must change for
  the gates and the M2 rung (`ChainAligned`, `LevelCloudBiasOK`, `OnInit`,
  `OnTick`, `OpenLevel`). Every function was token-audited to confirm no
  change beyond the index remap and the M2/gate logic.
- **M2-off equivalence.** `ChainAligned` and `LevelCloudBiasOK` were *proved*
  against the parent symbolically, not eyeballed: with `InpUseM2=false` the
  chain checks exactly the same set of timeframes for all five tiers
  (M5; M5+M15; …; M5…H4) and the cloud gate checks exactly the same
  timeframes with the same strictness (M5 tier: M5 future + M1 full; every
  other tier: its own TF future + the TF below future). With M2 on, the M5
  tier gains M2 beside M1 and the higher tiers are byte-for-byte unchanged in
  the cloud gate.
- **Index arithmetic.** Every level → timeframe mapping checked against the
  parent: level *l* now resolves through `TfIdxOfLevel(l)` = `tfs[l+2]`, which
  is the same timeframe the parent reached with `tfs[l+1]` for all five levels.
  No raw `+1` index expressions remain.
- **Kihon port.** `KihonOffset`, `KihonCount`, `KihonAnchor` and
  `KihonPeriodOpen` diffed against `po3-levels.mq5`: identical. The number
  series and `KIHON_SIMPLE` / `KIHON_COUNT` / `KIHON_SPAN_CAP` match.
- **PO3 strength.** `3^v3(R)` against a reproduction of the indicator's
  merge rule: 222 assignments, no disagreements.
- **Next-level arithmetic.** Against the parent PO3 build's `PO3NextLevel()`
  on 126 price/step/direction cases: no differences.
- **Structure.** Brace, paren and bracket balance; all 14 `PrintFormat` /
  `StringFormat` calls audited for specifier-versus-argument count.

### Status & caveats

- **Not deployed, and not compiled.** No MQL5 toolchain was available, so this
  build has never been through MetaEditor. Expect to fix compile errors on
  first load, then backtest on demo before reading anything into a result.
- **The production VPS file is untouched** — magic `20260865` shares positions
  with nothing, and specifically not with the live build's `20260858`, so this
  can run beside production without either managing the other's trades.
- **Gate 1 is now a single fixed rule, so its correctness is a question about
  the rule, not about configuration.** Daily H1, candles 9 and 17, ±2. There is
  no ladder to mistype and no N-of-M to get wrong; what remains to check is
  whether the rule is *worth having*, which is what the run is for.
- **The daily H1 gate is open roughly 40% of the session** (10 of ~23–24
  candles) at the default `InpTimeTol = 2`. That is a wide window by design —
  it is a tolerance around a turn that is *due*, not a precise trigger — but it
  is worth knowing before reading a marginal result as evidence the time filter
  works. `InpTimeTol = 0` takes only candles 9 and 17 exactly, for a much
  tighter test, and the two settings bracket the useful range.
- **Test weight.** Gate 1 is a single `Bars()` window per symbol per M1 bar,
  down from five when the ladder was present. If a backtest is still slow the
  other two levers are `InpUseM2=false`, which removes the extra M2 alignment
  leg, and `InpPO3Enabled=false`, which removes gate 3 without touching the
  structure gate.
- **M2 is on by default and does change the default behaviour.** With
  `InpUseM2=true` the M5 tier needs one more timeframe to agree than the
  parent did, so fewer entries — which is the point, but it means a result
  cannot be compared against the parent without turning the rung off first.
  Check the journal's per-symbol M2 line at startup: if a symbol reports the
  rung UNAVAILABLE, that symbol is silently running the parent's chain and an
  A/B across symbols would not be comparing like with like.
- **M2 is the thinnest data in the stack.** A 2-minute bar is close to the
  spread on a retail gold feed, and its ATR, its cloud and its kihon count are
  all built from far fewer ticks than the M5 rung beside them. Treat an M2
  agreement as a timing confirmation, not as evidence of structure.
- **`InpPO3Power` needs setting from the read-out before any result means
  anything.** The defaults are scaled to gold's ATR by tier as an illustration;
  on another instrument, or another volatility regime, they will put the gate
  in the wrong place — too fine and every entry is blocked, too coarse and
  every trade is a runner.
- **The TP changes the character of the trade.** The parent's winners run to
  the kumo edge or the chandelier; a PO3 take profit caps them at a level.
  That is the intended experiment, but a lower average win with a higher win
  rate is the expected shape, not a bug — and `InpPO3TpEnabled=false` isolates
  the room filter from the target to tell the two effects apart.

---

## 39. M1+M2 / M1+M2+M5 — fixed 90/120 targets and a session window

**File:** `experimental-m1-m2-fixed-tp-ea.mq5`
**Magic number:** `20260866`

A minimal fork that keeps the parent's alignment test and throws away almost
everything else. Two questions only: does **M1+M2** align, and does **M1+M2+M5**
align. The first fires the **M2 tier**, the second the **M5 tier**. Nothing
above M5 is read, and no directional gate sits on top — no cloud bias, no H4
bias, no H1 stand-in, no D1 filter. The chain is the whole entry condition, in
both directions.

The second change is the exit. The deployed build has **no profit target at
all**: it exits when price touches the tier's kumo edge and protects the trade
with a break-even stop and a chandelier trail. This build replaces that with two
fixed levels, one position, and nothing else:

| Level | Distance | Where it lives |
|---|---|---|
| SL | 90 pips | On the order at entry, hard |
| TP | 120 pips | On the order at entry |

Both ride on the order, so the **broker** closes the trade — the EA never
trails, never scales out, never moves a stop and has no break-even layer. A
trade is opened and it either stops out at 90 or targets out at 120; there is no
intermediate state to manage. The only defensive work left in the EA is
re-attaching a stop that has gone missing, because an unstopped position is
unbounded and the 90-pip stop is the entire risk definition of the build.

Because the stop is a fixed 90 pips rather than an ATR multiple, the money at
risk on a stop-out is *exactly* the configured percentage — there is no
ATR approximation to drift against the actual stop.

### One position at a time

A tier opens only when it is flat, and the entry scan runs **highest tier
first**, so when both chains align on the same minute only the M5 tier opens.
Any M2 trade still running is closed into it as a supersede. The account
therefore never holds more than one position per symbol, and never two.

### Pips on a gold feed

"1 pip" is `InpPipPoints` × the symbol's point, default **10**. On a feed
quoted to 2 decimals that makes one pip 0.10 of price, so the user's anchors
hold exactly: `4000.00 → 4012.00` is 120 pips and `4000.00 → 4009.00` is 90.
On a 3-decimal gold feed the same 120-pip move is 12000 points, so
`InpPipPoints` must be **100**. The EA prints `1 pip = <x> price units` and
the two resolved distances at startup so a wrong setting is visible in the
journal before it costs anything, and it refuses to start on a non-positive
value.

### The session filter

Entries are allowed only while the **daily H1 count** sits in one of two
windows — **7–11** and **15–19**, both inclusive, counted from the day open
with the candle in progress counted as its own candle. Those two windows are
the ±2 tolerance around kihon suchi **9** and **17**, the only two counts a
~23–24 candle trading day can reach (see §38 for why 26 is deliberately not in
the set); on a 24-candle day they cover ten candles, about 40% of the session.

The day open is read from the D1 bar itself (`iTime(sym, PERIOD_D1, 0)`) rather
than from a fixed hour, so a broker that rolls on a different clock, and the
weekend gap, need no special case. The count uses `Bars()` over the window
`[day open, now]` — the same method as §38, chosen because a bar *before* the
anchor is simply not in the window, which keeps candle 1 on the correct side of
the open where `iBarShift` with nearest-earlier rounding would put it on last
night's close and shift every mark by one.

The filter gates **entries only**. An open trade keeps running and can still
reach its stop or target outside the windows, which is exactly right here:
because both levels live on the order, a trade opened at candle 10 is the
broker's to close and does not need the window to stay open. A chain that
aligned while the window was shut is logged once every 15 minutes rather than
silently dropped, so suppressed signals are visible in review.

An unknown or implausible count (history still loading, no D1 bar, or a count
above 30) **blocks** rather than waves the trade through — the same stance the
cloud gate takes on unreadable buffers. It clears itself as soon as the history
lands.

### M2 is a real tier here, and it is optional

Unlike §38, where M2 was a *rung* in the chain with no tier of its own, this
build makes M2 tradable: it has a risk row, its own exit and its own comment
(`Exp Buy M2`). That is the point of the experiment — a 2-minute chain is the
fastest entry the alignment test can produce.

Some brokers do not serve a 2-minute feed. M2 is therefore **skipped rather
than enforced**: a symbol that refuses an M2 handle at init, or that has no M2
bars yet, drops the M2 tier with one journal line per symbol and runs the M5
chain as M1+M2+M5 only. This matters because `CheckAlign` returns 0 on
unreadable data — a rung enforced without data would block every entry on the
symbol and the EA would go silent with nothing in the journal to say why.

### Risk ladder

Sizing is a fixed % of actual equity measured against the **full 90-pip stop**,
so the money at risk is exact rather than ATR-approximated, in the parent's
three de-risking regimes:

| Equity | M2 tier | M5 tier |
|---|---|---|
| < `InpRiskTier2At` ($7,000) | 0.5% | 2.0% |
| $7,000 – `InpRiskTier3At` ($13,000) | 0.25% | 1.0% |
| ≥ $13,000 | 0.1% | 0.5% |

M5 is the higher-conviction chain — it needs M2 to agree as well — so it
carries four times the M2 risk. **The ladder is a judgement call, not a tested
result.** It is the first thing to change, and the two tiers can be equalised
by setting the four M5 values to the M2 values.

### What it deliberately does not have

Not hardened, and not for the VPS without more work: no robustness pack, no
disaster stop, no kumo-touch exit, no rejection exit, no chandelier trail, no
bias gates, no unknown-position guard and no margin cap. It exists to answer
one question — does the M1+M2 / M1+M2+M5 chain carry an edge when the exit is a
fixed 90/120 target instead of a touch — and it should be read as nothing more
than that.

### Reading a result

- **A fixed target changes the character of the trade.** The parent's winners
  run to the kumo edge; here every winner is capped at 120 pips and every loser
  is cut at 90. A lower average win with a higher win rate is the expected
  shape, not a bug — and with no break-even layer the win rate has to carry the
  edge on its own, since a trade that goes 100 pips into profit and reverses
  gives all of it back.
- **The M2 tier is the thinnest data in the build.** A 2-minute bar on a retail
  gold feed is close to the spread, so an M2 entry can be a spread artifact.
  Compare the M2 tier's results against the M5 tier's before drawing any
  conclusion from either.
- **The session filter roughly halves the trading day.** Only ~40% of a day's
  candles are eligible, so the trade count is not comparable to the parent
  without turning `InpSessionFilterEnabled` off first.
- **`InpMaxSpreadPoints` (60) and the 90-pip stop interact.** Gold's spread is
  a meaningful fraction of a 2-minute bar; a wide-spread M2 entry is much worse
  than a wide-spread M5 entry at the same 90-pip stop.
- **One position per symbol, always.** A tier opens only when flat and the scan
  runs highest-first, so when both chains align on the same minute only the M5
  tier opens and any running M2 trade is closed into it. The two tiers cannot
  both be long or short at the same time, so their results are not additive.
- **Restart recovery is exact here.** Both levels are on the position at fixed
  distances, so a mid-trade restart inverts either one to recover the entry —
  there is no partial-fill or break-even state to reconstruct, unlike the
  earlier split-target draft of this experiment.

---

## 40. Bottom-Up Stack EA — PO3 reaction veto + dealing-range zone veto

**File:** `experimental-bottomup-stack-kihon-po3-veto-ea.mq5`
**Magic number:** `20260867`

A fork of the kihon-suchi + PO3 gate experiment (§38, magic `20260865`), which
is itself a fork of the live VPS build. Gates 1–3, the M1-strict cloud bias, the
robustness pack and the M2 rung are all unchanged. What is new is **two
location vetoes** at the end of the entry chain, so an entry now answers five
questions, cheapest first:

| | Gate | Question | Source |
|---|---|---|---|
| 1 | **TIME** | Is a kihon suchi turn due, within ±2? | §38 |
| 2 | **STRUCTURE** | Does Ichimoku point a direction? | the parent |
| 3 | **PRICE** | Is there a PO3 level worth acting on, and room to it? | §38 |
| 4 | **REACTION** | Has price just been *rejected* at a major PO3 level? | **new** — §1's `PO3Bias()` ported |
| 5 | **LOCATION** | Is price on the right side of its PO3 dealing range? | **new** — §1 computed it for display only |

Gates 1, 4 and 5 are market-wide (they do not depend on the tier) and are read
once per symbol per minute; gates 2 and 3 are per-tier.

### Why a veto, and not an entry

This is the design decision the whole build rests on, and it is deliberately the
*conservative* half of the idea. The model being implemented is: a level acts as
resistance, is tested, and once broken becomes support; price approaches a
strong level, closes short of it, and reverses. That describes **two** possible
responses — trade the reaction (fade it, or trade the break-and-hold retest), or
refuse to trade *into* it. §38 recorded the first as deliberately not
implemented, on the user's instruction to start simple, and said it should not
be added back without being asked. **It is still not added back here.**

What this build adds is the second response, which is also the one §1 had
already implemented and §38 had already pointed at. The reason is §7's
measurement, quoted in §38: fading the analogous H4-Kijun breakout **won 0/13**
— even conditioned on high ADX or a large extension — while the *same*
level-touch entered **with** the trend won **61.6%** against **26.5%** for the
opposite close. The reversal and the continuation are not symmetric. So the
useful action at a level is not "trade the bounce", it is "do not be the
liquidity": a trade pushing *into* a level that has just rejected price is
refused, while trades *away* from it are still allowed. Both new gates restrict
entries; neither generates one.

### Gate 4 — the reaction veto

The level arithmetic is §38's, unchanged: a price is `raw = price ×
InpPO3Scale`, a level's strength is `3^v3(raw)`, and the levels of power ≥ k are
exactly the multiples of `3^k`. A **2187 level is a multiple of `3^7 = 2187`** in
raw space.

**Why a tag test and not a distance test.** On gold at ~4000 with `InpPO3Scale =
1` the only 2187-grade levels in view are 2187 and 4374. "Is price near a 2187
level *right now*" would therefore almost never be true, and a per-bar distance
check would be dead code. A tag-with-memory is not: the lookback extreme stays
near the level for as long as the rejection stands, so the veto covers the whole
period during which the level is doing its work.

The test, ported from §1's `PO3Bias()`:

1. scan the last `InpPO3VetoBars` (180) **closed H4** bars for the highest high
   and the lowest low;
2. round that extreme to the **nearest** multiple of `3^InpPO3VetoPower`
   (default 7 → 2187) and call it a **tag** when the extreme came within
   `InpPO3VetoTolFrac × 3^InpPO3VetoBasePower` of it;
3. for a high tag, the level is **rejecting** while the latest closed H4 close
   is still back inside it by that same tolerance. The low side is the mirror.

Three consequences worth stating, because each is a design choice rather than an
accident:

- **The tolerance comes off the BASE rung, not the level's own grade.** It is
  "how close counts as a tag" in the instrument's fine-grid terms — a fixed
  distance in price. Scaling it by the level's grade would give `0.4 × 2187 =
  875` on gold, roughly a quarter of the instrument's whole range, and every bar
  would tag every level. The base default is 4 (81 raw units), so the tag window
  is about **±32 dollars on gold**. §1 uses the same basis and the same 0.4.
- **Reclaim clears the veto by construction.** The rejection test is applied to
  the *latest closed* H4 bar on every read, so the moment price closes back
  through the level the tag simply stops being true. There is no separate
  reclaim state, and therefore no chance of one drifting out of step with the
  test that is supposed to maintain it.
- **The newer tag supersedes the older.** When both sides tag inside one
  lookback, the more recent extreme wins (series order: the lower index is the
  newer bar). That is §1's rule, kept.

**The verdict is directional.** A tagged HIGH means shorts only — no longs into
that resistance. A tagged LOW means longs only — no shorts into that support. A
lookback that tags neither leaves both directions open. This is what makes it
the asymmetry §7 measured rather than a flat block on both sides.

**It is cached on the H4 bar.** The verdict can only change when a new H4 bar
closes, so the closed H4 bar time *is* the cache key and the `CopyRates` of 180
bars runs **once per symbol per four hours**. §1 recomputes it on every M1 bar,
which §38 flagged as a cost; this build does not carry that cost. Only a
*successful* read is cached — a failure is retried on the next entry check
rather than remembered, so the gate clears itself the moment the history lands.

**An unreadable history blocks.** `CopyRates` returning nothing means the H4
series is not there yet, and the gate answers `VETO_UNKNOWN`, which blocks. That
is the stance gates 1 and 3 already take on unreadable data. Its consequence is
real and is called out under caveats: a symbol with fewer than 180 closed H4
bars cannot open a trade until it has them.

### Gate 5 — the dealing-range zone

The other half of the PO3 picture: not "is a level nearby" but "where inside its
range is price". `floor(price / step) × step` opens the range price is in and
the next rung closes it; the fraction of the way across that range is the
position. The thirds of it are the model's own reading — lower third
**discount**, middle **equilibrium**, upper **premium**.

As a gate it is the classic location rule, *buy discount and sell premium*,
written as two independent thresholds:

- a **long** is refused above `InpPO3ZoneLongMaxPct` of the range;
- a **short** is refused below `InpPO3ZoneShortMinPct`.

Both default to **50**, the equilibrium line — the loosest sensible setting: no
buying in premium, no selling in discount. Set them to **33.3 and 66.7** for the
strict three-thirds model, where only the discount third is bought, only the
premium third is sold, and the equilibrium middle is not traded at all.

The **label** in the journal is always the model's thirds, whatever the
thresholds are set to, so a journal line means one thing; the thresholds are the
gate and are free to be looser than the thirds. The range grade is
`InpPO3ZonePower` (default 5 → 243 on gold) and **not** the per-tier search
power: the zone is a property of where price is, not of which tier is asking, so
every tier reads the one range. The user's literal "9 range split into three 3s"
reading is `InpPO3ZonePower = 2` with the 33.3 / 66.7 thresholds.

The zone is read off the **bid** for both directions. The spread is a rounding
error against a range of hundreds of units, and using one price keeps the tiers'
readings comparable.

**Gate 5 is off by default**, so a first run measures gate 4 alone. The two are
independent and can be A/B'd separately against each other and against §38.

### Inputs

| Parameter | Default | Description |
|---|---|---|
| `InpPO3VetoEnabled` | `true` | Gate 4 (reaction veto) on/off |
| `InpPO3VetoPower` | `7` | Major level = `3^7` = **2187** |
| `InpPO3VetoBars` | `180` | Closed H4 bars scanned for the tagging extreme |
| `InpPO3VetoBasePower` | `4` | Tag tolerance is a fraction of `3^4` = 81 |
| `InpPO3VetoTolFrac` | `0.4` | ... that fraction — about ±32 dollars on gold |
| `InpPO3VetoLogSetup` | `true` | Journal the current tag state per symbol at startup |
| `InpPO3ZoneEnabled` | `false` | Gate 5 (dealing-range zone) on/off |
| `InpPO3ZonePower` | `5` | Range grade = `3^5` = 243; one range, read by every tier |
| `InpPO3ZoneLongMaxPct` | `50.0` | A long is refused **above** this % of the range |
| `InpPO3ZoneShortMinPct` | `50.0` | A short is refused **below** this % |

### Deliberately not implemented

- **Break-and-hold / retest entries** — "a level once broken becomes support" as
  a *signal*. Still not here, for the reason §38 gives: it is the entry half of
  the reaction and it has not been asked for. §7's 0/13 on the analogous fade is
  the standing argument against reading a level touch as a reason to trade.
- **Neither new gate is written into the position comment.** The comment names
  the trade's level and `SyncStateFromPositions()` parses it back; the R2 guard
  turns a comment that no longer names a level into a *blocked symbol*, so the
  comment format is load-bearing. It is left exactly as the parent had it. The
  new gates are visible in the journal instead — the startup read-out, and the
  throttled `BlockNote` line when one of them refuses a trade.

### Verification performed

There is no MQL5 compiler on this machine, so the build was verified statically
against the committed parent (§38 at `HEAD`, not the mid-edit working copy):

- **Fork integrity.** 43 functions in the parent, **none removed** in the fork.
  After comment and whitespace normalisation, **40 are identical**, **3 differ**
  (`OnInit`, `BlockNote`, `OnTick`) and **5 are new** (`PO3Px`,
  `PO3VetoReadSym`, `PO3VetoTag`, `PO3ZoneReadSym`, `PO3VetoLogSetup`).
- **The three changed functions were token-diffed.** `OnInit` has exactly two
  hunks — the gate-4 cache reset inside the per-symbol loop, and the
  `PO3VetoLogSetup()` call after `PO3LogSetup()`. `OnTick` has exactly two — the
  two symbol-wide reads beside gate 1, and the gate-4/gate-5 block inserted
  after gate 3's "room unknown" check and before the `topPo3` bookkeeping.
  `BlockNote` has one: its line no longer says "gate 3", because all three gates
  now share the one throttle.
- **Balance.** Braces 159 / 159, parentheses 903 / 903, brackets 464 / 464;
  nesting never goes negative.
- **Declaration order.** `PO3Step` is defined up in the PO3 core section, well
  above every new caller; the new enums and structs are declared before
  `OnInit`; and `PO3VetoRead` / `PO3ZoneRead` are plain data structs, returned by
  value the same way the parent already returns `PO3Read`.
- **Format strings.** All 12 `PrintFormat` calls in the fork audited for
  specifier-versus-argument count: **0 mismatches**. The two new read-out
  branches that would have used an inline string ternary were rewritten to
  assign to a local string first, matching the parent's own style.
- **Magic.** `20260867` is used by nothing else in the repo.

### Status & caveats

- **Not deployed, and not compiled.** No MQL5 toolchain was available, so this
  build has never been through MetaEditor. Expect to fix compile errors on first
  load, then backtest on demo before reading anything into a result.
- **The production VPS file is untouched**, and `20260867` shares positions with
  nothing — specifically not with the live build's `20260858`, §38's `20260865`
  or §39's `20260866`.
- **An unreadable H4 history blocks every entry on that symbol.** 180 H4 bars is
  about five weeks of trading, so a freshly added symbol is silent until it
  loads. The startup read-out prints `veto UNKNOWN` for it, and `BlockNote` says
  so once per streak rather than once a minute — but a silent symbol is the
  failure mode to watch for, and the reason the read-out exists.
- **Gate 4 defaults to the 2187 grade, which is rare on gold.** Expect very few
  blocks: at ~4000 the only 2187 multiples in view are 2187 and 4374. If the
  gate never fires, drop `InpPO3VetoPower` to `6` (729) — §1's default — and
  measure again. The two settings bracket the useful range.
- **Gate 5 is a large restriction when switched on.** Its 50/50 default refuses
  a long anywhere in the top half of a 243-unit range, so the trade count will
  move visibly. That is the point, but it means gate 5's effect should be read
  as its own A/B, not folded in with gate 4's.
- **The veto is a state, not an event.** It holds for as long as the level keeps
  rejecting price and clears when price closes back through it, so the journal
  will show long stretches of one block reason. That is the design; the reason
  string only reprints when it changes.
- **Clean A/B/C.** `InpPO3VetoEnabled = false` with `InpPO3ZoneEnabled = false`
  reproduces §38 exactly; turning on gate 4 alone isolates the reaction veto;
  both together is the full build.

---

## 41. Bottom-Up Stack EA — the tier set: a lean M5 + M15 + H1 stack

**File:** `experimental-bottomup-stack-m5-m15-h1-vps-ea.mq5`
**Forked from:** `ichimoku-h4-m1-vps-ea.mq5` (the live VPS build, magic
`20260858`), which is left untouched.
**Magic number:** `20260868` — held across all three drafts of this experiment
(the two M2 drafts and the eight-tier draft are deleted). Nothing else in the
repo uses it, so this build never adopts or manages the live build's positions
(`20260858`), the desktop twin's (`20260860`) or any fork's.

The parent trades **five** tiers — M5, M15, M30, H1, H4. This build trades
**three**, picked for separation rather than coverage:

| Tier | Chain that must align before it opens |
|---|---|
| M5 | M1 + M5 |
| M15 | M1 + M5 + M15 |
| H1 | M1 + M5 + M15 + H1 |

Plus **H4 as a bias, not a tier**: `tfs[]` still carries H4 and the H4 bias
filter still requires it aligned with the trade before any entry (the H1
stand-in covers M5 and M15 while H4 is flat). H4 has no risk row, no ATR handle,
no exit and no position of its own. M30 is gone entirely — neither a tier nor
read.

### Why three, and why these three

The chain is a strict **AND**, so the tier count is not a neutral choice. Every
tier added to the middle of the stack multiplies the rarity of every chain above
it while buying less and less independent information — adjacent timeframes are
highly correlated, and a rung earns its place by what it *adds*, not by existing.
Two observations drove the lean set:

1. **H4 was already doing the work.** The H4 bias runs the identical
   `CheckAlign(H4)` test an H4 *rung* would run, so for the H4 tier the rung was
   literally redundant with the bias, and for every other tier H4's direction was
   already required. Dropping H4 as a tier costs nothing in direction — it only
   removes a tradable level.
2. **M30 sat too close to its neighbours.** M15 → M30 is 2×, so an M30 rung
   largely repeated what M15 had already said, at the cost of a full extra
   condition on the H1 tier above it.

What is left is 3× then 4× spacing, which also keeps the Ichimoku horizons on
recognisable market rhythms — the periods are counts of *bars*, so 26 bars means
something different on every timeframe:

| Tier | Kijun = 26 bars | What that horizon is |
|---|---|---|
| M5 | ~2.2 h | intraday |
| M15 | 6.5 h | a session |
| H1 | 26 h | one trading day |
| (H4 — bias only) | 104 h | one trading week |

### The level space is small now, and every by-number test names its level

Three levels — **M5 = 0, M15 = 1, H1 = 2** — with `tfs[] = { M1, M5, M15, H1, H4 }`
and the parent's `lvl + 1` offset intact. Two by-number tests had to follow the
top tier as it moved from H4 to H1:

- the **D1 filter** now gates H1 (see the caveats — this is a real behaviour
  change for H1);
- the **tight break-even / full chandelier** bucket was `lvl >= 3` in the parent,
  meaning "H1 or H4". It is now `lvl >= LEV_H1`, so H1 keeps exactly the treatment
  it had and M5/M15 keep the looser spike-gated trail. Nothing moves.

One test changed shape: the H1-bias ceiling is level-relative, so
`ENUM_H1_BIAS_TIER` shrank to `{ M5 = 0, M15 = 1, H1 = 2 }` and its default moved
from M30 to **M15** — the tier below the top, which is what the parent's default
meant within its own stack. The H1 tier is deliberately excluded: the stand-in
*is* H1's direction, so letting H1 fall back on it would validate H1 against
itself.

### What the lean stack does to the trade count

Removing tiers is not symmetric with adding them, and the direction here is the
opposite of the eight-tier draft:

- **every chain gets shorter**, so every surviving tier fires more often. H1's
  chain drops from five rungs (M1 + M5 + M15 + M30 + H1) to three, and M15 loses
  M30 underneath it as well;
- **two tradable levels disappear** — M30 and H4 — so those entries are gone
  entirely. That is the cost of the change: fewer distinct setups, each firing
  more often;
- **H4's direction is not lost with the H4 tier.** The bias still requires it, so
  what disappears is H4 *entries*, never H4 *influence*.

The intended shape is a few well-spaced tiers each getting a fair share of the
bars, instead of five tiers where the top two almost never qualify and the bottom
one carries the count.

There is **no input that re-adds a tier**: the tier set *is* the level space, so
changing it is a code change. For a clean A/B against the five-tier parent, run
`ichimoku-h4-m1-vps-ea.mq5` itself on the same window.

### The cloud gate followed the tiers automatically

The parent's gate reads (a) the **tier's own timeframe** at the far end of the
future cloud and (b) the **timeframe directly below the tier**, the same way —
except where that timeframe is M1, which takes the full current+future check.
Both are index lookups (`tfs[lvl + 1]`, `tfs[lvl]`), so a shorter `tfs[]`
re-points them with no code change:

| Tier | own TF checked | "TF directly below" — what it now checks |
|---|---|---|
| M5 | M5 future | **M1 full (current + future)** |
| M15 | M15 future | M5 future |
| H1 | H1 future | **M15** future (was M30) |

M1 is still the only timeframe that must fully agree, and only for the M5 tier —
exactly the parent's rule. H4 is not referenced by the gate at all, because it is
not a tier.

### What the earlier drafts of this section established

Three tier sets have now been tried on this fork. The first two builds are
**deleted**; what they taught is kept here, because it is what motivated the lean
set:

1. **The M2 rung** (`-m2-rung-`, deleted). M2 as an extra *rung* between M1 and
   M5 could only ever filter — a rung is a timeframe that must agree, so it holds
   the entry count level or reduces it, never raises it. §38 found the same thing.
   It also needed real machinery: MT5 lists `PERIOD_M2`, but non-standard periods
   are built from the M1 series, so a symbol whose feed carries no M1 has no M2,
   and an *enforced* M2 rung would have failed every chain check in silence. The
   draft therefore had to skip the rung rather than require it.
2. **The M2 tier** (`-m2-tier-`, deleted). Making M2 tradable did add entries, but
   the earliest and thinnest ones: taken before M5 confirms, on the shallowest
   pullbacks, where a 2-minute bar sits closest to the spread.
3. **The eight-tier stack** (`-m10-m20-h2-tiers-`, deleted). M10, M20 and H2 as new
   tiers with M2 removed. This is the draft that showed the cost of the
   conjunction plainly: each added tier is also a rung above itself, so the three
   additions *tightened* every existing tier while adding three new ones, and the
   tier-1 risk rows summed to 55.5% of equity.

The lean stack is the response to (3): fewer tiers, wider spacing, and no tier
that merely repeats what its neighbour already says.

### Status & caveats

- **RESULT — user report: it does not perform as well as the live VPS build.**
  This is the only empirical datapoint the tier-set question has, and it points
  at the parent rather than at the lean set: **the five-tier stack stays the
  better tier set on the evidence so far.** The magnitude, the instrument, the
  window and whether it was a backtest or a forward test were not recorded, so
  read it as a direction rather than a measurement. It is enough to say the
  structural argument above — chain rarity, rung redundancy, the Kijun horizons
  — did not survive contact with the data, and **this build should not be
  promoted** on the strength of that argument. The obvious next test is which
  tier the performance was lost to: if it was H4's entries, H4 is the tier to
  put back first; if it was M30's, the parent's middle rung was doing more work
  than its 2x spacing suggested.
- **Not compiled, not backtested.** No MQL5 toolchain was available here. The
  fork has been statically audited — brace, paren and bracket balance; every
  level-to-timeframe index site converted; and a full `diff` against the parent
  showing only the intended changes — but it has never been through
  MetaEditor. Expect to fix compile errors on first load, then backtest on
  demo before reading anything into a result.
- **This is a fork, not a promotion.** The live build is untouched, and this
  build carries magic `20260868`, so nothing here can manage the live build's
  positions or vice versa.
- **Do not run it beside the live build on the same account and symbol.** The
  magics are distinct, which means both EAs would trade that symbol
  independently and the account's exposure would double. Use a demo account or
  a separate terminal.
- **The risk ladder is the parent's, not an invention.** M5 1%, M15 1%, H1 10% —
  the parent's own rows for those three tiers, with the M30 (5%) and H4 (20%) rows
  removed along with those tiers. The tier-1 total therefore falls from the
  parent's 37% to **12%** if all three ran at once.
- **That aggregate is still reachable.** Per §24 the "one position per symbol"
  claim is not enforced: a higher tier already running is never closed by a
  smaller signal, so all three can be open together. The R3 disaster stop sits at
  8 x ATR while sizing assumes 2 x, so the worst case on a full stack is four
  times the nominal risk.
- **H1 now carries a D1 filter the parent's H1 did not have.** The D1 gate was
  written as "the top tier" (`LEVELS - 1`), which was H4 in the parent and is H1
  here, so H1 entries additionally need the daily aligned. This is the one
  behaviour change beyond the tier count. `InpD1Filter = false` restores the
  parent's H1 exactly, and it is the first input to try if H1 trades look too
  rare.
- **Judge it on the pair, not on the count.** Shorter chains mean more entries at
  every surviving tier, but two levels are gone, so the net count could move
  either way. Compare win rate, average trade and worst drawdown against the
  parent on the same window, and read the M5/M15 entries separately from the H1
  ones — H1 is now the only tier taking the 10% row.
- **H4 is not a tier, and that is deliberate.** Its direction is still required on
  every trade through the bias, so what was given up is H4 *entries* — the rare,
  largest, longest-held ones. If forward results suggest the big swing trades were
  carrying the account, H4 is the first tier to put back.
- **One parent behaviour is inherited unchanged.** The parent's header claims
  "at most one position per symbol"; §24 shows that is not enforced — a higher
  tier already running is never closed by a smaller signal, so several tiers
  can run at once. This fork corrects the header text but deliberately does not
  change the behaviour.

---

## 42. Bottom-Up Stack EA — M2 as a tradable TIER

**File:** `experimental-bottomup-stack-kihon-po3-veto-m2tier-ea.mq5`
**Magic number:** `20260869`

A fork of §40's kihon + PO3 + veto build (`20260867`), which forks §38's
kihon + PO3 gate experiment (`20260865`), which forks the live VPS build
(`20260858`). Gates 1–5, the M1-strict cloud bias, the robustness pack and the
M2 rung are all unchanged. The one change is a **sixth tradable tier at the
bottom of the stack: M2**.

> **Not the same experiment as §41 — check which one you mean.** §41 has moved on
> twice: its M2 drafts were superseded and deleted, and
> `experimental-bottomup-stack-m5-m15-h1-vps-ea.mq5` (magic `20260868`) is now a
> **lean three-tier** fork of the **live VPS build** — M5, M15, H1, with H4 kept
> as a bias only — and it does not read M2 at all. **This** build is the one that
> keeps **M2 as a tradable tier**, on top of the kihon + PO3 + veto stack (§40's
> build), so its M2 trades must clear gates 1–5 as well. Different parents,
> different magics (`20260868` vs `20260869`) — the magics do not collide, so both
> can run side by side, but they answer different questions and their trade counts
> are not comparable. §41's own conclusion is that a lower tier is worth having
> only if it is *not* redundant with its neighbour; this build's M2 tier sits
> directly under M5, so that question applies to it too.

### What "an M2 tier" means

M2 now plays **two independent roles under two independent switches**:

| Role | Switch | Effect |
|---|---|---|
| **Rung** | `InpUseM2` (default on) | M2 is a step in the higher tiers' chains: the M5 tier needs M1 + M2 + M5, and every higher tier inherits it |
| **Tier** | `InpM2Tier` (default on) | M1 + M2 aligned opens an **M2 trade** — its own risk row, its own ATR handle, its own exits, managed by the same code as M5 |

Both are on by default, so the stack out of the box is:

```
M2 tier   <- M1 + M2
M5 tier   <- M1 + M2 + M5
M15 tier  <- M1 + M2 + M5 + M15
... and so on up to H4.
```

The two roles are genuinely independent. `InpM2Tier = false` reproduces §40
exactly (M2 as a rung only); `InpUseM2 = false` with the tier on gives M2
trading on M1 + M2 while M5 trades on M1 + M5 — a coherent build, just not the
default one.

### Why this is not just a setting

Levels are addressed by **index** (0 = the bottom of the stack), so adding a
tier at the bottom renumbered all five existing tiers:

| Level | Before (§40) | After |
|---|---|---|
| 0 | M5 | **M2** |
| 1 | M15 | M5 |
| 2 | M30 | M15 |
| 3 | H1 | M30 |
| 4 | H4 | H1 |
| 5 | — | H4 |

Every site that hardcoded a level number had to move with it. The four that
mattered, and what would have broken silently:

- **`LevelRiskPct()`** — a 6th row added and all five cases shifted. Left alone,
  every tier would have been sized with the row below it: the H4 tier would have
  risked H1's 10% instead of 20%.
- **`LevelCloudBiasOK()`** — the "this tier sits on M1, so it carries the full
  current+future check" special case was `lvl == 0`. Left alone it would have
  given the **M5** tier the M2 tier's treatment and left the M2 tier's own cloud
  unchecked. It now branches on `LVL_M2` for the new bottom and `LVL_M5` for the
  old one.
- **`ManageLevelProtection()`** — the break-even and chandelier arming
  thresholds split on `lvl >= 3`, where 3 was H1. After the shift 3 is M30, so
  the **M30 tier would have been given the H1/H4 tighter arming rule** and H1
  would have lost it.
- **`ENUM_H1_BIAS_TIER`** — the enum values *are* level indices, so the H1-bias
  ceiling moved from `{0,1,2,3}` to `{1,2,3,4}`. Left alone, the default
  `H1TIER_M30` would have allowed only up to M15 on the H1 stand-in. The M2 tier
  is deliberately not named in the enum but *is* covered by it: M2 is level 0,
  below every setting, so any mode but OFF lets the stand-in carry the M2 tier
  too — the same "lower tiers may stand in" rule read one rung further down.

Those four are the "M2's arrival is exactly the kind of change that leaves one
of those sites behind" trap §38's own comment warned about, and all four were
live. `LVL_M2`, `LVL_M5` and `LVL_H1` now name the three that mean something.

### The rung skip — the subtle one

`ChainAligned()` walks the chain from M1 upward and **skips the M2 rung when it
is inactive** (switch off, no handle, or no history yet). It returns 0 on
unreadable data, so skipping is what makes a broker without M2 non-fatal.

With M2 as the bottom tier, `TfIdxOfLevel(LVL_M2)` **is** `IDX_M2` — the M2
tier reads the very timeframe the rung skip is about. So the skip would have
applied to the M2 tier's own chain, which *is* M2, leaving it validating on
**M1 alone** and opening M2 trades on a single timeframe. The skip is now
level-aware:

```cpp
if(t == IDX_M2 && t < topIdx && !M2RungActive(s)) continue;
```

For the M2 tier `topIdx` is `IDX_M2`, so the guard cannot fire and M2 is
required. For every tier above it `topIdx` is larger and the skip behaves
exactly as it did before. A symbol with no M2 feed needs no special case:
`CheckAlign()` on an unreadable M2 returns 0, so the M2 tier simply never opens.

### Behaviour worth expecting

- **The M2 tier will usually be superseded by M5, not run alongside it.** The
  rung is on by default, so an M5 chain (M1 + M2 + M5) implies an M2
  alignment. The consolidation rule closes lower tiers when a higher one opens,
  so when both align on the same minute the M2 trade is closed into the M5
  entry. The M2 tier therefore opens mainly when **M2 aligns and M5 does not**.
  That is the expected shape, not a bug — but it means the tier's contribution
  is the trades the stack previously declined, not a doubling of the count.
- **An M2 feed is now needed for two things.** Both roles fail independently but
  for the same reason, and both remain non-fatal: a symbol without M2 loses the
  tier *and* the rung and keeps the other five tiers. The startup read-out
  prints both roles per symbol so a silent M2 tier is visible.
- **M2 is sized below M5** (0.5/0.25/0.05 against M5's 1/0.5/0.1). A 2-minute
  bar is close to the noise floor on a wide-spread feed, and a wrong M2 read
  costs the same dollars per lot as a wrong M5 read.
- **M2's PO3 power is 3, the same as M5's** (`InpPO3Power = "3,3,3,4,4,5"`), not
  2. The room filter's blocking fraction is roughly `InpPO3MinRR × refRisk /
  step`, and M2's reference risk is about 0.6 of M5's, so step 9 would read "no
  room" on about 40% of positions where step 27 reads about 14%. Over-blocking
  the thinnest tier is the worse error; the startup read-out prints what M2
  actually sees.
- **Gate 4 and gate 5 apply to the M2 tier too.** They are market-wide and
  directional, tested per tier, so the M2 tier is vetoed by the same rejection
  and zone rules as everything else. Nothing was special-cased for it.

### Inputs that changed

| Parameter | Default | Description |
|---|---|---|
| `InpM2Tier` | `true` | **New.** Let M1 + M2 open an M2 trade, with its own risk row and exits |
| `InpRiskPctM2` / `_T2` / `_T3` | `0.5` / `0.25` / `0.05` | **New.** M2's three equity-tier risk rows |
| `InpPO3Power` | `"3,3,3,4,4,5"` | Was `"3,3,4,4,5"`; M2's power added at the front (see above) |
| `InpH1BiasMaxTier` | `H1TIER_M30` | Enum values shifted to `1=M5, 2=M15, 3=M30, 4=H1` |

Everything else is unchanged from §40.

### Verification performed

No MQL5 compiler on this machine, so this is static verification against §40's
file as the parent:

- **Fork integrity.** 48 functions in the parent, **none removed**. After
  comment and whitespace normalisation **42 are identical**, **6 differ**
  (`OnInit`, `ChainAligned`, `LevelCloudBiasOK`, `LevelRiskPct`,
  `ManageLevelProtection`, `OnTick`) and **1 is new** (`M2TierActive`).
- **Every changed function token-diffed.** `ChainAligned` gains only `t < topIdx
  &&`; `LevelRiskPct` gains one `LVL_M2` case and shifts the other five case
  labels; `LevelCloudBiasOK` gains the M2 branch and changes `lvl == 0` to
  `LVL_M5`; `ManageLevelProtection` changes exactly two tokens, the two `3`s to
  `LVL_H1`; `OnTick` gains one hunk, the M2-tier guard at the top of the tier
  loop; `OnInit`'s three hunks are the M2 handle condition, the optional M2 ATR
  handle, and the two-role startup read-out.
- **A level-index sweep** for bare numbers compared against a level variable
  now finds only `lvl < 0` (a clamp in `PO3Verdict`) and `l >= 0` (a loop
  bound) — no bare level constants remain.
- **Balance.** Braces 164 / 164, parentheses 921 / 921, brackets 468 / 468.
- **Format strings.** All 33 `Print` / `PrintFormat` calls in the fork audited
  for specifier-versus-argument count: **0 mismatches**.
- **Magic.** `20260869`. `20260868` was claimed by the concurrent §41 fork
  *while this build was being written* — §41 held it first, for its M2 drafts
  and now for its eight-tier build — so this one was renumbered rather than
  shipped colliding; the collision was found by the repo-wide magic scan and
  both files now declare distinct numbers.

### Status & caveats

- **Not deployed, and not compiled.** Expect to fix compile errors on first
  load, then backtest on demo.
- **The production VPS file is untouched**, and `20260869` shares positions with
  nothing — specifically not the live `20260858`, §38's `20260865`, §39's
  `20260866`, §40's `20260867` or §41's `20260868`.
- **The tier's effect is mostly a filter, not a new trade stream.** Read the
  trade count before reading the profit: because M5 supersedes M2 whenever both
  align, the M2 tier trades the chains the stack used to decline. If the count
  barely moves, the interesting question is the average trade, not the sample
  size.
- **`TfIdxOfLevel()` now returns different timeframes for the same index than
  §38/§40 do.** Anything that compares this build's journal or comment levels
  against the parent's must map levels, not copy indices. The entry comments
  (`Exp Buy M2`, `Exp Buy M5`, …) are built and parsed by the same function, so
  the EA itself is self-consistent; it is cross-build reading that needs care.
- **An M2 tier inherits M2's data quality.** A 2-minute gold bar is close to
  the spread, and its ichimoku is built from far fewer ticks than M5's. Its
  kumo-touch exit, rejection exit and chandelier all run on that data. Treat it
  as the thinnest tier in the stack, which is why it is sized smallest.

## 43. Bottom-Up Stack EA — M1+M2 scalp tier with an M30 bias

**File:** `experimental-bottomup-stack-m1m2-scalp-m30-bias-ea.mq5`
**Magic number:** `20260870`

A fork of the **live VPS build** (`ichimoku-h4-m1-vps-ea.mq5`, `20260858`) by
direct user request: *"add an additional bias timeframe for scalping with
M1-M2 alignment only alignment. Use M30 for bias."* Read literally that is
three requirements, and the build is exactly those three:

| Requirement | Implementation |
|---|---|
| A new **scalping** tier | A sixth tradable tier at the bottom of the stack — **M2**, level 0 |
| **M1-M2 alignment only** | The tier's chain is `ChainAligned(s, IDX_M2)` — exactly M1 + M2. Nothing higher is read for alignment |
| **M30 for bias** | `M30Bias()` = `CheckAlign(s, IDX_M30)`, applied to the scalp tier and to nothing else |

Nothing in the five live tiers changed. That claim is verified below, not
asserted.

### The one design decision worth arguing about

There were two coherent readings of "use M30 for bias", and they produce very
different EAs:

- **M30 as the scalp tier's own bias** — chosen. The tier answers to M30 and
  nothing else, so it can scalp while H4 is flat and, more controversially,
  **against an aligned H4**.
- **M30 as another stand-in on the existing ladder** — rejected. That is what
  `experimental-bottomup-stack-m30-bias-ea-third-most-profitable.mq5` already
  does: M30 applies only when H4 **and** H1 are both flat, as a last resort.

The second is the more conservative design and reuses proven code, so it is
worth being explicit about why it was not used: it is **not what was asked
for**. A last-resort stand-in by construction cannot scalp against H4, and it
couples the new tier to the H4/H1 ladder the request treats as separate. The
chosen reading makes the scalp tier an independent regime — which is also the
more interesting experiment, because a counter-H4 scalp is a genuinely new
trade stream rather than a subset of one the stack already takes.

**The counter-trend exposure is real and intended.** An M2 long can open while
H4 is aligned bearish. If that turns out to be the wrong call, the switch is
`InpM30ScalpBias = false` (the tier then trades the bare M1+M2 chain), or gate
it explicitly — the note in `M30Bias()` says so at the call site.

### M2 is a TIER, not a rung — the difference from §42

§42 also added an M2 tier at the bottom, which makes it the obvious thing to
compare against twice over. **They are different experiments and their numbers
are not comparable.**

| | §42 (`20260869`) | §43 — this build (`20260870`) |
|---|---|---|
| Parent | §40's kihon + PO3 + veto build | the **live VPS build** (`20260858`) |
| M2 as a **rung** | yes, `InpUseM2` — M5 needs M1 + M2 + M5 | **no** — M5 stays M1 + M5 |
| M2 as a **tier** | yes, `InpM2Tier` | yes, `InpM2ScalpTier` |
| Scalp tier's bias | the parent's H4/H1 ladder | **M30 only, independent of H4** |
| Other gates | gates 1–5 (kihon, PO3, vetoes) | none added — the live build's own gates |

The rung difference is the load-bearing one. Because §42 keeps M2 as a rung,
its M2 tier fires on chains the M5 tier *also* satisfies, so M5 supersedes it
constantly and the tier mostly adds filter behaviour. Here M2 is **only** a
tier: `ChainAligned()` skips the M2 rung for every tier above the scalp tier,
so every M2-tier trade is a chain **no live tier would have taken**. The
contribution is additive by construction.

### The two hazards a fork like this inherits, and what was done about them

An adversarial static review of the first draft found two real defects. Both are
recorded here because both are the kind of thing that looks fine until it costs
money.

**1. The scalp tier could open against a running live-tier position.** The entry
scan *skips* a level that already holds a position rather than evaluating it
(`if(state[s][l] != 0) continue;`), and the supersede loop only walks **below**
the tier that opens (`for(int l = 0; l < topTier; l++)`). So a tier that is
already running neither blocks a new entry nor gets closed by one. For the five
live tiers that is the parent's behaviour. For the scalp tier it is a **new**
hazard, precisely because M30 rather than H4 grants its direction: with an H4
long already open, M1+M2 can align **short** on a later bar, and the scalp would
open against the live position. On a netting account MT5 then nets the two
orders together — shrinking or closing the live trade behind the EA's back while
`state[]` still reports it open, until the next `SyncStatePositions()`.

Fixed for the scalp tier only, via `HigherLiveLevelBusy()` and
`InpScalpNeedsFlatSymbol` (default on). The parent's equivalent case among the
five live tiers is deliberately **not** changed, to preserve parity — so read
the one-position rule narrowly: it now genuinely holds for the scalp tier, and
remains exactly as loose for the live tiers as it is in the parent. The first
draft's header claimed "at most one position per symbol runs at a time" without
qualification; that claim was false in the parent too and is now stated
correctly.

**2. A feed that refuses M2 would have killed the whole EA.** `OnInit` created
the M2 ichimoku and M2 ATR handles inside loops whose every iteration ended in
`if(handle == INVALID_HANDLE) return(INIT_FAILED);` — correct for the five live
timeframes, wrong for the added one. A broker refusing M2 would have aborted
initialisation for the **entire** EA, taking the five live tiers down with it and
printing nothing, because the read-out was after the failing loop. The tier's own
comment claimed the opposite ("non-fatal, and the five live tiers are
unaffected"). Both handle loops now exempt `IDX_M2` / `LVL_M2`: the symbol loses
the scalp tier, keeps everything else, and says so in the journal. This matches
how the repo's other M2 builds already treat a missing M2 feed (§38, §42).

A third, smaller fix: the "tier ACTIVE" read-out was decided in `OnInit`, where
a non-chart symbol's M2 series has often not been built yet and a timeseries
accessor returns 0 — so a healthy feed could report "no M2 history" and never
correct itself. It now fires once, lazily, on the first closed M1 bar where M2
actually carries enough bars to read.

### M2's cloud rule, and why it is a switch

The scalp tier's **own** cloud is governed by `InpM2CloudFull`, default
**`false`** — M2 takes the M5+ future-only rule, i.e. the live build's "M1 full /
M5+ future-only" split simply extended one timeframe down. That is the reading
most faithful to "the live VPS build plus a scalp tier", and it is what the rest
of this section assumes.

`InpM2CloudFull = true` gives M2 the M1-style **full** current+future check
instead, on the argument that a 2-minute bar is close in character to M1. **That
is the sibling M2 build's default** — `experimental-bottomup-stack-kihon-po3-
veto-m2tier-ea.mq5` (§42) ships `InpM2CloudFull = true`. The two builds
therefore disagree on M2's cloud rule out of the box, and **their scalp trade
sets are not comparable until they are set the same way**. Flagged here because
"two M2 experiments, same idea, different numbers" is exactly the kind of
cross-build misreading §42's own notes warn about.

### Level renumbering — the four sites that would have broken silently

Adding a tier at the bottom renumbered all five existing levels (M5 0→1,
M15 1→2, M30 2→3, H1 3→4, H4 4→5). Four sites hardcoded a level number and all
four were live; each fix is one or two tokens.

1. **`LevelRiskPct()`** — the M2 row was prepended and the five `case` labels
   shifted. Left alone, **every tier would have been sized with the row below
   it**: H4 would have risked H1's 10% instead of 20%, H1 would have risked
   M30's 5%, and so on down. This is the most expensive of the four and the
   hardest to see, because the trades and their direction are unchanged — only
   the lot sizes are wrong.
2. **`LevelCloudBiasOK()`** — the "this tier sits directly on M1, so it carries
   the full current+future M1 cloud check" case was `lvl == 0`, and 0 is now
   M2. The trap is that the *obvious* fix (leave it as `lvl == 0`) is wrong in
   a way that looks right: it would have given the M5 tier future-only
   treatment on **M2** — a timeframe its chain does not even contain — and left
   **M1 unchecked for M5 entirely**. The correct condition is `lvl <= LVL_M5`,
   because M2 is not a rung here, so **both** the M2 and M5 tiers sit directly
   on M1. §42 needed a different fix at this same site for the same reason its
   rung differs.
3. **`ManageLevelProtection()`** — the break-even and chandelier arming bucket
   split on `lvl >= 3`, where 3 was H1. After the shift 3 is M30, so M30 would
   have been handed the H1/H4 **tighter** arming rule and H1 would have lost
   it. Now `lvl >= LVL_H1`; the token diff is exactly two `3`s.
4. **`ENUM_H1_BIAS_TIER`** — the enum member values *are* level indices, so the
   ceiling moved from `{0,1,2,3}` to `{1,2,3,4}`. Left alone, the default
   `H1TIER_M30` would have meant "up to M15" and silently dropped the M30 tier
   from the H1 stand-in.

A sweep for any bare numeric literal compared against a level variable now
finds only `lvlMatch < 0` (a clamp) — no bare level constants remain.
`LEVELS - 1` is still the H4 tier in both of its uses.

### Inputs added

| Parameter | Default | Description |
|---|---|---|
| `InpM2ScalpTier` | `true` | Let M1 + M2 aligned open an M2 scalp trade, with its own risk row, ATR handle and exits |
| `InpM30ScalpBias` | `true` | The scalp tier's only directional gate. Off = it trades the bare M1+M2 chain |
| `InpScalpNeedsFlatSymbol` | `true` | Never scalp while any live tier holds a position (hazard 1 above). Off restores the parent's looser semantics for the scalp tier alone |
| `InpM2CloudFull` | `false` | M2's **own** cloud: `true` = M1-style full check, `false` = the M5+ future-only rule. §42 defaults this to `true` — see above |
| `InpRiskPctM2` / `_T2` / `_T3` | `0.5` / `0.25` / `0.05` | The scalp tier's three equity-tier risk rows (a budget, not a lot count — see the caveats). The parent's three-tier ladder is unchanged |

Everything else is unchanged from the live build, including all of its own
inputs.

### Verification performed

No MQL5 compiler on this machine, so this is static verification with the
parent file as ground truth.

- **Fork integrity, function level.** 29 functions in the parent, 30 in the
  fork: **none removed, exactly one added** (`M30Bias`). After comment and
  string-literal normalisation **22 are byte-identical** and **7 differ**:
  `ChainAligned`, `EntryBiasOK`, `LevelCloudBiasOK`, `LevelRiskPct`,
  `ManageLevelProtection`, `OnInit`, `OnTick`.
- **Every changed function token-diffed**, and each diff is only what the
  design calls for: `ChainAligned` gains the rung-skip and two index names;
  `LevelCloudBiasOK` changes two tokens (`== 0` → `<= LVL_M5`, `0` → `IDX_M1`);
  `LevelRiskPct` gains the M2 case and shifts five labels;
  `ManageLevelProtection` changes exactly two `3`s; `EntryBiasOK` gains the M2
  block that returns before the H4/H1 ladder; `OnInit` gains the M2 read-out;
  `OnTick` gains one guard line. **No other function was touched at all.**
- **Chain mapping traced for all six tiers.** M2 = M1+M2; M5 = M1+M5;
  M15 = M1+M5+M15; M30 = +M30; H1 = +H1; H4 = +H4. The five original chains are
  identical to the parent's, which is the whole point of skipping the rung.
- **Cloud gate traced for all six tiers.** M2 and M5 → tier TF future-only +
  **M1 full check**; M15 and above → tier TF future-only + TF-below future-only.
  This reproduces the parent's M5+ behaviour exactly.
- **Position-comment compatibility.** Comments are built by `LevelComment()`
  from `tfName[lvl + 1]`, and `tfName[]` shifted with the levels, so the
  *strings* are unchanged per timeframe (`Exp Buy M5` is still `Exp Buy M5`).
  Positions opened by the live build are not adopted either way (different
  magic), but the naming stays consistent for journal reading.
- **Balance.** Braces 89/89, parentheses 499/499, brackets 376/376.
- **Format strings.** The file contains no `PrintFormat` calls; the two new
  `Print` calls in `OnInit` use concatenation only, so there are no
  specifier-versus-argument pairs to mismatch.
- **Independently reviewed.** An adversarial static review was run against the
  parent as ground truth, hunting specifically for a fifth renumbering escape,
  chain-logic errors, and regressions in the five live tiers. It found no
  renumbering escape and confirmed the five live tiers unchanged — and it found
  the two real defects described above, both now fixed. The review's verdict on
  the first draft was "the renumbering work is genuinely clean; the two things
  worth acting on are the running-position hazard and the fatal M2 handle".
- **Magic.** `20260870` — fresh, shared with nothing. `20260869` was the
  previous highest in use (AGENTS.md said `20260865` and was stale; corrected).

### Status & caveats

- **Not deployed, and not compiled.** Expect to fix compile errors on first
  load, then backtest on demo.
- **The production VPS file and the desktop twin are untouched.** Nothing was
  promoted, and per AGENTS.md no VPS file was modified.
- **`PERIOD_M2` must exist on the broker's feed.** It is a standard MT5
  timeframe, but a symbol whose feed refuses M2 loses the tier: `OnInit` exempts
  the M2 handles from its fatal check, `scalpReady[]` goes false for that symbol
  and the journal says so. **The five live tiers keep running** — that is the
  whole point of the exemption, and it is now true (see hazard 2 above).
- **Read the scalp tier's risk as a budget, not a lot count.** The scalp tier
  carries a smaller *risk budget* than M5 (0.5% vs 1%), but lots scale as
  `riskPct / ATR(tier TF)` and ATR(M2) < ATR(M5), so the scalp tier's **lot
  size is frequently larger** than M5's. What stays smaller is the money at the
  disaster stop (2% vs 4% of equity at 8 × ATR). "Sized below M5" means the
  budget; it does not mean a smaller position.
- **Expect the scalp tier to be rare, and check that first.** It only opens
  when M1+M2 align *and* M30 agrees *and* no live tier passes its gates on that
  same minute *and* (by default) no live tier holds a position. If the journal
  shows almost no `bias M30` entries, the question is those filters, not the
  code.
- **Read the counter-H4 trades separately.** Entries log `(bottom-up, bias M30)`
  and the tier is `Exp Buy M2` / `Exp Sell M2`, so the trades taken against an
  aligned H4 can be isolated. That subset has no precedent in the live build,
  and it is the part most likely to decide whether this build is worth keeping.

---

## 44. Bottom-Up Stack EA — a hard take profit on M2 and M5

**File:** `experimental-bottomup-stack-m1m2-scalp-m30-bias-hardtp-ea.mq5`
**Forked from:** `experimental-bottomup-stack-m1m2-scalp-m30-bias-ea.mq5`
(section 43 — the M1+M2 scalp tier with an M30 bias, magic `20260870`),
which is left untouched
**Magic number:** `20260871` — fresh, so this build never adopts or manages
positions belonging to any other file

### What changed

The whole bottom-up family has **no profit target anywhere**. Every tier
rides a kumo-touch exit with the BE/chandelier layer behind it, and the only
thing attached to the order is the wide disaster stop. This build is the
first to put a **broker-side TP on the ticket at the moment it is sent**, on
the two smallest tiers only:

| Tier | Target | On a 4000.00 gold entry |
|------|--------|-------------------------|
| M2   | `InpTPPipsM2` = 30 pips | long 4003.00, short 3997.00 |
| M5   | `InpTPPipsM5` = 60 pips | long 4006.00, short 3994.00 |
| M15, M30, H1, H4 | none | unchanged from the parent |

`LevelTPPips()` returns 0 for every tier above M5, and 0 is also MT5's own
"no TP" value, so the four upper tiers need no special case — they send the
same order the parent sends.

### Pip size, and why it auto-resolves

A pip here is the **gold convention: 0.10 of price**. The two defaults are
therefore a 3.00 target on M2 and a 6.00 target on M5. In points — the unit
MT5 actually works in — that depends on the feed:

| Feed | 1 point | Points per pip | M2 (30 pips) | M5 (60 pips) |
|------|---------|----------------|--------------|--------------|
| 2-decimal gold | 0.01  | 10  | 300 points  | 600 points  |
| 3-decimal gold | 0.001 | 100 | 3000 points | 6000 points |

`InpPipPoints = 0` (the default) makes `PipPoints()` resolve this from
`SYMBOL_DIGITS` as `round(0.10 / point)`. The fixed-TP sibling (section 38)
instead hard-codes `InpPipPoints = 10` and tells the reader to change it to
100 on a 3-decimal feed — a step that is silent when missed and puts every
target at **a tenth** of the intended distance. Auto-resolving removes that
failure mode: the same pip figure means the same price distance on either
feed. OnInit prints the resolved points-per-pip and the resulting price
distance per symbol, so the number is stated rather than assumed.

The auto rule is **gold-specific by design**. On a 5-digit FX symbol it would
make one pip 0.10 of price — 1000 FX pips — so a non-gold symbol needs
`InpPipPoints` set explicitly (10 for 5-digit FX). `Symbols` defaults to
`GOLDm#`, so the default path is the correct one.

### The target is additive, not a replacement

This was a deliberate choice over the fixed-TP sibling's philosophy, where
the target and the disaster stop are the *only* ways out. Here the
kumo-touch exit, the rejection-candle exit, the BE stop, the chandelier
trail and the disaster stop **all still run on M2 and M5**, and the trade
ends on whichever arrives first. The consequence is worth stating plainly:

- This build can only ever **shorten** an M2/M5 trade relative to the
  parent, never extend one. Any trade that would have run past 30/60 pips
  and been handed to the trail is now cut at the target instead.
- Every other trade in the file — all four upper tiers, and any M2/M5 trade
  that never reaches its target — is **identical to the parent's**. So the
  A/B against section 43 isolates exactly one thing: what capping the two
  scalp tiers costs or saves.
- `InpHardTPEnabled = false` restores the parent exactly.

### Two mechanics that make the anchor hold

1. **Every `PositionModify` now carries the current TP back in.** The parent
   passed a bare `0` in that slot, which was correct when no tier had a
   target but would have **stripped the target the first time BE or the
   chandelier fired** — the trade would have silently reverted to parent
   behaviour mid-flight, and only on the trades that went far enough to arm
   BE. `tpCur` is read once per `ManageLevelProtection()` call and re-read
   before the trail block, since the BE block may have modified the ticket.
2. **A missing target self-heals**, mirroring the disaster stop's R3 path. A
   target rejected at send time by the broker's minimum stop distance, or
   stripped later, is re-attached on the next minute from the **entry**
   anchor — not the current quote — so it lands where it would have at open.
   `SyncStateFromPositions()` restores `entryPrice` from
   `POSITION_PRICE_OPEN`, so this survives a restart mid-trade. The entry
   log says `TP deferred (broker distance)` when the target did not go out
   with the order, so a deferred target is visible rather than silent.

A TP fill needs no bookkeeping of its own: `SyncStateFromPositions()`
rebuilds every level's state from the live positions each minute, so a
broker-side close frees the tier on the next bar exactly as a stop-out does.

### What to watch

- **The reward:risk of M2/M5 now drifts with volatility.** Risk sizing is
  unchanged and still runs off ATR (`InpRiskATRMult`), with the disaster
  stop at ATR x `InpDisasterATRMult` — but the target is a *fixed* pip
  distance. 30 pips is a long way in a quiet session and a short one in a
  fast session, so the effective R:R of these two tiers is not constant the
  way it is in the fixed-TP sibling, where both legs are fixed. This is
  inherent to mixing a fixed target with an ATR stop; judge the two tiers
  against section 43 before reading anything into the numbers.
- **M2 and M5 now have different targets** (30 vs 60), where every previous
  fixed-target build used one number for both. The M5 tier holds a longer
  chain and a longer bar, so the wider target is the intent — but it does
  mean the two tiers are no longer comparable to each other on target size.
- **Check the resolved pip line in the journal before trusting a backtest.**
  It is the one number that silently invalidates every result if the feed is
  not what was assumed, which is exactly why OnInit prints it per symbol.
- **Not yet compiled or backtested.** The file was written and statically
  checked (brace/paren balance, no `PositionModify` left stripping the TP,
  format-specifier arity) but there is no MQL5 compiler on the machine it
  was authored on. MetaEditor is the first step before any test run.

---

## 45. Bottom-Up Stack EA — an M1 tier, re-cut targets, and a five-band risk ladder

**File:** `experimental-bottomup-stack-m1-m2-scalp-tiers-5band-ea.mq5`
**Forked from:** `experimental-bottomup-stack-m1m2-scalp-m30-bias-hardtp-ea.mq5`
(section 44 — the hard M2/M5 take profit, magic `20260871`), which is left
untouched
**Magic number:** `20260872` — fresh, so this build never adopts or manages
positions belonging to any other file

### 1. A seventh tier: M1, alone

The entry condition is `CheckAlign(M1) != 0` and nothing else. No higher
timeframe confirms it. This is a deliberate break with the rule every build
in this family has carried since the beginning — *"M1 alone never trades; it
is only the start of the stack"* — and it sits behind `InpM1Tier`.

Its bias is **M30 alone** (`InpM1M30Bias`), the same gate the M2 scalp tier
uses and for the same reason: the bottom tiers are a separate regime that
does not consult H4 or the H1 stand-in ladder. So the M1 tier trades while
H4 is flat, and **against an aligned H4**. Expect a high trade count and no
higher-timeframe agreement whatsoever; this is the least confirmed entry in
the file by a wide margin, and the honest expectation is that it is the
first thing to switch off if the results disappoint.

**The level index now equals the TF index.** With M1 tradable the level list
`{M1,M2,M5,M15,M30,H1,H4}` is exactly `tfs[]`, so the parent's `lvl + 1`
offset — which existed only because level 0 was M2 — is gone from all 18 of
its call sites. `LVL_*` and `IDX_*` are now equal by construction, and both
are kept because they say different things at a call site (which *tier* vs
which *timeframe*). `ENUM_H1_BIAS_TIER` shifted up by one with them, so
`H1TIER_M5 = 2` where it was 1.

The cloud gate gained a case: the M1 tier has no "TF below" to confirm, so
the M1 cloud checked in full **is** its whole gate.

### 2. Targets re-cut, M1 given one, and a tight hard stop added

| Tier | TP | SL | reward:risk | on a 4000.00 long |
|------|----|----|-------------|-------------------|
| M1   | 30 pips | 20 pips | 1.50 : 1 | TP 4003.00, SL 3998.00 |
| M2   | 40 pips | 25 pips | 1.60 : 1 | TP 4004.00, SL 3997.50 |
| M5   | 50 pips | 30 pips | 1.67 : 1 | TP 4005.00, SL 3997.00 |
| M15+ | none | none | — | 8xATR disaster stop only, as the parent |

A pip is still the gold convention (0.10 of price), still auto-resolved from
`SYMBOL_DIGITS`. The **target** is still additive — every managed exit still
runs on these tiers. The **stop** is not: it *replaces* the wide disaster
stop on M1/M2/M5.

Two details keep "tighter" honest:

- **Clamped to the tighter of the fixed distance and 8xATR.** On a quiet
  feed a fixed 20 pips can exceed 8xATR, which would make the "tight" stop
  *wider* than the parent's — the opposite of the point. `HardStopDistance()`
  takes the minimum of the two, so the clamp bites at low ATR (at ATR 0.10 on
  gold, all three tiers fall back to 8xATR = 0.80) and the fixed figure rules
  everywhere above.
- **The broker minimum stop distance is still the floor.** A stop too tight
  to place is widened to the nearest legal level, not dropped.

#### The sizing change, which matters more than the stop itself

`RiskLots()` sized every tier against `2 x ATR` while the stop sat at
`8 x ATR` — which is why, throughout this family, a stop-out has cost about
**4x** the percentage named in the input. A *fixed* pip stop has no fixed
relationship to 2xATR at all, so leaving sizing untouched would have made
the risk table fiction on precisely the three tiers this change is about:
lots sized for a 2xATR loss, stopped out at whatever ratio 20 pips happened
to bear to 2xATR that minute.

So M1/M2/M5 are now sized on **the stop they will actually run**. The
consequence must be read before comparing any two tiers:

| tiers | sized against | stopped at | a stop-out costs |
|-------|---------------|------------|------------------|
| M1, M2, M5 | their hard stop | their hard stop | **~1x** the stated risk % |
| M15, M30, H1, H4 | 2 x ATR | 8 x ATR | **~4x** the stated risk % (unchanged) |

**The two halves of the risk ladder are no longer on one scale.** The §45
risk table above still describes the *sizing* basis correctly for every
tier, but the money a stop-out costs now differs by a factor of four between
the bottom three tiers and the top four. OnInit prints this split at startup
rather than leaving it to be discovered.

### 3. Three risk bands become five, and 13k+ carries more risk

The parent's ladder cut H4 to 2.0% above 13000, against 10.0% in the
7000–13000 band. That 5x cliff outran the equity growth that triggered it,
so an account crossing 13000 risked **fewer dollars than it had at 7000**:

| | equity | total risk | money at risk |
|--|--------|-----------|---------------|
| parent, band 2 floor | $7,000  | 18.75% | $1,321 |
| parent, band 3 floor | $13,000 | 3.45%  | **$448** |

The new ladder is anchored on **H4 per band**, with every other tier holding
the fixed fraction of H4 that bands 1 and 2 have always used (M1 0.0125,
M2 0.025, M5/M15 0.05, M30 0.25, H1 0.5):

| band | equity | M1 | M2 | M5 | M15 | M30 | H1 | **H4** | total | $ at floor |
|------|--------|----|----|----|-----|-----|----|--------|-------|-----------|
| 1 | < 7000      | 0.25   | 0.5   | 1.0  | 1.0  | 5.0  | 10.0 | **20.0** | 37.75% | $1,132 |
| 2 | 7000–13000  | 0.125  | 0.25  | 0.5  | 0.5  | 2.5  | 5.0  | **10.0** | 18.88% | $1,321 |
| 3 | 13000–17000 | 0.0875 | 0.175 | 0.35 | 0.35 | 1.75 | 3.5  | **7.0**  | 13.21% | $1,718 |
| 4 | 17000–20000 | 0.05   | 0.1   | 0.2  | 0.2  | 1.0  | 2.0  | **4.0**  | 7.55%  | $1,284 |
| 5 | 20000+      | 0.025  | 0.05  | 0.1  | 0.1  | 0.5  | 1.0  | **2.0**  | 3.77%  | $755 |

**Bands 1 and 2 are unchanged.**

Three things about this ladder that are easy to misread:

- **13000 is no longer a de-risking point — it is a step UP.** At H4 7.0%
  the band-3 floor risks **$1,718** against band 2's $1,321, so crossing
  13000 *increases* money at risk by about 30% rather than holding it level.
  The de-risking now begins at 17000. That is the intended shape, but it is
  the opposite of what the parent's ladder did at this edge — and the
  opposite of the "restore dollar continuity" reasoning that motivated the
  first pass at these bands. It is the first thing to re-read if drawdown
  past 13k looks wrong.
- **M30 in band 3 rises 8.75x** (0.2 → 1.75), far more than the H4 anchor
  alone implies. The parent's 13000+ band was the **one place** M30 broke
  the ladder's own shape — `0.10 x H4` where every other band uses
  `0.25 x H4`. The new bands restore the shape, so M30 gains more than its
  neighbours here. `InpRiskPctM30_T3 = 0.7` holds it at the old ratio.
- **Band 5 merely matches the parent's old 13000+ risk** (H4 2.0%) rather
  than going below it. So the most conservative band in this file is no
  tighter than what the parent applied from 13000 upward — the whole ladder
  now sits at or above the parent's everywhere past 13000.

As always the input % is the **sizing** basis (2xATR) and the disaster stop
sits at 8xATR, so a full stop-out costs **4x** the figure: band 1 is 151% at
the disaster stop, band 3 is 52.9%, band 5 is 15.1%. OnInit prints every
band with totals.

### The one-position rule now covers both bottom tiers

`HigherLiveLevelBusy()` became `OtherLevelBusy(s, lvl)`, scanning **every**
other level rather than only the five live ones. The parent's narrower
question was right when M2 was the only M30-biased tier: the only hazard was
M2 opening against a live H4-biased trade. With M1 tradable there are two
tiers taking direction from M30, and they can disagree **with each other** —
a running M2 long and an M1 short would have passed the parent's check,
because it never looked at level 0. On a netting account MT5 nets the
opposing orders, shrinking or closing the live trade while `state[]` still
reports it open. `InpScalpNeedsFlatSymbol` governs both tiers.

### What to watch

- **The M1 tier is the whole experiment.** Everything else here is a
  parameter change. Its entries log `(bottom-up, bias M30)` on tier `Exp Buy
  M1` / `Exp Sell M1`, so they are separable — read them on their own before
  judging the build, and read the counter-H4 subset separately again.
- **M1 will usually be superseded, not run alongside.** The scan is
  highest-tier-first, so any tier that aligns on the same minute beats it;
  and `OtherLevelBusy` blocks it while anything else is open. Its real
  contribution is the minutes when *only* M1 aligns.
- **A 1-minute bar is below the noise floor** for an Ichimoku reading that
  nothing else confirms. Treat a good M1 result with more suspicion than a
  good M5 one, and compare against §44 with `InpM1Tier = false` to isolate
  what the tier actually added.
- **Band 3 changed two things at once** — the H4 anchor *and* M30's ratio.
  If band 3 behaves oddly, test `InpRiskPctM30_T3 = 0.7` before concluding
  anything about the anchor.
- **The equity curve now gets riskier before it gets safer.** Because band 3
  steps up, a run from 7k to 17k raises money at risk the whole way and only
  starts tapering at 17000. Any drawdown statistic taken across that range
  is measuring two different risk regimes, so split it at 13000 before
  comparing against §44.
- **The hard stop makes the bottom tiers cheap to be wrong on, and that may
  change what the tiers are for.** At ~1x risk with 1.5:1 reward, M1/M2/M5
  no longer need the win rate they did when a stop-out cost 4x. Judge them on
  expectancy, not on hit rate, and do not carry conclusions from §44 across —
  its M2/M5 trades were sized and stopped on completely different terms.
- **Not yet compiled or backtested.** No MQL5 compiler on the machine it was
  authored on. It was checked statically (brace/paren balance, `PrintFormat`
  arity, no `PositionModify` stripping a TP), the risk ladder was simulated
  against the intended table, the entry scan was traced through nine
  scenarios covering M1-alone, counter-H4, supersede and both flat-symbol
  blocks, and the stop clamp and sizing were simulated across an ATR range to
  confirm the 1x / 4x split. MetaEditor is still the first step before any
  test run.

---

## 46. Bottom-Up Stack EA — the five-band risk ladder, and nothing else

**File:** `experimental-bottomup-stack-5band-risk-ea.mq5`
**Forked from:** `ichimoku-h4-m1-vps-ea.mq5` — the **live VPS build** (magic
`20260858`), which is left untouched
**Magic number:** `20260873` — fresh, so this build never adopts or manages
positions belonging to any other file

### What this build is, and what it deliberately is not

The trading logic is the live build's, **byte for byte**: five tiers (M5,
M15, M30, H1, H4), M1 as the start of every chain and never a tier of its
own, **no M2 anywhere**, the H4 bias with the H1 stand-in, the D1 filter on
the H4 tier, kumo-touch exits, **no profit target**, the 8xATR disaster
stop, and the robustness pack R2–R6. A `diff` against the live build over
non-comment lines shows only the risk inputs, `LevelRiskPct()` and the new
startup read-out.

It **drops** everything explored in sections 43–45 — the M2 scalp tier
(`20260870`), the hard M2/M5 take profits (`20260871`), and the M1 tier,
re-cut targets and tight hard stops (`20260872`). Those files remain as the
record. The only thing carried across is the band edges and percentages.

That also means the **1x / 4x sizing split of §45 is gone**: every tier here
is sized on `2 x ATR` and stopped at `8 x ATR`, so a stop-out costs about
**4x** the stated risk percent on all five tiers, uniformly, exactly as the
live build has always behaved.

### The ladder

| band | equity | M5 | M15 | M30 | H1 | **H4** | total | $ at floor | at 8xATR |
|------|--------|----|-----|-----|----|--------|-------|-----------|----------|
| 1 | < 7000      | 1.0  | 1.0  | 5.0  | 10.0 | **20.0** | 37.00% | $1,110 | 148.0% |
| 2 | 7000–13000  | 0.5  | 0.5  | 2.5  | 5.0  | **10.0** | 18.50% | $1,295 | 74.0%  |
| 3 | 13000–17000 | 0.35 | 0.35 | 1.75 | 3.5  | **7.0**  | 12.95% | $1,684 | 51.8%  |
| 4 | 17000–20000 | 0.2  | 0.2  | 1.0  | 2.0  | **4.0**  | 7.40%  | $1,258 | 29.6%  |
| 5 | 20000+      | 0.1  | 0.1  | 0.5  | 1.0  | **2.0**  | 3.70%  | $740   | 14.8%  |

**Bands 1 and 2 are the live build's, unchanged.** H4 anchors each band and
every other tier holds the fixed fraction of it the ladder has always used
(M5/M15 `0.05`, M30 `0.25`, H1 `0.5`).

### Why the upper bands moved

The live build cuts H4 from 10.0% to 2.0% at 13000 — a 5x drop that
**outran the equity growth which triggered it**:

| | equity | total | money at risk |
|--|--------|-------|---------------|
| live build, band 2 floor | $7,000  | 18.50% | $1,295 |
| live build, band 3 floor | $13,000 | 3.40%  | **$448** |

An account that grew past 13000 traded *smaller in dollars* than it had at
7000. That is the defect these bands fix.

### Three things about the new bands that are easy to misread

- **13000 is no longer a de-risking point — it is a step UP.** The band-3
  floor risks **$1,684** against band 2's $1,295, so crossing 13000
  *increases* money at risk by about 30%. De-risking now begins at 17000.
  Intended, but it is the opposite of what the live build does at this edge,
  and the first thing to re-read if drawdown past 13k looks wrong.
- **M30 in band 3 rises 8.75x** (0.2 → 1.75), far more than the H4 anchor
  alone implies. The live build's 13000+ band was the **one place** M30 broke
  the ladder's own shape — `0.10 x H4` where every other band uses
  `0.25 x H4`. Restoring the shape means M30 gains more here than its
  neighbours. `InpRiskPctM30_T3 = 0.7` holds it at the old ratio.
- **Band 5 merely matches the live build's old 13000+ risk** (H4 2.0%)
  rather than going below it, so this ladder sits at or above the live one
  **everywhere** past 13000.

### What to watch

- **This is the cleanest A/B in the family.** One variable changed against a
  build with known live results, so any difference is the ladder and nothing
  else. Compare it against `20260858` on identical data before drawing a
  conclusion, and split the statistics at 13000 — above that edge the two
  builds are running materially different risk.
- **The equity curve gets riskier before it gets safer.** A run from 7k to
  17k raises money at risk the whole way. Any drawdown figure taken across
  that range is measuring two regimes at once.
- **A band-1 H4 stop-out still costs ~80% of equity** (20% sized, 4x at the
  disaster stop), and band 1 as a whole is 148%. Unchanged from the live
  build, but it is the number that decides whether the top of this ladder is
  survivable, and raising the upper bands does not touch it.
- **Not yet compiled or backtested.** No MQL5 compiler on the machine it was
  authored on. It was checked statically (brace/paren balance, `PrintFormat`
  arity), the resolved ladder was simulated at every band floor against the
  intended anchors and shape ratios, and a non-comment `diff` against the
  live build was used to confirm nothing but the ladder changed. MetaEditor
  is still the first step before any test run.

---

## 47. Bottom-Up Stack EA — scalp capture on the small tiers, and a per-tier report

**File:** `experimental-bottomup-stack-scalp-capture-vps-ea.mq5`
**Forked from:** `ichimoku-h4-m1-vps-ea.mq5` — the **live VPS build** (magic
`20260858`), which is left untouched
**Magic number:** `20260874` — fresh, so it never manages another file's
positions

### The question

"I am not able to pick up small scalps — are they worth trading?" Sections
39 and 42–45 answered it by adding *new, faster tiers* (M1, M2) and *fixed
targets*. None of them has a recorded result. This build asks the question
the other way round: the live build already *enters* plenty of trades on
M5/M15/M30 — how much of the small profit those trades show does the exit
logic hand back, and does banking it pay?

### Why the live build misses small scalps

Reading the live exit stack for an M5/M15/M30 trade:

| Move in profit, then reverses | Live build's exit | Result |
|---|---|---|
| < +1 x ATR | nothing armed — rides back to the **kumo edge** (or the 8 x ATR disaster stop) | full loss, often more than the 2 x ATR the trade was sized on |
| +1 to +2 x ATR | BE armed — stop at **entry + 15 points** | a scratch, ~$0.15 on gold |
| >= +2 x ATR | spike-lock trail at **peak - 1 x ATR** | a win of >= 1 x ATR |

So a small-tier trade only ever keeps money when it runs at least two ATRs.
Everything between +0.1 and +1.9 ATR is a loss or a scratch. That is the
"missed scalp". It is an exit problem, not an entry problem — the trades are
there; the profit is not kept.

Two structural points shape whether scalps are *worth* it:

- **Entries are late by construction.** Price *and* chikou must clear
  tenkan, kijun and the cloud on M1 and on the tier TF, and the chikou must
  clear the high/low of 26 bars ago. By the time that holds, the easy part of
  a short move is usually over. A trend-follower's edge sits in the few long
  runs, not in the win rate, so hard targets on *every* trade (§§39, 44, 45)
  risk cutting off exactly the tail the $100 → $14000 run was made of.
- **Costs scale against small targets.** Spread plus slippage on gold is a
  fixed cost per round trip; against a 1 x ATR(M5) target it is a
  noticeable fraction, against a kumo-edge winner it is noise. A scalp
  layer only makes sense on tiers whose ATR is many times the spread —
  which is why M1/M2 tiers are not the answer and M5 is the floor here.

### What the build does

Everything from the live build is kept — entries, the H4/H1/D1 bias gates,
the cloud gate, sizing, the kumo-touch exit, BE, the chandelier, the
disaster stop, R2–R6. On tiers **M5 .. `InpScalpMaxTier`** (default M30;
H1/H4 already trail from +0.5 x ATR):

1. At **+`InpScalpTP1ATR` x ATR(level TF, at entry)** (default 1.0) the EA
   closes **`InpScalpClosePct` %** (default 50) of the position.
2. The runner's stop moves to **entry + `InpScalpLockATR` x ATR** (0.3) — a
   locked profit, not the 15-point BE.
3. The runner's chandelier is **armed immediately**, `InpScalpTrailATR`
   (1.0) behind the peak, instead of waiting for the +2 x ATR spike.
4. The runner still has the kumo-touch exit, so a trade that becomes a trend
   still rides it.

The target is measured on the **ATR at entry**, stored per trade, so it does
not drift while the trade is open (the live BE arming uses the current ATR).

`InpScalpClosePct = 100` turns the layer into a pure fixed-target scalp —
the whole trade closes at +1 x ATR. `InpScalpCapture = false` restores the
live exits exactly.

**Unsplittable positions:** GOLDm# has a **0.10 minimum lot**, so anything
under 0.20 lots cannot be halved. `InpScalpUnsplit` decides what happens:
`0` (default) leaves the trade on the live exits, `1` applies the lock and
early trail to the whole position, `2` closes it all. `1` was the original
behaviour and it was ruinous in the backtest (see results) — tightening the
whole trade at +1 ATR strangles exactly the runs the system lives on.

**Identity after a partial close:** MT5 **empties the position comment** on
a partial close. The live family identifies a tier by its comment, so the
first backtest orphaned every runner: R2 flagged it as unknown and blocked
all entries until the disaster stop closed it. The build now matches a
position by comment **or** by the position identifier recorded at entry
(`IsLevelPosition`), and after a restart falls back to the opening deal's
comment (`LevelFromIdentity`). Any future build that partially closes must
do the same.

**Restart:** the entry ATR is approximated by the current ATR, and a
position whose volume is below its entry deal volume is treated as already
banked, so a restart never takes the scalp twice.

### The per-tier report

`OnDeinit` prints one line per tier to the journal (the Strategy Tester
journal after a test run):

```
tier | trades | win% | net | PF | avg win | avg loss | MFE<0.5 / 0.5-1 / 1-2 / 2-3 / 3+ ATR | give-backs | scalps banked
```

- **MFE** is the best open profit the trade reached, in ATRs at entry,
  taken from the level-TF bar highs/lows checked once a minute.
- **give-backs** are trades that reached **+1 ATR** and still closed at or
  below zero — the direct count of missed scalps.
- **scalps banked** counts trades on which a partial close happened.
- Only closed trades are counted; anything the tester force-closes at the
  end of the run is missing.

The report is collected whether capture is on or off, so it is also a
diagnostic for the live logic.

### How to run the test

Same symbol, same window, same deposit, every-tick modelling:

1. `InpScalpCapture = false` — the baseline. Read the M5/M15/M30 lines:
   how many trades sit in the 1-2 ATR MFE bucket, and how many give-backs.
   If give-backs are rare, there is nothing to capture and the answer is
   "no, not worth it".
2. `InpScalpCapture = true`, defaults (50% at +1 ATR). Compare **net and PF
   per tier** and the account's max drawdown against run 1.
3. `InpScalpClosePct = 100` — pure scalping on the small tiers. If this
   beats run 2, the small tiers are scalp tiers; if it loses to both, the
   small tiers earn their keep only on the occasional trend and the scalp
   is not worth taking.
4. Optional: `InpScalpTP1ATR` 0.75 / 1.5 to see how sensitive it is.

Judge the H1/H4 lines too: they should be identical across runs 1–3 *only*
if no small-tier trade changes a later entry. They can differ, because a
small tier that closes earlier frees its level for a new entry sooner.

### Status & caveats

- **Compiled clean in MetaEditor** (0 errors, 0 warnings) and backtested on
  2026-09-23 — results below.
- **Do not run it beside the live build** on the same account and symbol:
  the magics differ, so both would trade and exposure would double.
- **A partial close reduces the win the runner can make.** With 50% banked,
  a trade that would have run to a big kumo-edge exit earns roughly half
  of it plus the scalp. Whether the extra scalps outweigh that is exactly
  what run 1 vs run 2 measures.
- **Inherited from the live build, unchanged:** the risk sizing basis is
  2 x ATR while real losers exit at the kumo edge or 8 x ATR, so a losing
  small-tier trade can cost several times its stated percentage; and the
  BE/trail modify tests for shorts assume a stop already exists (the
  disaster stop provides it — with `InpDisasterStopEnabled = false` a short
  would never get its BE or trail).

### Results — GOLDm#, 2026-01-01 → 2026-09-19, $100, 1:1000, 1-minute OHLC

XM `XMGlobal-MT5 5` history, run from the Bottles MT5 install. The baseline
reproduces the user's live report ($100 → ~$14,000), so the setup is sound.

| Run | Settings | Net | PF | Max balance DD |
|---|---|---|---|---|
| **off** | live exits | **$13,681** | **1.40** | **29.1%** |
| half | 50% at +1 ATR, lock 0.3, early trail | $14,030 | 1.39 | 28.9% |
| bare | 50% at +1 ATR, no lock, live trail | $13,899 | 1.42 | 29.1% |
| full M5 | pure scalp on M5 only | $13,927 | 1.36 | 42.1% |
| full M5+M15 | pure scalp on M5 and M15 | $13,461 | 1.32 | 41.3% |
| full M5–M30 | pure scalp on M5, M15, M30 | $13,421 | 1.23 | 49.6% |
| *(first draft)* | 50%, unsplittable = lock+trail, comment bug | $182 | — | 78% |

Baseline per tier (capture off):

| Tier | Trades | Win % | Net | PF | Give-backs |
|---|---|---|---|---|---|
| M5 | 933 | 64.3 | $912 | 1.11 | 47 (5%) |
| M15 | 515 | 70.5 | $1,143 | 1.27 | 20 (4%) |
| M30 | 325 | 76.0 | $5,002 | 1.51 | 8 |
| H1 | 184 | 83.2 | $4,692 | 1.53 | 1 |
| H4 | 37 | 83.8 | $1,933 | 1.61 | 0 |

Reading:

- **The give-back leak is small.** Only ~5% of M5 and ~4% of M15 trades
  reached +1 ATR and closed at or below zero. Most trades that run 1–2 ATR
  are already scratched at break-even + 15 points (counted as small wins —
  that is where the 64% M5 win rate comes from).
- **Partial banking is roughly neutral**: +1.6% to +2.6% net at the same
  drawdown. On one price path that is inside the noise, not an edge.
- **Pure scalping does not pay.** Net is flat to lower, and drawdown rises
  from 29% to 41–50%. Scalping M5 turns that tier's net negative; the
  money moves to other tiers only because equity paths diverge.
- **M5 is the weakest tier** in every run — PF 1.11, 47% of all trades for
  7% of the profit. M30 and H1 carry the account.

### Results — the same window on real ticks (Model 4)

| Run | Net | PF | Max balance DD | Max equity DD |
|---|---|---|---|---|
| **off** (live exits) | **$13,464** | **1.38** | **21.4%** | **43.5%** |
| half (50% at +1 ATR, lock, early trail) | $13,524 | 1.37 | 35.4% | 47.2% |
| full M5 (pure scalp on M5) | $13,470 | 1.34 | 36.8% | 48.6% |

Per tier, capture off: M5 929 trades, PF 1.10, $836, **116 give-backs
(12.5%)**; M15 512, PF 1.25, $1,081, 66 give-backs; M30 325, PF 1.64,
$6,270; H1 183, PF 1.40, $3,717; H4 37, PF 1.52, $1,559.

On real ticks the give-back count doubles (spread and wicks now hit the
break-even + 15-point stop, which OHLC modelling often skipped). The 50%
partial does cut M5 give-backs from 116 to 50, **but net is unchanged and
the balance drawdown rises from 21% to 35%**. Pure M5 scalping turns the
M5 tier negative (PF 0.94, −$817).

### Verdict

**Scalps are not worth trading with this entry signal.** Across both tick
models and six settings, net profit stays within ±3% of the live build's.
Every scalping variant pays for that with more drawdown, and the pure
scalp loses money on the tier it is applied to. The live exits stay as
they are. The partial-close machinery and the per-tier report stay in this
file for future tests. The per-tier numbers point at a different question
worth testing next: **M5 is 47% of all trades for ~6% of the profit at PF
~1.10**, so removing or restricting the M5 tier may cut drawdown and costs
at little cost to profit.

---

## 48. Bottom-Up Stack EA — the M5 tier tightened

**File:** `experimental-bottomup-stack-m5-tight-vps-ea.mq5`
**Forked from:** `experimental-bottomup-stack-scalp-capture-vps-ea.mq5`
(§47), with scalp capture **off** by default, which makes it the live VPS
build (`20260858`, untouched) plus the per-tier report
**Magic number:** `20260875`

### Why

In §47 the M5 tier was 47% of all trades but made only ~6% of the profit
(profit factor 1.10 on real ticks). This build adds switchable filters that
apply **only to the M5 tier** (`M5TierOK()`, called in the entry loop for
`l == 0`). M15 and above are untouched. With every filter off it
reproduces the live build to the cent ($13,463.81).

| Input | What it requires of an M5 entry |
|---|---|
| `InpM5Enabled = false` | no M5 trades at all (the control) |
| `InpM5NeedH4` | the H4 bias itself, not the H1 stand-in |
| `InpM5NeedH1` | H1 aligned with the trade as well |
| `InpM5CloudFull` | the M5 cloud twisted the trade's way now **and** at the far end (the M1 rule) |
| `InpM5MaxCloudATR` | entry no further than X x ATR(M5) from the M5 cloud edge |
| `InpM5MaxSpread` | a tighter spread cap, in points |

### Results — GOLDm#, $100, 1:1000, real ticks, one filter at a time

**2026-01-01 → 2026-09-19 (the window the M5 problem was found in):**

| Run | Net | PF | Balance DD | Equity DD | M5 trades | M5 PF | M5 net |
|---|---|---|---|---|---|---|---|
| live (all off) | $13,464 | 1.38 | 21.4% | 43.5% | 929 | 1.10 | $836 |
| no M5 | $13,295 | **1.52** | 23.0% | 44.1% | 0 | — | — |
| **NeedH4** | $13,349 | 1.42 | 28.9% | 31.8% | 605 | **1.29** | **$1,319** |
| NeedH1 | $13,320 | 1.41 | 29.1% | 32.2% | 796 | 1.16 | $1,146 |
| CloudFull | $13,413 | 1.41 | 28.9% | 31.9% | 725 | 1.13 | $864 |
| cloud dist ≤ 2 ATR | $13,430 | 1.47 | 30.4% | 41.9% | 188 | 0.80 | −$377 |
| cloud dist ≤ 3 ATR | $9,179 | 1.22 | 55.0% | 59.4% | 344 | 0.89 | −$496 |
| cloud dist ≤ 4 ATR | $14,050 | 1.47 | 27.6% | 30.7% | 505 | 1.11 | $474 |
| spread ≤ 35 | $13,280 | 1.38 | 24.2% | 29.3% | 922 | 1.03 | $250 |

**2025-01-01 → 2026-01-01 (out of sample):**

| Run | Net | PF | Equity DD | M5 trades | M5 PF | M5 net |
|---|---|---|---|---|---|---|
| live (all off) | $14,320 | 1.88 | 29.2% | 1,547 | 1.12 | $592 |
| no M5 | $14,646 | **2.03** | **24.9%** | 0 | — | — |
| **NeedH4** | $13,941 | 1.90 | 29.8% | 1,076 | **1.22** | **$773** |
| NeedH1 | $14,785 | 1.89 | 29.5% | 1,366 | 1.07 | $338 |
| CloudFull | $13,813 | 1.85 | 30.8% | 1,167 | 1.09 | $363 |

### Reading

- **Account totals are noisy.** With 20% H4 risk and compounding from $100,
  one different early trade reshapes the whole equity path. The 3 ATR
  distance cap losing a third of the profit while 2 and 4 ATR do not is
  that noise, not a real effect. Differences of ±5% in net mean nothing.
  The M5 tier's own profit factor is the steadier measure.
- **`InpM5NeedH4` is the only filter that improved M5 in both years**
  (PF 1.10 → 1.29 and 1.12 → 1.22, about 30–35% fewer M5 trades). The trades
  it drops are the M5 entries taken on the H1 stand-in while H4 is flat,
  and they were the weak ones. It is the default here.
- **The distance cap is backwards.** M5 entries close to the cloud are
  the *worse* ones (PF 0.80 at ≤ 2 ATR). The far-from-cloud entries are
  momentum and they carry the tier.
- **Removing M5 entirely is the strongest account-level result**: profit
  factor up in both years (1.38 → 1.52, 1.88 → 2.03), net within noise
  (−1% and +2%), and 40–47% fewer trades, so less spread and commission
  paid. Tightening M5 improves the tier, but at the account level it does
  no better than dropping it.
- The spread cap (35 points) cut M5's profit factor. Gold's typical spread
  sits near that level, so it mostly removed good trades.

### Status & caveats

- Compiled clean (0 errors, 0 warnings); backtested on 2026-09-23 as above.
- One symbol (GOLDm#), one broker feed, two windows.
- **PROMOTED 2026-09-23 (user decision): the M5 tier is dropped from both
  main builds** (`InpM5Tier = false`), not tightened. The new VPS file was
  backtested on the 2026 window and reproduced the "no M5" run exactly
  ($13,294.55, PF 1.52, zero M5 entries). The pre-change builds are
  archived as the `-archived20260923` pair.
- Do not run it beside the live build on the same account and symbol.


---

## 49. M1+M2 kihon / PO3 range scalper

**File:** `experimental-m1m2-kihon-po3-scalper-ea.mq5`
**Magic number:** `20260876`

A standalone scalper, not a fork of the live build. It uses the **top-down**
model: one trade, only when every timeframe agrees. The new parts are *when*
it may trade (kihon suchi times of the day) and *where* it exits (a PO3
number). Three gates, cheapest first:

| | Gate | Question |
|---|---|---|
| 1 | **TIME** | Is the day's H1, M30 or M15 count on a kihon number? |
| 2 | **STRUCTURE** | Are M1 and M2 clear on price and chikou, and do M5–H4 agree? |
| 3 | **PRICE** | Is there room inside the PO3 range to the next level? |

### Gate 1 — kihon times on H1, M30 and M15

Each timeframe is counted from the **day open** (the D1 bar, so the broker's
own rollover). The counting is §38's, ported from `po3-levels.mq5`: inclusive,
so the candle at the open is candle 1, with `Bars()` over `[day open, now]`.
The gate is open while **any** enabled timeframe's count is within
`InpKihonTol` of a kihon number **that a trading day can reach on that
timeframe**:

| TF | candles a day | numbers used |
|---|---|---|
| H1 | ~24 | 9, 17 |
| M30 | ~48 | 9, 17, 26, 33, 42 |
| M15 | ~96 | 9, 17, 26, 33, 42, 51, 65, 76 |

The reach cap is the general form of §38's "26 trap". Without it, a tolerance
would let the gate open near the end of the day on a number the count never
gets to.

With the default `InpKihonTol = 0` the gate is open for the candle carrying
the number and nothing else: one hour for each H1 number, 30 minutes for
each M30 one, 15 minutes for each M15 one. Some of these overlap, because
M30 candle 17 and H1 candle 9 both cover 08:00–08:30. On a midnight-rollover
broker the open windows are roughly:

- H1: 08:00–09:00 and 16:00–17:00
- M30: 04:00, 08:00, 12:30, 16:00 and 20:30, 30 minutes each
- M15: 02:00, 04:00, 06:15, 08:00, 10:15, 12:30, 16:00 and 18:45, 15 minutes each

After removing overlaps that is about 4½ hours a day. Each toggle (`InpKihonH1/M30/M15`) removes one
timeframe's windows, so their effects can be tested separately. An unknown
count (history still loading) does not open the gate.

The gate applies to **entries only**. A running trade has its SL and TP on the
order, and the broker closes it at any hour.

### Gate 2 — M1 + M2 trigger, top-down confirmation

The family's `CheckAlign`, unchanged, on M1, M2, M5, M15, M30, H1 and H4, all in
the same direction. The last closed close must be beyond tenkan, kijun and the
whole cloud, and the chikou must be beyond that bar's high or low and beyond
tenkan, kijun and the cloud as they stood there. M1 is checked first because it
is the cheapest to fail. `InpAlignTop` sets the highest timeframe that has to
agree. `H4` is the full M1-to-H4 alignment, and `M2` leaves only the scalp
trigger.

Unlike §39, **M2 is required**. The build is defined by its M1+M2 trigger, so a
broker without an M2 feed fails init with a journal line instead of quietly
trading a different chain.

### Gate 3 — the PO3 range

The range is the cell between two adjacent multiples of `3^InpPO3Power`, using
the indicator's scale (`InpPO3Scale`, 1 = whole numbers). At the default power
2 that is a **9-dollar cell on gold**.

- **Target:** the next level strictly beyond the fill price in the trade's
  direction, so a price sitting on a level targets the next one. The TP is
  placed `InpTPBufferPips` (5) **in front of** it.
- **Stop:** the level one step behind, plus `InpSLBufferPips` (10) beyond it.
  It is widened to `InpMinSLPips` (20) when price is sitting on that level.
- **Veto:** skipped when the reward is under `InpMinTPPips` (20; raised to 30 below) or reward:risk
  under `InpMinRR` (1.0). A skip is journalled with the reason and the kihon
  reading.

At `InpMinRR = 1.0` this effectively means longs from the lower part of the
cell and shorts from the upper part: the trade must have more room ahead than
behind. The journal labels the target level with its real power, the same
number the indicator shows (e.g. `4374.00 (2187)`).

### Position and risk

- **One position per symbol.** Both levels ride on the order, and the EA never
  trails, never moves the stop and has no break-even. Its only upkeep is
  re-attaching a missing stop. After a restart, that stop is the position's own
  or, if it is already gone, the range stop rebuilt from the open price.
- **Sizing:** `InpRiskPct` (1%) of equity against **this trade's** stop
  distance. That distance varies with where price sits in the cell, so the
  money lost on a stop-out is the same either way.

### What it deliberately does not have

No robustness pack, no bias ladder, no cloud-bias gate, no kumo-touch exit, no
trail and no margin cap. There is also no limit on trades per kihon window: after a
TP or SL the EA can re-enter on the next minute if all three gates still pass.

### Status & caveats

- **Compiled clean in MetaEditor** (0 errors, 0 warnings) and backtested
  on 2026-09-23 with the defaults. The result is below: **it loses**.
- **The defaults are a starting point, not a result.** The power (cell size),
  both buffers, the minimum stop and the minimum rr all interact. A 9-dollar
  cell with a 1.0 rr floor admits longs only in the bottom ~3.75 dollars
  of the cell: a target of $4.75–$8.50 against a stop of $2–$4.75. Try power 3 (27) before concluding the idea does not work.
- **Full H4-to-M1 agreement plus about 4½ hours a day plus a room veto is
  very selective.** Expect few trades. `InpAlignTop` and `InpKihonTol` are the
  first two settings to loosen if a test produces too few trades to read.
- **Minimum lot versus a small account.** On GOLDm# the 0.10 minimum lot
  against a 10-dollar stop risks ~$100. A $100 test account cannot size down to
  1%, so test on a larger deposit to see the idea's real effect.
- Do not run it beside the live build on the same account and symbol.

### Results — GOLDm#, 2026-01-01 → 2026-09-19, $10,000, 1:1000, defaults

| Model | Net | PF | Trades | Won | Avg win / loss | Max balance DD |
|---|---|---|---|---|---|---|
| 1-minute OHLC | −$1,760 | 0.90 | 252 | 26.6% | $231 / −$93 | 40.4% |
| real ticks | **−$2,882** | **0.84** | 253 | 26.1% | $222 / −$94 | 45.1% |

A $10,000 deposit was used so the 1% sizing is not overridden by the
minimum lot. 588 aligned signals at kihon times were skipped by the room
check (349 no room, 239 rr too low). The entries split fairly evenly across
the three clocks: 122 on an H1 number, 149 on M30, 106 on M15.

Breaking down the 1-minute OHLC run's trades by entry rr shows where it
loses:

| entry rr | trades | won |
|---|---|---|
| < 1.5 | 44 | 50% |
| 1.5 – 2.5 | 58 | 22% |
| ≥ 2.5 | 150 | 21% |

**Most trades (60%) are rr ≥ 2.5, and those lose.** A high rr here means
price was sitting on the level behind it, so the stop fell back to the
2-dollar minimum (`InpMinSLPips` 20), which gold's normal M1 noise takes out.
The trades that had to hold a stop beyond a real distance won half the time.
The H1/M30/M15 trigger made no difference (25–28% wins on each), so the time
gate is not what is failing.

Next runs to make, in order:
`InpMinSLPips` 40–60 (or a cap on rr), `InpPO3Power = 3`,
`InpKihonGateEnabled = false` (to measure the time gate), and
`InpAlignTop = M2`. They were not run because the tester needs the local
MT5 window to be closed.

### Revision — the whole kihon candle, confluence, and breakouts

User direction after the first run: a kihon time is the **whole candle**, so a
trade can come at any minute of the H1 hour (or the M30/M15 candle). The
strongest times are when **all three** timeframes are on a number together,
and the EA should **watch for breakouts** during those times.

- **The whole candle was already the rule.** At `InpKihonTol = 0` the gate
  stays open for the full candle. The first run's entries were spread across
  every minute of the hour, not bunched at the open. The header now says so
  explicitly.
- **Confluence — `InpKihonMinTFs` (1–3, default 1).** This is how many of H1,
  M30 and M15 must be on a number at the same moment. On a midnight-rollover
  broker, **all three** coincide at 08:00–08:15 (H1 9, M30 17, M15 33) and
  16:00–16:15 (H1 17, M30 33, M15 65). The journal tags each reading with its
  count, e.g. `H1:9* M30:17* M15:33* x3`. In the first run, the 34 trades taken
  at x3 won **41%**, against 25% at x1 and 23% at x2. With wins averaging 2.4×
  the loss, 41% is profitable. The sample is small, so this needs the
  dedicated runs below.
- **Breakout entry — `InpBreakoutOnly` (default on).** On every closed M1 bar,
  whether or not a window is open and whether or not a trade is running, the
  EA records the bar on which the **M1+M2 pair turns aligned** in a
  direction: from not aligned, or from the opposite side. An entry then needs:
  - that breakout to fall **inside the current kihon window**;
  - the full chain to M5–H4 aligned the same way;
  - the PO3 room check to pass.

  Each breakout is traded **once**. The window being judged starts at the
  **latest** of the hit timeframes' window starts, i.e. when the current
  confluence began. So at x3 the breakout must come inside the 15 minutes
  where all three overlap. A breakout skipped for lack of PO3 room stays
  available for the rest of the window, in case price pulls back into room.
  `InpBreakoutOnly = false` restores the first run's behaviour: any minute the
  chain is aligned.

Compiled clean in MetaEditor (0 errors, 0 warnings). Runs to make:
breakout at x1 / x2 / x3, and state entry at x3. These are not yet backtested,
because the local MT5 window was open.

### Revision — Ichimoku structure targets (gate 2b)

User direction: the multi-timeframe read should look beyond the question
"is it broken out". It should also see where price is **moving toward**. The
example: M1 and M5 have broken out, but M15 is still inside its cloud and
heading for its SSB. The SSB becomes the target, because price will bounce
there. That only holds if M15's price and chikou are free to reach it, and M30,
H1 and H4 are free within that range too.

How it is built (`InpStructTarget`, default on):

- **The chain is walked, not just passed or failed.** `ChainWalk` reports how
  far the M1-upward alignment holds. If it reaches `InpAlignTop` (H4), the
  trade is the fully aligned case and keeps the **PO3 target**, as before.
- **Partial chain.** If it holds at least to `InpStructMinTop` (default **M5**,
  so M1+M2+M5 have broken out) but stops below the top, the first timeframe
  that fails becomes the **target timeframe**. It qualifies when:
  - its price (the fill price) is **inside its cloud**;
  - the cloud edge **ahead** is its **SSB**: for a long, SSB above SSA; for a
    short, below it.

  The TP is that SSB, less `InpTPBufferPips`.
- **"Free" means no Ichimoku structure is in the way:**
  - *Price:* on the target timeframe and every timeframe above it up to
    `InpAlignTop`, none of tenkan, kijun, SSA or SSB (last closed bar) lies
    strictly between entry and the SSB.
  - *Chikou* (`InpStructChikou`, default on): on those same timeframes, the
    chikou (the last close, plotted Kijun bars back) must be able to move the
    same distance. Its path is the column at its position plus the next
    `InpChikouPathBars − 1` columns toward the present (3 in total by
    default). The candle high (long) or low (short), and the four lines as
    they stood in those columns, must not lie on that path.
- **Stop and room are unchanged.** The stop is still the PO3 range stop
  (beyond the level behind, minimum 20 pips), and `InpMinTPPips` / `InpMinRR`
  still veto. The journal names the target: `M15 SSB 4488.20` or
  `4491.00 (9)`.
- **Breakout and kihon rules still apply.** The M1+M2 breakout must fall inside
  the kihon window, and the confluence minimum holds.
- Structure vetoes ("M30 kijun in the way", "price not in its cloud") are
  routine, so they are not journalled. Only a chain that reached a target and
  failed on room is logged.

Design choices that were not specified and are open to change:
- only the **SSB** counts as a target, not SSA or a kijun;
- only the **first** failing timeframe is read;
- the stop stays the PO3 stop rather than an Ichimoku level behind.

Compiled clean in MetaEditor (0 errors, 0 warnings). Not yet backtested.

### Revision — an SSB on a PO3 number targets the PO3 number

User direction: when the non-aligned timeframe's line **coincides with a PO3
number**, the setup is higher probability, and the **PO3 level** is the
target.

- The nearest multiple of the range step (`3^InpPO3Power`) to the SSB counts
  as coinciding when it is within **`InpStructPO3TolPips` (default 10 pips,
  one dollar on gold)** of the SSB and still ahead of entry. The target is then
  the **PO3 number**, not the SSB. The TP sits `InpTPBufferPips` in front of it
  as usual, and the journal reads e.g. `M15 SSB 4490.40 = PO3 4491.00 (9)`.
- The free-road check runs to **whichever comes first** of the SSB and the PO3
  number. If the PO3 number is just past the SSB, the SSB itself is not
  counted as an obstacle. If it is just short, that is where the road ends.
- **`InpStructNeedPO3` (default off)** trades a structure target *only* when its
  SSB sits on a PO3 number. Off, an SSB with no PO3 number near it still
  targets the SSB, so the two can be compared in a backtest.
- On the default 9-dollar grid, a one-dollar tolerance catches about 2 in 9
  SSBs by chance alone (any price is within $1 of a level 2/9 of the time).
  A real edge would show up as those trades beating that base rate. The
  tolerance and the grid are the settings to tune.

Compiled clean in MetaEditor (0 errors, 0 warnings). Not yet backtested.

### Revision — any of the four lines is a target

User direction: the target line can be **SSA, kijun, tenkan or SSB**, not only
the SSB.

- The target timeframe's target is now its **nearest line ahead of price**,
  whichever of tenkan, kijun, SSA and SSB price would reach first. The two
  SSB-only preconditions are gone: price no longer has to be inside the
  cloud, and the SSB no longer has to be the edge ahead. If the timeframe has
  no line ahead of price, there is no structure target.
- Because the target is the nearest line, none of the target timeframe's
  *own* lines can be on the road. Its chikou still has to be free, and the
  timeframes above it still have to be free on price and chikou.
- The PO3 rule from the previous revision applies to whichever line is the
  target: within `InpStructPO3TolPips` of a PO3 number, the PO3 number is the
  target. The journal reads e.g. `M15 kijun 4490.40 = PO3 4491.00 (9)`.
- The earlier sections' mentions of "the SSB" as the only target describe the
  first cut. This revision replaces them.

Compiled clean in MetaEditor (0 errors, 0 warnings). Not yet backtested.


### Revision — 30 pips minimum to the target

User direction: a move of **less than 30 pips is not worth trading** (30 pips
= 4000 → 4003 on gold). `InpMinTPPips` now defaults to **30** (was 20). It is
measured from the fill price to the **TP itself**, i.e. after the 5-pip
buffer in front of the level, so it is what the trade actually earns. The
target level therefore has to be about 35 pips away. The rule applies to every
target: PO3 levels, Ichimoku lines, and PO3 numbers on a line.

Compiled clean in MetaEditor (0 errors, 0 warnings). Not yet backtested.

### Results — the revised build (whole candle, confluence, breakouts, line targets, 30-pip minimum)

GOLDm#, $10,000, 1:1000, **real ticks**, default settings unless the variant
says otherwise. 2026 = 2026-01-01 → 2026-09-19; 2025 = the full year, out of
sample.

| Run | Window | Net | PF | Trades | Won | Max balance DD |
|---|---|---|---|---|---|---|
| **defaults** (breakout, x1, line targets on, chikou on) | 2026 | −$2,668 | 0.78 | 192 | 26.6% | 40.3% |
| **defaults** | **2025** | **+$4,846** | **1.23** | 235 | 35.7% | 13.6% |
| line targets off | 2026 | −$2,056 | 0.78 | 130 | 25.4% | 35.5% |
| line targets, chikou check off | 2026 | −$4,222 | 0.76 | 283 | 23.3% | 54.3% |
| line targets on PO3 numbers only | 2026 | −$2,138 | 0.79 | 145 | 26.2% | 35.5% |
| breakout, x3 confluence | 2026 | −$68 | 0.96 | 23 | 30.4% | 9.8% |
| **no breakout rule, x3** | 2026 | **+$661** | **1.18** | 51 | 35.3% | 11.8% |
| no breakout rule, x3 | **2025** | −$1,026 | 0.79 | 71 | 28.2% | 14.0% |
| no breakout rule, x3, min stop 40 | 2026 | +$462 | 1.16 | 46 | 41.3% | 7.3% |

Per-trade breakdown of the defaults. R is +rr for a win and −1 for a loss:

| Split | 2026 | 2025 |
|---|---|---|
| PO3 target (full chain) | 130 trades, 25% won, −15.2 R | 189, 33%, **+26.6 R** |
| Ichimoku line target | 47, 28%, −5.5 R | 32, 47%, +9.2 R |
| line on a PO3 number | 15, 33%, −1.0 R | 14, 43%, +9.6 R |
| stop ≤ 25 pips | 80, 21%, −4.2 R | 113, 25%, +13.0 R |
| stop 26–45 pips | 83, 24%, −25.1 R | 93, 46%, +31.9 R |
| stop > 45 pips | 29, 48%, +7.7 R | 29, 45%, +0.5 R |
| confluence x1 / x2 / x3 | −14.1 / −7.6 / +0.0 R | +27.7 / +17.0 / +0.8 R |

### Reading

- **Nothing holds across both years.** The defaults lose 27% in 2026 and
  gain 48% in 2025. The best 2026 variant (x3 confluence without the breakout
  rule, PF 1.18) loses in 2025 (PF 0.79). The earlier "x3 wins 41%" finding
  was a 2026 effect.
- **Line targets beat full-chain PO3 targets in both years**, per trade:
  - 2026: −0.10 R vs −0.12 R;
  - 2025: +0.41 R vs +0.14 R.

  This is the only split that points the same way twice. The sample is
  46–62 line trades per year, so treat it as a lead, not a result.
- **A line sitting on a PO3 number is not clearly better** than a plain line:
  33% vs 28% won in 2026, 43% vs 47% in 2025, on about 15 trades each.
- **The chikou check on the free road helps.** Turning it off added 91 trades
  and $1,550 of loss in 2026.
- **The breakout rule cut trades without improving them** in 2026 (x3: 23
  trades, PF 0.96, vs 51 trades, PF 1.18 without it). It was not tested
  separately in 2025.
- **2026 losses are mostly shorts.** In 2026 the defaults' shorts won 23% and
  longs 30%. In 2025 shorts won 47% and longs 33%. That reads as the year's
  trend, not a rule.
- One symbol, one broker feed, two windows. The year-to-year swing is larger
  than any filter's effect, so no default was changed on this evidence.

### Revision — week kihon clocks, and the VPS build's exits

User direction: add a kihon suchi time **for the week**, counting **H4, H1
and M30** from the first candle that opens the week. Let the **SL be the
cloud** and let the **TP run**, both as in the VPS build.

**Week clocks.** Three more clocks count from the week open (the W1 bar), so
candle 1 is the first candle that opens the week. They are capped at what five
trading days reach:

| Clock | Candles a week | Kihon numbers used |
|---|---|---|
| H4 | ~30 | 9, 17, 26 |
| H1 | ~120 | 9 … 76 |
| M30 | ~240 | 9 … 226 |

They sit alongside the day clocks (`InpKihonWeekH4/H1/M30`). The gate is open
when `InpKihonMinTFs` of the six clocks are on a number (now 1–6; default 1,
so any one opens it). The journal tags week readings with a `w`, e.g.
`wH4:17*`.

**VPS exits (`InpExitMode = EXIT_VPS`, the new default).** These are ported
from the live build's `InCloudTouch` and `ManageLevelProtection`.

- **Stop = the cloud.** The trade closes when the bid (long) or ask (short)
  touches the **exit timeframe's cloud**. By the VPS rule, the exit timeframe
  is the **highest timeframe aligned at entry**: H4 for a full-chain trade,
  M5–H1 for a partial-chain (line-target) trade. `InpExitCloudTF` can fix it
  instead. The exit timeframe is written into the position comment
  (`PO3 Scalp Buy H4`) so a restart finds it.
- **No take profit.** Profit is protected the way the live build does it:
  - break-even (entry + 15 points) at +1 ATR;
  - then a chandelier 1 ATR behind the peak from +2 ATR;
  - on an H1/H4 exit timeframe, both arm at +0.5 ATR;
  - an **8 × ATR disaster stop** on the order, re-attached if it goes
    missing.
- **Sizing.** The risk is 1% of equity against the **distance to the exit
  cloud at entry**, floored at `InpMinSLPips`. An entry already touching that
  cloud is skipped.
- **Targets become a room filter.** The PO3/line target is still worked out,
  but only vetoes entries with less than `InpMinTPPips` (30) of room. No TP is
  attached and the reward:risk check is not used.
- `InpExitMode = EXIT_TARGET` restores the fixed TP and PO3 stop.

### Results — week clocks + VPS exits

GOLDm#, $10,000, 1:1000, real ticks, defaults.

| Exits | Window | Net | PF | Trades | Won | Avg win / loss | Max balance DD |
|---|---|---|---|---|---|---|---|
| **VPS** | 2026 | **+$70** | 1.03 | 120 | 60.8% | $31 / −$47 | 4.6% |
| **VPS** | 2025 | **+$910** | 1.39 | 143 | 72.7% | $31 / −$59 | 4.6% |
| target | 2026 | −$2,846 | 0.82 | 259 | 25.9% | $191 / −$81 | 46.6% |
| target | 2025 | +$7,761 | 1.22 | 350 | 34.3% | $357 / −$153 | 20.0% |

VPS-mode trades, by exit timeframe and by how they closed:

| Split | 2026 | 2025 |
|---|---|---|
| H4 exit (full chain) | 59 trades, 54% won, **+$302** | 76, 76%, **+$1,076** |
| H1 exit | 16, 75%, +$42 | 28, 71%, +$269 |
| M30 exit | 7, 57%, +$63 | 10, 60%, −$227 |
| M15 exit | 12, 58%, +$73 | 8, 75%, −$9 |
| **M5 exit** | 26, 54%, **−$410** | 21, 57%, **−$200** |
| closed by the cloud touch | 27, 0% won, −$2,212 | 25, 0%, −$2,294 |
| closed by BE / trail / disaster | 93, 74%, +$2,283 | 118, 86%, +$3,204 |
| longs / shorts | +$217 / −$146 | +$1,561 / −$652 |

### Reading

- **The VPS exits make money in both years, the first version of this
  scalper to do so,** and with a tenth of the drawdown (4.6% vs 20–47%). The
  profit is small: +0.7% and +9% on the year. Most trades are closed early by
  the BE or trail stop for about $31, and every cloud-touch exit is a full
  loss of about $85.
- **The stop is wide.** The median distance to the exit cloud at entry was
  848 pips in 2026 and 417 in 2025 (the H4 cloud on most trades), so 1% risk
  buys small lots. That is why the dollar figures are small next to target
  mode.
- **Consistent in both years:**
  - full-chain trades exiting on the **H4 cloud are the profit**;
  - trades exiting on the **M5 cloud lose**;
  - shorts lose;
  - partial-chain (line-target) trades are net negative (−$232 and −$166),
    which reverses the small lead line targets showed in target mode.
- **Target mode still swings** from −28% to +78% between the years. With the
  week clocks added it trades more (259 and 350 trades) but reads the same as
  before.
- Next to try: drop the M5-exit trades (`InpStructMinTop = M15`), or fix the
  exit cloud at H1 (`InpExitCloudTF`) to shorten the stop on full-chain
  trades.

Compiled clean in MetaEditor (0 errors, 0 warnings).

### Revision — a pullback entry mode, and a 2024 test

User direction, after the recommendation to trade the lower timeframes *with*
the higher trend rather than fade it: build a **pullback mode** and backtest
**2024–2026**.

**`InpEntryMode`:** `ENTRY_BREAKOUT` (default, everything above), `ENTRY_PULLBACK`,
or `ENTRY_BOTH` (pullback checked first; still one position per symbol).
A pullback entry needs:

1. **Trend:** H4 aligned (`CheckAlign`, price and chikou), and H1 aligned the
   same way (`InpPBNeedH1`, default on).
2. **A real counter move:** M1+M2 aligned *against* the trend at some bar
   within the last `InpPBLookbackMins` (30) minutes.
3. **A level:** the extreme of the M1 bars in that window (the low for a
   long) within `InpPBLevelTolPips` (15) of a PO3 number (the 3^power grid),
   or of a tenkan, kijun, SSA or SSB on M5, M15, M30 or H1.
4. **The turn:** M1+M2 turning back *with* the trend inside a kihon window.
   This is the same breakout tracking the breakout entry uses, once per turn.

Exits:
- a hard stop `InpSLBufferPips` beyond the pullback extreme (at least
  `InpMinSLPips`, skipped beyond `InpPBMaxSLPips` = 150);
- no take profit, and no cloud-touch exit, since the dip usually sits in a
  lower cloud;
- the VPS build's BE and chandelier, on `InpPBManageTF`'s ATR (M15).

The position comment carries ` PB ` so a restart manages it the same way.

### Results — 2024–2026, VPS exits

GOLDm#, $10,000, 1:1000, real ticks. 2026 runs to 09-19.

| Entry | 2024 | 2025 | 2026 |
|---|---|---|---|
| **breakout** (default) | **+$680**, PF 1.38, 115 trades, 5.0% DD | **+$910**, PF 1.39, 143, 4.6% | **+$70**, PF 1.03, 120, 4.6% |
| pullback | −$14, PF 0.98, 26 trades | −$28, PF 0.97, 23 | −$588, PF 0.00, 8 |
| both | +$535, PF 1.24, 120 | +$567, PF 1.20, 150 | −$132, PF 0.95, 122 |
| pullback, managed on H1 ATR | +$116, PF 1.11, 26 | −$334, PF 0.59, 23 | −$588, PF 0.00, 8 |

### Reading

- **The breakout entry with VPS exits is profitable in all three years.** 2024
  is a year it was never tuned on. PF runs 1.38 / 1.39 / 1.03 at about 5%
  drawdown. It is still small money (+7%, +9%, +0.7% a year at 1% risk), but
  it is the first setting of this scalper to hold up across three windows.
- **The pullback mode has no edge.** It loses slightly in every year on very
  few trades. Its losers take the full swing stop (about −$80 to −$100),
  while BE and the trail close its winners early (about $55–61, and around $0
  in 2026). Managing on H1's wider ATR does not fix it. Adding it to the
  breakout lowers the result in all three years.
- The levels the dips reached were mostly PO3 numbers (29 of 57 trades),
  then SSA and tenkan.
- **The default stays `ENTRY_BREAKOUT`.** The pullback mode is kept, off, for
  further work. The next lever would be its exit (a target at the prior swing
  extreme instead of BE/trail), not more entry filters.

Compiled clean in MetaEditor (0 errors, 0 warnings).

### Revision — pullback with a swing-target TP

User direction: try the pullback with a **swing target** as the TP.

**`InpPBExit`** (default now `PB_EXIT_SWING`; `PB_EXIT_TRAIL` is the BE +
chandelier version above):
- The TP is the extreme the dip came **from**: the highest high (long) or
  lowest low (short) of the last `InpPBSwingBars` (60) M1 bars, placed
  `InpTPBufferPips` in front of it.
- The swing stop beyond the dip stays. There is no BE and no trail; both
  levels ride on the order.
- Skipped when the target is under `InpMinTPPips` (30), or under
  `InpPBMinRR` × the stop (0 = off).

GOLDm#, $10,000, real ticks, `InpEntryMode = ENTRY_PULLBACK`:

| Variant | 2024 | 2025 | 2026 |
|---|---|---|---|
| swing TP, 60-bar swing, 30-min lookback | −$234, PF 0.25, 4 trades | +$90, PF 1.44, 9 | −$310, PF 0.22, 8 |
| … plus rr ≥ 1.0 | +$3, 2 trades | +$104, 1 | −$299, 3 |
| swing TP, 240-bar swing, 60-min lookback | −$127, PF 0.89, 34 | −$888, PF 0.49, 41 | −$379, PF 0.45, 11 |

### Reading

- **The swing target does not rescue the pullback.** At the default windows it
  finds only 1–9 trades a year. With the windows widened it loses in every year
  (PF 0.45–0.89).
- **The geometry is against it.** The stop sits beyond the dip, typically
  30–130 pips away. The swing the dip came from is usually close, so the target
  is often under 30 pips and the trade is skipped. The trades that are left
  win about $38–44 against losses of about $100. A 56–68% win rate cannot
  carry that.
- Across trail exits and swing targets, the pullback entry has now lost in
  every configuration tried over 2024–2026. **Conclusion: no edge in this
  form. `InpEntryMode` stays `ENTRY_BREAKOUT`.** The code is kept, off, in
  case a different pullback definition is wanted later, e.g. a tighter stop
  at the level itself rather than at the dip's extreme.

Compiled clean in MetaEditor (0 errors, 0 warnings).

---

## 50. The live logic, tier by tier, over 2024–2026 at $100

**File:** `experimental-bottomup-stack-m5-tight-vps-ea.mq5` (the §48 build)
**Magic number:** `20260875`

User direction: stop adding tiers. Simulate the live build with only its
profitable tiers, H4 first, over **2024, 2025 and 2026**, with the VPS
build's risk regime and a **$100** start.

**Method.** The §48 build with `InpM5Enabled = false` reproduces the live VPS
build to the cent: the 2026 run below returns $13,294.55, the §48 figure.
This build gained four tier switches, `InpTierM15/M30/H1/H4` (all on by
default, so behaviour is unchanged). A tier switched off never opens, and
the scan moves on to the next tier down. The risk regime is the live one:
- tier 1 (< $7k): M15 1% / M30 5% / H1 10% / H4 20%;
- then halved to 13k;
- then 0.1 / 0.2 / 1 / 2% above 13k.

The live VPS file was not touched.

GOLDm#, 1:1000, **real ticks**, each year run separately. 2026 runs to 09-19.
The 2024 runs load 2023 history for warm-up (27M ticks), so the data is
complete.

### $100 start

| Tiers | 2024 | 2025 | 2026 |
|---|---|---|---|
| **live** (M15+M30+H1+H4) | **ruin**: −$100.72, stopped out 2024-08-02 | +$14,646, PF 2.03 | +$13,295, PF 1.52 |
| H4+H1+M30 | **ruin**: −$99.99 | +$14,188, PF 2.24 | +$13,378, PF 1.61 |
| H4+H1 | **ruin**: −$99.93 | +$13,176, PF 3.44 | +$226, PF 1.03 (92% DD) |
| H4 only | −$44, PF 0.89, 87% DD | +$303, PF 1.11 | +$76, PF 1.11 |

### 2024 at $10,000 (no minimum-lot distortion)

| Tiers | Net | PF | Max DD |
|---|---|---|---|
| live | +$4,973 | 1.09 | 55.4% |
| H4+H1+M30 | +$4,645 | 1.10 | 52.3% |

### Per tier, from the live runs

| Tier | 2024 ($10k) | 2025 ($100) | 2026 ($100) |
|---|---|---|---|
| **H4** | **+$6,812, PF 2.03** | +$3,965, PF 2.13 | +$1,813, PF 1.61 |
| **H1** | +$1,397, PF 1.08 | +$5,172, PF 2.50 | +$4,495, PF 1.53 |
| M30 | **−$2,137, PF 0.90** | +$4,612, PF 2.00 | +$5,917, PF 1.62 |
| M15 | **−$1,098, PF 0.87** | +$925, PF 1.36 | +$1,070, PF 1.25 |

### Reading

- **At $100, 2024 ruins every combination that includes the H1 tier.** That
  includes the live build, which is stopped out on 2024-08-02. H4 alone
  survives, but only just (87% drawdown). The data is complete, so this is a
  real out-of-sample warning for the live build.
- **The ruin is mostly the account size.** The same 2024 at $10,000 makes
  +$4,973 (PF 1.09), though with a 55% drawdown. At $100, GOLDm#'s 0.10
  minimum lot and the 20% / 10% tier-1 risk on H4 / H1 mean an early losing
  run leaves the account unable to size down. The last two positions stopped
  out were both 0.10 lots.
- **H4 and H1 are the only tiers profitable in all three years.** M30 and M15
  lost in 2024 and won in 2025–26. M15 has the lowest PF of the four tiers
  every year.
- **But H4+H1 alone is not the best account.** In 2026 it made only $226 at a
  92% drawdown. The M30 tier adds most of the 2025–26 compounding.
  **H4+H1+M30 (dropping M15) matched or beat the live build in 2025 and 2026**
  (+$14,188 / +$13,378, PF 2.24 / 1.61 vs 2.03 / 1.52) with fewer trades. It
  was ruined in 2024 at $100 like the live build, and at $10k made about the
  same as live.
- **H4 alone is too slow to compound from $100** (37–67 trades a year,
  +$76 to +$303).
- Each year was run separately from $100. Compounding and the drop from 20%
  to 10% to 2% H4 risk at $7k and $13k make each run strongly path-dependent,
  so differences of a few percent mean nothing. The 2024 ruin and the per-tier
  signs are the robust findings.

## 51. PO3 sweep rejection — a basic false-break test

**File:** `experimental-po3-sweep-rejection-ea.mq5`
**Magic number:** `20260877`

A standalone EA, not a fork of the stack. It tests the user's reading of
Hopi's PO3 dealing ranges on gold, one rule at a time, before any of it goes
near the live logic.

**The reading.** When price breaks a PO3 level, a close beyond it decides
nothing: price often passes the level, runs to the next small level, and is
rejected. It usually does not reach the **midpoint of the next range**. The
user reads the rejection from the candles; the build approximates that with a
turtle soup or an engulfing candle on M1/M5. The minimum range gold plays out
is a 3, New York usually a 9 or a 27, and red news a 27; the higher the power,
the stronger the level.

### The rule

On a 27 range (`InpLevelPower = 3`), level 4077, next range 4077–4104:

| Price | Meaning |
|---|---|
| 4090.5 | **Acceptance line**, `InpAcceptPct` (50) of the next range. A signal-TF close beyond it = a real break |
| 4077–4090.5 | **Sweep zone**, undecided |
| 4077 | **Level**. A close back through it on a rejection bar = a **rejection** |

A sweep starts when a closed bar trades through a level that the bar before
closed on the other side of. It ends:

- **accepted** — a close beyond the acceptance line;
- **rejected** — a close back through the level on a bar where the sweep took
  out the prior `InpTSLookback`-bar extreme (**turtle soup**), or the bar
  engulfs the previous bar's body (**engulfing**), per `InpPattern`;
- **expired** — neither within `InpSweepMaxBars` bars.

The level's **grade** (27, 81, 243, ... — the highest power of three it
divides by, the `po3-levels.mq5` arithmetic) is recorded with every sweep, so
"the higher the power, the stronger the level" can be read straight off the
results.

### The trade

A rejection opens one market order against the sweep: the stop
`InpStopBufferPts` beyond the acceptance line (price there means the break was
real), the target `InpTPPct` (100) of a range back through the level, skipped
below `InpMinRR` (1.0). Filters: `InpBias` (default H4, the last closed close
beyond the cloud in the trade's direction — a fade is taken only against a
counter-trend pop, which is the side §7's evidence favours), a server-hour
session window, and a spread cap. One position at a time; no break-even or
trail.

### Measurement

Every resolved sweep is written to `po3-sweep-<symbol>.csv` in the terminal's
**common** Files folder: start/end time, side, level, grade, acceptance line,
extreme, overshoot as % of a range, bars, outcome, pattern, start hour,
traded. `OnDeinit` prints, per grade, the sweeps, accepted / rejected /
expired counts and the average overshoot of rejected sweeps. With
`InpTrade = false` the EA is only a measurement.

Questions to answer from the first run: what share of 27/81/243 breaks are
rejected versus accepted; whether the rejected ones really stay short of the
midpoint; whether New York hours (start hour) differ; and whether
the rejection trade makes money with and without the bias.

### Caveats

- Compiled and backtested in the local Bottles MT5 install (results below).
- **The turtle soup test is loose when the level sits beyond the prior
  extreme**: crossing the level then takes out the extreme by definition, so
  any close back through the level qualifies. The engulfing-only setting is
  the stricter read.
- A sweep that closes back through the level **without** a pattern stays open
  and can still reject later or expire.
- Levels are fixed multiples of `3^InpLevelPower` scaled by `InpPO3Scale`, as
  in the indicator; check they line up with `po3-levels.mq5` on the chart
  before reading results.

### Backtests

GOLDm#, **real ticks**, $10,000, 1% risk, M5 chart, compiled clean (0
errors, 0 warnings). 2024 and 2025 are full years; 2026 runs to 09-19. The
first eight rows use the original defaults (all hours, either pattern, H4
bias, 27 levels on M5) with one input changed per row.

| Setting | 2024 | 2025 | 2026 |
|---|---|---|---|
| defaults | −$486, PF 0.95 | +$7,759, PF 1.27 | +$1,300, PF 1.03, 36% DD |
| no bias | −$2,593, PF 0.80 | +$2,303, PF 1.06 | −$4,516, PF 0.93, 55% DD |
| H1 bias | −$666, PF 0.92 | +$7,958, PF 1.31 | −$1,397, PF 0.96 |
| engulfing only | −$673, PF 0.92 | +$8,598, PF 1.45 | +$2,561, PF 1.13 |
| New York 15–20 server | +$1,130, PF 1.17 | +$3,225, PF 1.29 | +$1,280, PF 1.10 |
| M1 signals | +$247, PF 1.02 | +$2,633, PF 1.07 | −$1,555, PF 0.98, 51% DD |
| 81 levels | +$17, PF 1.01 (22 trades) | +$895, PF 1.17 | +$333, PF 1.03 |
| 9 levels | −$3,948, PF 0.87 | −$3,175, PF 0.94 | −$3,293, PF 0.91 |
| **New York + engulfing** (new default) | **+$584, PF 1.14, 12% DD** | **+$4,453, PF 1.85, 9% DD** | **+$974, PF 1.20, 7% DD** |
| New York + engulfing, no bias | −$2,134, PF 0.66 | +$1,319, PF 1.14 | +$1,410, PF 1.15 |

**What the sweeps did** (27 levels on M5, every sweep, not only traded ones):

| Year | 27-level sweeps | Accepted (past the midpoint) | Rejected (turtle soup or engulfing) | Avg overshoot of a rejected sweep |
|---|---|---|---|---|
| 2024 | 1,498 | 4% | 74% | 8% of a range |
| 2025 | 2,891 | 14% | 70% | 13% |
| 2026 | 3,946 | 26% | 65% | 20% |

### Reading

- **The midpoint rule holds as a description.** Most breaks of a 27 level
  never close past the next range's midpoint, and the rejected ones turn
  early, 8–20% of a range past the level. Acceptance grows with volatility,
  from 4% in 2024 to 26% in 2026.
- **A rejection alone is not an edge.** Traded at all hours, the rejection
  wins about 40% at R:R ≥ 1 and roughly breaks even. The turtle soup test is
  too loose (see caveats); engulfing-only is better in 2025 and 2026.
- **New York is where it works.** It is the only single change profitable in
  all three years, and with engulfing it is the only setting profitable every
  year at a low drawdown. Sweeps are most frequent at 15–18 server time and
  are *accepted* there most often (about 60% rejected against 65–70% in other
  hours), which fits the user's note that New York plays out bigger ranges.
  The trades that survive the filter are the fewer, larger moves.
- **The cloud bias is required.** Removing it turns every good setting into a
  loser in at least one year (New York + engulfing: 2024 goes from +$584 to
  −$2,134). This agrees with §7: fade a pop only against the trend.
- **The level's power made no difference.** 27, 81 and 243 levels were
  rejected at the same rate in every year (65–74%), and 2187 was, if
  anything, accepted *more* often. On this measure a higher power is not a
  stronger level. Samples above 243 are small.
- **9 ranges lose every year**, which matches "the minimum is a 3, New York is
  a 9 or 27": a 9 range is noise on M5 at these prices. **81 ranges** are
  flat with few trades.
- **Sample size.** The best setting trades 73–110 times a year, so each year's
  PF has a wide error band. Treat it as a lead worth combining with the stack,
  not a finished system.
- **The session window is in server hours** (GOLDm# broker, GMT+3 in summer),
  so 15–20 is New York there and must be re-set for another broker or
  across DST changes.

## 52. Unraided liquidity — part of the PO3 levels indicator

**File:** `po3-levels.mq5` (indicator, no magic number) — the
"Unraided liquidity" input group

The PO3 levels indicator (§38) also marks the swing highs and lows that price
has not yet traded through — the resting liquidity a sweep is expected to
take — as a ray from the tip of the wick to the right edge, **light blue**
for highs (`InpLiqHighColor`, `clrLightSkyBlue`) and **purple** for lows
(`InpLiqLowColor`, `clrMediumPurple`), at width 2 (`InpLiqWidth`), level with the medium PO3 lines (729, 2187) so they
stand out from the thin fine grids. When a level is raided its line is
removed. It was first written as a separate `unraided-liquidity.mq5`, then
folded into `po3-levels.mq5` so the levels, the kihon counts and the
liquidity come from one indicator on one chart.

**The swing.** A fractal with a wider window: a high is a swing when it stands
above the `InpLiqLeft` candles before it and the `InpLiqRight` candles after
it, both 6 by default (a Williams fractal is 2 and 2). Ties are settled one
way so equal highs give one line, not two: the swing must be *strictly* above
its left side but only *as high as* its right side, so of a run of equal highs
the oldest is the swing. A swing is confirmed only once all its right-hand
candles have closed, so a line never appears and then disappears because the
swing failed.

**The raid.** `InpLiqRaid = LIQ_RAID_WICK` (default): any later wick trading
*beyond* the level — matching it is not a raid, equal highs stay liquidity.
This is read off the live candle, so a line goes the moment price trades
through. `LIQ_RAID_CLOSE`: a closed candle beyond the level; the live candle
is ignored until it closes.

**The timeframe.** `InpLiqTF = PERIOD_CURRENT` follows the chart. Any other
value locks the swings (and the raid check) to that timeframe on every chart.
When the locked timeframe is higher than the chart's, the line starts at the
chart candle inside the locked candle that printed the extreme
(`InpLiqSnap`), so it sits on the wick you can see rather than on the locked
candle's open.

**Scope.** `InpLiqLookback` (100) candles of the source timeframe are
searched. One newest-to-oldest pass carries the furthest price traded since
each candle, so every swing's raided/unraided state is settled in the same
pass. It is gated: a rescan runs only when a source candle opens (a swing
confirms, or a close raid lands) or price trades beyond the nearest unraided
level; any other tick costs three reads. The lines are `PO3_U`
objects, a sub-prefix no other sweep in the indicator matches. Hovering a line
shows its price, timeframe and swing time. `InpShowLiq` turns the whole
feature off.

**The price beside each swing.** `InpLiqValues` (on by default) writes each
unraided level's price, and the last raided high's and low's, at its
wick, in the line's colour: above a high and
below a low, so it sits clear of the candles that made the swing. The size
follows the PO3 labels (`InpFontSize`); the face is lighter (`InpLiqFont`,
Segoe UI Light by default) so it reads as a note on the line, not a level of
its own. The text is a `PO3_U…_V` object, pruned with its line when the level
is raided (`PO3_UR…V` for the dashed ones, swept with their dashes).

**The last raided level.** `InpLiqLastRaid` (on by default) keeps the most
recently raided high and the most recently raided low on the chart as a
**dashed** line in the same colour and width, running from the wick to the
candle that raided it (on a locked higher timeframe, the chart candle inside
it that went beyond, or closed beyond for a close raid). "Most recent" is by
the raid candle; when one candle takes several levels, the furthest one is
kept, since price reached it last. Only swings inside the lookback count.
MT5 renders a dashed style **only at width 1**, so at width 1 it is one native
dashed line; wider, it is a row of short solid segments at `InpLiqWidth`,
cut to about 12 px on and 8 px off at the chart's zoom (never shorter than one
bar, never more than 150 dashes) and re-cut when the zoom changes. These are
`PO3_UR` objects; the tooltip gives the level, timeframe, swing and raid
times.

**Lighter redraws (same change).** Three costs elsewhere in the indicator were
cut at the same time, with nothing on the chart changing:

- a price step used to delete and recreate every PO3 line; the rebuild now
  diffs against the last pass, restyling the lines still in the window and
  deleting only the ones that left it;
- a new bar used to trigger that full rebuild just to move the labels; now it
  only slides the labels to the new bar;
- the candle countdown and the session timer set their fixed properties once,
  when created, and afterwards rewrite only the text (and position or colour).

## 53. Liquidity target — take profit at the highest clear unraided level

**File:** `experimental-bottomup-stack-liquidity-target-vps-ea.mq5`
**Magic number:** `20260878`

A fork of the **live VPS build** as it stands on 2026-09-23 (M1-strict cloud
bias, robustness pack, M5 tier off). Entries, bias gates, risk and every
existing exit are the live build's byte for byte. The one addition joins the
live logic to the unraided liquidity of §52: **on the breakout — the moment a
tier's chain aligns and the trade opens — the trade is given a take profit at
an unraided liquidity level.**

### The target

- **Liquidity** is found with the `po3-levels` rules of §52, ported into the
  EA: a swing high stands *strictly* above the `InpLiqLeft` (6) candles before
  it and *at least as high as* the `InpLiqRight` (6) candles after it, within
  the last `InpLiqLookback` (100) candles; lows mirror it. A swing is
  **unraided** while no later wick has traded *beyond* it, the live candle
  included, so a level taken out this minute is no longer a target.
- A **long targets an unraided high** above price, a **short an unraided low**
  below it — the resting stops the move is expected to run into.
- **The highest clear timeframe supplies it.** A timeframe is **clear** when
  it has **broken out**: its last closed price *and* its chikou (that close,
  plotted Kijun bars back) are both beyond the cloud in the trade's
  direction. The stack M1, M5, M15, M30, H1, H4 is climbed from M1 and stops
  at the first timeframe that is not clear. Example: M1, M5 and M15 have
  broken out but M30 is still in its cloud, so M15 is the highest clear
  timeframe and the **nearest** unraided M15 level beyond the entry is the
  target. The test is the cloud half of `CheckAlign` (no tenkan/kijun), and
  the traded tier's chain passed `CheckAlign`, so the target timeframe is
  always the tier's own or higher — an M15 trade whose M30 and H1 have also
  broken out targets H1 liquidity. The level only has to clear the broker's
  minimum stop distance.
- **TP** = the level, pulled `InpLiqTPOffsetPoints` (0) toward price. At 0 the
  TP fills when price *matches* the level, a hair before the raid itself
  (which needs price to trade beyond).
- **No unraided level on that timeframe** (price is beyond every swing in
  the lookback): by default the trade opens without a TP, exactly as the
  live build does. Lower timeframes are not tried. `InpLiqNeedTarget = true` skips that tier instead, and
  the tier loop goes on to the next lower tier, which may then open — so with
  it on, the consolidation rule can open a smaller tier where live would have
  opened a larger one.

The target is fixed at entry and never moved; a restart leaves it on the
position.

### Interaction with the live exits

The target is **additive**: the kumo-touch exit, the (off by default)
rejection exit, break-even, the chandelier trail and the 8 x ATR disaster stop
all still run, so the TP can only shorten a trade. The live build calls
`PositionModify(ticket, sl, 0)`, which would strip a TP on the first BE,
trail or disaster-stop repair; here every modify passes the position's
current TP back in (the same fix §44 needed). The entry journal line and push
now end in `target <TF> <level>` or `target <TF> none`.

`InpLiqTarget = false` reproduces the live build exactly.

### Status

Compiled clean in MetaEditor (0 errors, 0 warnings). **Not yet
backtested.** The questions for the tester: how often each timeframe supplies
the target, how often the TP is hit before the kumo-touch exit, and whether
cutting the H1/H4 runners at the target costs more of the trend tail than it
saves on trades that reverse after taking the liquidity.

## 54. M5-base stack — alignment from M5 up to H4

**File:** `experimental-bottomup-stack-m5-base-vps-ea.mq5`
**Magic number:** `20260879`

A fork of the **live VPS build** as it stands on 2026-09-23 (M1-strict cloud
bias, robustness pack, M5 tier off). The one change: **the bottom-up stack
starts at M5, not M1.** M1 takes no part in alignment.

| Tier | Live build needs | This build needs |
|---|---|---|
| M15 | M1 + M5 + M15 | M5 + M15 |
| M30 | M1 … M30 | M5 … M30 |
| H1 | M1 … H1 | M5 … H1 |
| H4 | M1 … H4 | M5 … H4 |

M5 alone never trades; it is only the start of the stack, as M1 was.
With the M5 tier already off in the live build, the tier set is unchanged
(M15, M30, H1, H4). The difference is that no entry has to wait for M1 to line
up, so the question is whether M1's agreement was filtering out bad entries or
only delaying good ones.

**The cloud gate** stays the live one: the tier's timeframe and the one below
it, future cloud only. Live applies the strict M1 rule (current *and* future
cloud) to no tier since the M5 tier was dropped, so nothing is lost by default.
`InpBaseCloudFull` (off) moves that rule onto the new base: the M15 tier then
needs M5 twisted its way at both the current bar and the far end of the
future cloud.

**Unchanged:** H4 bias with the H1 stand-in, the D1 filter on the H4 tier,
risk tiers, disaster stop, break-even, chandelier trail, kumo-touch exit and
the robustness pack. The loop is still paced by closed M1 bars, so exits are
checked as often as live. The M1 Ichimoku handle is still created but no
longer read for entries. The parent's header comment is kept below a new
experiment banner.

Compiled clean in MetaEditor (0 errors, 0 warnings).

### Results (2026-09-24): worse than the live build, do not promote

GOLDm# (XMGlobal-MT5 5, Micro: 1 lot = 1 oz, 0.1 lot minimum), $100,
1:1000, real ticks, default inputs, each year separately. The user ran it
under the name `earthly-ea` (source identical to this file). Figures are
rebuilt from the tester log: 4,588 positions, summing exactly to each run's
final balance. Drawdown is on closed trades.

| Year | Live build (§48/§50) | M5 base |
|---|---|---|
| 2024 | ruined, 2024-08-02 | **ruined, 2024-07-02** ($401 → $0.43), PF 0.92 |
| 2025 | +$14,646, PF 2.03, 25% equity DD | +$13,990, PF 1.89, **96% DD** ($1,977 → $79, Jun–Aug) |
| 2026 to 09-19 | +$13,295, PF 1.52, 44% equity DD | +$14,196, PF 1.36, **63% DD** ($10,333 → $3,868) |

Per tier (trades, PF): 2026 M15 724 / 1.17, M30 427 / 1.33, H1 224 / 1.36,
H4 42 / 2.02. 2025 M15 1,160 / 1.46, M30 628 / 1.71, H1 316 / 2.22, H4 67 /
2.15. 2024 M15 0.92, M30 0.93, H1 1.12, H4 0.69.

**Reading.** Without M1 in the chain, about a third more trades get through
(2026: 1,417 against about 1,060) at a lower profit factor. Net profit is
about the same, but the drawdowns are far deeper, and 2025 came within $79 of
ruin. M1's agreement was filtering out weak entries, not just delaying good
ones. The live build stays.

## 55. M5-base, keep tiers — a bigger tier no longer closes the smaller ones

**File:** `experimental-bottomup-stack-m5-base-keep-tiers-vps-ea.mq5`
**Magic number:** `20260880`

A fork of the M5-base stack (§54). The live family runs **one position per
symbol**: when several tiers align only the largest opens, and any smaller
tier still running is closed ("superseded"). This build drops that
consolidation. With `InpKeepLowerTiers` on (the default):

- **Every aligned flat tier opens on the same bar.** If M15 and M30 align
  together, both open, each with its own risk % and its own comment.
- **Nothing is superseded.** A running M15 trade keeps going when M30 (or
  H1, H4) opens, and leaves only through its own exits: cloud touch on M15,
  break-even, trail or disaster stop.
- A tier that is already in a trade still does not open a second one; it is
  one position per tier, so at most four per symbol (M15, M30, H1, H4).

**Exposure.** Risk is still sized per tier, but the positions now stack: in
the tier-1 regime (equity below $7000) M15 1% + M30 5% + H1 10% + H4 20% can
all be open at once, 36% of equity against the 2 × ATR reference distance.
The per-order margin cap (80% of free margin) is applied to each order in
turn, so later orders on a busy bar may be cut down.

**Account type.** It needs a **hedging** account: on a netting account the
tiers would merge into one position. Tiers can also end up on opposite sides
(for example, a lower tier opening on the H1 stand-in against an older H4
trade after H4 goes flat). The live build could do this too, but only while
no higher tier fired.

`InpKeepLowerTiers = false` reproduces §54 exactly. Everything else (entries,
cloud gate, bias, risk %, exits) is §54's.

**Result (user report, 2026-09-24): detrimental.** The EA did not perform
well; keeping the lower tiers open alongside the bigger one made it worse than
the M5 base. The one-position-per-symbol supersede rule stays. Do not promote.

Compiled clean in MetaEditor (0 errors, 0 warnings). The questions it was
built to answer: whether the lower-tier trades that used to be
cut at supersede add profit or just add drawdown on top of the higher tier,
and how deep the drawdown goes with 36% stacked.

## 56. M5-base, risk x1.25 — the same stack at a quarter more risk

**File:** `experimental-bottomup-stack-m5-base-risk125-vps-ea.mq5`
**Magic number:** `20260881`

A fork of the M5-base stack (§54), written after the keep-tiers fork (§55)
proved detrimental. The one change: **every risk % is multiplied by 1.25**,
in every tier and every regime.

| Tier | Regime 1 (< $7000) | Regime 2 ($7000–$13000) | Regime 3 ($13000+) |
|---|---|---|---|
| M5 (never trades) | 1 → 1.25 | 0.5 → 0.625 | 0.1 → 0.125 |
| M15 | 1 → 1.25 | 0.5 → 0.625 | 0.1 → 0.125 |
| M30 | 5 → 6.25 | 2.5 → 3.125 | 0.2 → 0.25 |
| H1 | 10 → 12.5 | 5 → 6.25 | 1 → 1.25 |
| H4 | 20 → 25 | 10 → 12.5 | 2 → 2.5 |

**Unchanged:** the regime thresholds ($7000 and $13000), the sizing distance
(ATR × 2, the reference the % is measured against), the 80% free-margin cap,
and everything about entries and exits. Since there is still one position per
symbol, the most at risk at once is the H4 tier's 25% in regime 1 (was 20%).
The margin cap can trim the larger H1/H4 orders on a small account, so the
real increase there may be less than 25%.

The risk figures in the parent's header and `LevelRiskPct` comments are left
as the parent's; a new banner at the top gives the x1.25 values.

Compiled clean in MetaEditor (0 errors, 0 warnings). **Not yet backtested.**
Compare against §54 on the same period: net profit should rise roughly in
proportion, and the question is how much the drawdown grows with it.

## 57. M5-base, five equity regimes

**File:** `experimental-bottomup-stack-m5-base-risk125-5regime-vps-ea.mq5`
**Magic number:** `20260882`

A fork of the risk ×1.25 build (§56). The change is to sizing only: **five
equity regimes instead of three.** The old $13000+ regime is split at $17000
and $20000, and each new regime is half the one before.

| Tier | < $7000 | $7000–$13000 | $13000–$17000 | $17000–$20000 | $20000+ |
|---|---|---|---|---|---|
| M15 | 1.25 | 0.625 | 0.25 | 0.125 | 0.0625 |
| M30 | 6.25 | 3.125 | 0.5 | 0.25 | 0.125 |
| H1 | 12.5 | 6.25 | 2.5 | 1.25 | 0.625 |
| H4 | 25 | 12.5 | 5 | 2.5 | 1.25 |

(M5 carries the M15 figures but never trades in the M5-base stack.) New
inputs `InpRiskTier4At` (17000) and `InpRiskTier5At` (20000) and the
`_T4` / `_T5` risk inputs; `LevelRiskPct` picks the regime from the equity at
entry.

**History.** The first version of this build (filed as `…-risk250-5regime-…`)
also doubled every figure, ×2.5 of the M5 base, which put H4 at 50% below
$7000. At 50% against a 2 × ATR sizing distance, a trade run to the 8 × ATR
disaster stop would lose about twice the account. The user had it reduced
back the same day: regimes 1–2 returned to §56's figures, and the three
regimes above $13000 kept the figures they had (so regime 3 is twice §56's
old $13000+ tier).

Everything else (entries, the M5-base chain, cloud gate, bias, exits, the
80% margin cap) is §54's.

Compiled clean in MetaEditor (0 errors, 0 warnings). **Not yet backtested.**
Against §56 it only differs once equity passes $13000, so compare on a period
long enough to get there.

## 58. M1/M5 liquidity scalper — M1+M5 alignment, unraided M5 target, fractal stop

**File:** `experimental-m1m5-liquidity-scalper-ea.mq5`
**Magic number:** `20260883`

A standalone scalper written on user request (2026-09-24), not a fork of the
bias stack. There is **no higher-timeframe bias**: no H4/H1 bias, D1 filter,
cloud-twist gate or tier ladder. Only M1 and M5 matter.

### The rules

- **Entry.** On each closed M1 bar, when the symbol has no position of this
  magic, M1 and M5 must both pass the live build's `CheckAlign` in the same
  direction: price above (below) tenkan, kijun and the cloud, and chikou
  above (below) the high (low), tenkan, kijun and cloud Kijun bars back.
  The spread filter (`InpMaxSpreadPoints`, 60) is kept.
- **Take profit: unraided M5 liquidity.** The nearest unraided M5 swing
  beyond the entry: a high above price for a buy, a low below it for a sell.
  This is the `po3-levels` scan of §52, ported as in §53: a swing must stand
  out from 6 candles on the left (strictly) and 6 on the right, the scan
  covers the last 100 M5 candles, and a level counts as raided once a later
  wick trades beyond it. `InpLiqTPOffsetPoints` (0) pulls the TP in front of
  the level. The distance is measured from the side that triggers the TP
  (the bid for a buy, the ask for a sell) and must clear the broker's
  minimum stop distance.
- **Stop loss: two fractals back.** Williams fractals (`iFractals`) on
  `InpFractalTF` (M1 by default) are walked from the newest confirmed one
  (bar 3, since a fractal on bar 2 still depends on the live candle) back
  through `InpFractalLookback` (200) candles. Only fractals beyond the
  entry count: lows below it for a buy, highs above it for a sell. The
  `InpFractalCount`-th one (2) is the SL. In a clean uptrend this is the
  higher low before the latest one, and so the lower of the two.
  `InpSLBufferPoints` (0) pushes the SL further beyond the fractal.
- **No target or no stop means no trade.** The reason is journalled once per
  aligned run instead of every minute.
- **Size: the live VPS build's risk regime for an M5 trade.** Risk is a
  % of the actual equity at entry, reduced as the account grows:
  `InpRiskPctM5` 1% below `InpRiskTier2At` ($7000), `InpRiskPctM5_T2` 0.5%
  up to `InpRiskTier3At` ($13000), and `InpRiskPctM5_T3` 0.1% above that.
  The % is measured against **the distance from the entry to the fractal
  stop**, so a trade stopped out loses that % of equity. The stop is
  placed first and never moved to suit the size. Live, which has no stop,
  measures against ATR × 2 instead. Two limits bend the %: a very close
  fractal gives a large size, which the margin cap then limits, and a very
  far one can round down to the broker's minimum lot, which then risks more
  than the %. The order is capped to `InpMarginUsePct` (80%) of free
  margin, and `InpFixedLots` (0.10) is the fallback when sizing data is
  missing. The first version traded a fixed 0.10 lots on every trade.
- **Exits.** One position per symbol, and it closes only at its SL or TP.
  There is no kumo-touch exit, break-even or trail. While alignment holds,
  a new trade opens on the next closed M1 bar after the last one closes,
  targeting the next unraided level.

### History (2026-09-24)

An M15 tier (M1+M5+M15 aligned, TP at unraided M15 liquidity, superseding
the M5 scalp) was added and then removed the same day at the user's
request. The build is M1+M5 only again. At the same time the fixed 0.10 lots
were replaced by the live risk regime, first measured against ATR(M5) × 2
as live does, then (the same day, at the user's request) against the
fractal stop distance as above.

### Choices made where the request was open

- The fractal timeframe defaults to **M1**, the scalping timeframe. Set
  `InpFractalTF = PERIOD_M5` for a wider stop on the same timeframe as the
  target.
- "Two fractals" is counted back in time among the fractals beyond the
  entry, not by price rank.

### Status

Compiled clean in MetaEditor (0 errors, 0 warnings). **Not yet
backtested.** Questions for the tester: the win rate against the reward:risk
that the M5 target and M1 stop give, how often an aligned bar finds no
unraided M5 level, and whether an M5 fractal stop does better.

---

## 59. XAUUSDc cent fork — the live build on an Exness cent account

**File:** `experimental-bottomup-stack-xauusdc-cent-vps-ea.mq5`
**Magic number:** `20260884`

A copy of the live VPS build (`ichimoku-h4-m1-vps-ea.mq5`: M1-strict cloud
bias, M5 tier off, robustness pack on) for trading **`XAUUSDc` on an Exness
cent account**. It will be backtested in the strategy tester before any live
use. **None of the trading logic changes.** Entries, bias gates, the kumo-touch
exit, break-even, the chandelier and the disaster stop are all live's. The
four changes are about the account and the instrument:

1. **`Symbols` = `XAUUSDc`.**
2. **Live's risk regime at half the %, on a cent account.** The three
   regimes are live's, but every % is **halved** (user decision
   2026-09-24):

   | Regime (equity in USC) | M15 | M30 | H1 | H4 |
   |---|---|---|---|---|
   | tier 1, below 7000 | 0.5 | 2.5 | 5 | 10 |
   | tier 2, 7000–13000 | 0.25 | 1.25 | 2.5 | 5 |
   | tier 3, 13000 and up | 0.05 | 0.1 | 0.5 | 1 |

   The M5 figures are halved too, although the M5 tier stays off. Each % is
   measured against ATR × 2, as live. On a cent account the equity and the symbol's tick value are
   both in USC, so a % of equity becomes the same number of lots with no
   change. The regime **thresholds** are read in account units: **cents
   are treated like live's dollars**, so the risk steps down at
   `InpRiskTier2At` = **7000 USC** and `InpRiskTier3At` = **13000 USC**
   (user decision 2026-09-24). A first version converted them to 700 000 /
   1 300 000 USC to match live's real money. That was dropped at the
   user's request.
   **Minimum 0.01 lots:** a size below the broker minimum is rounded **up**
   to 0.01, the same clamp live uses, so on a small account a low-% tier can
   risk more than its %. `InpFixedLots` (0.01) is only the fallback when
   sizing data is missing.
3. **Point inputs scaled to the feed.** Live's point inputs were tuned on
   `GOLDm#`, which quotes to 2 decimals (1 point = 0.01). Exness quotes gold
   to 3 decimals (1 point = 0.001), so unscaled they would cover a tenth of
   the price distance. The BE stop (15 points) would sit inside the spread,
   and the 60-point spread cap would block nearly every entry, the same
   failure as the BTCUSD fork (§35). `Slippage`, `InpMaxSpreadPoints` and
   `InpBECoverPoints` are therefore now in **2-decimal gold points (0.01 of
   price)**, and `PtScale()` (`round(0.01 / point)`) multiplies them by 10 on
   a 3-decimal feed and by 1 on a 2-decimal one. The defaults (30 / 60 / 15)
   keep live's price distances: $0.30 slippage, $0.60 spread cap and $0.15
   BE cover. The ATR-based distances (BE arming, trail, disaster stop) needed
   no change.
4. **Fresh magic `20260884`.**
5. **Minimum-lot guard** (user decision 2026-09-24). On a practice start
   of **100 USC** ($1), every % sizes below 0.01 lot and is rounded up, so
   the lot floor sets the risk, not the %. At 0.01 lot, $1 of gold is 1 USC,
   which is 1% of the account. The table estimates the loss over 2 × ATR
   with typical gold ATRs:

   | Tier | Target % (tier 1) | 0.01 lot risks | At the 8 × ATR disaster stop |
   |---|---|---|---|
   | M15 (ATR ≈ $3) | 0.5 | ~6% | ~24% |
   | M30 (ATR ≈ $4.5) | 2.5 | ~9% | ~36% |
   | H1 (ATR ≈ $7) | 5 | ~14% | ~56% |
   | H4 (ATR ≈ $15) | 10 | ~30% | ~120% |

   `MinLotGuardOK()` takes the **final** lots (after the minimum-lot
   rounding and the margin cap) and computes the loss over
   `ATR(tier TF) × InpRiskATRMult`. It skips the tier when that loss is
   above `InpMaxTradeRiskPct` (**10%**) of equity. The selection loop then
   **falls through to the next lower aligned tier**. That tier's chain is
   part of the higher one, so it is usually aligned too. At 100 USC, M15
   and M30 trade while H1 and H4 wait. Each tier unlocks by itself as
   equity grows: H1 at about 140 USC and H4 at about 300 USC with the ATRs
   above. Unreadable sizing data blocks the tier. A skip is logged once per
   tier-TF bar. `InpMaxTradeRiskPct = 0` switches the guard off.

   Leverage was considered and rejected as the control. It changes only
   the margin held, not the loss per $1 of gold, and it blocks trades
   without regard to their risk.

OnInit prints one line per symbol: digits, point scale, the resolved spread
cap / BE cover / slippage, the regime thresholds in account units, the
minimum lot and the account currency.

### Backtesting it

- Tester symbol `XAUUSDc` from an Exness cent login, with **Every tick based
  on real ticks**. The practice start is a **100 USC** deposit ($1). Set the
  tester's leverage to the real account's.
- Check the OnInit journal line first. It should read `digits 3, point scale
  x10`, `regimes at 7000 / 13000 USC`, `min-lot guard 10.0%` and `min lot
  0.01`. Early on, expect `skipped by min-lot guard` lines for H1/H4.

### Status & caveats

- **Not yet compiled or backtested.** Compile with F7 in MetaEditor.
- On a cent account, 0.01 lots is 1/100 of the real exposure 0.01 lots has on
  a standard account. The 0.01 floor is therefore far less of a constraint
  than live's, and a small account can follow the % closely. That is what
  makes the cent account suitable for this regime.
- **Risk at the disaster stop.** The stop sits 8 × ATR away while sizing
  uses 2 × ATR, so a trade that runs to it loses about 4× its %. At the
  halved figures that is about 40% on an H4 trade and 20% on an H1 trade
  below 7000 USC, and 20% / 10% between 7000 and 13000 USC. Live's figures
  are double that.
- **Lot value.** `XAUUSDc` is 100 oz per lot with profit in USC, so 1 lot
  moves $1.00 of real money per $1 of gold, the same as live's `GOLDm#` (1 oz
  per lot, in $). The 0.01 minimum is $0.01 per $1, a tenth of live's 0.1-lot
  floor, so rounding up to the minimum rarely adds risk here.
- The 60 (×10) spread cap is live's price distance. If Exness's cent gold
  spread is wider, entries will be blocked, and the tester will show no
  entries at all. The fix is to raise `InpMaxSpreadPoints`, not to switch it
  off.

## 60. Unmitigated fair value gaps — part of the PO3 levels indicator

**File:** `po3-levels.mq5` (indicator, no magic number, v1.46) — the
"Fair value gaps" input group

The PO3 levels indicator (§38, §52) also shades every **fair value gap** that
price has not yet filled, as a box from the gap's middle candle to the right
edge: **dark green** for bullish gaps (`InpFvgBullColor`, `C'0,64,48'`) and
**dark red** for bearish ones (`InpFvgBearColor`, `C'80,24,32'`). The boxes
sit behind the candles, and MT5 gives a rectangle no transparency, so the
fills are dark on purpose — tuned for a black chart; pick pale fills on a
light one.

**The gap.** Three candles in a row. Bullish: the third candle's low is above
the first candle's high, and the gap is the range between them — the middle
candle moved so fast that nothing traded it both ways. Bearish mirrors it:
the third's high below the first's low. A gap is confirmed only once its third
candle has closed, so a box never appears and then vanishes because the live
candle wicked back. `InpFvgMinPts` (0) drops gaps narrower than that many
points.

**Mitigation.** Read off the wicks of every candle after the third, the live
candle included, so a box goes the moment price reaches it.
`InpFvgMit = FVG_MIT_FULL` (default): price trades to the far edge — the whole
gap filled. `FVG_MIT_HALF`: price reaches the middle (the consequent
encroachment). `FVG_MIT_TOUCH`: any trade into the gap.

**The timeframe and scope.** `InpFvgTF = PERIOD_CURRENT` follows the chart, so
the gaps are always the ones on whatever timeframe is open; any other value
locks the gaps and the mitigation check to that timeframe on every chart, and
the box starts at the locked middle candle's open. `InpFvgLookback` (200)
candles of the source timeframe are searched. One newest-to-oldest pass
carries the lowest low and highest high since each gap, so every gap's state
is settled at once. It is gated like the liquidity: a rescan runs only when a
source candle opens, a chart candle opens (the boxes' right edges move to it)
or price reaches the nearest mitigation price on either side. The boxes are
`PO3_F` objects, a sub-prefix no other sweep in the indicator matches; hovering
one shows its range, timeframe and middle-candle time. `InpFvgBull` /
`InpFvgBear` hide one side; `InpShowFvg` turns the whole feature off.

Compiled clean in MetaEditor (0 errors, 0 warnings); not yet checked on a live
chart.

## 61. Kihon panel buttons — show or hide the timetables from the chart

**File:** `po3-levels.mq5` (indicator, no magic number, v1.47) — the
"Kihon panel buttons" input group

The three kihon blocks of the PO3 levels indicator (§38) — the count panel,
the segment panel and the schedule panel — now **start hidden**
(`InpShowPanel`, `InpShowSeg`, `InpShowSched` default to `false`). The schedule
alone is taller than most charts have room for. A row of three buttons,
**Count / Segments / Schedule**, at the bottom left of the chart
(`InpButtonCorner`, `InpButtonX`, `InpButtonY`) shows or hides each block with
one click, without the properties dialog. A lit button (the panel's hit
colour, pressed) means its block is showing. Hiding a block hands its place to
the one after it, as the input switches always did.

The three inputs set how the blocks start. The buttons flip them from there,
and the choice **survives a timeframe change**: OnDeinit keeps it in a terminal
global keyed by chart id (`PO3_Toggle_<chart>`), the same trick the session
timer uses. Any other reload, including an input change, starts from the
inputs again, so a value set in the dialog always does what it says.
`InpShowButtons` removes the button row.

Charts that already carry the indicator keep their stored inputs (on); re-add
it to get the hidden defaults. Compiled clean in MetaEditor (0 errors,
0 warnings).

**Fine grids off by default (v1.48).** The PO3 grids 3, 9 and 27 now default
to off, joining 1, so a fresh chart opens with only 81 and up drawn. Tick them
in "PO3 levels to show" for the whole nest; no level moves either way. As with
the panels, charts that already carry the indicator keep their stored inputs
until it is re-added.

**Count panel shown by default (v1.49).** `InpShowPanel` defaults to `true`
again, so a fresh chart opens with the kihon count panel showing; the segment
and schedule panels still start hidden. The Count button hides it as before.
Charts that already carry the indicator keep their stored inputs until it is
re-added. Compiled clean in MetaEditor (0 errors, 0 warnings).

## 62. Chikou exit — close when the tier's chikou falls back into price

**File:** `experimental-bottomup-stack-chikou-exit-vps-ea.mq5`
**Magic number:** `20260885`

A fork of the **live VPS build** as it stands on 2026-09-25 (M1-strict cloud
bias, robustness pack, M5 tier off). Entries, bias gates, risk and protection
are the live build's byte for byte. The one addition is a **second exit
condition on every tier**.

The live build closes a trade only when price touches the tier TF's cloud
edge (plus the BE / chandelier / disaster stops). Here a trade **also closes
when the tier TF's chikou closes back inside price**:

- The chikou is the last closed tier-TF bar's close, plotted Kijun (26) bars
  back — the same reading `CheckAlign` uses at entry.
- Entry required it **clear of the candle 26 bars back**: above its high for
  a long, below its low for a short. The exit fires once it is not: **long
  exits when close <= that candle's high, short when close >= its low**. A
  chikou that falls straight through the candle counts too.
- Each tier watches **its own timeframe**: an H1 trade closes on the H1
  chikou, an M30 trade on the M30 chikou, M15 on M15, H4 on H4.
- It is evaluated once per closed M1 bar, but only reads closed tier-TF bars,
  so its answer changes only when a tier-TF bar closes. A trade opens only
  while its chikou is clear, so it cannot fire on the entry's own bar.
- The kumo-touch exit stays; whichever comes first closes the trade. The
  journal / push reason is `chikou in price`.

`InpChikouExit = false` reproduces the live build exactly. The expected
effect is earlier exits: the chikou test fails well before price reaches the
cloud in most pullbacks, so trades should be shorter with smaller give-backs
and more exits near break-even. Not yet compiled or backtested.
