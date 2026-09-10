# Ichimoku Multi-Timeframe EAs

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-MetaTrader%205-blue.svg)](https://www.metatrader5.com/)
[![Language](https://img.shields.io/badge/Language-MQL5-orange.svg)](https://www.mql5.com/)
[![Strategy](https://img.shields.io/badge/Strategy-Bottom--Up%20Bias%20Stack-green.svg)](https://github.com/n30dyn4m1c/ichimoku-h4-m1-align)

**MetaTrader 5 Expert Advisors for multi-timeframe Ichimoku Kinko Hyo trading, with a bias-driven bottom-up tier stack, ATR profit protection, and equity-scaled position sizing.**

Free MetaTrader 5 Expert Advisors built on Ichimoku Kinko Hyo across a stack
of timeframes. Two main builds sit at the repo root — the VPS deployment and
its MT5 desktop counterpart. Their trading logic is identical; the desktop
build adds terminal `Alert()` popups and the weekly equity reminder.

| EA | File | Model | Stack | Exit signal | Magic |
|----|------|-------|-------|-------------|-------|
| **Bottom-Up Stack — M1-Strict Cloud Bias — VPS** | `ichimoku-h4-m1-vps-ea.mq5` | Bottom-up, M1-strict cloud bias | M1 → H4, five tradable tiers | Kumo touch on the tier's own timeframe | `20260858` |
| **Bottom-Up Stack — M1-Strict Cloud Bias — MT5 Desktop** | `ichimoku-h4-m1-mt5pc-ea.mq5` | Bottom-up, M1-strict cloud bias | M1 → H4, five tradable tiers | Kumo touch on the tier's own timeframe | `20260860` |

Both builds carry their own magic number, so they can run on the same account
— even the same symbol — without touching each other's positions.

> ### 🛡️ Robustness pack (added 2026-08-23)
>
> Both main builds carry a five-part hardening pack (review recommendations
> R2–R6), promoted verbatim from
> `experiments/experimental-bottomup-stack-m1-strict-cloud-bias-robustness-vps-ea.mq5`.
> The trading logic is unchanged; what changed is what happens when the
> broker, the link or the box misbehaves:
>
> - **R2 — unknown-position guard.** A position carrying the EA's magic whose
>   comment no longer names a tier (brokers rewrite or truncate comments on
>   partial fills) used to be invisible: orphaned from break-even, the trail
>   and the cloud exit while the EA opened duplicates behind it. It is now
>   logged once per ticket and blocks new entries on that symbol until it is
>   gone.
> - **R3 — disaster stop.** Every entry carries a wide hard SL at
>   `ATR(tier TF) × InpDisasterATRMult` (default 8), so a gap or a dead VPS
>   cannot run unbounded. See [Risk Protection](#risk-protection).
> - **R4 — peak rebuild.** After a restart mid-trade the chandelier
>   references are rebuilt from tier-timeframe history since the position
>   opened, instead of collapsing to the open price and loosening the trail.
> - **R5 — order robustness.** The filling mode is chosen per symbol (the FOK
>   default breaks on IOC-only brokers), and one order may commit at most
>   `InpMarginUsePct` % of free margin (default 80, was 100).
> - **R6 — twin rule.** The desktop build carries the identical pack; only
>   the magic, the `Alert()` popups and the equity reminder differ.
>
> The pre-pack builds are archived as the `-archived20260823` pair.
> Recommendation R1 — a supersede-invariant guard that would abort a new
> entry while a higher-tier position survives its close attempt — was
> deliberately **not** implemented.
>
> ### 🔄 M1-strict cloud bias (changed 2026-08-20)
>
> On 2026-08-20 the main builds were replaced by the **M1-strict cloud-bias**
> iteration of the bottom-up stack — the most profitable version so far
> (user report 2026-08-20, $100 → $14000 on Jan–Aug 2026 data). The change
> is in the cloud-bias gate (Span A vs Span B): **M1 must be twisted the
> trade's way at BOTH the current bar and the far end of the future cloud**,
> while **M5 and above only look at the future cloud** (the current cloud
> may be either direction). The previous bottom-up bias-stack builds
> (magic `20260850` VPS / `20260852` desktop) are archived as
> `ichimoku-h4-m1-vps-ea-archived20260820.mq5` and
> `ichimoku-h4-m1-mt5pc-ea-archived20260820.mq5`.
>
> ### 🔄 Bottom-up, not top-down (changed 2026-08-18)
>
> The main builds used to be **top-down alignment** EAs: every timeframe from
> the anchor (H4 or H1) down to M1 had to agree before a single trade could
> open. That model is now retired from the repo root — the last top-down VPS
> and desktop builds are preserved in
> [`archives/`](archives/) as `ichimoku-h4-m1-vps-ea-archived20260818.mq5`
> and `ichimoku-h4-m1-mt5pc-ea-archived20260818.mq5`.
>
> The current builds are **bottom-up and bias-driven**. The chain is grown
> *upward* from M1: five tiers (M5, M15, M30, H1, H4) each trade their own
> chain, and **direction** comes from a bias timeframe — H4 as the primary
> bias, with H1 standing in for the lower tiers when H4 has no direction of
> its own — rather than from every timeframe agreeing top-down. A clean
> M1→M30 chain can therefore trade while H4 is still undecided, which the
> top-down model forbade. See
> [How the Strategy Works](#how-the-strategy-works).
>
> Note that this is **not** the same thing as the top-down alignment files
> still in [`experiments/`](experiments/) (`experimental-h4-h1-align-ea.mq5`,
> `experimental-d1-h4-align-ea.mq5`, `experimental-h4-m15-align-ea.mq5` and
> friends) — those remain top-down and are unaffected by this change.

**Repository layout:**

- `ichimoku-h4-m1-vps-ea.mq5` — the live VPS build (bottom-up bias stack; do not modify; see AGENTS.md)
- `ichimoku-h4-m1-mt5pc-ea.mq5` — MT5 desktop build (same logic) with alerts and the weekly equity reminder
- `archives/` — retired builds, including the 2026-08-18 top-down VPS and desktop originals and the 2026-08-14 pre-merge pair
- `experiments/` — experimental EAs, the MS-W1-D1 build, and [EXPERIMENTAL-NOTES.md](experiments/EXPERIMENTAL-NOTES.md)
- `ICHIMOKU-THEORIES.md` — the time/wave/price theory research the filters are drawn from
- `utilities/` — deployment scripts and the Python monitor

> The repository is still named `ichimoku-h4-m1-align` after the original
> top-down H4→M1 build. The name is kept so existing clones, deploy scripts
> and links keep working — it no longer describes the main strategy.

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

Each EA trades a symbol (defaults to `GOLDm#`, configurable) through **five
tiers stacked bottom-up from M1**. A tier opens only when every timeframe
from M1 up to that tier is aligned in one direction — Ichimoku price *and*
Chikou Span confirmation on each — and only when a **bias timeframe grants
the direction**: H4 primarily, with H1 standing in for the lower tiers while
H4 is undecided. Positions exit the moment price **touches the tier's own
kumo edge**, with a break-even stop and a chandelier trail protecting profit
along the way. Every trade risks a fixed percentage of *actual equity*, and
that percentage steps down as the account grows.

**Highlights:**
- ✅ Five bottom-up tiers (M5 / M15 / M30 / H1 / H4) — each one trades its own aligned chain, so a clean fast chain no longer waits on the slow timeframes
- ✅ Bias gate — H4 grants direction to the whole stack, with an H1 stand-in so an undecided H4 doesn't freeze the lower tiers; the H4 tier is additionally gated by D1
- ✅ Per-timeframe Ichimoku alignment (trend + Chikou confirmation) on every rung of the chain
- ✅ Touch-based kumo exit — the trade is cut when price reaches the tier's cloud edge, without waiting for a candle to close
- ✅ Profit protection — a wide disaster stop attached at entry, a break-even stop once in profit, then an ATR chandelier trail (spike-gated on the lower tiers)
- ✅ Equity-percentage risk sizing with three de-risking regimes as the account grows
- ✅ Entry consolidation — when several tiers align at once, only the largest opens and smaller running tiers are closed into it
- ✅ Spread filter to avoid entries during wide/illiquid conditions
- ✅ Multi-symbol support (comma-separated watch list, up to 60 symbols)
- ✅ Crash/restart-safe — per-tier state and chandelier peaks are rebuilt from open positions and tier-timeframe history, so a restart mid-trade resumes correctly
- ✅ Broker-tolerant — per-symbol order filling mode, a capped margin commitment, and a guard that halts new entries on a symbol holding a position the EA can no longer identify
- ✅ Push notifications and journal lines on every entry/exit, plus terminal `Alert()` popups on the desktop build
- ✅ Weekly equity reminder with a suggested profit-withdrawal amount (desktop build only)

---

## VPS Deployment Build

`ichimoku-h4-m1-vps-ea.mq5` is the build that runs unattended on the VPS. It
carries the bottom-up bias stack described in
[How the Strategy Works](#how-the-strategy-works) and is tuned for a cheap,
always-on box:

- **Once-per-minute gating.** `OnTick()` returns immediately unless a new
  closed M1 bar has appeared (`lastMinuteKey = TimeCurrent() / 60`), so the
  EA does almost no work between bars and burns negligible CPU/network on a
  24/7 VPS. The desktop build keeps the same gating, so behaviour is
  identical — only the alerts differ.
- **No popups, no equity reminder.** Every entry, exit and supersede-close
  sends a `SendNotification` push and writes a journal `Print`; the terminal
  `Alert()` popups and the weekly equity reminder are left out entirely so
  the VPS session stays quiet and nothing waits for a click. The
  `*-mt5pc-ea.mq5` desktop build restores both.
- **Verified exits.** `CloseLevelPositions()` re-scans after closing and the
  tier's state is cleared only when zero positions remain — a failed close
  (requote, market halt) is retried on the next M1 bar instead of freeing the
  tier for a fresh entry on top of a live position.
- **Margin-capped sizing.** `CapLotsToMargin()` uses `OrderCalcMargin` to
  shrink the computed volume until it fits inside `InpMarginUsePct` % of free
  margin (default 80), so an oversized tier is trimmed rather than rejected
  by the broker and something is always left in reserve.
- **Quiet, efficient operation.** Failed orders and stop modifications log
  their broker retcode, duplicate symbols in the watch list are ignored, and
  stop modifications that would only tighten microscopically are skipped to
  cut broker request volume.

The VPS build's magic number is `20260858`, carried over from the experiment
it was promoted from (`experiments/experimental-bottomup-stack-m1-strict-
cloud-bias-ea-most-profitable.mq5`) so any position that experiment already
opened keeps being managed. It is distinct from the desktop build's
`20260860` and from the retired magics (`20260850` VPS / `20260852`
desktop), so nothing collides on a shared account.

> **Do not edit this file casually.** It is the deployed production build —
> see [AGENTS.md](AGENTS.md).

### MT5 desktop build (`ichimoku-h4-m1-mt5pc-ea.mq5`)

`ichimoku-h4-m1-mt5pc-ea.mq5` is the desktop counterpart: the same bottom-up
stack, the same M1-strict cloud-bias gating, exits, profit protection and
risk regimes, under its own magic (`20260860`), with two desktop
conveniences added.

**1. Terminal alerts.** Alongside the journal line and the push notification,
the desktop build raises an `Alert()` popup on:

| Event | Example message |
|-------|-----------------|
| Entry | `3:47 PM \| Buy GOLDm# M30 @ 0.42 (bottom-up, bias H1)` |
| Kumo-touch exit | `4:12 PM \| Close GOLDm# Long M30 (kumo touch)` |
| Rejection exit | `4:12 PM \| Close GOLDm# Long M15 (rejection)` |
| Tier superseded by a larger one | `4:15 PM \| Close GOLDm# M15 (superseded by M30)` |
| Exit signalled but positions still open | `4:12 PM \| GOLDm# M30 exit signal but positions still open — will retry` |
| Entry signalled but the order failed | `3:47 PM \| GOLDm# M30 entry signal but order failed, retcode 10019` |

The entry alert names the bias that authorised the trade — `bias H4`,
`bias H1` (the stand-in on a flat H4) or `bias H1x` (the stand-in against an
aligned H4) — so the popup alone tells you which path fired. The "level
closed" confirmation that follows an exit is push + journal only, so a normal
exit produces one popup rather than two.

**2. The weekly equity reminder.** Every `InpCheckDay` (default Friday) the
EA compares live equity against a baseline stored in a terminal global
variable keyed by account login — so it survives restarts, recompiles and
re-attaches. If the profit over that baseline clears `InpMinProfitTrigger`,
it alerts with a suggested withdrawal of `InpWithdrawProfitPct`% of the
profit (default 50%) and, when `InpSendPush` is on, pushes the same message
to the MT5 mobile app:

```
Profit: 412.60. Suggest withdrawing: 206.30
```

It is a nudge to bank gains periodically — it is informational only and
**never moves money**. It is evaluated once per new H4 bar and fires at most
once a day. Set `InpResetBaseline = true` once (then back to `false`) to
re-baseline on current equity after a deposit or a withdrawal.

Use the desktop build on an always-on desktop or laptop where you want to see
what the EA is doing; use the VPS build on the VPS.

### Deploying the VPS build (`utilities/deploy.sh`)

`utilities/deploy.sh` downloads the VPS EA (`ichimoku-h4-m1-vps-ea.mq5`)
straight into the local MT5 `MQL5/Experts` folder — no copy-paste or
clipboard needed (handy over VNC where clipboard sync is flaky). Run it on
the machine that runs MT5 (the VPS):

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
  compile the file, then remove and re-attach (or restart MT5) so the
  running EA picks up the new `.ex5` build.

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

> **Migrating from an older build.** The filename never changes, so an
> existing `deploy.sh` / `auto-deploy.sh` setup picks a new build up with no
> changes — but the magic number has moved twice: `20260846`/`20260847`
> (top-down) → `20260850` (bottom-up bias stack) → **`20260858`** (the
> current M1-strict cloud-bias build). A position still open under an old
> magic is invisible to the new build and will never be managed or closed by
> it, so close those positions (or manage them out by hand) before or
> immediately after the switch. Recompile with F7 and re-attach the EA so the
> running instance is the new `.ex5`.

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

### The bottom-up tier stack

The stack has six timeframes — **M1, M5, M15, M30, H1, H4** — and five
*tradable tiers*. A tier is named after its top timeframe, and it opens only
when the **whole chain from M1 up to that timeframe** is aligned in one
direction:

| Tier | Chain that must align | Notes |
|------|-----------------------|-------|
| **M5** | M1 + M5 | Fastest tier |
| **M15** | M1 + M5 + M15 | |
| **M30** | M1 + M5 + M15 + M30 | Default ceiling for the H1 stand-in bias |
| **H1** | M1 + M5 + M15 + M30 + H1 | |
| **H4** | M1 + M5 + M15 + M30 + H1 + H4 | Additionally gated by the D1 bias |

**M1 never trades on its own** — it is only the foot of the chain.

This is the inverse of the retired top-down builds. There, one trade opened
only when *everything* down to M1 agreed, so a single disagreeing high
timeframe silenced the EA completely. Here each tier stands on its own chain,
so the M5 and M15 tiers keep working through stretches when H4 and H1 are
undecided.

### Per-timeframe alignment

A timeframe counts as **bullish** when, on its last confirmed bar:

| Level | Price condition | Chikou (lagging span) condition |
|-------|-----------------|----------------------------------|
| Tenkan-sen | Price > Tenkan | Chikou > Tenkan at its plotted position |
| Kijun-sen | Price > Kijun | Chikou > Kijun at its plotted position |
| Kumo (cloud) | Price above cloud top | Chikou above cloud top at its plotted position |
| Price action | — | Chikou above the high of the candle at its plotted position |

**Bearish** is the exact mirror (price and Chikou below every level).
`CheckAlign()` uses these `CopyBuffer` offsets to read it:

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

### The bias gate — H4 primary, H1 stand-in

An aligned chain is *permission to consider* a trade; the **bias** decides
whether it is allowed and in which direction.

**H4 is the bias for the whole stack** (`InpH4Bias`, default on): H4 bullish
allows buys only, H4 bearish sells only. On its own that rule freezes all
five tiers whenever H4 is unaligned, M5 included — and H4 spends a large
share of its time neither clearly above nor clearly below its own
tenkan/kijun/cloud, so a perfectly clean M1→M30 chain produced nothing at
all during those stretches.

**The H1 stand-in** (`InpH1BiasMode`, default `H1BIAS_FLAT_H4`) fixes that:
when H4 carries no direction, a tier at or below `InpH1BiasMaxTier` (default
M30) may still open, provided **H1 itself is aligned** with the trade — the
same price + chikou test, one timeframe down. With
`InpH1BiasCloudCheck` on (default), the H1 kumo must carry the trade's bias
as well.

| H4 state | Tier ≤ `InpH1BiasMaxTier` | Tier above it (H1 / H4) |
|----------|---------------------------|--------------------------|
| Aligned **with** the trade | opens — logged `bias H4` | opens — logged `bias H4` |
| **Flat** (unaligned / in its cloud) | opens **if H1 is aligned** — logged `bias H1` | blocked |
| Aligned **against** the trade | blocked, unless `InpH1BiasMode = H1BIAS_ALWAYS` — then logged `bias H1x` | blocked |

The **H4 tier can never use the stand-in** — it always needs H4 itself, and
on top of that the **D1 filter** (`InpD1Filter`, default on): D1 bullish
allows only H4-tier buys, D1 bearish only sells, and D1 inside its cloud
blocks the H4 tier entirely.

Every entry logs the bias that authorised it (`bias H4` / `bias H1` /
`bias H1x`), so the journal separates stand-in trades from H4 ones without
having to reconstruct the H4 state afterwards.

**Modes:**

| `InpH1BiasMode` | Value | Behaviour |
|-----------------|-------|-----------|
| `H1BIAS_OFF` | 0 | No stand-in — H4 governs every tier on its own |
| `H1BIAS_FLAT_H4` | 1 (default) | Stand in only while H4 is flat; never against an aligned H4 |
| `H1BIAS_ALWAYS` | 2 | Stand in even against an aligned H4 — genuinely counter-trend on the lower tiers |

Setting `InpH1BiasMode = H1BIAS_OFF` is the A/B baseline: it reduces entry
behaviour to "H4 governs everything".

### Cloud bias gate

Independently of the directional bias, `InpCloudBiasEnabled` (default on)
requires the kumo itself to carry the trade's bias — Span A above Span B for
a long, below for a short — on **the tier's own timeframe and the timeframe
directly below it**. The test is applied twice per timeframe: at the current
bar *and* at the far end of the projected cloud (`Kijun` bars ahead), so a
cloud that is about to twist against the trade blocks the entry as well. The
same double check is applied to the H1 kumo when `InpH1BiasCloudCheck` is on.

### Entry consolidation

Tiers are evaluated from the largest down, and **only the largest aligned
tier opens**. Any smaller tier already running on that symbol is closed first
and reported as *superseded* — so at most one position per symbol is live at
a time, always the highest tier that qualifies. Example: M15 is running and
then M30 aligns as well — the M15 trade closes and only M30 opens.

### Exit Logic

- **Kumo touch.** A trade is closed as soon as price **touches the tier
  timeframe's cloud edge** — no waiting for a candle to close inside the
  kumo. A long exits when the bid touches the cloud's upper edge; a short
  when the ask touches the lower edge.
- **Rejection candle** (`InpRejectionExit`, default off). A very strong
  rejection candle against the trade on the tier's timeframe also closes it.
  All four conditions must hold on the last closed bar: the candle closes
  against the trade, it sweeps the swing extreme of the previous
  `InpRejSwingBars` bars, its wick into that sweep is at least
  `InpRejWickPct` of the candle's total range, and it closes back within the
  outermost `InpRejClosePct` of that range.
- **Superseded.** A running tier is closed when a larger tier opens on the
  same symbol (see [Entry consolidation](#entry-consolidation)).

Exits are **verified**: the tier's state is cleared only once a re-scan finds
no positions left, so a failed close is retried on the next M1 bar rather
than freeing the tier for a fresh entry on top of a live position.

### Risk Protection

**The entry stop is a disaster stop, not a working stop.** Since 2026-08-23
every entry carries a wide hard SL at `ATR(tier TF) × InpDisasterATRMult`
(default 8.0) — far enough away that it never takes a trade the strategy
would have managed out, close enough that a gap, a dead VPS or a broken link
cannot run unbounded. A missing stop self-heals on the next management pass.
The trade otherwise runs until one of the exits above fires, and the real
protection is a two-stage layer that engages once the trade is in profit,
using ATR computed on **each tier's own timeframe**:

- **Break-even.** Once profit reaches the ATR threshold — `InpBEProfitATR`
  (default 1.0 × ATR) on M5/M15/M30, the tighter `InpBEProfitH1H4` (default
  0.5 × ATR) on H1/H4 — the stop moves to entry plus `InpBECoverPoints`
  (default 15 points, to cover the spread). One-shot per trade.
- **Chandelier trail.** The H1 and H4 tiers trail the stop behind the peak
  once profit clears `InpTrailActivateATR` (default 0.5 × ATR), at a distance
  of `InpTrailATR` × ATR. The M5/M15/M30 tiers use a **spike-gated** version
  that only arms on a sharp move (`InpSpikeLockATR`, default 2.0 × ATR), so
  ordinary noise doesn't strangle a young trade. The trail only ever
  tightens, and it never sits inside the broker's minimum stop distance.

`InpMaxSpreadPoints` (default 60) skips entries when the live spread is too
wide; set it to `0` to disable the filter.

> The disaster stop is a backstop, not a risk budget. Position size is
> measured against `InpRiskATRMult` (2 × ATR), while the stop sits at 8 ×
> ATR — so a trade that runs all the way to it loses roughly four times the
> nominal risk percentage. Day-to-day the exit is meant to be the kumo touch,
> and that is checked once per closed M1 bar: between two M1 closes a fast
> adverse move is capped only by the disaster stop. Size accordingly and test
> on demo first.

### Equity-Based Position Sizing

Every trade risks a **fixed percentage of actual equity at the moment of
entry**, measured against a reference distance of
`ATR(tier TF) × InpRiskATRMult` (default 2.0). That distance is a *sizing
basis only* — the stop actually attached to the order is the much wider
disaster stop described above.

The percentage steps down as the account grows, across three regimes:

| Tier | Regime 1 — equity < `InpRiskTier2At` ($7,000) | Regime 2 — $7,000 to $13,000 | Regime 3 — equity ≥ `InpRiskTier3At` ($13,000) |
|------|------------------------------------------------|------------------------------|------------------------------------------------|
| M5 | 1.0% | 0.5% | 0.1% |
| M15 | 1.0% | 0.5% | 0.1% |
| M30 | 5.0% | 2.5% | 0.2% |
| H1 | 10.0% | 5.0% | 1.0% |
| H4 | 20.0% | 10.0% | 2.0% |

The table is deliberately aggressive on the small account and de-risks hard
as equity builds. There are no multipliers and no streak compounding. If ATR
or tick data can't be read, the EA falls back to `InpFixedLots` (default
0.10). `CapLotsToMargin()` then shrinks the volume with `OrderCalcMargin` so
the order fits free margin instead of being rejected.

> **These numbers are not a recommendation.** 20% of equity on a single H4
> trade with no entry stop is a very large bet, tuned for a specific small
> account that could afford to lose it. Edit the `InpRiskPct*` inputs to fit
> your own balance and risk appetite before running this anywhere near real
> money.

### Weekly Equity Reminder

Desktop build only — the [VPS build](#vps-deployment-build) leaves it out.
Every `InpCheckDay` (default Friday), the EA compares current equity to a
stored baseline; if the profit over that baseline exceeds
`InpMinProfitTrigger`, it raises an alert (and a push, when `InpSendPush` is
on) suggesting a withdrawal of `InpWithdrawProfitPct`% of the profit. It is a
nudge to bank gains periodically, it fires at most once a day, and it does
**not** withdraw anything automatically. Full description in
[MT5 desktop build](#mt5-desktop-build-ichimoku-h4-m1-mt5pc-eamq5).

---

## Getting Started

### Requirements

- [MetaTrader 5](https://www.metatrader5.com/) terminal
- A broker account (demo strongly recommended for testing) with the symbol(s) you intend to trade available

### Installation

1. Download the build you want from this repository. For hands-on desktop trading use `ichimoku-h4-m1-mt5pc-ea.mq5` — it adds terminal alerts and the weekly equity reminder. For unattended 24/7 deployment use `ichimoku-h4-m1-vps-ea.mq5`; it can share the account with the desktop build — see [VPS Deployment Build](#vps-deployment-build).
2. Open MetaTrader 5 → **File → Open Data Folder**.
3. Copy the file into `MQL5/Experts/`.
4. In MT5, open **Navigator → Expert Advisors**, right-click and **Refresh**, or restart MT5.
5. Compile it: open the file in **MetaEditor** (F4 in MT5) and press **Compile** (F7). Confirm there are no errors.
6. Drag the EA onto a chart of the symbol you configured (e.g. `GOLDm#`). The EA manages all symbols in its `Symbols` input internally, so the chart it's attached to is just an anchor — one instance is enough.
7. Make sure **AutoTrading** is enabled (toolbar button) and, in the EA's **Common** tab, that "Allow live trading" and "Allow DLL imports" (if prompted) are checked as needed.
8. Enable **Allow WebRequest**/notifications if you want push alerts — set this up under **Tools → Options → Notifications** with your MetaQuotes ID.

### Recommended First Steps

- Run it in the **Strategy Tester** first (MT5 supports multi-symbol/multi-timeframe testing) to see how the tier stack behaves historically on your symbol.
- Then run it on a **demo account** for at least a few weeks before considering live capital.
- Review and adjust the risk regimes (`InpRiskPct*`, `InpRiskTier2At`, `InpRiskTier3At`) — the shipped percentages were tuned for a specific small account and are almost certainly not appropriate for your balance or risk appetite. Remember there is **no entry stop loss**: the percentage is sized against an ATR reference distance, not a stop the broker will honour.
- A/B the H1 stand-in bias against the H4-only behaviour by running the same period with `InpH1BiasMode = H1BIAS_OFF`, so you can see exactly which trades the stand-in adds and what they cost.

---

## Configuration (Inputs)

Both builds share this input set; the equity-reminder group exists only on
the desktop build.

**Core**

| Parameter | Default | Description |
|-----------|---------|--------------|
| `Symbols` | `GOLDm#` | Comma-separated list of symbols to watch (up to 60) |
| `Tenkan` | 9 | Ichimoku Tenkan-sen period |
| `Kijun` | 26 | Ichimoku Kijun-sen period |
| `SenkouB` | 52 | Ichimoku Senkou Span B period |
| `Slippage` | 30 | Maximum allowed slippage, in points |

**Risk Management (per tier, % of actual equity)**

| Parameter | Default | Description |
|-----------|---------|--------------|
| `InpFixedLots` | 0.10 | Fallback volume when ATR/tick data for sizing is unavailable |
| `InpRiskATRMult` | 2.0 | Reference distance for sizing = ATR(tier TF) × this (sizing basis only — the attached stop is the wider disaster stop) |
| `InpRiskTier2At` | 7000.0 | Equity at which risk drops to regime 2 (half) |
| `InpRiskTier3At` | 13000.0 | Equity at which risk drops to regime 3 (tiny) |
| `InpRiskPctM5` / `M15` / `M30` / `H1` / `H4` | 1 / 1 / 5 / 10 / 20 | Regime 1 risk % per tier |
| `InpRiskPctM5_T2` … `InpRiskPctH4_T2` | 0.5 / 0.5 / 2.5 / 5 / 10 | Regime 2 risk % per tier |
| `InpRiskPctM5_T3` … `InpRiskPctH4_T3` | 0.1 / 0.1 / 0.2 / 1 / 2 | Regime 3 risk % per tier |
| `InpMarginUsePct` | 80.0 | Maximum % of free margin one order may commit (R5) |

**Entry Filters**

| Parameter | Default | Description |
|-----------|---------|--------------|
| `InpCloudBiasEnabled` | `true` | Require Span A vs Span B bias on the tier's timeframe and the one below it |
| `InpH4Bias` | `true` | H4 is the bias for the whole stack (H4 flat = no trades unless the H1 bias stands in) |
| `InpD1Filter` | `true` | D1 filter on the H4 tier: H4 trades only with D1; D1 in the cloud = no H4 trades |
| `InpMaxSpreadPoints` | 60 | Max spread (points) to allow an entry; `0` disables the filter |

**H1 Bias**

| Parameter | Default | Description |
|-----------|---------|--------------|
| `InpH1BiasMode` | `H1BIAS_FLAT_H4` (1) | `0` = off (H4 governs every tier), `1` = stand in only while H4 is flat, `2` = stand in even against an aligned H4 |
| `InpH1BiasMaxTier` | `H1TIER_M30` (2) | Highest tier allowed to enter on the H1 bias — `0` M5, `1` M15, `2` M30, `3` H1. The H4 tier is deliberately not an option |
| `InpH1BiasCloudCheck` | `true` | Also require the H1 kumo to carry the trade's bias |

**Profit Protection**

| Parameter | Default | Description |
|-----------|---------|--------------|
| `InpATRPeriod` | 14 | ATR period — each tier uses its own timeframe's ATR |
| `InpBEProfitATR` | 1.0 | Break-even arms once profit ≥ this × ATR (M5/M15/M30 tiers) |
| `InpBEProfitH1H4` | 0.5 | Break-even arms once profit ≥ this × ATR (H1/H4 tiers — tighter) |
| `InpBECoverPoints` | 15 | Points beyond entry for the break-even stop (covers the spread) |
| `InpSpikeLockATR` | 2.0 | Spike-gated chandelier arms once profit ≥ this × ATR (M5/M15/M30) |
| `InpTrailActivateATR` | 0.5 | H1/H4 chandelier trail arms once profit ≥ this × ATR |
| `InpTrailATR` | 1.0 | Trail distance behind the peak, × ATR (tier timeframe) |

**Disaster Stop**

| Parameter | Default | Description |
|-----------|---------|--------------|
| `InpDisasterStopEnabled` | `true` | Attach the wide hard SL at entry (R3) — turn it off to reproduce the pre-2026-08-23 stopless behaviour |
| `InpDisasterATRMult` | 8.0 | Disaster stop distance = ATR(tier TF) × this |

**Rejection Exit**

| Parameter | Default | Description |
|-----------|---------|--------------|
| `InpRejectionExit` | `false` | Close a trade on a very strong rejection candle against it on the tier's timeframe |
| `InpRejSwingBars` | 8 | Recent swing window (bars) the rejection candle must sweep |
| `InpRejWickPct` | 0.5 | Wick must be ≥ this fraction of the candle's total range |
| `InpRejClosePct` | 0.35 | Close must sit in the outermost this fraction of the range |

**Equity Reminder — desktop build only**

| Parameter | Default | Description |
|-----------|---------|--------------|
| `InpMinProfitTrigger` | 5.0 | Minimum profit over the baseline before the reminder fires |
| `InpWithdrawProfitPct` | 50.0 | Suggested withdrawal as a percentage of that profit |
| `InpCheckDay` | Friday | Day of the week the reminder is evaluated |
| `InpResetBaseline` | `false` | Set to `true` once to re-baseline on current equity |
| `InpSendPush` | `true` | Also push the equity reminder to the MT5 mobile app |

> The VPS build has no equity-reminder group at all — it ends at the
> rejection-exit inputs.

## Timeframe Stack and Tiers

The main builds evaluate the stack **bottom-up**: the chain is grown from M1
upward, and the tier is named after the highest timeframe in its chain.

| Index | Timeframe | Role |
|-------|-----------|------|
| 0 | M1 | Foot of every chain — never trades on its own |
| 1 | M5 | Tier 1 |
| 2 | M15 | Tier 2 |
| 3 | M30 | Tier 3 — default ceiling for the H1 stand-in bias |
| 4 | H1 | Tier 4, and the **stand-in bias** timeframe |
| 5 | H4 | Tier 5, and the **primary bias** for the whole stack |
| — | D1 | Not tradable — the extra bias filter on the H4 tier only |

Tiers are checked largest first, and only the largest aligned tier opens (see
[Entry consolidation](#entry-consolidation)).

### Top-down stacks (archived and experimental builds)

The retired top-down builds in [`archives/`](archives/) and the top-down
alignment EAs in [`experiments/`](experiments/) work the other way — every
timeframe from the anchor down to M1 must agree before one trade opens:

**H4-M1 (archived VPS/desktop, `InpTopTF = TOP_H4`):**

| Index | Timeframe | Role |
|-------|-----------|------|
| 0 | H4 | Highest — trend anchor |
| 1 | H1 | Intermediate |
| 2 | M30 | Intermediate |
| 3 | M15 | Exit reference |
| 4 | M5 | Fine filter |
| 5 | M1 | Trigger bar |

**H1-M1 (archived VPS/desktop, `InpTopTF = TOP_H1`):**

| Index | Timeframe | Role |
|-------|-----------|------|
| 0 | H1 | Highest — trend anchor |
| 1 | M30 | Intermediate |
| 2 | M15 | Intermediate |
| 3 | M5 | Exit reference |
| 4 | M1 | Trigger bar |

**MS-W1-D1 Alignment EA (`experiments/ichimoku-ms-w1-d1-ea.mq5`):**

| Index | Timeframe | Role |
|-------|-----------|------|
| 0 | MS | Highest — trend anchor |
| 1 | W1 | Intermediate |
| 2 | D1 | Lowest — bar-gating and exit reference (default) |

---

## Technical Notes

- **Magic numbers:** `20260858` (VPS M1-strict cloud-bias build), `20260860`
  (MT5 desktop M1-strict cloud-bias build). Each EA identifies and manages
  only its own positions by magic number, so the two builds can run together
  on one account — even one symbol — without interfering with each other,
  with other EAs, or with manual trades. The retired bottom-up bias-stack
  builds used `20260850` (VPS) / `20260852` (desktop), and the retired
  top-down builds `20260846` / `20260847` (VPS) and `20260830` / `20260831`
  (desktop). Those numbers are free as far as the *main* builds go, but
  several files in `experiments/` still use them — see the clash warning in
  [Experimental EAs](#experimental-eas) — so check before running an archived
  or experimental build alongside a current one.
- **Per-tier state recovery:** `SyncStateFromPositions()` rebuilds every
  tier's direction, entry reference, peak and break-even memory from the open
  positions filtered by magic number, using the position comment
  (`Exp Buy M15`, `Exp Sell M30`, …) to tell tiers apart. A terminal restart,
  VPS reboot, or a position closed manually mid-trade therefore resumes on
  the right tier with no stale state.
- **Per-symbol M1 gating:** the whole loop runs at most once a minute, and
  each symbol re-evaluates only on a newly closed M1 bar of its own.
- **Chikou Span handling:** the Chikou value is read directly from `close[1]`
  in price data rather than the Ichimoku buffer, avoiding an offset bug where
  reading Chikou from the indicator buffer silently degrades it into a lagged
  copy of the price check. See the inline comments in `CheckAlign()` for the
  full offset derivation.
- **Bias logging:** entries record which bias authorised them — `bias H4`,
  `bias H1`, or `bias H1x` — so H1 stand-in trades can be separated from H4
  ones in the journal without reconstructing the H4 state after the fact.

---

## Archived Builds

[`archives/`](archives/) keeps every build that has been retired from the
repo root, so a deployment can always be rolled back and old behaviour can be
re-read:

| File | What it is |
|------|------------|
| `ichimoku-h4-m1-vps-ea-archived20260823.mq5` | The VPS build as it stood before the **robustness pack** (R2–R6) was promoted into it on 2026-08-23 — same M1-strict cloud-bias strategy, magic `20260858` |
| `ichimoku-h4-m1-mt5pc-ea-archived20260823.mq5` | Its desktop twin from the same promotion (magic `20260860`) |
| `ichimoku-h4-m1-vps-ea-archived20260820.mq5` | The **bottom-up bias-stack VPS build** replaced on 2026-08-20 (H4 bias + H1 stand-in, kumo-touch exits; magic `20260850`), superseded by the M1-strict cloud-bias build |
| `ichimoku-h4-m1-mt5pc-ea-archived20260820.mq5` | Its desktop twin, replaced the same day (magic `20260852`) |
| `ichimoku-h4-m1-vps-ea-archived20260818.mq5` | The **top-down** dual-mode VPS build replaced on 2026-08-18 (`InpTopTF` = `TOP_H4` / `TOP_H1`, kijun-start filter, BE30, M15/M5 Kijun-cross exit; magics `20260846` / `20260847`) |
| `ichimoku-h4-m1-mt5pc-ea-archived20260818.mq5` | Its desktop twin, replaced the same day (magics `20260830` / `20260831`) |
| `ichimoku-h4-m1-vps-ea-archived20260814.mq5`, `ichimoku-h1-m1-vps-ea-archived20260814.mq5` | The two separate VPS builds that were merged into the dual-mode file on 2026-08-14 |
| `ichimoku-h4-m1-mt5pc-ea-archived20260814.mq5`, `ichimoku-h1-m1-mt5pc-ea-archived20260814.mq5` | Their desktop counterparts from the same merge |
| `ichimoku-h4-m1-ea-archived20260811.mq5`, `ichimoku-h1-m1-ea-archived20260811.mq5` | The oldest standard top-down alignment builds |

Archived files are kept as-is and are not maintained. **Check the magic
number before running one alongside a current build.** Most archived builds
carry their own number and will not collide, but the `-archived20260823`
pair shares `20260858` / `20260860` with the live builds — running either of
them next to the current VPS or desktop EA means two EAs managing one set of
positions. Two archived builds of the same generation clash the same way.

---

## Experimental EAs

Every experimental strategy lives in [`experiments/`](experiments/), prefixed
`experimental-` so it can never be confused with the two main builds at the
repo root. They are newer and less tested than the main builds — treat them
as research code and demo-test them first.

The full write-up for each family is in
**[experiments/EXPERIMENTAL-NOTES.md](experiments/EXPERIMENTAL-NOTES.md)**;
the tables below are the index. The § column points at the notes section.

> **Magic numbers are not all unique.** Forks were sometimes given a number a
> sibling already used. Files sharing a magic **must not run on the same
> account at the same time** — they would each try to manage the other's
> positions. The known clashes are `20260848`, `20260850`, `20260851` and
> `20260854` (marked ⚠️ below), plus the deliberate `20260858` lineage, which
> the live VPS build also uses.

### Bottom-up stack family (the current model)

The lineage that produced the live builds. Each row forks the row above it
unless stated otherwise.

| File (`experiments/`) | Magic | What it changes | § |
|---|---|---|---|
| `experimental-bottomup-stack-ea.mq5` | `20260848` ⚠️ | The original five-tier bottom-up build — M1 grown upward, each tier trading its own chain | 19 |
| `experimental-bottomup-stack-ea-very-profitable.mq5` | `20260848` ⚠️ | The snapshot the family settled into; parent of the hardening forks below | 19 |
| `experimental-bottomup-stack-ea-very-profitable-intrabar.mq5` | `20260853` | M30/H1/H4/D1 alignment read on the **forming** candle, with close confirmation against fakeouts; M1–M15 still wait for the close | 33 |
| `experimental-bottomup-stack-ea-very-profitable-windows-laptop.mq5` | `20260850` ⚠️ | Multi-level positions restored, plus a disaster stop (4 × ATR) and a per-tier re-entry cooldown | 32 |
| `experimental-bottomup-stack-ea-very-profitable-windows-laptop-minimal.mq5` | `20260852` | Structural fixes **only** — one position per symbol, disaster stop, per-tick kumo exit. Written after backtests showed the filtered forks did worse than the raw snapshot | 32 |
| `experimental-bottomup-stack-ea-very-profitable-windows-laptop-overextension-protection.mq5` | `20260851` ⚠️ | Adds an H4 pullback guard — turtle-soup sweep and rejection-candle exhaustion checks on every tier | 32 |
| `experimental-bottomup-stack-office-pc-v2.mq5` | `20260849` | Safety layer over the snapshot: real SL at entry, per-trade risk ceiling, drawdown-aware sizing, daily-loss circuit breaker | 32 |
| `experimental-bottomup-stack-h1-bias-ea.mq5` | `20260850` ⚠️ | H1 stands in for the bias when H4 is flat. **Promoted 2026-08-18** to the main builds | 20 |
| `experimental-bottomup-stack-d1-ladder-ea.mq5` | `20260851` ⚠️ | Adds a D1 tier, a flat-kijun filter on every timeframe, and a D1 → H4 → H1 bias ladder | 21 |
| `experimental-bottomup-stack-standard-account-ea.mq5` | `20260854` ⚠️ | Re-scales the H1-bias fork's money management for a full-size account funded with ~$100 — quarter risk, min-lot gate that skips rather than rounds up | 22 |
| `experimental-bottomup-stack-news-blackout-vps-ea.mq5` | `20260854` ⚠️ | Flattens positions before high-impact ("red folder") events from the terminal's built-in calendar and blocks entries until after them | 34 |
| `experimental-bottomup-stack-m1-tier-ea.mq5` | `20260856` | Makes M1 a sixth **tradable** tier — opens on M1 alignment alone, exits on the M1 cloud | 23 |
| `experimental-bottomup-stack-refined-ea.mq5` | `20260857` | Consolidation hardening; the cloud-bias gate looks only at the projected kumo 26 bars ahead | 24 |
| `experimental-bottomup-stack-m30-bias-ea-third-most-profitable.mq5` | `20260855` | Redefines a valid kumo breakout on **M1–D1** (price + chikou beyond the kumo + tenkan/kijun twist) and adds an M30 last-resort bias with tenkan-close exits. Third most profitable (user report, 2026-08-20) | 25 |
| `experimental-bottomup-stack-m1-strict-cloud-bias-ea-most-profitable.mq5` | `20260858` | M1 must be twisted the trade's way at **both** the current bar and the far end of the future cloud; M5+ check the future cloud only. Most profitable so far — **promoted 2026-08-20** to the main builds | 26 |
| `experimental-bottomup-stack-m1m5-strict-cloud-bias-ea-second-most-profitable.mq5` | `20260858` | M5 joins the full current+future check | 27 |
| `experimental-bottomup-stack-m1m5m15-strict-cloud-bias-ea.mq5` | `20260858` | M15 joins the full check | 28 |
| `experimental-bottomup-stack-m1m5m15m30-strict-cloud-bias-ea.mq5` | `20260859` | M30 joins the full check; only H1 and H4 stay future-only | 29 |
| `experimental-bottomup-stack-m1-strict-cloud-bias-btcusd-ea.mq5` | `20260861` | BTCUSD# test fork of the live build: spread gate off, BE cover raised to 300 points, full cloud check on M1/M5/M15 | 35 |
| `experimental-bottomup-stack-standard-account-m1m5m15-cloud-ea.mq5` | `20260862` | Forks the **live** build for a ~$100 full-size account: hard 2 × ATR stop at entry, risk priced against it, 5% per-trade cap, min-lot skip, daily-loss / drawdown / cooldown breakers | 30 |
| `experimental-bottomup-stack-m1-strict-cloud-bias-robustness-vps-ea.mq5` | `20260863` | The robustness pack (R2–R6) hardening the live build. **Promoted 2026-08-23** into the main builds | 36 |
| `experimental-bottomup-stack-market-profile-vps-ea.mq5` | `20260864` | **Newest.** Adds a TPO market-profile layer measured on M30 — POC, value area, daily key levels, session stacking, day-shape read — driving entries through an AUTO regime dispatcher | 37 |

### Top-down alignment builds

The retired model: every timeframe from the anchor down to M1 must agree
before one trade opens. Kept for reference and A/B work.

| File (`experiments/`) | Magic | What it is | § |
|---|---|---|---|
| `experimental-h4-m1-po3-ea.mq5` | `20260502` | H4-M1 alignment plus a Power-of-Three dealing-range filter | 1 |
| `experimental-h4-m15-align-ea.mq5` | `20260724` | H4 anchor, stack trimmed to M15 | 5 |
| `experimental-h4-m15-vps-ea.mq5` | `20260825` | VPS-style build of the H4-M15 clone — push/journal only, no popups | 11 |
| `experimental-h4-m1-be30-ea.mq5` | `20260811` | Break even + spread cover once a trade is profitable within 30 minutes of entry | 8 |
| `experimental-h1-m1-be30-ea.mq5` | `20260813` | The same BE30 rule on the H1 anchor | 8 |
| `experimental-h4-m1-be15-ea.mq5` | `20260812` | Break even after 15 continuous minutes in profit, with a kihon-suchi time filter | 9 |
| `experimental-h4-m1-pullback-ea.mq5` | `20260807` | Re-enters the trend on a bounce off the H4 kijun after a full-alignment breakout | 7 |
| `experimental-h4-m1-news-filter-ea.mq5` | `20260832` | Closes an hour before every high-impact release, flat until five minutes after | 13 |
| `experimental-h4-m1-kijun-start-vps-ea.mq5` | `20260846` | The dual-mode H4/H1 VPS merge with the kijun-start filter | 18 |
| `experimental-h4-m1-no-m30-ea.mq5` | `20260822` | Alignment-filter pruning — M30 dropped from the chain | 11 |
| `experimental-h4-m1-no-m30-m1-ea.mq5` | `20260823` | M30 and M1 dropped | 11 |
| `experimental-h4-m1-no-m30-m5-m1-ea.mq5` | `20260824` | M30, M5 and M1 dropped | 11 |
| `experimental-h4-m1-no-m1-ea.mq5` | `20260828` | M1 dropped | 11 |
| `experimental-h1-m1-no-m1-ea.mq5` | `20260829` | M1 dropped, H1 anchor | 11 |
| `experimental-h4-h1-align-ea.mq5` | `20260817` | Symbol-agnostic H4-H1 swing build | 31 |
| `experimental-d1-h4-align-ea.mq5` | `20260816` | The same stack anchored one scale up, D1 → H4 | 31 |
| `experimental-h4-h1-ignition-ea.mq5` | `20260821` | Equivalence-aware compression/breakout ("ignition") entry engine | 10 |
| `experimental-h4-h1-per-timeframe-ea.mq5` | `20260826` / `20260827` | Each timeframe trades its own breakout and exits on a tenkan close | 12 |

### Other models

| File (`experiments/`) | Magic | What it is | § |
|---|---|---|---|
| `experimental-h1-m1-reversion-ea.mq5` | `20260722` | Ichimoku time-theory mean reversion rather than trend following | 2 |
| `experimental-m1-m5-breakout-ea.mq5` | `20260717` | Fast M1-M5 breakout alignment | 3 |
| `experimental-m30-m1-breakout-ea.mq5` | `20260723` | The same breakout on a shorter M30 anchor | 4 |
| `experimental-kumo-breakout-ea.mq5` | `20260845` | Kumo breakout with a flat-kijun filter | 17 |
| `experimental-structure-map-ea.mq5` | `20260834` | Drops the alignment gate entirely: maps price against every Ichimoku structure across up to six timeframe slots, scores the read into a conviction number, and takes the continuation bounce only when stop, room and reward:risk all work out | 14 |
| `experimental-structure-map-d1-ea.mq5` | `20260835` | The same engine one scale up — daily structures, M15 timing | 15 |
| `ichimoku-ms-w1-d1-ea.mq5` | `20260806` | The MS → W1 → D1 long-horizon build described [above](#ms-w1-d1-alignment-build); watched by the Python monitor rather than run on a VPS | 6 |

### Karen Peloille family

Five builds mechanising the system from *Trading with Ichimoku* (ch. 3–4):
the Kijun break is the signal, the Lagging Span validates it, and entry is a
Tenkan (or Kijun) pullback on the management timeframe. All are documented in
notes section 16.

| File (`experiments/`) | Magic | Her strategy |
|---|---|---|
| `experimental-karen-multitf-ea.mq5` | `20260840` | Medium-term, D1 → H4 → H1 |
| `experimental-karen-vst-ea.mq5` | `20260841` | Very-short-term, H1 → M15 → M5 |
| `experimental-karen-kijun-retest-ea.mq5` | `20260842` | Kijun retest |
| `experimental-karen-countertrend-ea.mq5` | `20260843` | Counter-trend at the Senkou Span B |
| `experimental-karen-candle3-ea.mq5` | `20260844` | Three-candle impulse |

> The per-symbol US30, Silver and BTCUSD variants of the H4-H1 swing EA were
> removed from the repo — their per-symbol tuning is superseded by the
> symbol-agnostic H4-H1 builds, which accept any symbol through the `Symbols`
> input.

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
