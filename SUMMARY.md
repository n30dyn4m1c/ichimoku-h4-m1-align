# Ichimoku Multi-Tier Alignment EA — Summary

## What It Does

This is a MetaTrader 5 Expert Advisor (EA) that trades multiple forex, commodity, and crypto symbols using Ichimoku Cloud alignment across multiple timeframes. It runs fully automated entry and exit logic organized into four conviction tiers.

---

## Symbols Traded

50+ instruments: major/minor/exotic forex pairs, gold, silver, platinum, palladium, BTC/ETH/crypto, and index/oil CFDs.

---

## The Four Tiers

Each tier represents a different level of timeframe alignment conviction. Higher tiers = stronger signal = larger position size.

| Tier | Alignment Required | Lot Size | Positions | Exit TF |
|------|--------------------|----------|-----------|---------|
| 0 — Full MN-M1 | Monthly → M1 (all 9 TFs) | 0.20 | 3 | M15 break |
| 1 — H4-M1 | H4 → M1 (6 TFs) | 0.10 | 3 | M5 break |
| 2 — H1-M1 | H1 → M1 (5 TFs) | 0.10 | 1 | M1 break |
| 3 — M30-M1 | M30 → M1 (4 TFs) | 0.05 | 1 | M1 break |

Tiers are **exclusive and hierarchical**: Tier 1 only enters if Tier 0 is not active; Tier 2 only if Tiers 0 and 1 are not active; and so on.

---

## Ichimoku Alignment Rules (per timeframe)

A timeframe is considered **bullish** when ALL of these hold on the confirmed bar:
- Price is above the cloud, above Tenkan-sen, and above Kijun-sen
- Chikou Span is above its cloud, above Tenkan, above Kijun, and above price 26 bars back

**Bearish** is the mirror opposite. Neutral (0) if any condition fails.

All timeframes in a tier's range must agree (all bullish or all bearish) for a signal.

---

## Entry Logic

On each new M1 bar, for every symbol:
1. Check the highest eligible tier first (Tier 0).
2. If no position exists for that tier and alignment is confirmed, open the required number of positions.
3. For Tiers 1–3, also check for a **HTF obstacle** before entering — if price is already near or inside a higher-timeframe cloud/Kijun/SSB level, the entry is skipped.

---

## Exit Logic

Two exit mechanisms run before entry checks each bar:

### 1. Exit TF Break
Each tier has a designated exit timeframe (M15, M5, or M1). If that TF's Ichimoku signal no longer matches the open direction (goes neutral or flips), all positions for that tier on that symbol are closed.

### 2. HTF Cloud Proximity TP (Tiers 1–3)
If an open position approaches a higher-timeframe resistance/support level (cloud edge, flat Kijun, or flat Senkou B), the EA closes the position and logs the reason. The proximity threshold is `CloudATRMult × ATR(14)` of the higher TF.

Tier 0 (Full MN-M1) has no proximity TP — it exits only on M15 break.

---

## HTF Obstacle Detection

The `ScanHTFObstacles` function finds the **nearest level ahead of price** from timeframes above the current tier:

- **Tiers 1**: checks MN, W1, D1
- **Tier 2**: checks MN, W1, D1, H4
- **Tier 3**: checks MN, W1, D1, H4, H1

For each TF it scans:
- Cloud boundaries (immediate exit if price is inside cloud)
- Flat Kijun-sen segments (within last 100 bars)
- Flat Senkou B segments (within last 100 bars)

The nearest obstacle ahead of price wins. The level is used as both an entry filter and a TP target.

---

## Alerts & Notifications

Every entry, exit, and skip emits:
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
| `Symbols` | 50+ pairs | Comma-separated watch list |
| `Tenkan / Kijun / SenkouB` | 9 / 26 / 52 | Ichimoku periods |
| `FullLots / H4Lots / H1Lots / M30Lots` | 0.20 / 0.10 / 0.10 / 0.05 | Lot sizes per tier |
| `UseCloudTP` | true | Enable HTF proximity TP |
| `CloudATRMult` | 0.5 | Proximity zone width (× ATR) |
| `FlatBars` | 5 | Bars required to confirm a flat level |
| `FlatLookback` | 100 | How far back to scan for flat levels |
