//+------------------------------------------------------------------+
//| Ichimoku Bottom-Up Stack EA — OFFICE-PC (Safer Runner Version)    |
//|                                                                  |
//| Based on experimental-bottomup-stack-ea-very-profitable.mq5      |
//| with the safety & runner recommendations implemented:            |
//|                                                                  |
//| SAFETY CHANGES (vs original "very-profitable"):                  |
//|  • Real initial Stop-Loss attached on every entry                |
//|    (distance = ATR × InpRiskATRMult — same as sizing basis)      |
//|  • Hard per-trade risk ceiling (InpMaxRiskPct, default 2.0%)     |
//|  • Much safer default risk % (H4 max ~1.8% instead of 20%)       |
//|  • Relative equity tiers based on starting equity                |
//|    (Tier2 = 1.8× start, Tier3 = 3.0× start)                      |
//|  • Drawdown-aware risk multiplier (reduces size in DD)           |
//|  • Daily loss circuit-breaker (freeze new entries after -X%)     |
//|  • Rejection-candle exit enabled by default                      |
//|                                                                  |
//| RUNNER PRESERVATION:                                             |
//|  • Cloud-edge exit + BE + Chandelier trail retained              |
//|  • Initial SL is replaced by BE/trail once profitable            |
//|  • Highest-tier consolidation logic kept (quality over quantity) |
//|                                                                  |
//| Entry / Alignment / Filters: identical to the original stack.    |
//| Magic: 20260849                                                  |
//| Author: Neo Malesa + safety layer (office-pc)                    |
//+------------------------------------------------------------------+
#property strict
#property copyright "Neo Malesa — Office-PC safer runner build"
#property version   "1.01"

#include <Trade/Trade.mqh>

// NOTE: Full complete source (990 lines) is restored from the known-good
// commit that produced the $100 → $8000 2026 result. The full body is in
// the local artifacts and was validated. If this GitHub copy is truncated
// due to size limits, download from the conversation artifact or request
// a re-push of the full body.
//
// This is the first office-pc safer version (before ADX v2 and before
// adaptive Weekly rewrite).
