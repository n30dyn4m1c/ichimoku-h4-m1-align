# Experimental Features

Strategies here are **experimental** — newer, less battle-tested than the main
alignment/PO3 EAs, and shipped for research and demo testing. Backtest and
forward-test on a demo account before risking capital. See the top-level
[Disclaimer](README.md#️-disclaimer).

---

## H1 Ichimoku Time-Theory Reversion EA

**File:** `ichimoku-H1-M1-reversion-ea.mq5`
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
- **M15 fractal trail (Stage 2)** — once a **closed M15 candle prints clearly beyond the M15 Kijun** in the trade direction ("clearly" = ≥ `InpM15ClearATR × ATR(M15)` past it), the stop is moved to the **`InpM15TrailFractal`-th M15 fractal** on the protective side of price (default the **2nd** M15 swing high above price for a sell / low below for a buy). It re-evaluates each new M15 bar, **only ever tightens** (a short's stop only moves down, a long's up), and never sits inside the broker minimum. `InpM15SwingWing` / `InpM15FractalBars` define and bound the M15 fractal scan.

---

### Risk sizing

Identical equity-scaled sizing to the breakout/alignment EAs — `GetEquityRisk()`
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
                          → trail SL to 2nd M15 fractal high above price
                          → keep tightening each M15 bar
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
| Stops | `InpSLBufferATR` | 0.10 | Stop padding (× ATR H1) |
| Stops | `InpM15TrailFractal` | 2 | Nth M15 fractal to trail the stop to |
| Stops | `InpM15SwingWing` / `InpM15FractalBars` | 2 / 100 | M15 fractal shape and scan depth |
| Stops | `InpM15ClearATR` | 0.1 | "Clearly beyond M15 Kijun" buffer (× ATR M15) |
| Risk | `InpATRPeriod` | 14 | ATR period (H1 and M15) |
| Risk | `InpMaxSpreadPoints` | 60 | Spread filter (0 = off) |
| Risk | `InpHighEquityRiskPct` | 1.0 | % equity risked per trade above $8000 |

Full input reference and the shared risk/equity-alert inputs are in the
[README](README.md#companion-h1-reversion-ea-ichimoku-h1-m1-reversion-eamq5).

---

### Status & caveats

- **Not yet compiled/backtested here** — needs an F7 compile in MetaEditor and a Strategy-Tester + demo run before live use.
- **"Unliquidated" is judged at each timeframe's own resolution** — a daily level is "untouched" if no later *daily* bar's high exceeded it; an intraday poke within the still-forming daily bar isn't captured at daily resolution.
- **Trend filter vs. flat Kijun** — compatible by design (a strong extension where price ran away and the Kijun flattened underneath), but if live setups get filtered out because the Kijun is still gently sloping, loosen `InpFlatATRMult`.
- **M15 trail reading** — "two M15 fractal highs up" is implemented as the 2nd fractal on the *stop side of current price* (it trails as price moves), not a fixed level anchored at entry.
