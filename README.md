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
| **Bottom-Up Stack — M1-Strict Cloud Bias — VPS** | `ichimoku-h4-m1-vps-ea.mq5` | Bottom-up, M1-strict cloud bias | M1 → H4, four tradable tiers (M15–H4; M5 dropped) | Kumo touch on the tier's own timeframe | `20260858` |
| **Bottom-Up Stack — M1-Strict Cloud Bias — MT5 Desktop** | `ichimoku-h4-m1-mt5pc-ea.mq5` | Bottom-up, M1-strict cloud bias | M1 → H4, four tradable tiers (M15–H4; M5 dropped) | Kumo touch on the tier's own timeframe | `20260860` |

Both builds carry their own magic number, so they can run on the same account
— even the same symbol — without touching each other's positions.

> ### ✂️ M5 tier dropped (changed 2026-09-23)
>
> Both main builds no longer open **M5** trades (`InpM5Tier = false`). M15,
> M30, H1 and H4 trade exactly as before, and M1 and M5 still form the bottom
> of every chain. Real-tick backtests on GOLDm# (notes §47–48) found M5 was
> about half of all trades at a profit factor of ~1.1. Without it the
> account's profit factor rose from **1.38 to 1.52** (Jan–Sep 2026) and **1.88
> to 2.03** (2025, out of sample) at the same net profit, on 40–47% fewer
> trades. One side effect: the full current-and-future M1 cloud check only
> ever applied to the M5 tier, so it now applies to none. The magic numbers
> are unchanged, so an M5 position already open is still managed to its exit.
> The pre-change builds are archived as the `-archived20260923` pair;
> `InpM5Tier = true` restores M5.
>
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
- `tools/` — `mt5-check.sh`, the weekday VPS health check
- `utilities/` — deployment scripts, the Python monitor and the account-split simulator

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

Each EA trades a symbol (defaults to `GOLDm#`, configurable) through **four
tiers (M15, M30, H1, H4) stacked bottom-up from M1**. M1 and M5 form the
foot of every chain but do not trade; the M5 tier was dropped on
2026-09-23 (`InpM5Tier`, see below). A tier opens only when every timeframe
from M1 up to that tier is aligned in one direction — Ichimoku price *and*
Chikou Span confirmation on each — and only when a **bias timeframe grants
the direction**: H4 primarily, with H1 standing in for the lower tiers while
H4 is undecided. Positions exit the moment price **touches the tier's own
kumo edge**, with a break-even stop and a chandelier trail protecting profit
along the way. Every trade risks a fixed percentage of *actual equity*, and
that percentage steps down as the account grows.

**Highlights:**
- ✅ Four bottom-up tiers (M15 / M30 / H1 / H4; the M5 tier is switchable and off by default) — each one trades its own aligned chain, so a clean fast chain no longer waits on the slow timeframes
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

#### The VPS host (how the live build actually runs)

The live terminal runs on an Ubuntu VPS under Wine, set up like this:

- **Portable install:** `~/.wine/drive_c/Program Files/XM Global MT5/`,
  with the EA at `MQL5/Experts/ichimoku-h4-m1-vps-ea.{mq5,ex5}`, attached to
  a GOLDm# chart in the `ichimoku-live` profile.
- **systemd:** `mt5.service` starts `terminal64.exe /profile:ichimoku-live`
  on the virtual display `:1` (`xvfb.service`), with `Restart=always`.
  `x11vnc.service` serves that display on `localhost:5900`; reach it through
  an SSH tunnel (`ssh -L 5900:localhost:5900 …`).
- **The auto-update trap, and the fix.** When MetaTrader auto-updates, the
  terminal launches its LiveUpdate helper and then exits. With systemd's
  default `KillMode=control-group`, that exit takes the helper down with it,
  so the update never lands and the service restart-loops every ~2 minutes
  with the EA never loading. That happened from **2026-09-18 to 2026-09-23**
  (build 6182), and the EA did not run for five days. The fix is a drop-in
  so systemd only stops the main process:

  ```bash
  sudo mkdir -p /etc/systemd/system/mt5.service.d
  printf '[Service]\nKillMode=process\n' | sudo tee /etc/systemd/system/mt5.service.d/override.conf
  sudo systemctl daemon-reload
  systemctl show mt5 -p KillMode      # -> KillMode=process
  ```

  Applied on the live VPS on 2026-09-23. **If the EA goes quiet, first
  check the terminal log** (`logs/YYYYMMDD.log`, UTF-16) for `LiveUpdate
  start` repeating every couple of minutes. To clear a stuck update by
  hand: `sudo systemctl stop mt5`, start `terminal64.exe /portable
  /profile:ichimoku-live` on `DISPLAY=:1` so it can update itself, confirm
  `terminal64.exe` has a new date, then `pkill` it and `sudo systemctl start
  mt5`.
- **Deploying without MetaEditor on the VPS:** back up the old files, copy
  the new `.mq5` over with `scp`, and copy a `.ex5` compiled from the same
  source by a terminal on the **same MT5 build** (so the VPS loads it
  directly). Then restart the service or re-attach the EA.
- **Health check (`tools/mt5-check.sh`):** a weekday cron job that emails
  you only when something is wrong. It checks that `mt5.service` is running,
  that `ichimoku-h4-m1-vps-ea` loaded after the terminal's last start (the
  log lines `… started for …` and `expert … loaded successfully`, confirmed
  on the VPS 2026-09-24), and that the terminal log shows no LiveUpdate
  restart loop. The VPS cannot send mail itself (DigitalOcean blocks SMTP
  ports 25/465/587, and ntfy.sh no longer forwards email anonymously), so
  the email goes through [healthchecks.io](https://healthchecks.io): a
  healthy run sends a silent ping, and a failed run sends a `/fail` ping
  carrying the report, which healthchecks.io emails. A dead VPS sends no
  ping, which healthchecks.io also emails about. Installed on the VPS
  2026-09-24 as `~/mt5-check.sh` with cron `0 0 * * 1-5` (00:00 UTC =
  10:00 UTC+10, Mon–Fri). To finish setup: create a healthchecks.io check
  with schedule type **Cron** `0 10 * * 1-5`, your time zone and 1 h grace,
  turn off "notify when up" on its email integration, put
  `HC_PING=https://hc-ping.com/<uuid>` in `~/.mt5-check.conf` on the VPS,
  and run `~/mt5-check.sh --test` to get a test email.

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
*tiers*, four of which trade by default (M5 is off since 2026-09-23). A tier is named after its top timeframe, and it opens only
when the **whole chain from M1 up to that timeframe** is aligned in one
direction:

| Tier | Chain that must align | Notes |
|------|-----------------------|-------|
| **M5** | M1 + M5 | **Off by default** (`InpM5Tier = false`) — dropped 2026-09-23, see below |
| **M15** | M1 + M5 + M15 | |
| **M30** | M1 + M5 + M15 + M30 | Default ceiling for the H1 stand-in bias |
| **H1** | M1 + M5 + M15 + M30 + H1 | |
| **H4** | M1 + M5 + M15 + M30 + H1 + H4 | Additionally gated by the D1 bias |

**M1 never trades on its own** — it is only the foot of the chain.

**Why M5 is off.** Real-tick backtests on GOLDm#
([notes §47–48](experiments/EXPERIMENTAL-NOTES.md)) found the M5 tier was
about half of all trades at a profit factor of ~1.1 — the most spread paid
for the thinnest edge. Without it, the account's profit factor rose from
1.38 to 1.52 (Jan–Sep 2026) and from 1.88 to 2.03 (2025, out of sample) at
the same net profit, on 40–47% fewer trades. Tightening M5 instead (H4-only
bias, H1 confirmation, a full M5 cloud check, a cloud-distance cap, a spread
cap) never beat dropping it. Scalping the small tiers with partial or fixed
targets was also tested and rejected: net profit stayed flat while drawdown
rose. `InpM5Tier = true` restores the tier. Since M5 was the only tier whose
cloud gate checked M1 with the full current-and-future rule, that rule now
applies to no tier.

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
allows buys only, H4 bearish sells only. On its own that rule freezes every
tier whenever H4 is unaligned — and H4 spends a large
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
| M5 *(unused while `InpM5Tier = false`)* | 1.0% | 0.5% | 0.1% |
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

### Account-split simulator (`utilities/account-split-sim.py`)

A Monte Carlo **model** (not a backtest) of the money management above:
one account against splitting profit into new accounts, and what to do with
the money once the accounts are maxed out. Trades are drawn from the per-tier
backtest statistics in the notes (§47, §48, §50), and one year in three is
2024-like (the year that ruined a $100 account). Every account on a path takes
the same trades, so a bad year hits them all at once. Calibrated against the
real $100 and $10k backtests. Needs `numpy`.

```bash
python3 utilities/account-split-sim.py                     # the default plan below
python3 utilities/account-split-sim.py --split-at 3000 --years 2
python3 utilities/account-split-sim.py --harvest-at 7000 --keep 5000
python3 utilities/account-split-sim.py --compare-harvest   # what to do once maxed
python3 utilities/account-split-sim.py --help
```

Defaults: an XM Micro account (0.1-lot minimum = 0.1 oz of gold), the live
risk regime, a $100 start, every account that reaches $5,000 opens a new
$1,000 account, at most 8 accounts (XM's limit per profile), 3 years.

Findings (3 years, 400 paths; medians):

| Plan | Median | Chance of ending below the start |
|---|---|---|
| One account from $100 (standard 0.01 lot) | $30k | ~28% |
| One account from $100 (Micro) | $32k | ~3.5% |
| Split at $5k into $1k accounts, only the newest splits | $133k | ~4.5% |
| **Split at $5k into $1k accounts, every account splits** | **$207k** | ~5% |

- **Correction (2026-09-24): a $100 start is NOT made safe by the Micro
  account.** The real backtests (§50, §54) already ran on XM Micro (GOLDm#,
  1 lot = 1 oz, 0.1 lot minimum), and both the live build and the M5 base
  were ruined from $100 in 2024. The model treats trades as independent. The
  EA can hold several tiers at once, and losses cluster, so the model's
  first-account risk (the `micro` rows) is too optimistic. Treat the first
  $100 account as something that can be lost in a 2024-like year. The
  $1,000 child accounts are less exposed.
- **Splitting works because the risk regime is per account.** An account
  past $7k or $13k de-risks, so splitting keeps more money in the high-risk
  regime. It is a choice to take more risk, not a free gain.
- **Once the 8 accounts are full, withdraw rather than let them run.**
  Withdrawing whenever an account reaches $7k, back down to $5k, gave a median
  of about $449k with about $416k of it already banked, against $213k (none
  banked) when the accounts were left to grow. That is the same effect again:
  an account held under a threshold keeps trading at the higher risk, and its
  gains leave as they are made.

All of this assumes the 2025–26 edge continues live. The model ignores
broker limits, slippage across many accounts, fees and taxes.

### Scaling plan: up to 8 XM Micro accounts

The plan the simulator above was used to design. **It runs the live VPS EA**
(`ichimoku-h4-m1-vps-ea.mq5`, M5 tier off). The simulator's trade statistics
come from that build's backtests (notes §48, §50). The M5-base experiment
(§54) was backtested and came out worse (deeper drawdowns, lower profit
factor), so the plan stays on the live build.

**Setup**

- **Broker:** XM Global, **Micro** accounts (MT5, minimum 0.1 micro lot =
  0.1 oz of gold). XM allows up to **8 live accounts per profile**, with free
  instant transfers between them. Check the GOLD contract size and minimum
  volume under Market Watch → Specification. The plan assumes 0.1 lot = 0.1 oz.
- **EA:** the live VPS build, unchanged, on every account. Its default
  `Symbols = GOLDm#` is already XM's gold symbol on Micro accounts (the
  backtests ran on `XMGlobal-MT5 5`), so no input needs changing. The same
  magic number on every account is fine, since accounts never see each other's
  positions.
- **VPS:** one MT5 terminal per account, each installed in its own folder,
  about 300–500 MB of RAM each (about 4 GB for 8). XM's VPS is free with $5k
  of equity and 5 standard lots a month, counted across accounts under one
  email; otherwise it is $28 a month.

**Rules**

1. **Start** one account with **$100**.
2. **Split:** whenever **any** account reaches **$5,000**, move **$1,000** out
   of it into a new Micro account running the same EA. Every account splits,
   not only the newest; that is what keeps the money in the fastest-growing
   risk regime.
3. **Stop splitting at 8 accounts.**
4. **Once there are 8, harvest:** whenever an account is above **$7,000**,
   withdraw it back down to **$5,000**, and move the money out of XM to a bank
   account. Weekly or monthly is close enough; the simulation withdrew at every
   crossing.
5. **Leave the EA's settings alone** across all accounts. The rules above do
   the money management.

**What the model expects (3 years, medians)**

| Stage | Result |
|---|---|
| One account, no splitting | $32k |
| Splitting at $5k into $1k accounts (rules 1–3) | $207k, all still in the accounts |
| + harvesting at $7k down to $5k (rule 4) | ~$449k total, ~$416k of it already withdrawn |
| Chance of ending below the $100 start | the model says ~4–5%, but **real backtests ruined a $100 Micro account in 2024**, so the true risk is much higher |

**Risks.**
- **One risk hits every account at once.** All 8 accounts trade the same
  signals at the same moment, so a 2024-like year hurts them all together.
- **Rules 2 and 4 take on more risk.** Both keep money in the high-risk
  regime, which the EA's de-risking was designed to prevent.
- **The figures are a model.** They assume the 2025–26 edge continues live,
  and ignore slippage, fees, taxes and broker limits. Leverage at XM drops to
  1:200 above $20k of equity; ask XM whether that counts per account or per
  profile.

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
| `InpM5Tier` | `false` | M5 tier opens trades. Dropped on 2026-09-23 (notes §48); `true` restores it |

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
| 1 | M5 | Tier 1 — rung of every chain, **not traded by default** (`InpM5Tier`) |
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
  the right tier with no stale state. **Caution for any future build that
  partially closes:** MT5 empties the position comment on a partial close,
  so comment-only identification loses the tier. Match on the position
  identifier as well, the way the scalp-capture experiment (§47) does.
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
| `ichimoku-h4-m1-vps-ea-archived20260923.mq5` | The VPS build as it stood before the **M5 tier was dropped** on 2026-09-23 — five tradable tiers (M5–H4), M1-strict cloud bias, robustness pack; magic `20260858` |
| `ichimoku-h4-m1-mt5pc-ea-archived20260923.mq5` | Its desktop twin from the same change (magic `20260860`) |
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

The directory also holds one **indicator** (`po3-levels.mq5`), which is a
chart tool rather than a strategy: it carries no `experimental-` prefix
because it places no orders. It is indexed at the end of this section.

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
| `experimental-bottomup-stack-market-profile-vps-ea.mq5` | `20260864` | Adds a TPO market-profile layer measured on M30 — POC, value area, daily key levels, session stacking, day-shape read — driving entries through an AUTO regime dispatcher | 37 |
| `experimental-bottomup-stack-kihon-po3-ea.mq5` | `20260865` | A three-gate chain: a kihon suchi **time** gate fixed to the **daily H1 setup** — H1 counted from the day open, judged against candles **9 and 17** (±2), both hardcoded because a day's ~23–24 candles can reach no other kihon number — then the parent's structure gate, then a PO3 **price** gate that measures room to the next level in the tier's own ATR and takes profit at it. Adds an optional **M2 rung** to the alignment chain — a step between M1 and M5, not a tradable tier | 38 |
| `experimental-m1-m2-fixed-tp-ea.mq5` | `20260866` | The two shortest rungs only — **M1+M2** opens the M2 tier, **M1+M2+M5** opens the M5 tier — with **one position** and fixed levels instead of the parent's kumo-touch exit: **SL 90 pips, TP 120 pips**, both on the order, no break-even and no trail. No cloud/bias gates by default. Entries are restricted to two **session windows**, daily H1 candles **7–11** and **15–19** counted from the day open | 39 |
| `experimental-bottomup-stack-kihon-po3-veto-ea.mq5` | `20260867` | Forks the kihon + PO3 build to add two **location vetoes** after its three gates. **Gate 4** is a directional **rejection veto**: the last 180 closed H4 bars are scanned for an extreme that tagged a **2187-grade** PO3 level and closed back inside it, after which only entries *away* from that level are allowed — §1's `PO3Bias` ported onto this build's level arithmetic and cached per H4 bar. **Gate 5** is an optional **dealing-range zone** veto that refuses longs above / shorts below a configurable fraction of the price's PO3 range (50/50 = the equilibrium line, 33.3/66.7 = the strict discount/premium thirds), off by default | 40 |
| `experimental-bottomup-stack-m5-m15-h1-vps-ea.mq5` | `20260868` | A fork of the **live** VPS build that **cuts the tier set to three** — **M5, M15, H1** (3× then 4× spacing) — on the argument that a strict-AND chain is starved by extra rungs. **H4 stays as the bias but is no longer a tier** (`tfs[]` still carries it; the H4 bias still gates every entry), and **M30 is gone entirely**. Dropping H4 as a tier costs no direction because the H4 bias runs the identical `CheckAlign(H4)` an H4 rung would. Chains shorten to M1+M5 / +M15 / +H1, the **cloud gate re-points itself** (it looks up `tfs[lvl+1]` and `tfs[lvl]`), and the tier-1 risk total falls from the parent's 37% to **12%**. One behaviour change beyond the count: the **D1 filter now gates H1** (`InpD1Filter=false` restores the parent's H1). Supersedes the M2 and eight-tier drafts of the same experiment, both deleted. **User report: underperforms the live VPS build** — so the five-tier parent remains the better tier set on the evidence so far, and this build should not be promoted | 41 |
| `experimental-bottomup-stack-kihon-po3-veto-m2tier-ea.mq5` | `20260869` | Forks the kihon + PO3 + veto build to add a sixth **tradable tier at the bottom: M2**. `InpM2Tier` lets **M1 + M2 aligned open an M2 trade** with its own risk row (0.5/0.25/0.05), its own ATR handle and its own exits, managed by the same code as M5 — while `InpUseM2` keeps M2 as the **rung** in the higher chains, so M5 still needs M1 + M2 + M5. Adding a tier at the bottom renumbered all five existing levels (M5 0→1 … H4 4→5), so the risk table, the M1-full-cloud case, the H1/H4 break-even bucket and the H1-bias ceiling all moved with it, and the rung-skip in `ChainAligned` became level-aware so an inactive rung cannot leave the M2 tier validating on M1 alone | 42 |
| `experimental-bottomup-stack-m1m2-scalp-m30-bias-ea.mq5` | `20260870` | The **live VPS build plus one scalping tier**. Adds a sixth tradable tier at the bottom — **M2** — whose alignment is **M1 + M2 and nothing else**, with **M30 as its own bias**: it does not consult H4, does not use the H1 stand-in ladder, and so can scalp while H4 is flat *and* against an aligned H4 (counter-trend by design; `InpM30ScalpBias=false` drops the gate to the bare chain). The decisive difference from §42: **M2 is a tier, not a rung** — `ChainAligned()` skips it for every tier above, so M5 is still M1 + M5 and **the five live tiers keep their exact chains, bias ladder, D1 filter, exits and risk**, making this fork's live-tier trade set identical to the parent's. A live tier holding a position blocks the scalp (`InpScalpNeedsFlatSymbol`), closing a hazard the new tier would otherwise introduce on netting accounts. Sized below M5 (0.5/0.25/0.05) because a 2-minute bar sits near the noise floor. `InpM2CloudFull=false` here vs **`true` in §42**, so the two M2 builds are **not** comparable on M2's cloud until set alike. `InpM2ScalpTier` switches the tier off entirely | 43 |
| `experimental-bottomup-stack-m1m2-scalp-m30-bias-hardtp-ea.mq5` | `20260871` | Forks §43 to attach a **hard, broker-side take profit to the two smallest tiers at entry** — the first profit target anywhere in this family, which otherwise rides kumo-touch exits and has no TP at all. **M2 takes 30 pips, M5 takes 60** (`InpTPPipsM2`/`InpTPPipsM5`); **M15, M30, H1 and H4 take none** and are byte-for-byte the parent. A pip is the gold convention, **0.10 of price**, so the defaults are a **3.00 / 6.00** target; `InpPipPoints=0` **auto-resolves points-per-pip from `SYMBOL_DIGITS`** (10 on a 2-decimal feed, 100 on a 3-decimal one) so a feed change cannot move every target by 10x — set it explicitly for non-gold. **The target is additive, not a replacement**: the kumo-touch exit, rejection candle, BE stop, chandelier trail and disaster stop all still run on M2/M5, so this can only *shorten* those trades. Every `PositionModify` now carries the TP back in (the parent passed a bare `0`, which would have stripped it on the first BE or trail move), and a target rejected by the broker's min-distance self-heals next minute from the entry anchor. Note the **fixed target against an ATR stop makes M2/M5 reward:risk drift with volatility**. `InpHardTPEnabled=false` restores the parent exactly | 44 |
| `experimental-bottomup-stack-m1-m2-scalp-tiers-5band-ea.mq5` | `20260872` | Forks §44 with three changes. **(1) A seventh tier: M1, alone** — the chain is `CheckAlign(M1)` and nothing else, no higher timeframe confirms it, breaking the family's founding rule that M1 never trades alone (`InpM1Tier`). Its bias is **M30** (`InpM1M30Bias`), the same gate the M2 scalp uses, so it trades while H4 is flat *and* against an aligned H4. With M1 tradable the level list equals `tfs[]`, so the parent's **`lvl + 1` offset collapses to `lvl`** at all 18 sites and `ENUM_H1_BIAS_TIER` shifts up one. **(2) Targets re-cut and a tight hard SL added** — M1 **30p TP / 20p SL** (1.50:1), M2 **40/25** (1.60:1), M5 **50/30** (1.67:1); M15+ keep no target and the 8xATR disaster stop alone. The hard stop **replaces** the disaster stop on those three tiers and is **clamped to the tighter of the fixed distance and 8xATR**, so it can never end up wider than the parent's. Critically, **`RiskLots` now sizes those tiers on the stop they actually run** — a fixed pip stop has no fixed relation to the 2xATR sizing reference, so leaving sizing alone would have made the risk table fiction exactly where this build lives. Consequence to read before comparing tiers: **a stop-out costs ~1x the stated risk % on M1/M2/M5 but still ~4x on M15+**; the two halves of the ladder are no longer one scale. **(3) The risk ladder goes three bands to five, and 13k+ carries more risk**: the parent cut H4 to 2.0% above 13000, a 5x cliff that made a 13k account risk *fewer dollars* ($448) than a 7k one ($1,321). Anchored on H4 per band — **20 / 10 / 7 / 4 / 2%** at `<7k / 7-13k / 13-17k / 17-20k / 20k+` — with every tier holding the fixed fraction of H4 that bands 1-2 always used. Bands 1 and 2 unchanged. **13000 is no longer a de-risking point but a step UP**: the band-3 floor risks $1,718 against band 2's $1,321, so crossing 13000 raises money at risk ~30% and the tapering only begins at 17000. Note **M30 in band 3 rises 8.75x** (0.2 → 1.75) because the parent's 13000+ band was the one place M30 broke the ladder's shape (`0.10xH4` vs `0.25xH4`), and **band 5 merely matches the parent's old 13000+ risk** (H4 2.0%) rather than going below it. `HigherLiveLevelBusy()` became **`OtherLevelBusy(s, lvl)`**, scanning every other level rather than only the live ones, since M1 and M2 can now collide with each other | 45 |
| `experimental-bottomup-stack-5band-risk-ea.mq5` | `20260873` | The **live VPS build with one change: the risk ladder**. Trading logic is the live build's byte for byte — five tiers (M5…H4), M1 only as the start of a chain, no M2, H4 bias with the H1 stand-in, D1 filter on H4, kumo-touch exits, **no profit target**, the 8xATR disaster stop, robustness pack R2-R6. Deliberately **drops the M1/M2 trading tiers, hard TPs and tight hard SLs** of §§43-45, keeping only their band edges. Three bands become five, anchored on H4 at **20 / 10 / 7 / 4 / 2%** for `<7k / 7-13k / 13-17k / 17-20k / 20k+`, every tier holding the fixed fraction of H4 the ladder has always used. Bands 1-2 unchanged. Fixes a real defect: the live build cut H4 from 10% to 2% at 13000, a 5x drop that outran the equity growth triggering it, so a 13k account risked **fewer dollars** ($448) than a 7k one ($1,295). Now **13000 is a step UP** — the band-3 floor risks $1,684, ~30% above band 2 — and de-risking begins at 17000. Note **M30 in band 3 rises 8.75x** (0.2 → 1.75) because that band was the one place M30 broke the ladder's shape, and **band 5 merely matches the live build's old 13000+ risk**. OnInit prints the resolved ladder | 46 |
| `experimental-bottomup-stack-scalp-capture-vps-ea.mq5` | `20260874` | The **live VPS build plus a scalp-capture exit layer and a per-tier report** — entries, bias gates, risk and every existing exit are the live build's byte for byte. The live build gives small moves back: BE arms at +1 x ATR but only moves the stop to entry + 15 points, and the M5/M15/M30 trail waits for a +2 x ATR spike, so a trade that runs +1.9 ATR and turns closes at break-even. Here, on M5..`InpScalpMaxTier` (default M30), at **+`InpScalpTP1ATR` x ATR-at-entry (1.0)** the EA **banks `InpScalpClosePct` (50%)**, locks the runner at **entry + 0.3 x ATR**, and arms the chandelier at once; the runner keeps the kumo-touch exit, so the trend tail is untouched. `InpScalpClosePct=100` makes it a pure fixed-target scalp; `InpScalpCapture=false` restores the live exits exactly. **OnDeinit prints a per-tier report** — trades, win %, net, PF, avg win/loss, MFE buckets in ATR, and **give-backs** (trades that reached +1 ATR and still closed <= 0) — so one run with capture off measures how many scalps the live logic leaves behind. Compiled clean in MetaEditor (0 errors, 0 warnings). **Backtested (GOLDm#, Jan–Sep 2026, $100, 1-min OHLC and real ticks): scalps are not worth it** — net stays within ±3% of the live build's $13.5k in every variant, while drawdown rises (real ticks: 21% live vs 35% partial, 37% pure M5 scalp) and pure scalping turns M5 negative. Also found: **MT5 empties the position comment on a partial close**, so the build matches tiers by position identifier as well; `InpScalpUnsplit` handles positions below 2x the 0.10 minimum lot | 47 |
| `experimental-bottomup-stack-m5-tight-vps-ea.mq5` | `20260875` | The live VPS build (via §47, scalp capture off) with **switchable filters on the M5 tier only**: `InpM5Enabled`, `InpM5NeedH4` (no H1 stand-in), `InpM5NeedH1`, `InpM5CloudFull`, `InpM5MaxCloudATR`, `InpM5MaxSpread`. All off reproduces the live build to the cent. **Backtested on real ticks, 2026 and out-of-sample 2025:** `NeedH4` is the only filter that raised M5's profit factor in both years (1.10→1.29, 1.12→1.22) and is the default. The cloud-distance cap is backwards (entries near the cloud are the weak ones). **Dropping M5 entirely gave the best account profit factor both years** (1.38→1.52, 1.88→2.03) at the same net profit and 40–47% fewer trades Also carries **tier switches** (`InpTierM15/M30/H1/H4`, all on by default) for the §50 simulation: **the live logic at $100 is ruined in 2024** (stopped out 2024-08-02; +$4,973 at $10k). H4 and H1 are the only tiers profitable in all three years, and dropping M15 matched or beat live in 2025–26 | 48, 50 |
| `experimental-bottomup-stack-liquidity-target-vps-ea.mq5` | `20260878` | The **live VPS build** (M5 tier off) with **one addition: a take profit at unraided liquidity**. On every entry the Ichimoku stack is climbed from M1 while each timeframe is **clear** — broken out, its **price and chikou both beyond the cloud** in the trade's direction — and the **highest clear timeframe** supplies the target (M1, M5, M15 clear but M30 in the cloud → M15): its **nearest** unraided swing high (long) or low (short) beyond the entry becomes a broker-side TP. Swings and raids are the `po3-levels` rules of §52 (fractal 6/6, last 100 candles, a wick beyond = raided). No unraided level on that timeframe: the trade opens without a TP as live does (`InpLiqNeedTarget` skips it instead). The target is **additive** — kumo-touch, BE, chandelier and the disaster stop still run — and every `PositionModify` now carries the TP back in. `InpLiqTarget=false` reproduces the live build. Compiled clean; not yet backtested | 53 |
| `experimental-bottomup-stack-m5-base-vps-ea.mq5` | `20260879` | The **live VPS build** (M5 tier off) with the stack **starting at M5 instead of M1**: M1 takes no part in alignment, the chains are M5+M15 / +M30 / +H1 / +H4, and M5 alone never trades. Cloud gate, bias, risk and exits are live's; `InpBaseCloudFull` (off) gives M5 the full current+future cloud check M1 used to carry. **Backtested ($100, real ticks): worse than live**: ruined in 2024 a month earlier, 2025 +$13,990 (PF 1.89 vs 2.03) with a **96% drawdown**, 2026 +$14,196 (PF 1.36 vs 1.52), about a third more trades. Do not promote | 54 |
| `experimental-bottomup-stack-m5-base-keep-tiers-vps-ea.mq5` | `20260880` | The M5-base stack (§54) with **no supersede**: every aligned flat tier opens on the same bar, and a running lower-tier trade keeps going to its own exit when a bigger tier opens. Up to four positions per symbol (one per tier), up to 36% tier-1 risk at once. Needs a hedging account. `InpKeepLowerTiers=false` restores §54. **User report: detrimental** — performed worse than the M5 base; do not promote | 55 |
| `experimental-bottomup-stack-m5-base-risk125-vps-ea.mq5` | `20260881` | The M5-base stack (§54) with **every risk % raised by 25%** in all three regimes: tier 1 M15 1.25 / M30 6.25 / H1 12.5 / H4 25. Regime thresholds, sizing distance and margin cap unchanged. Not yet backtested | 56 |
| `experimental-bottomup-stack-m5-base-risk125-5regime-vps-ea.mq5` | `20260882` | The risk ×1.25 build (§56) with **five equity regimes** instead of three. Below $13000 the risk is §56's (M15 1.25 / M30 6.25 / H1 12.5 / H4 25 below $7000); the old $13000+ regime is split at $17000 and $20000 into H4 5 → 2.5 → 1.25 (half each step). A ×2.5 doubling was tried first and reduced back below $13000. Not yet backtested | 57 |

### Top-down alignment builds

The retired model: every timeframe from the anchor down to M1 must agree
before one trade opens. Kept for reference and A/B work.

| File (`experiments/`) | Magic | What it is | § |
|---|---|---|---|
| `experimental-h4-m1-po3-ea.mq5` | `20260502` | H4-M1 alignment plus a Power-of-Three dealing-range filter | 1 |
| `experimental-m1m2-kihon-po3-scalper-ea.mq5` | `20260876` | A kihon-timed M1+M2 scalper. Gate 1: **six kihon clocks**, day H1/M30/M15 counted from the day open and week H4/H1/M30 counted from the week open; `InpKihonMinTFs` of them must be on a reachable kihon number, anywhere inside that candle. Gate 2: M1 and M2 clear on price and chikou and must **turn** aligned inside the window (`InpBreakoutOnly`). M5–H4 must agree; if the chain stops at M5 or above, the next timeframe's **nearest line** (tenkan/kijun/SSA/SSB), or a **PO3 number** on it, is the target, provided the price and chikou road to it is free on every timeframe above. Gate 3: at least **30 pips** of room to the target (PO3 level on a full chain). **Exits (`InpExitMode`):** default is the **VPS build's**, a stop on the touch of the highest aligned timeframe's cloud, no TP, BE, chandelier and an 8xATR disaster stop, sized on the distance to that cloud. `EXIT_TARGET` is the older fixed TP at the target and PO3 stop. **Backtested (real ticks, $10k): VPS exits +$70 in 2026 (PF 1.03) and +$910 in 2025 (PF 1.39), 4.6% drawdown, profitable in both years for the first time; target exits −$2,846 / +$7,761.** H4-exit trades carry the profit, M5-exit trades lose, in both years. **Breakout + VPS exits over 2024 / 2025 / 2026: +$680 / +$910 / +$70 (PF 1.38 / 1.39 / 1.03, ~5% DD).** A **pullback entry mode** (`InpEntryMode`: M1+M2 dip against an aligned H4/H1 into a PO3 number or line, then turn back) was built and **loses in all three years**, with trail exits and with a **swing-target TP** (`InpPBExit`) alike, so it is off by default | 49 |
| `experimental-po3-sweep-rejection-ea.mq5` | `20260877` | A standalone, basic test of the **PO3 false-break** reading: price breaks a PO3 level (27 by default), overshoots into the next range and is usually rejected before that range's **midpoint**. Each sweep on M5 (or M1) ends **accepted** (a close beyond the midpoint, `InpAcceptPct`), **rejected** (a close back through the level on a **turtle soup** or **engulfing** bar) or **expired**. A rejection is traded against the sweep, with the stop beyond the midpoint, the target a range back and an optional H1/H4 cloud bias and session window. Every sweep goes to `po3-sweep-<symbol>.csv` (common Files) and a per-grade summary is printed; `InpTrade = false` only measures. **Backtested (real ticks, $10k, 1% risk):** the default, **New York hours (15–20 server) + engulfing + H4 cloud bias**, is the only setting profitable in all three years: **+$584 / +$4,453 / +$974 in 2024 / 2025 / 2026 (PF 1.14 / 1.85 / 1.20, ≤12% DD)**, 73–110 trades a year. All hours, either pattern: −$486 / +$7,759 / +$1,300. No bias, 9 ranges and M1 signals lose. **Higher-grade levels were not rejected more often**: 27, 81 and 243 levels show the same rejection rate | 51 |
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
| `experimental-m1m5-liquidity-scalper-ea.mq5` | `20260883` | **Newest.** A standalone **M1+M5 scalper with no higher-timeframe bias**. Entry: M1 and M5 both aligned the same way (the live `CheckAlign`: price and chikou beyond tenkan, kijun and cloud), checked on each closed M1 bar. **TP** at the nearest **unraided M5 liquidity** level beyond the entry (the `po3-levels` rules of §52: swings 6/6, last 100 candles). **SL** two fractals back: the **second Williams fractal** low below the entry for a buy, or the second fractal high above it for a sell, on M1 (`InpFractalTF`). No target or no stop means no trade. Sized with the **live VPS build's M5-tier risk regime**: 1% of equity below $7000, 0.5% to $13000 and 0.1% above, measured against the **distance to the fractal stop** (a stopped-out trade loses that %; the stop is never moved to suit the size) and capped to 80% of free margin, one position per symbol, and it exits only at the SL or TP. Compiled clean; not yet backtested | 58 |

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

### Indicators

Chart tools rather than strategies — they draw and place no orders, so they
carry no magic number and the index has no magic column.

| File (`experiments/`) | What it is | § |
|---|---|---|
| `po3-levels.mq5` | Power-of-Three support/resistance levels on the chart — every grid from 1 to 19683, each price owned by the **highest** power of three that lands on it, so the biggest numbers read as the strongest levels — together with Ichimoku **kihon suchi** candle counts, the kihon segment panel and a timetable of when this week's kihon candles open — and the **unraided liquidity**: fractal-style swing highs and lows (6 candles each side, last 100 candles, chart timeframe or a locked one) that price has not yet traded through, drawn from the wick to the right edge in light blue (highs) and purple (lows) until raided, each with its price written at the wick in the same colour, with the last raided high and low kept as a dashed line (same colour and width) from the wick to the raid candle, also priced at the wick. It is the source of the level arithmetic and the counting convention the `kihon-po3` EA ports, so the EA and the chart agree on what "on a kihon number" means | 38, 52 |

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
