# Ichimoku Multi-Tier Alignment EA — Summary

## What It Does

This is a MetaTrader 5 Expert Advisor (EA) that trades one or more symbols using Ichimoku Cloud alignment across multiple timeframes. It runs fully automated entry and exit logic organized into three conviction tiers. No stop loss or take profit is used — exits are driven entirely by Ichimoku signal breaks.

---

## Symbols Traded

Configurable via the `Symbols` input as a comma-separated list. Default: `GOLDm#`. Supports up to 60 symbols simultaneously.

---

## The Three Tiers

Each tier represents a different level of timeframe alignment conviction. Higher tiers = stronger signal = larger position size.

| Tier | Alignment Required | Lot Size | Positions (default) | Exit TF |
|------|--------------------|----------|---------------------|---------|
| 0 — Full MN-M1 | Monthly → M1 (all 9 TFs) | 0.20 | 3 | M15 break |
| 1 — H4-M1 | H4 → M1 (6 TFs) | 0.10 | 3 | M5 break |
| 2 — H1-M1 | H1 → M1 (5 TFs) | 0.10 | 1 | M1 break |

Tiers are **exclusive and hierarchical**: Tier 1 only enters if Tier 0 is not active; Tier 2 only if Tiers 0 and 1 are not active.

Position counts per tier are configurable via inputs (`FullCount`, `H4Count`, `H1Count`).

---

## Ichimoku Alignment Rules (per timeframe)

Signal is checked on the **confirmed bar** (shift 1). A timeframe is **bullish** when ALL of these hold:
- Price close is above the cloud, above Tenkan-sen, and above Kijun-sen
- Chikou Span is above its cloud (26 bars back), above Tenkan, above Kijun, and above price 26 bars back

**Bearish** is the mirror opposite. Neutral (0) if any condition fails.

All timeframes in a tier's range must agree (all bullish or all bearish) for a signal.

---

## Entry Logic

Fires once per M1 bar close, for every symbol:
1. Check Tier 0 first. If no position exists and full MN→M1 alignment is confirmed, open `FullCount` positions.
2. If Tier 0 is not active, check Tier 1 (H4→M1).
3. If Tiers 0–1 are not active, check Tier 2 (H1→M1).

Each tier opens its configured number of positions at market with no SL or TP.

---

## Exit Logic

Exit checks run before entry checks each bar. Each tier has a designated exit timeframe:

| Tier | Exit TF |
|------|---------|
| 0 — Full MN-M1 | M15 |
| 1 — H4-M1 | M5 |
| 2 — H1-M1 | M1 |

If the exit TF's Ichimoku signal no longer matches the open direction (goes neutral or flips), all positions for that tier on that symbol are closed at market.

---

## Alerts & Notifications

Every entry and exit emits:
- `Print()` to the MT5 journal
- `Alert()` popup
- `SendNotification()` to the MT5 mobile app

All messages include local PC time in 12-hour format.

---

## State Management

- `tierState[symbol][tier]` tracks whether each tier is long (+1), short (-1), or flat (0) per symbol.
- On EA restart, `SyncStateFromPositions()` scans all open positions and restores state using magic numbers (one unique magic per tier).

---

## Key Parameters

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `Symbols` | `GOLDm#` | Comma-separated watch list (up to 60) |
| `Tenkan / Kijun / SenkouB` | 9 / 26 / 52 | Ichimoku periods |
| `FullLots / H4Lots / H1Lots` | 0.20 / 0.10 / 0.10 | Lot size per position per tier |
| `FullCount / H4Count / H1Count` | 3 / 3 / 1 | Number of positions per tier |
| `Slippage` | 30 | Max slippage in points |
