# Promotion proposal — VPS revamp (notes §74)

**Nothing here has been done.** This PR adds
`experiments/experimental-vps-revamp-ea.mq5` (magic `20260894`) and its
validation. It does not change `ichimoku-h4-m1-vps-ea.mq5`,
`ichimoku-h4-m1-mt5pc-ea.mq5` or anything on the VPS. Promotion is a separate
change that you approve after the checks in sections 5 and 6.

**Status of the evidence:**
- The revamp has **not** been compiled in MetaEditor and has **not** been run
  in the MT5 Strategy Tester. It was type-checked with g++ against an MQL5
  stub (`utilities/mq5-check/`), which is not a compile.
- Every number is a simulation (`utilities/vps-sim/`, HistData M1 bars,
  constant spread, no swaps). The details are in
  `experiments/EXPERIMENTAL-NOTES.md` §74.

## 1. Decisions that are yours

| # | Decision | My recommendation | Why |
|---|---|---|---|
| 1 | `InpOnePosition` on or off | **On** | It is the design the header documents, and it has the lower drawdown (28% median against 37%). Off earns more in simulation (median $296 against $156 from $100 after 12 months) but clusters losses. |
| 2 | `InpRiskScale` | **0.5** on a small account | Median max drawdown 28% against 39% at 1.0. No run was ruined at either. |
| 3 | `InpSupersedeGuard` (review R1) | Your call; it ships **off** | You declined R1 on 2026-08-23 and AGENTS.md says not to add it back unasked. It is a switch only. I would turn it on: it stops the bigger tier opening while the smaller one could not be closed. |
| 4 | Whether the daily/weekly limits and Friday flat suit how you want to trade | On | They change when the EA trades, not only how much. |

## 2. Recommended input set

Group A (defect fixes) stays as shipped, all `true`. Change these from their
defaults:

| Input | Default in the experiment | Recommended |
|---|---|---|
| `InpSizeOnCloudDist` | `false` | `true` |
| `InpRiskScale` | `1.0` | `0.5` |
| `InpMaxOpenRiskPct` | `0` | `30` |
| `InpDDRiskAtPct` | `0` | `25` |
| `InpDDRiskFactor` | `0.5` | `0.5` |
| `InpFriFlatHour` | `-1` | `22` |
| `InpDailyLossPct` | `0` | `5` |
| `InpWeeklyLossPct` | `0` | `10` |

Leave off: `InpArmOnPeak`, `InpRealignAfterStop`, `InpExitMaxSpread`,
`InpMaxMinLotRiskPct`, `InpMaxConsecLosses`, `InpFriNoEntryHour`,
`InpQuietFromHHMM`/`InpQuietToHHMM`. They were tested and did not help
(§74). The live inputs (risk bands, disaster stop, filters) are unchanged.

What this set did in simulation, 67 accounts started two weeks apart, 12
months each:

| Start | Ruined | Ended below start | Ended below half | End 10% / 50% / 90% | Median / 90th pct max drawdown |
|---|---|---|---|---|---|
| $100 | 0% | 12% | 0% | $98 / $156 / $340 | 28% / 37% |
| $1,000 | 0% | 16% | 0% | $886 / $1,543 / $2,941 | 28% / 41% |
| $10,000 | 0% | 4% | 0% | $10,275 / $13,301 / $14,156 | 13% / 25% |

The live build on the same test: 60% of $100 accounts ruined, median end $0.

On a $100 account the 0.1-lot minimum is often too large for the H4 tier
under the 30% cap. Those entries are skipped and written to the journal.

## 3. Proposed change to the root VPS file

The revamp re-orders the file into sections, so a line diff against the live
file is a rewrite of almost every line and is not reviewable. The proposal is
therefore: **replace the root file with the revamp file, then apply the three
edits below.** What changed in substance:

- 18 functions are byte-identical to the live file, and the live input block
  is carried verbatim (same names, order and defaults, so the settings saved
  in the chart profile still apply).
- Changed: `OnInit`, `OnTick` (split into `ProcessExits`, `SelectTier`,
  `ProcessEntry`), `SyncStateFromPositions`, `LevelRiskPct`, `RiskLots`,
  `OpenLevel`, `ManageLevelProtection`, `ExitLevel`. `CheckAlign` and
  `DailyAlign` now share `AlignOn`.
- §74 lists every switch and what it does with the switch off.

Steps (do not run them until sections 5 and 6 pass):

```bash
git mv ichimoku-h4-m1-vps-ea.mq5 archives/ichimoku-h4-m1-vps-ea-archivedYYYYMMDD.mq5
```

```bash
cp experiments/experimental-vps-revamp-ea.mq5 ichimoku-h4-m1-vps-ea.mq5
```

Then edit the new root file:

**Edit 1 — the magic number stays the live one**, so positions the live build
has open keep being managed:

```diff
-int MAGIC = 20260894;   // VPS revamp experiment (§74) — distinct from the live 20260858
+int MAGIC = 20260858;   // live VPS build (revamp, notes §74); desktop twin runs 20260860
```

**Edit 2 — the banner** names the file as the live build:

```diff
-//| Ichimoku Bottom-Up Stack EA — VPS REVAMP (experiment, notes §74)  |
-//| Magic 20260894. A revamp of the live VPS build                    |
-//| (ichimoku-h4-m1-vps-ea.mq5, magic 20260858, NOT touched), built   |
-//| on the §73 review fork. Headless: no Alert(), one closed M1 bar   |
-//| at a time, state rebuilt from the account after a restart.        |
+//| Ichimoku Bottom-Up Stack EA — the live VPS build since YYYY-MM-DD |
+//| Magic 20260858. The revamp of notes §74, promoted from            |
+//| experiments/experimental-vps-revamp-ea.mq5. Previous build:       |
+//| archives/ichimoku-h4-m1-vps-ea-archivedYYYYMMDD.mq5. Headless: no |
+//| Alert(), one closed M1 bar at a time, state rebuilt on restart.   |
```

Replace the banner's `STATUS:` lines with the MT5 results you record in
section 5.

**Edit 3 — the recommended values become the defaults.** The VPS chart keeps
its saved inputs, but an input that is new to the chart takes the default in
the file, so the defaults are what will actually run:

```diff
-input bool   InpSizeOnCloudDist     = false;  // #2 ...
+input bool   InpSizeOnCloudDist     = true;   // #2 ...
-input double InpRiskScale           = 1.0;    // Multiplies every risk band ...
+input double InpRiskScale           = 0.5;    // Multiplies every risk band ...
-input double InpMaxOpenRiskPct      = 0.0;    // Cap lots so the loss at every hard stop ...
+input double InpMaxOpenRiskPct      = 30.0;   // Cap lots so the loss at every hard stop ...
-input double InpDailyLossPct        = 0.0;    // No new entries for the rest of the server day ...
+input double InpDailyLossPct        = 5.0;    // No new entries for the rest of the server day ...
-input double InpWeeklyLossPct       = 0.0;    // No new entries for the rest of the week ...
+input double InpWeeklyLossPct       = 10.0;   // No new entries for the rest of the week ...
-input double InpDDRiskAtPct         = 0.0;    // While equity is this % or more below ...
+input double InpDDRiskAtPct         = 25.0;   // While equity is this % or more below ...
-input int    InpFriFlatHour         = -1;     // Close every position on Friday ...
+input int    InpFriFlatHour         = 22;     // Close every position on Friday ...
```

Things to know before the root file changes:

- **`utilities/auto-deploy.sh` polls `master`.** If its cron job is active on
  the VPS, the new source lands in `MQL5/Experts/` within five minutes of the
  merge. The running EA does not change until the `.ex5` is replaced and the
  EA is re-attached, but the source and the binary will then differ.
- **Open positions.** A position the old build opened is picked up by its
  comment. Its chandelier peak is rebuilt from M1 bars since its entry (#3),
  and its existing stop is never loosened.
- **The first day.** The day, week and high-water-mark values are created on
  the first minute the new build runs, from the equity at that moment.
- AGENTS.md needs its "VPS EA files" paragraph and the README its build
  description updated in the same change.

## 4. The matching desktop twin

The twin rule (AGENTS.md) allows three differences: the magic, the `Alert()`
calls, and the equity reminder. Build `ichimoku-h4-m1-mt5pc-ea.mq5` from the
promoted VPS file with exactly these edits, after archiving the current one as
`archives/ichimoku-h4-m1-mt5pc-ea-archivedYYYYMMDD.mq5`:

1. **Magic.**
   ```diff
   -int MAGIC = 20260858;   // live VPS build (revamp, notes §74); desktop twin runs 20260860
   +int MAGIC = 20260860;   // desktop build (revamp, notes §74); VPS twin runs 20260858
   ```
2. **Equity reminder.** Copy these from the current desktop file, unchanged:
   the `"Equity Reminder (desktop only)"` input group; the `GV_BASE_EQUITY`
   and `GV_LAST_ALERT_DAY` defines; `datetime lastEquityBar = 0;`; the
   functions `InitEquityAlert()` and `CheckEquityAlert()`; the call
   `InitEquityAlert();` at the end of `OnInit()`; and the once-per-H4-bar
   hook at the top of `OnTick()`, after the minute gate.
3. **`Alert()` calls**, five places:
   ```diff
   // OpenLevel
   -      Print(msg); SendNotification(msg);
   +      Print(msg); Alert(msg); SendNotification(msg);

   // ExitLevel, the exit signal (the popup follows the same once-only rule as the push)
   -   if(!InpQuietRetries || !exitNotified[s][l]) SendNotification(msg);
   +   if(!InpQuietRetries || !exitNotified[s][l]) { Alert(msg); SendNotification(msg); }

   // ExitLevel, the retry line
   -   Print(PCTime() + " | " + syms[s] + " " + tfName[l + 1] + " exit signal but positions still open — will retry");
   +   msg = PCTime() + " | " + syms[s] + " " + tfName[l + 1] + " exit signal but positions still open — will retry";
   +   Print(msg); if(!InpQuietRetries) Alert(msg);

   // SupersedeLower
   -      if(!InpQuietRetries || !exitNotified[s][l]) SendNotification(msg);
   +      if(!InpQuietRetries || !exitNotified[s][l]) { Alert(msg); SendNotification(msg); }

   // ProcessEntry, the failed order
   -      Print(PCTime() + " | " + syms[s] + " " + tfName[topTier + 1] +
   -            " entry signal but order failed, retcode " + IntegerToString(trade.ResultRetcode()));
   +   {
   +      string fail = PCTime() + " | " + syms[s] + " " + tfName[topTier + 1] +
   +                    " entry signal but order failed, retcode " + IntegerToString(trade.ResultRetcode());
   +      Print(fail); Alert(fail);
   +   }
   ```

Then confirm nothing else drifted:

```bash
diff ichimoku-h4-m1-vps-ea.mq5 ichimoku-h4-m1-mt5pc-ea.mq5
```

One point to decide: with `InpQuietRetries` on, the desktop's retry popup is
silenced with the push. The current desktop build pops up on every retry.

## 5. MT5 Strategy Tester checklist

Run this before anything else. I could not.

**Compile.** Open `experiments/experimental-vps-revamp-ea.mq5` in MetaEditor,
press F7. It must give 0 errors and 0 warnings. If it does not, stop and send
me the messages.

**Tester settings, every run:**

| Setting | Value |
|---|---|
| Symbol | `GOLDm#` |
| Period | M1 |
| Modelling | Every tick based on real ticks |
| Deposit | 100 USD (and 10,000 USD where marked) |
| Leverage | 1:1000 |
| Optimisation | Disabled |
| Dates | 2024.01.01–2024.12.31, 2025.01.01–2025.12.31, 2026.01.01–2026.11.06 (and 2023.04.15–2023.12.31 if XM has the ticks) |

**Runs.** "Off" means every input in the three "Revamp" groups at its off
value: all group A `false`, group B `false`/`0`/`1.0`, group C `0`/`-1`.

| Run | EA | Inputs | Deposits | What it must show |
|---|---|---|---|---|
| T0 | `ichimoku-h4-m1-vps-ea` | defaults | 100, 10,000 | The reference. 2024: ruined 2024-08-02; 2025: about +$14,646 (§50). |
| T1 | revamp | all revamp switches **off** | 100, 10,000 | **The same trades as T0**: same count, same net, same dates. Any difference is a bug in the revamp; stop. |
| T2 | revamp | defaults (group A on) | 100 | Fewer trades than T0; never more than one position open. |
| T3 | revamp | T2 + `InpSizeOnCloudDist=true` | 100 | No ruin in 2024. |
| T4 | revamp | section 2 set with `InpRiskScale=1.0` | 100 | Simulated: 2024 −22%, 2025 +342%, 2026 +67%, max drawdown about 53%. |
| T5 | revamp | section 2 set (`InpRiskScale=0.5`) | 100, 10,000 | Simulated from $100: 2024 −16%, 2025 +236%, 2026 +99%, max drawdown about 41%. |
| T6 | revamp | T5 with `InpOnePosition=false` | 100 | For decision 1. |

For each run record net profit, profit factor, maximal equity drawdown %,
total trades, and the ruin date if there is one.

**Read the tester journal of T5 for:**
- `entry not taken:` lines. Each reason should appear at most once per tier
  bar, not once a minute.
- `weekend flat` closes on Fridays at 22:00 server time, and no entry after.
- No position left with `S/L` 0.00 in the trade list.
- `Daily loss limit` and `Weekly loss limit` appear at most once per day or
  week.

The simulator does not reproduce MT5's 2026 compounded figure at the live
bands (§69), so expect T0 and T1 to match each other but not the simulator in
2026.

## 6. Two-week demo forward test

Only after section 5 passes.

**Setup**
- An XM **demo** Micro account, GOLDm#, 1:1000, with the balance set to your
  live balance.
- The compiled revamp (magic `20260894`) on one GOLDm# chart, inputs as in
  section 2, push notifications to your phone.
- Run it on a machine that stays on. Putting a second terminal on the VPS is
  your call: it is a 1 GB droplet and the live terminal must not be starved.
  I have not touched the VPS.
- The live VPS build keeps running unchanged on the real account.

**Every day (5 minutes)**
- Experts journal: no line repeating every minute; no `order failed`, `close
  failed` or `modify failed` runs.
- Open positions: at most one on GOLDm# with this magic, each with a stop.
- Pushes received: entries and exits only, plus at most one line per loss
  limit.

**Once in week 1, once in week 2**
- **Restart test.** With a position open, close and reopen the terminal.
  The EA must log nothing alarming, keep the position's stop where it was or
  tighter, and exit it normally.
- **AutoTrading off for five minutes**, then on. No burst of pushes.

**Both Fridays**
- At 22:00 server time every position closes with reason `weekend flat` and
  nothing opens until Monday.

**At the end**
- Compare with the simulator over the same dates:
  ```bash
  python3 utilities/vps-sim/download.py
  ```
  ```bash
  python3 utilities/vps-sim/vpssim.py run --recommended --risk-scale 0.5 --from YYYY-MM-DD --to YYYY-MM-DD --start-eq 100
  ```
  The demo's entries should be the same tiers on the same days as the
  simulator's. Exact prices and a few entries will differ (different feed,
  real spread).

**Pass:** no position ever without a stop for more than a minute; never two
positions at once; no loss on one trade above 30% of equity (the open-risk
cap; a weekend or news gap can exceed it); no repeating journal error; the
restart test clean twice. **Fail on any one of these**: do not promote, and send me the journal.

Two weeks will hold about 15 trades. That tests the plumbing. It says nothing
about profit.

## 7. Rollback plan

Promotion keeps the previous builds in `archives/` under the names in
sections 3 and 4. To go back:

1. On the VPS, back up what is running, as the README's "The VPS host"
   section says:
   ```bash
   cd ~/.wine/drive_c/Program\ Files/XM\ Global\ MT5/MQL5/Experts
   ```
   ```bash
   cp ichimoku-h4-m1-vps-ea.mq5 ichimoku-h4-m1-vps-ea.mq5.revamp.bak
   ```
   ```bash
   cp ichimoku-h4-m1-vps-ea.ex5 ichimoku-h4-m1-vps-ea.ex5.revamp.bak
   ```
   Take the same two backups of the **old** files before promoting, as
   `.pre-revamp.bak`. Rolling back is then copying those two files back.
2. In the repo, restore the root files from the archive and merge:
   ```bash
   git mv archives/ichimoku-h4-m1-vps-ea-archivedYYYYMMDD.mq5 ichimoku-h4-m1-vps-ea.mq5
   ```
   (after removing the promoted root file in the same commit; the same for
   the desktop pair).
3. Put the old `.mq5` and an `.ex5` compiled from it on the **same MT5
   build** back in `MQL5/Experts/` (`deploy.sh` for the source, `scp` for
   the `.ex5`), then re-attach the EA or restart `mt5.service` at a quiet
   moment. That restart is yours to do.
4. The magic number is the same before and after, so the old build manages
   any position the revamp opened. Its stop stays where it is.
5. The revamp leaves terminal global variables named `ICHI_20260858_*`. The
   old build ignores them. Delete them from Tools → Global Variables (F3) if
   you promote again later, so a stale high-water mark is not reused; or set
   `InpDDResetHWM=true` for one start.

Rolling back the inputs alone is faster and needs no file change: set every
"Revamp" input to its off value and the EA trades the live logic.
