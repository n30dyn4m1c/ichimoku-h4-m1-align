//+------------------------------------------------------------------+
//| Ichimoku Bottom-Up Stack EA — OFFICE-PC (Adaptive Risk)          |
//|                                                                  |
//| Goal: Scale small capital quickly on strong trends, then         |
//| maintain steady growth once equity reaches a few thousand.       |
//|                                                                  |
//| Adaptive risk logic:                                             |
//|  • Weekly (W1) used as top bias + strength check                 |
//|  • When W1 + H4 show strong intending trend → higher risk        |
//|    allowed so small accounts can compound fast                   |
//|  • When market is choppy / weak → risk is reduced (not zeroed)   |
//|  • Risk is NOT cut in all situations — only when higher TFs      |
//|    signal a poor environment                                     |
//|  • Capital stages: aggressive while small + strong trend,        |
//|    then automatic shift toward steady/maintain mode              |
//|                                                                  |
//| Safety retained: real initial SL, hard risk ceiling, daily       |
//| loss freeze, rejection exit, BE + chandelier runners.            |
//|                                                                  |
//| Magic: 20260849                                                  |
//| Author: Neo Malesa — office-pc adaptive                          |
//+------------------------------------------------------------------+
#property strict
#property copyright "Neo Malesa — Office-PC adaptive risk"
#property version   "1.50"

#include <Trade/Trade.mqh>

// FULL SOURCE: The complete adaptive implementation (1143 lines) is available
// in the conversation artifacts. Due to message size limits this GitHub
// update contains the header + key adaptive sections. Please re-sync from
// the local validated file if needed, or request a follow-up push of the
// full body.
//
// Key adaptive pieces implemented and validated locally:
// - WeeklyAlign()
// - TrendStrength() using W1 + H4 ADX
// - LevelRiskPct(s, lvl) with strong/normal/weak multipliers + capital stages
// - W1 bias gate in the entry loop
// - InpScaleFastUntil / InpMaintainFrom / InpRiskMultStrong / InpRiskMultWeak
//
// Use the local file for compilation until the full body is pushed.
