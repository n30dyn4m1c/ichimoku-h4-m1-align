# Project Instructions

## VPS EA files — do NOT modify

The VPS EA files are deployed and running live on a VPS. They are the
production versions and must never be changed without explicit, specific
instruction from the user.

VPS files (by name pattern):

- `ichimoku-h4-m1-vps-ea.mq5` — the single VPS build. Since 2026-08-18 it
  carries the **bottom-up bias stack** (magic `20260850`), promoted from
  `experiments/experimental-bottomup-stack-h1-bias-ea.mq5`. It replaced the
  earlier dual-mode top-down alignment build (`InpTopTF`: `TOP_H4` /
  `TOP_H1`, magics `20260846`/`20260847`), which is archived as
  `archives/ichimoku-h4-m1-vps-ea-archived20260818.mq5`.

Unless the user explicitly states that a VPS file should be updated, leave
them untouched — even when a change applies to all other EAs.

## MT5 desktop EA file — editable

- `ichimoku-h4-m1-mt5pc-ea.mq5` — the single desktop build, the same
  bottom-up bias stack as the VPS file but with `Alert()` popups on every
  entry/exit and the weekly equity reminder restored (magic `20260852`).
  It replaced the earlier dual-mode top-down desktop build (magics
  `20260830`/`20260831`), archived as
  `archives/ichimoku-h4-m1-mt5pc-ea-archived20260818.mq5`.

## Keeping the two builds in step

The desktop build is the VPS build plus desktop conveniences. When the
trading logic changes in one, it must change in the other — the only
intended differences are:

1. the magic number (`20260850` VPS / `20260852` desktop),
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
