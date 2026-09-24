# Project Instructions

## VPS EA files — do NOT modify

The VPS EA files are deployed and running live on a VPS. They are the
production versions and must never be changed without explicit, specific
instruction from the user.

VPS files (by name pattern):

- `ichimoku-h4-m1-vps-ea.mq5` — the single VPS build. Since 2026-08-20 it
  carries the **M1-strict cloud bias** (magic `20260858`), promoted from
  `experiments/experimental-bottomup-stack-m1-strict-cloud-bias-ea-most-
  profitable.mq5` — the most profitable iteration of the cloud-bias
  experiment (user report 2026-08-20). Rule: on M1 the cloud twist
  (Span A vs Span B) must agree at BOTH the current bar and the far end
  of the future cloud; M5 and above only look at the future cloud. It
  replaced the bottom-up bias-stack build (magic `20260850`), archived as
  `archives/ichimoku-h4-m1-vps-ea-archived20260820.mq5`.

Since 2026-08-23 both builds also carry the **robustness pack** (review
recommendations R2–R6: unknown-position guard, disaster stop, chandelier
peak rebuild, per-symbol order filling + capped margin use, and the twin
rule). It was promoted verbatim from
`experiments/experimental-bottomup-stack-m1-strict-cloud-bias-robustness-vps-ea.mq5`;
the pre-pack builds are archived as the `-archived20260823` pair.
Recommendation R1 (the supersede-invariant guard) was deliberately **not**
implemented — do not add it back without being asked.

Since 2026-09-23 both builds **no longer open M5 trades** (`InpM5Tier =
false`, user instruction after the §47–48 backtests); M15–H4 are unchanged.
The pre-change builds are archived as the `-archived20260923` pair.

Unless the user explicitly states that a VPS file should be updated, leave
them untouched — even when a change applies to all other EAs.

## The VPS host

The live terminal runs under Wine as `mt5.service` on the user's VPS; the
README section "The VPS host" documents the layout, the deploy method and
the MetaTrader auto-update restart loop (fixed with `KillMode=process` on
2026-09-23). Treat anything on the VPS as production: back up before
replacing a file, and never restart or stop the service without the user
asking.

## MT5 desktop EA file — editable

- `ichimoku-h4-m1-mt5pc-ea.mq5` — the single desktop build, the same
  M1-strict cloud-bias logic as the VPS file but with `Alert()` popups on
  every entry/exit and the weekly equity reminder restored (magic
  `20260860`). It replaced the earlier bottom-up bias-stack desktop build
  (magic `20260852`), archived as
  `archives/ichimoku-h4-m1-mt5pc-ea-archived20260820.mq5`.

## Keeping the two builds in step

The desktop build is the VPS build plus desktop conveniences. When the
trading logic changes in one, it must change in the other — the only
intended differences are:

1. the magic number (`20260858` VPS / `20260860` desktop),
2. the `Alert()` calls on entries, exits, supersede-closes and failed
   orders,
3. the equity-reminder inputs, globals and the `InitEquityAlert()` /
   `CheckEquityAlert()` pair with its once-per-H4-bar hook in `OnTick()`.

`diff` the two files after any change and confirm nothing else has drifted.

## Top-down vs bottom-up

The repo now holds two different models, and they should not be conflated
in code or docs:

- **Top-down alignment** (the archived builds and most files in
  `experiments/`): every timeframe from the anchor down to M1 must agree
  before one trade opens.
- **Bottom-up bias stack** (the current VPS and desktop builds): the chain
  is grown upward from M1, each tier trades its own chain, and direction is
  granted by a bias timeframe (H4 primary, H1 stand-in) instead of by
  top-down agreement.

## Documentation

Three files carry the docs, and they must stay in step with the code:

- `README.md` — the two main builds, their inputs, and an index table of
  every file in `experiments/` and `archives/`.
- `experiments/EXPERIMENTAL-NOTES.md` — one numbered section per
  experiment. The README's `§` column points at these numbers, so a new
  section must be added at the end (never renumbered) and the README table
  updated in the same change.
- `ICHIMOKU-THEORIES.md` — the time/wave/price theory the filters draw on.

A new EA is not finished until it has a row in the README table and a
section in the notes.

## Magic numbers

Several experiments share a magic number with a sibling (`20260848`,
`20260850`, `20260851`, `20260854`); the README flags them. **Give any new
build a number nothing else uses** — check with:

```bash
grep -hoE '^(int|input +int|const +int) +MAGIC[A-Z_0-9]* *= *[0-9]+' \
  *.mq5 experiments/*.mq5 | grep -oE '[0-9]+$' | sort | uniq -c | sort -rn
```

The highest number in use is `20260884` (the XAUUSDc cent
fork). This line goes stale every time an
experiment is added — re-run the command above rather than trusting it.
