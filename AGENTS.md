# Project Instructions

## VPS EA files — do NOT modify

The VPS EA files are deployed and running live on a VPS. They are the
production versions and must never be changed without explicit, specific
instruction from the user.

VPS files (by name pattern):

- `ichimoku-h4-m1-vps-ea.mq5` — the single VPS build, dual-mode
  (`InpTopTF`: `TOP_H4` = H4→M1 stack, `TOP_H1` = H1→M1 stack). It
  replaced the two former VPS files on 2026-08-14; the archived originals
  live in `archives/`.

Unless the user explicitly states that a VPS file should be updated, leave
them untouched — even when a change applies to all other EAs.

## MT5 desktop EA file — editable

- `ichimoku-h4-m1-mt5pc-ea.mq5` — the single desktop build, dual-mode
  like the VPS file but with `Alert()` popups and the weekly equity alert
  restored (magics `20260830` H4 / `20260831` H1). It replaced the two
  former desktop files on 2026-08-14; the archived originals live in
  `archives/`.

