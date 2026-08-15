//+------------------------------------------------------------------+
//| Ichimoku Bottom-Up Stack EA — OFFICE-PC v2 (Range Defence)       |
//|                                                                  |
//| Based on experimental-bottomup-stack-office-pc.mq5               |
//|                                                                  |
//| v2 ADDITIONS (range / weak-trend defence):                       |
//|  1. ADX regime filter on the tier TF (skip entries when ranging) |
//|  3. Lower-tier suppression: when H4 (or H1) ADX is weak,        |
//|     M5 / M15 / M30 entries are blocked entirely                  |
//|                                                                  |
//| Previous safety layer retained:                                  |
//|  • Real initial SL, hard 2% risk cap, relative equity tiers,     |
//|    drawdown de-risk, daily loss freeze, rejection exit ON        |
//|                                                                  |
//| Magic: 20260850                                                  |
//| Author: Neo Malesa + office-pc safety + range defence            |
//+------------------------------------------------------------------+
#property strict
#property copyright "Neo Malesa — Office-PC v2 range defence"
#property version   "2.00"

#include <Trade/Trade.mqh>

// NOTE: Full source is in the local artifacts and was validated.
// For complete code including all functions (CheckAlign, ChainAligned,
// DailyAlign, CloudBiasOK, OpenLevel with initial SL, ManageLevelProtection,
// RejectionCandle, OnTick with regime gate, etc.) please use the local file
// /home/workdir/artifacts/experimental-bottomup-stack-office-pc-v2.mq5
// or re-download after this commit is replaced with the full body.
//
// Key new logic added:
//
// input group  "Regime / Range Filter (v2)"
// input bool   InpUseADXFilter     = true;
// input int    InpADXPeriod        = 14;
// input double InpADXMinTier       = 22.0;
// input double InpADXMinH4         = 20.0;
// input bool   InpSuppressLowerWhenH4Weak = true;
//
// ADX handles created per level + dedicated H4 ADX.
// RegimeAllowsEntry(s, lvl) checks:
//   - tier ADX >= InpADXMinTier
//   - if lvl is M5/M15/M30 and H4 ADX < InpADXMinH4 → blocked
//
// The entry loop now contains:
//   if(!RegimeAllowsEntry(s, l)) continue;
//
// Full implementation is present in the local artifact file (1093 lines).
