# Time Theory, Wave Theory, and Price Theory

An investigation into the three core theories behind Ichimoku Kinko Hyo (一目均衡表),
and how they relate to this project's EA strategy.

**Status:** Research / reference document · **Date:** 2026-08-20
**Scope:** basics of each theory, how they interlock, how they map onto this repo's EAs.

---

## 1. Provenance: Hosoda's "three essences"

Ichimoku Kinko Hyo was developed in the late 1930s by the Japanese journalist
Goichi Hosoda (細田悟一), writing as *Ichimoku Sanjin* (一目山人, "what a man in the
mountain sees"), and published publicly in the late 1960s. In the West, Ichimoku is
almost always used as its "graphic environment" only — the five lines (Tenkan-sen,
Kijun-sen, Senkou Span A/B and the Kumo cloud, Chikou Span) and their crosses. But
Hosoda built the method on **three supporting theories**, which he considered the
actual essence of the system:

| Japanese | Romaji | English |
|----------|--------|---------|
| 時間論 | Jikan-ron | **Time Theory** |
| 波動論 | Hado-ron | **Wave Movement Theory** |
| 値段論 / 値幅観測論 | Nedan-ron / Nehaba-kansoku-ron | **Price Theory** (price-margin observation) |

A useful one-line summary of each:

- **Time Theory** — *when* moves start and end: markets turn on predictable
  counting cycles (kihon suchi / taito suchi), and the dates where cycles coincide
  are "change days" (変化日).
- **Wave Theory** — *how* moves unfold: every trend is built from a small set of
  repeating wave shapes (I, V, N, and their combinations), each leg measured
  against the "equilibrium" lines.
- **Price Theory** — *how far* moves go: once a wave shape is identified, its
  size projects price targets (the N / V / E / NT calculations).

The three theories are meant to be used **together**: the wave structure tells you
where you are in the move, time theory tells you when the next turn is due, and
price theory frames how far the move can carry. The graphic environment (lines +
cloud) is the tool you use to *read* all of this off the chart.

> Note on naming: some Western sources call the third pillar "Target Price Theory"
> or "Price Margin Observation Theory". They are the same thing — Hosoda's term
> literally means "price-range observation theory", i.e. measuring how far a wave
> should travel.

---

## 2. Time Theory (時間論, Jikan-ron)

### 2.1 The basic numbers — Kihon Suchi (基本数値)

The heart of time theory is a list of cycle lengths — the *kihon suchi* ("basic
numbers") — that Hosoda derived empirically from decades of Japanese market
observation. The canonical list:

```
9, 17, 26, 33, 42, 51, 65, 76, 83, 97, 101, 129, 172, 200, 226, 257, 676
```

(These are exactly the numbers in this repo's `InpTimeCycles` default.)

The primary anchors are **9** and **26**, and they have a tidy calendar
explanation tied to the old Japanese trading calendar, when markets traded six
days a week:

| Period | Meaning (old 6-day-week calendar) |
|--------|-------------------------------------|
| 9 | one and a half trading weeks |
| 17 | 26 − 9 — the gap between the two anchors (some sources read it as ~three weeks) |
| 26 | one trading month (also the Kijun-sen period) |
| 52 | two trading months (also the Senkou Span B period) |
| 676 | 26 × 26 — the long-cycle anchor (26 months ≈ 2+ years) |

The rest of the list (33, 42, 51, 65, 76, 83, 97, 101, 129, 172, 200, 226, 257)
are not clean multiples of 9 or 26; they were compiled empirically. Many cluster
near multiples of 9 or 26 (e.g. 42 ≈ 9×4.7, 101 ≈ 26×3.9, 129 ≈ 26×5), which is
the sense in which the series is "built from combinations of 9 and 26".

### 2.2 The equal numbers — Taito Suchi (対等数値)

A second, simpler series used for longer-range projection — the *taito suchi*
("equal numbers") — is just the multiples of 26:

```
26, 52, 78, 104, 130, 156, 182, 208, 234, 260, …
```

Where kihon suchi are the "texture" of short/medium cycles, taito suchi give the
coarse grid for multi-month horizons.

### 2.3 Change days (変化日, Henka-bi)

The practical output of time theory is a set of **change days**: dates on which a
market turn (reversal, acceleration, or pause) becomes *due*.

The mechanics:

1. Identify significant swing highs/lows on the chart (preferably confirmed by the
   equilibrium — see Wave Theory).
2. Count forward kihon suchi periods (9, 17, 26, 33, …) from each swing point.
3. Each landing date is a candidate change day.
4. When counts **from several independent reference points land on the same day**,
   the change day is considered much stronger — Hosoda's "three ships meeting"
   (三舟観測) analogy: three vessels arriving in port on the same tide.
5. Change days themselves can serve as new reference points (count forward again),
   producing a lattice of nested cycle windows.

Practical uses:

- **Avoid chasing** a move whose bar count has just landed on a kihon suchi number —
  the move is "mature" and a turn is due. This is *exactly* what this repo's time
  filter does (see §7).
- **Time entries** on a pullback: wait for the pullback leg to reach a cycle count
  (e.g. 9 or 17 bars) before entering with the trend.
- **Time exits**: scale out or trail harder when a wave has run its cycle count.

### 2.4 Caveats

- Cycle counting is *interpretive*: which swing points you anchor on, and whether
  you count 9 from a high or 17 from a low, changes the answer. Two analysts will
  rarely mark identical change days.
- The numbers were derived from pre-war Japanese equity data. They carry no
  guaranteed validity for other markets/eras — though the 9/26/52 structure
  remains the default on every charting platform.
- Time theory gives *windows of likelihood*, not precise predictions. It is a
  timing aid, not a signal generator.

---

## 3. Wave Theory (波動論, Hado-ron)

### 3.1 The wave shapes: I, V, N — and the complex P, Y, W

Hosoda's wave theory classifies every price structure into a small set of shapes.
The basic unit is the swing (one directional leg); shapes are named by how many
legs they contain:

| Wave | Legs | Shape | Notes |
|------|------|-------|-------|
| **I** | 1 | a single directional leg | the atom of structure |
| **V** | 2 | up then down, or down then up | a reversal shape |
| **N** | 3 | up–down–up (bullish) or down–up–down (bearish) | **the fundamental trend unit** |
| **P** | 4 | N plus one more leg | first complex form |
| **Y** | 5 | five alternating legs | deeper complex form |
| **W** | 6 | two N-shapes sharing a middle leg | the largest common shape |

The **N wave** is the one that matters for trading:

```
Uptrend N wave                  Downtrend N wave

        B
       / \                       A
      /   \                       \
     /     C                       \      C
    /       \                       \    / \
   /         \                       \  /   \
  A           X (target)              B      X (target)
```

- Wave 1: A → B (the initial push away from equilibrium)
- Wave 2: B → C (the pullback / correction)
- Wave 3: C → X (the continuation — this is the leg you want to ride)

This is Hosoda's **three-wave principle** (三波動): a trend phase is composed of
three waves — push, pullback, continuation. Note how different this is from
Elliott Wave's 5-wave impulse: Hosoda's trend unit is 3 waves, and every 3rd wave
completes a "cycle" that is measured by time theory (see below).

### 3.2 Waves and equilibrium

Waves are judged **against the equilibrium** — the Kijun-sen and the Kumo cloud:

- Wave 1 typically starts *at or from* the Kijun/cloud (a bounce off equilibrium).
- Wave 2 (the pullback) ideally *returns to* the Kijun or the cloud edge — a
  "Kijun touch". If wave 2 fails to reach equilibrium, the trend is strong; if it
  slices through, the wave count is invalidated.
- Wave 3 continues until it hits a price target (§4) or a change day (§2).

This is precisely the structure this project's EAs key off: the "Kijun touch"
definitions in the reversion EA (`InpTimeCycles` counting "consecutive H1 candles
since the last Kijun touch") and the alignment builds' "price + Chikou vs
Tenkan/Kijun/cloud" filters are equilibrium-relative wave readings.

### 3.3 Waves and time theory are coupled

The two theories are not independent:

- Each leg of a wave tends to last a kihon suchi number of bars (commonly 9–17 for
  wave 1; the full N wave often lands near 26–33 — note the EA's reversion cycles
  9/17/26/33 ±2).
- Waves tend to *terminate on change days*. A wave 3 that reaches a price target
  on a change day is a high-confidence "mature" move — the standard signal to
  stand aside or fade.
- A wave that has not yet completed its count is "young" — continuation is more
  likely than reversal.

### 3.4 Relation to other wave theories

| Framework | Trend unit | Count | Fractal? |
|-----------|-----------|-------|----------|
| **Ichimoku (Hosoda)** | 3 waves (N-wave) | I / V / N / P / Y / W shapes | yes, shapes nest |
| **Elliott Wave** | 5-wave impulse + 3-wave correction | 1-2-3-4-5 / a-b-c | yes, all degrees |
| **Dow Theory** | swings within primary trend | no fixed count | no |

Ichimoku's wave theory is the closest to Elliott in spirit (both see recurring
wave structure and both allow nesting), but Hosoda's is simpler: no 5-wave
requirement, no explicit correction rules — the N-wave and its extensions cover
everything, and the time dimension (cycle counts) is built into the wave labels
rather than bolted on later.

---

## 4. Price Theory (値段論, Nedan-ron)

### 4.1 Price measurement from the N wave

Once an N wave is identified (A → B → C as above), Price Theory projects where
wave 3 should end. There are **four classic calculations**, each of which assumes
a different relationship between the legs:

| Target | Formula (up-wave) | Meaning |
|--------|-------------------|---------|
| **N**  | `C + (B − A)` | wave 3 = wave 1 in length, measured from the wave-2 low — the benchmark |
| **E**  | `B + (B − A)` | wave-1 length measured from the wave-1 high — for shallow pullbacks (the move "extends" as if wave 2 barely happened) |
| **V**  | `B + (B − C)` | the wave-2 leg's length flipped upward from B — for V-shaped structures |
| **NT** | `C + (C − A)` | the A→C span measured from C — for deep pullbacks that nearly erase wave 1 |

where for an **up** N wave:

- **A** = start of wave 1 (the low)
- **B** = end of wave 1 (the high)
- **C** = end of wave 2 (the pullback low)

For a **down** N wave, mirror everything: A = the high, B = the wave-1 low,
C = the pullback high, and the targets are:

| Target | Formula (down-wave) |
|--------|---------------------|
| N  | `C − (A − B)` |
| E  | `B − (A − B)` |
| V  | `B − (C − B)` |
| NT | `C − (A − C)` |

### 4.2 Worked example

Up-wave: A = 100, B = 110, C = 105 (wave 1 = +10, pullback = −5):

| Target | Calculation | Level |
|--------|-------------|-------|
| N  | 105 + (110 − 100) | **115** |
| E  | 110 + (110 − 100) | **120** |
| V  | 110 + (110 − 105) | **115** |
| NT | 105 + (105 − 100) | **110** |

Down-wave: A = 100, B = 90, C = 95 (wave 1 = −10, pullback = +5):

| Target | Calculation | Level |
|--------|-------------|-------|
| N  | 95 − (100 − 90) | **85** |
| E  | 90 − (100 − 90) | **80** |
| V  | 90 − (95 − 90) | **85** |
| NT | 95 − (100 − 95) | **90** |

Nice property: expanded algebraically, the four formulas are identical for up and
down waves — they only depend on which of A/B/C you combine:

```
N  = B + C − A
E  = 2B − A
V  = 2B − C
NT = 2C − A
```

So in code (e.g. an EA), you can compute all four targets from the three swing
points with one set of formulas and no directional branch.

### 4.3 Choosing between N, E, V, NT

The selection heuristic is about **how deep wave 2 retraces wave 1**:

- **Shallow pullback** (C close to B) → **E**: the trend is strong; the target is
  measured from the top of wave 1, the most aggressive projection.
- **Normal pullback** (C in the middle, ~30–70% of wave 1) → **N**: the
  benchmark — wave 3 mirrors wave 1.
- **Deep pullback** (C close to A) → **NT**: wave 3 only needs to recover the
  A→C span; the most conservative projection.
- **V-shaped structure** (hardly any wave 2 — price reverses straight off B) →
  **V**: the next leg mirrors the last leg (B−C) flipped.

Different books/sources state these rules slightly differently — treat them as
guidance, not gospel. Many practitioners simply plot all four levels and read
them as a **target ladder**: the market "should" at least reach NT, likely reach
N, and only exceptional trends reach E. In this reading, the four calculations
are less a choice than a *range of scenarios*.

### 4.4 Price theory in context

- Targets are always framed by the equilibrium: a target that sits inside the
  Kumo is weak (the cloud will absorb the move); a target beyond a flat Kijun in
  the direction of the trend is the classic continuation profile.
- Price theory is not standalone — it needs Wave Theory to identify A/B/C and
  Time Theory to know *when* the target should arrive. A target reached on a
  change day = mature move; a target reached early = possible blow-off.

---

## 5. The integrated workflow

The three theories form one loop, which is how the original system was meant to
be used (and how modern implementations like LuxAlgo's *Ichimoku Theories* script
package them):

1. **Read the structure** (Wave Theory): label the current shape — I, V, or N,
   and where within it price sits (wave 1, 2, or 3) relative to the equilibrium.
2. **Time the turn** (Time Theory): count kihon suchi bars from the significant
   swing points; mark the next change-day windows.
3. **Frame the move** (Price Theory): compute N/V/E/NT targets from the wave's
   A/B/C points; treat them as the target ladder.
4. **Trade the plan**: with the trend, enter on confirmations (e.g. Tenkan/Kijun
   alignment or pullback-to-Kijun), manage toward the target ladder, and stand
   aside or tighten when a target coincides with a change day.

None of the three theories is a signal by itself — they are filters and framers.
The system is trend-following at heart: it reads best in trending conditions, and
its projections are "planning insight" rather than predictions.

---

## 6. Relationship to this project

The repo's EAs already implement slices of this framework:

| Project feature | Theory | What it does |
|-----------------|--------|--------------|
| **Time Theory Filter** (`InpUseTimeFilter`, `InpTimeCycles`) | Time | Counts consecutive bars since the last Kijun touch on each timeframe; if the count **exactly equals** a kihon suchi number (9/17/26/33/42/51/65/76/83/97/101/129/172/200/226/257/676) the move is "mature" and the breakout entry is skipped. Between cycles, the move has "room to continue to the next number". This is change-day logic used as an entry veto. |
| **H1-M1 Reversion EA** (`InpTimeCycles` = 9/17/26/33 ±2) | Time + Wave | The inverse use: after the move has run a full cycle *and* the Kijun has gone flat, the change day is treated as a turn point — fade the extension back to the flat Kijun. The "Kijun touch" reset is wave-2/equilibrium logic. |
| **Alignment builds** (price + Chikou vs Tenkan/Kijun/Kumo) | Wave (equilibrium) | Trend-following wave-3 continuation: all timeframes must agree that price is on the trend side of the equilibrium. Effectively buys young N-wave legs, not mature ones. |
| Exit logic (Kijun cross, trail) | Wave | Wave-2-invalidation exit: when price crosses back through the equilibrium, the wave count is broken. |

Notable gaps — where the framework *could* extend the EAs (research ideas only,
not implemented):

- **Price Theory targets**: compute N/V/E/NT from the last swing structure and use
  the ladder as TP levels or trailing reference instead of fixed RR targets.
- **Wave-shape classification**: label I/V/N automatically (swing detection on the
  anchor timeframe) to filter entries by wave position (e.g. only wave-3
  continuations).
- **Change-day windows**: replace exact-match cycle veto with a ±tolerance window
  and/or anchor-timeframe-only checks (the reversion EA already uses ±2; the
  README suggests testing the same for the alignment filter).

---

## 7. Limitations and evidence

- **Empirical, not derived.** The kihon suchi numbers come from pre-war Japanese
  market observation. Nothing guarantees they generalize to FX/crypto/H4-M1
  stacks — they are a prior, not a law.
- **Interpretive.** Wave labels, anchor points, and cycle counts are chosen by the
  analyst. The same chart can yield different counts; hindsight bias is a real
  hazard when "validating" these theories visually.
- **No edge found in this project's A/B tests.** The time filter was removed from
  the VPS build because live/backtest A/B runs showed no performance edge
  (entries were blocked without improving win quality). The reversion EA is
  experimental and has not replaced the alignment builds.
- **Self-fulfilling component.** Because many traders use 9/26/52 and watch
  change days, some clustering of turning points around these dates is
  inevitable — which makes the theories hard to falsify either way.
- **Best use:** planning aid — timing windows, target ladders, and "maturity"
  checks layered on top of a concrete, backtestable entry/exit system (which is
  exactly how the repo uses them: optional filters and experimental variants,
  off by default).

---

## 8. References

- [Ichimoku Kinkō Hyō — Wikipedia](https://en.m.wikipedia.org/wiki/Ichimoku_Kink%C5%8D_Hy%C5%8D) — history of Hosoda and the three theories; the 9/26/52 calendar origins.
- [Ichimoku Theories — LuxAlgo](https://www.luxalgo.com/library/indicator/ichimoku-theories/) — modern packaged implementation of Time/Wave/Price theory (kihon suchi & taito suchi modes, I/V/N/P/Y/W waves, N-wave targets).
- [What is Ichimoku Price Theory? — Trade Stocks and Forex](https://www.tradestocksandforex.com/ichimoku-price-theory/) — the N/V/E measurement formulas (citing 2nd Skies Trading, 2013).
- [Ichimoku Hosoda waves' target price indicator (formulas) — MQL5 Freelance job #65312](https://www.mql5.com/en/job/65312) — independent confirmation of the four targets: V = B+(B−C), N = C+(B−A), E = B+(B−A), NT = C+(C−A).
- Manesh Patel, *Trading with Ichimoku Clouds: The Essential Guide to Ichimoku Kinko Hyo Technical Analysis* (Wiley) — English reference work covering the time elements.
- Nicole Elliott, *Ichimoku Charts: An Introduction to Ichimoku Kinko Clouds* (Harriman House) — wave and price theory in English.
- David Linton, *Cloud Charts: Trading Success with the Ichimoku Technique* — alternative English treatment of the technique.
- [Ichimoku Kinko Hyo Philosophy Explained — BriefGuard](https://briefguard.com/en/learn/ichimoku_kinko_hyo_philosophy) — accessible overview of the philosophy behind the three theories.
- This repo: `README.md` (§ Time Theory Filter) and `experiments/EXPERIMENTAL-NOTES.md` (§ 2, H1-M1 Time-Theory Reversion EA) — the project's own implementations and A/B results.
