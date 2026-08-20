//+------------------------------------------------------------------+
//| Ichimoku Bottom-Up Stack EA — M30 BIAS variant (EXPERIMENT)      |
//| THIRD MOST PROFITABLE VERSION SO FAR (user report, 2026-08-20) — |
//| the -third-most-profitable suffix marks its rank in the family:  |
//| behind m1-strict-cloud-bias-ea-most-profitable (1st, $100 ->     |
//| $14000 Jan-Aug 2026) and m1m5-strict-cloud-bias-ea-second-most-  |
//| profitable (2nd).                                                 |
//| Fork of ichimoku-h4-m1-vps-ea.mq5 (the live H1-bias bottom-up    |
//| VPS build, magic 20260850), which is left untouched.             |
//| The parent's full behaviour is preserved — H4 bias primary, H1   |
//| stand-in for the lower tiers, five tradable tiers, kumo-touch    |
//| exits, D1 filter on the H4 tier — with TWO experimental changes: |
//|   A. NEW KUMO-BREAKOUT DEFINITION, ALL TIMEFRAMES M1..D1. A      |
//|      valid kumo breakout anywhere in the stack (the per-TF test  |
//|      behind the entry chains and the H4/H1 biases, the D1 filter |
//|      and the M30 gate) is now: price beyond the kumo AND chikou  |
//|      beyond the kumo at its own position AND the tenkan/kijun    |
//|      twist carrying the direction (tenkan > kijun bullish,       |
//|      < bearish). The old per-line conditions (price and chikou   |
//|      above tenkan/kijun individually, chikou above the prior     |
//|      high / below the prior low) no longer apply.                |
//|   B. M30 BIAS (last-resort stand-in). When there is NO H4 bias   |
//|      and NO H1 bias (H4 flat and H1 flat), the two smallest      |
//|      tiers may still open provided M30 shows the valid kumo      |
//|      breakout of definition A. Under this M30 bias ONLY the      |
//|      m1-m5 chain (M5 tier) and the m1-m5-m15 chain (M15 tier)    |
//|      fire — M30/H1/H4 tiers never use the stand-in — and those   |
//|      trades CLOSE WHEN A CANDLE CLOSES BEYOND THE HIGHEST        |
//|      TIMEFRAME'S TENKAN SEN — not on a touch: the M5 tier exits  |
//|      on an M5 candle close beyond the M5 tenkan, the M15 tier on |
//|      an M15 candle close beyond the M15 tenkan. The position     |
//|      comment carries a "T" suffix for these trades (e.g. "Exp    |
//|      Buy M5T") so the exit mode survives a restart.              |
//| Entry: per-TF kumo breakout (definition A above), checked        |
//|        BOTTOM-UP: a tier opens only when the full stack          |
//|        M1..tier TF shows the breakout in one direction:          |
//|          Tier M5 : M1 + M5 aligned              -> open trade     |
//|          Tier M15: M1 + M5 + M15 aligned        -> open trade     |
//|          Tier M30: M1 + M5 + M15 + M30 aligned  -> open trade     |
//|          Tier H1 : M1 ... H1 aligned            -> open trade     |
//|          Tier H4 : M1 ... H4 aligned            -> open trade     |
//|        M1 alone never trades — it is only the start of the stack. |
//|        The cloud bias gate (Span A vs Span B) applies to the tier |
//|        TF and the TF directly below it, H4 is the bias for the    |
//|        whole stack (H4 bullish -> buys only, bearish -> sells     |
//|        only, flat -> no trades unless a stand-in covers it), the  |
//|        H1 stand-in lets the tiers at or below InpH1BiasMaxTier    |
//|        open when H4 is flat, and the M30 bias (InpM30Bias) covers |
//|        the M5/M15 tiers when H4 AND H1 are both flat. The H4      |
//|        tier stays gated by the D1 bias as in the parent.          |
//| Exit:  parent-authorised trades (H4/H1) close on a TOUCH of the   |
//|        level TF's cloud edge, exactly as in the parent. The       |
//|        M30-authorised M5/M15 trades close when a CANDLE CLOSES    |
//|        BEYOND the highest timeframe's TENKAN SEN — the M5 tier on |
//|        an M5 candle close beyond the M5 tenkan, the M15 tier on   |
//|        an M15 candle close beyond the M15 tenkan — never the      |
//|        cloud, and never on a mere touch.                          |
//|        A very strong REJECTION candle against the trade also      |
//|        closes it (parent conditions: sweep of the recent swing    |
//|        extreme of InpRejSwingBars bars, wick >= InpRejWickPct of  |
//|        the range, close in the outer InpRejClosePct — all four    |
//|        must hold). No entry stop loss in this build — the trade   |
//|        runs until an exit, with the profit protection layer       |
//|        taking over once it turns green:                           |
//|          Break-even   : profit >= ATR threshold (tighter for the  |
//|                         H1/H4 levels) -> SL to entry + cover      |
//|          Chandelier   : H1/H4 levels trail the stop behind the    |
//|                         peak once profitable (InpTrailActivateATR);|
//|                         M5/M15/M30 keep the spike-gated trail     |
//|                         (InpSpikeLockATR), only ever tightening   |
//|        ATR comes from each level's own TF.                        |
//| Risk:  the parent's — single position per level per symbol,       |
//|        consolidation (largest aligned tier opens), three equity   |
//|        regimes that de-risk as the account grows, ATR-based       |
//|        sizing, no multipliers.                                    |
//| VPS:   inherited from the parent — no Alert() popups and no       |
//|        equity alert; every entry/exit sends a SendNotification    |
//|        push and a journal Print, and all logic runs only on       |
//|        closed M1 bars (once per minute) to keep CPU/network use   |
//|        negligible.                                                |
//| Magic: 20260855 — fresh, so this experiment never adopts or       |
//|        manages positions belonging to the live builds (20260850   |
//|        VPS, 20260852 desktop) or any other fork.                  |
//| Author: Neo Malesa                                               |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

//--- Input Parameters ---
input string Symbols  = "GOLDm#";
input int    Tenkan   = 9;
input int    Kijun    = 26;
input int    SenkouB  = 52;
input int    Slippage = 30;

input group  "Risk Management (per level, % of actual equity)"
input double InpFixedLots       = 0.10;   // Fixed lots fallback (sizing data unavailable)
input double InpRiskATRMult     = 2.0;    // Reference stop distance = ATR(level TF) x this (risk sizing basis)
input double InpRiskTier2At     = 7000.0; // Equity where risk drops to tier 2 (half regime)
input double InpRiskTier3At     = 13000.0;// Equity where risk drops to tier 3 (tiny regime)
input double InpRiskPctM5       = 1.0;    // M5   — tier 1 (equity < Tier2At)
input double InpRiskPctM15      = 1.0;    // M15  — tier 1
input double InpRiskPctM30      = 5.0;    // M30  — tier 1
input double InpRiskPctH1       = 10.0;   // H1   — tier 1
input double InpRiskPctH4       = 20.0;   // H4   — tier 1
input double InpRiskPctM5_T2    = 0.5;    // M5   — tier 2 (half regime)
input double InpRiskPctM15_T2   = 0.5;    // M15  — tier 2
input double InpRiskPctM30_T2   = 2.5;    // M30  — tier 2
input double InpRiskPctH1_T2    = 5.0;    // H1   — tier 2
input double InpRiskPctH4_T2    = 10.0;   // H4   — tier 2
input double InpRiskPctM5_T3    = 0.1;    // M5   — tier 3 (equity >= Tier3At)
input double InpRiskPctM15_T3   = 0.1;    // M15  — tier 3
input double InpRiskPctM30_T3   = 0.2;    // M30  — tier 3
input double InpRiskPctH1_T3    = 1.0;    // H1   — tier 3
input double InpRiskPctH4_T3    = 2.0;    // H4   — tier 3

// H1 stand-in bias mode — what the lower tiers may do when the H4 bias
// does not carry the trade.
//   H1BIAS_OFF     : no stand-in; H4 governs every tier on its own
//   H1BIAS_FLAT_H4 : stand-in allowed only while H4 is FLAT (unaligned /
//                    in its cloud) — never against an aligned H4
//   H1BIAS_ALWAYS  : stand-in allowed even when H4 is aligned the OTHER
//                    way (counter-H4 trading on the lower tiers)
enum ENUM_H1_BIAS_MODE { H1BIAS_OFF = 0, H1BIAS_FLAT_H4 = 1, H1BIAS_ALWAYS = 2 };

// Highest tier permitted to enter on the H1 stand-in bias. The H4 tier is
// deliberately absent — it always needs H4 (and D1) itself.
enum ENUM_H1_BIAS_TIER { H1TIER_M5 = 0, H1TIER_M15 = 1, H1TIER_M30 = 2, H1TIER_H1 = 3 };

input group  "Entry Filters"
input bool   InpCloudBiasEnabled = true;   // Require Span A vs Span B bias on the level TF + the TF below
input bool   InpH4Bias           = true;   // H4 is the bias — tiers trade in H4's direction (H4 flat = no trades unless the H1 bias stands in)
input bool   InpD1Filter         = true;   // D1 filter for the H4 tier: H4 trades only in the D1's direction; D1 in the cloud = no H4 trades
input int    InpMaxSpreadPoints  = 60;     // Max spread in points to allow entry (0 = no limit)

input group  "H1 Bias (lets the lower tiers trade when H4 is flat)"
input ENUM_H1_BIAS_MODE InpH1BiasMode    = H1BIAS_FLAT_H4; // 0=off (H4 only), 1=stand in only while H4 is flat, 2=stand in even against an aligned H4
input ENUM_H1_BIAS_TIER InpH1BiasMaxTier = H1TIER_M30;     // Highest tier allowed to enter on the H1 bias (0=M5, 1=M15, 2=M30, 3=H1)
input bool   InpH1BiasCloudCheck = true;   // Also require the H1 cloud (Span A vs Span B) to carry the trade's bias

input group  "M30 Bias (last-resort stand-in for the small tiers)"
input bool   InpM30Bias = true;   // When H4 and H1 are BOTH flat, the M5/M15 tiers may open on M30's valid kumo breakout (price + chikou beyond kumo + tenkan > kijun); these trades exit on the highest-TF tenkan sen instead of the cloud

input group  "Profit Protection"
input int    InpATRPeriod         = 14;    // ATR period (each level uses its own TF's ATR)
input double InpBEProfitATR       = 1.0;   // BE arms once profit >= this x ATR (M5/M15/M30 levels)
input double InpBEProfitH1H4      = 0.5;   // BE arms once profit >= this x ATR (H1/H4 levels — tighter)
input int    InpBECoverPoints     = 15;    // Points beyond entry for the BE stop (covers spread)
input double InpSpikeLockATR      = 2.0;   // Chandelier trail arms once profit >= this x ATR (M5/M15/M30 spike lock)
input double InpTrailActivateATR  = 0.5;   // H1/H4 chandelier trail arms once profit >= this x ATR
input double InpTrailATR          = 1.0;   // Trail distance behind the peak, x ATR (level TF)

input group  "Rejection Exit (strong rejection candle)"
input bool   InpRejectionExit = false;  // Close a trade when a very strong rejection candle forms against it on the tier TF
input int    InpRejSwingBars  = 8;      // Recent swing window (bars) the rejection candle must sweep
input double InpRejWickPct    = 0.5;    // Wick must be >= this fraction of the candle's total range
input double InpRejClosePct   = 0.35;   // Close must sit in the outermost this fraction of the range (strong close-back)

//--- Constants and Global Variables ---
#define MAX_SYMS 60
#define LEVELS   5      // tradable levels: M5, M15, M30, H1, H4
#define TFS      6      // stack: M1, M5, M15, M30, H1, H4
#define IDX_H1   4      // index of H1 in tfs[] — the stand-in bias TF
#define IDX_H4   5      // index of H4 in tfs[] — the primary bias TF
#define IDX_M30  3      // index of M30 in tfs[] — the last-resort bias TF

ENUM_TIMEFRAMES tfs[TFS] = { PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4 };
string          tfName[TFS] = { "M1", "M5", "M15", "M30", "H1", "H4" };

int      ich[MAX_SYMS][TFS];
int      ichD1[MAX_SYMS];           // D1 ichimoku handle — H4-tier bias filter
int      atr[MAX_SYMS][LEVELS];       // ATR(level TF) — BE and spike-lock trail sizing
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar[MAX_SYMS];
int      state[MAX_SYMS][LEVELS];     // per level: 0 = flat, 1 = long, -1 = short
int      lastMinuteKey = -1;

double   entryPrice[MAX_SYMS][LEVELS];   // reference entry price per level (BE + trail arming)
double   peakHigh[MAX_SYMS][LEVELS];     // highest high since entry (long chandelier reference)
double   peakLow[MAX_SYMS][LEVELS];      // lowest low since entry (short chandelier reference)
bool     beMoved[MAX_SYMS][LEVELS];      // BE stop already moved to break even (one-shot)
bool     tenkanExit[MAX_SYMS][LEVELS];   // true = M30-bias trade — exits on the tier TF's tenkan sen, not the cloud

int MAGIC = 20260855;   // fresh — M30-bias experiment (VPS 20260850, desktop 20260852)

CTrade trade;

//==============================================================
// Initialization and Deinitialization
//==============================================================

int ParseSymbols(string list)
{
   string parts[];
   int n = StringSplit(list, ',', parts);
   int cnt = 0;
   for(int i = 0; i < n && cnt < MAX_SYMS; i++)
   {
      string sym = parts[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);
      if(StringLen(sym) == 0) continue;
      bool dup = false;
      for(int j = 0; j < cnt; j++)
         if(syms[j] == sym) { dup = true; break; }
      if(dup) continue;
      if(SymbolSelect(sym, true)) syms[cnt++] = sym;
   }
   return cnt;
}

int OnInit()
{
   symsCount = ParseSymbols(Symbols);
   if(symsCount <= 0) return(INIT_FAILED);

   for(int s = 0; s < symsCount; s++)
   {
      lastM1bar[s] = 0;
      for(int l = 0; l < LEVELS; l++)
      {
         state[s][l] = 0;
         entryPrice[s][l] = 0.0;
         peakHigh[s][l]   = 0.0;
         peakLow[s][l]    = 0.0;
         beMoved[s][l]    = false;
         tenkanExit[s][l] = false;
      }

      for(int t = 0; t < TFS; t++)
      {
         ich[s][t] = iIchimoku(syms[s], tfs[t], Tenkan, Kijun, SenkouB);
         if(ich[s][t] == INVALID_HANDLE) return(INIT_FAILED);
      }

      ichD1[s] = iIchimoku(syms[s], PERIOD_D1, Tenkan, Kijun, SenkouB);
      if(ichD1[s] == INVALID_HANDLE) return(INIT_FAILED);

      for(int l = 0; l < LEVELS; l++)
      {
         atr[s][l] = iATR(syms[s], tfs[l + 1], InpATRPeriod);
         if(atr[s][l] == INVALID_HANDLE) return(INIT_FAILED);
      }
   }

   trade.SetDeviationInPoints(Slippage);
   trade.SetExpertMagicNumber(MAGIC);
   SyncStateFromPositions();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   for(int s = 0; s < symsCount; s++)
   {
      for(int t = 0; t < TFS; t++)
         if(ich[s][t] != INVALID_HANDLE) IndicatorRelease(ich[s][t]);
      if(ichD1[s] != INVALID_HANDLE) IndicatorRelease(ichD1[s]);
      for(int l = 0; l < LEVELS; l++)
         if(atr[s][l] != INVALID_HANDLE) IndicatorRelease(atr[s][l]);
   }
}

//==============================================================
// Position State Sync (recover after restart)
//==============================================================

string LevelComment(int lvl, int dir)
{
   return (dir == 1 ? "Exp Buy " : "Exp Sell ") + tfName[lvl + 1];
}

// Tenkan-exit variant: M30-bias trades carry a "T" suffix so the exit mode
// survives a restart (e.g. "Exp Buy M5T" exits on the M5 tenkan, while
// "Exp Buy M5" exits on the M5 cloud like the parent).
string LevelCommentT(int lvl, int dir)
{
   return LevelComment(lvl, dir) + "T";
}

// Match a position comment to a level/direction; writes the exit mode into
// 'isTenkan' (true = tenkan-sen exit for an M30-bias trade).
bool MatchLevelComment(string comm, int lvl, int dir, bool &isTenkan)
{
   if(comm == LevelComment(lvl, dir))  { isTenkan = false; return true; }
   if(comm == LevelCommentT(lvl, dir)) { isTenkan = true;  return true; }
   return false;
}

// Rebuild per-level state from the positions on the account so a restart
// mid-trade resumes the correct levels. The position comment carries the
// level (e.g. "Exp Buy M15") and, for M30-bias trades, a "T" suffix that
// restores the tenkan exit mode. Entry/peak/BE memory is rebuilt from the
// open price for a restart mid-trade and cleared when the level is flat.
void SyncStateFromPositions()
{
   bool hasPos[MAX_SYMS][LEVELS];
   for(int s = 0; s < symsCount; s++)
   {
      for(int l = 0; l < LEVELS; l++)
      {
         state[s][l] = 0;
         hasPos[s][l] = false;
      }
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      string sym   = PositionGetString(POSITION_SYMBOL);
      int    magic = (int)PositionGetInteger(POSITION_MAGIC);
      int    type  = (int)PositionGetInteger(POSITION_TYPE);
      string comm  = PositionGetString(POSITION_COMMENT);

      if(magic != MAGIC) continue;

      int dir = (type == POSITION_TYPE_BUY) ? 1 : -1;

      for(int s = 0; s < symsCount; s++)
      {
         if(syms[s] != sym) continue;
         for(int l = 0; l < LEVELS; l++)
         {
            bool isTenkan = false;
            if(MatchLevelComment(comm, l, 1, isTenkan) || MatchLevelComment(comm, l, -1, isTenkan))
            {
               state[s][l] = dir;
               tenkanExit[s][l] = isTenkan;
               hasPos[s][l] = true;
               // EA (re)started mid-trade — rebuild the peak reference from
               // the open price and let it accumulate fresh extremes from here
               if(entryPrice[s][l] == 0.0)
               {
                  entryPrice[s][l] = PositionGetDouble(POSITION_PRICE_OPEN);
                  peakHigh[s][l]   = entryPrice[s][l];
                  peakLow[s][l]    = entryPrice[s][l];
               }
               break;
            }
         }
      }
   }

   // Levels with no open position get their protection memory cleared
   for(int s = 0; s < symsCount; s++)
   {
      for(int l = 0; l < LEVELS; l++)
      {
         if(!hasPos[s][l])
         {
            entryPrice[s][l] = 0.0;
            peakHigh[s][l]   = 0.0;
            peakLow[s][l]    = 0.0;
            beMoved[s][l]    = false;
            tenkanExit[s][l] = false;
         }
      }
   }
}

//==============================================================
// Alignment Check — NEW KUMO-BREAKOUT DEFINITION (applies to
// every timeframe from M1 to D1, entry chains and biases alike).
// A valid kumo breakout on a timeframe requires, in the trade's
// direction:
//   * PRICE beyond the kumo — the last closed bar's close above
//     the cloud's upper edge (bullish) / below the lower edge
//     (bearish), and
//   * CHIKOU beyond the kumo — the chikou span (that same close
//     plotted Kijun bars back) beyond the cloud at its own
//     position, and
//   * THE TWIST — tenkan > kijun (bullish) / tenkan < kijun
//     (bearish) on the last closed bar.
// Nothing else: the old per-line conditions (price and chikou
// above tenkan/kijun individually, chikou above the prior high/
// below the prior low) are gone. Returns 1 (bullish), -1
// (bearish), 0 (none).
//==============================================================

int CheckAlign(int s, int tfIdx)
{
   ENUM_TIMEFRAMES tf = tfs[tfIdx];

   int sh      = 1;              // last closed bar
   int chShift = sh + Kijun;     // chikou's chart position for bar sh (Kijun bars back)

   MqlRates rt[];
   if(CopyRates(syms[s], tf, 0, chShift + 1, rt) <= 0) return 0;
   ArraySetAsSeries(rt, true);

   if(ArraySize(rt) <= chShift) return 0;

   double tenkan[1], kijun[1], senA[1], senB[1];
   if(CopyBuffer(ich[s][tfIdx], 0, sh, 1, tenkan) <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 1, sh, 1, kijun)  <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 2, sh, 1, senA)   <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 3, sh, 1, senB)   <= 0) return 0;

   double closeP = rt[sh].close;
   double cHi    = MathMax(senA[0], senB[0]);
   double cLo    = MathMin(senA[0], senB[0]);

   bool priceAbove = (closeP > cHi);
   bool priceBelow = (closeP < cLo);
   if(!priceAbove && !priceBelow) return 0;   // price inside the kumo

   double senA_ch[1], senB_ch[1];
   if(CopyBuffer(ich[s][tfIdx], 2, chShift, 1, senA_ch) <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 3, chShift, 1, senB_ch) <= 0) return 0;

   double chik = closeP;                        // chikou span value for bar sh
   double cHiC = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC = MathMin(senA_ch[0], senB_ch[0]);

   // Price + chikou beyond the kumo, twist carrying the direction
   if(priceAbove && chik > cHiC && tenkan[0] > kijun[0]) return  1;
   if(priceBelow && chik < cLoC && tenkan[0] < kijun[0]) return -1;

   return 0;
}

//==============================================================
// Chain Check (bottom-up): the full stack M1..topIdx must be
// aligned in the SAME direction for a level to open.
//==============================================================

int ChainAligned(int s, int topIdx)
{
   int dir = CheckAlign(s, 0);
   if(dir == 0) return 0;

   for(int t = 1; t <= topIdx; t++)
   {
      if(CheckAlign(s, t) != dir) return 0;
   }
   return dir;
}

//==============================================================
// Daily Bias Filter (H4 tier): D1 is the bias for H4 trades.
// Same NEW kumo-breakout definition as CheckAlign but on D1 —
// D1 bullish (price + chikou beyond the kumo AND tenkan > kijun)
// allows only H4 buys, D1 bearish only H4 sells. A D1 close
// INSIDE the cloud (or unreadable) returns 0 — no new H4 trades
// then.
//==============================================================

int DailyAlign(int s)
{
   ENUM_TIMEFRAMES tf = PERIOD_D1;

   int sh      = 1;
   int chShift = sh + Kijun;

   MqlRates rt[];
   if(CopyRates(syms[s], tf, 0, chShift + 1, rt) <= 0) return 0;
   ArraySetAsSeries(rt, true);
   if(ArraySize(rt) <= chShift) return 0;

   double tenkan[1], kijun[1], senA[1], senB[1];
   if(CopyBuffer(ichD1[s], 0, sh, 1, tenkan) <= 0) return 0;
   if(CopyBuffer(ichD1[s], 1, sh, 1, kijun)  <= 0) return 0;
   if(CopyBuffer(ichD1[s], 2, sh, 1, senA)   <= 0) return 0;
   if(CopyBuffer(ichD1[s], 3, sh, 1, senB)   <= 0) return 0;

   double closeP = rt[sh].close;
   double cHi    = MathMax(senA[0], senB[0]);
   double cLo    = MathMin(senA[0], senB[0]);

   bool priceAbove = (closeP > cHi);
   bool priceBelow = (closeP < cLo);
   if(!priceAbove && !priceBelow) return 0;   // D1 close inside the cloud — no H4 trades

   double senA_ch[1], senB_ch[1];
   if(CopyBuffer(ichD1[s], 2, chShift, 1, senA_ch) <= 0) return 0;
   if(CopyBuffer(ichD1[s], 3, chShift, 1, senB_ch) <= 0) return 0;

   double chik = closeP;                        // chikou span value for bar sh
   double cHiC = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC = MathMin(senA_ch[0], senB_ch[0]);

   // Price + chikou beyond the kumo, twist carrying the direction
   if(priceAbove && chik > cHiC && tenkan[0] > kijun[0]) return  1;
   if(priceBelow && chik < cLoC && tenkan[0] < kijun[0]) return -1;

   return 0;
}

//==============================================================
// Cloud Bias Filter: the cloud must carry the trade's bias
// (Span A above Span B for a long, below for a short) at both
// the last closed bar and the far end of the future-cloud
// window. Unreadable values count as blocking.
//==============================================================

bool CloudBiasOK(int s, int tfIdx, int dir)
{
   double aNow[1], bNow[1], aFar[1], bFar[1];
   if(CopyBuffer(ich[s][tfIdx], 2, 1,         1, aNow) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, 1,         1, bNow) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 2, 1 - Kijun, 1, aFar) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, 1 - Kijun, 1, bFar) <= 0) return false;

   if(dir == 1) return aNow[0] > bNow[0] && aFar[0] > bFar[0];
   return aNow[0] < bNow[0] && aFar[0] < bFar[0];
}

// The bias must hold on the level TF and the TF directly below it
// (level lvl opens on TF lvl+1, so the pair is TF lvl and TF lvl+1).
bool LevelCloudBiasOK(int s, int lvl, int dir)
{
   if(!CloudBiasOK(s, lvl + 1, dir)) return false;
   if(!CloudBiasOK(s, lvl, dir))     return false;
   return true;
}

//==============================================================
// H4 Bias Filter: H4 is the bias for the whole stack. Every tier
// only trades in H4's direction — H4 bullish means only buys on
// all timeframes (a lower-TF sell is just a pullback), H4 bearish
// means only sells. If H4 has no alignment, no trades open —
// except on the tiers the new H1 stand-in bias covers (below).
//==============================================================

int H4Bias(int s)
{
   return CheckAlign(s, IDX_H4);    // 1 = bullish, -1 = bearish, 0 = flat/unreadable
}

// Raw H1 alignment — 1 = bullish, -1 = bearish, 0 = flat/unreadable.
// (NEW) Used by the M30 bias gate to verify that H1 carries NO direction
// of its own before the last-resort stand-in may apply.
int H1Bias(int s)
{
   return CheckAlign(s, IDX_H1);
}

//==============================================================
// H1 Bias Filter (NEW). The stand-in bias for the lower tiers:
// same alignment test as the H4 bias, one timeframe down, with
// an optional H1 cloud-bias confirmation on top. It is only ever
// consulted by EntryBiasOK() below, and only for the tiers the
// user has opened up via InpH1BiasMaxTier.
//==============================================================

bool H1BiasOK(int s, int dir)
{
   int h1 = CheckAlign(s, IDX_H1);
   if(h1 != dir) return false;      // H1 flat or opposed — nothing to stand in with

   // Optional extra confirmation: the H1 kumo itself must be twisted the
   // trade's way, now and at the far end of the future cloud.
   if(InpH1BiasCloudCheck && !CloudBiasOK(s, IDX_H1, dir)) return false;

   return true;
}

// Is this tier allowed to fall back on the H1 bias at all?
bool H1BiasTier(int lvl)
{
   if(InpH1BiasMode == H1BIAS_OFF)     return false;
   if(lvl >= LEVELS - 1)               return false;   // never the H4 tier
   return lvl <= (int)InpH1BiasMaxTier;
}

//==============================================================
// M30 Bias Filter (NEW). The last-resort stand-in for the two
// smallest tiers. It is only consulted when there is NO H4 bias
// and NO H1 bias (H4 flat and H1 flat) and requires a valid kumo
// breakout on M30 — the SAME definition as every other timeframe
// from M1 to D1 (see CheckAlign): price beyond the kumo, chikou
// beyond the kumo at its own position, and the tenkan/kijun
// twist carrying the direction (tenkan > kijun bullish,
// < bearish).
//==============================================================

bool M30BreakoutOK(int s, int dir)
{
   return CheckAlign(s, IDX_M30) == dir;
}

//==============================================================
// Entry Bias Gate: H4 primary, H1 stand-in for the lower tiers,
// M30 last-resort stand-in for the two smallest tiers.
//
//   1. H4 aligned WITH the trade  -> allowed, whatever the tier.
//      This is the primary path.
//   2. H4 FLAT -> the tiers at or below InpH1BiasMaxTier may still
//      open if H1 carries the trade — an undecided H4 no longer
//      freezes the whole stack.
//   3. H4 FLAT AND H1 FLAT -> the M5 and M15 tiers may still open
//      if M30 shows the valid kumo breakout (definition A: price +
//      chikou beyond the kumo + the tenkan/kijun twist). These
//      trades exit on the highest-TF tenkan sen, not the cloud.
//   4. H4 aligned AGAINST the trade -> still blocked, unless the
//      user opts into H1BIAS_ALWAYS. The M30 bias never stands in
//      against an aligned H4 or an aligned H1 — it applies ONLY
//      when there is no H4 or H1 bias at all.
//
// Writes into 'via' the bias that authorised the entry so the caller
// can log it: "H4", "H1" (stand-in on a flat H4), "H1x" (stand-in
// against an aligned H4), "M30" (last-resort kumo breakout), "--"
// when no bias gate applied at all.
//==============================================================

bool EntryBiasOK(int s, int lvl, int dir, string &via)
{
   via = "--";

   if(!InpH4Bias)
   {
      // H4 bias switched off: the H1 stand-in, where enabled, is the only
      // directional gate left on those tiers. Higher tiers stay ungated,
      // exactly as they were when the H4 bias is switched off.
      if(!H1BiasTier(lvl)) return true;
      if(!H1BiasOK(s, dir)) return false;
      via = "H1";
      return true;
   }

   int h4 = H4Bias(s);
   if(h4 == dir) { via = "H4"; return true; }          // primary path

   // M30 BIAS (NEW): last-resort stand-in. Applies ONLY when there is no
   // H4 bias and no H1 bias at all — h4 flat, H1 carrying no direction —
   // and M30 shows the valid kumo breakout (price + chikou beyond the
   // kumo + the tenkan/kijun twist, same definition as every other
   // timeframe M1..D1). Only the two smallest tiers (m1-m5 and m1-m5-15
   // chains) use it, and their trades exit on the tenkan sen instead of
   // the cloud.
   if(InpM30Bias && lvl <= 1 && h4 == 0 && H1Bias(s) == 0 && M30BreakoutOK(s, dir))
   {
      via = "M30";
      return true;
   }

   if(!H1BiasTier(lvl)) return false;                  // H1/H4 tiers need H4 itself
   if(h4 != 0 && InpH1BiasMode != H1BIAS_ALWAYS)       // H4 is aligned the other way
      return false;
   if(!H1BiasOK(s, dir)) return false;

   via = (h4 == 0) ? "H1" : "H1x";   // H1x = taken against an aligned H4
   return true;
}

//==============================================================
// Exit Check: price TOUCHES the level TF's cloud edge — no wait
// for a candle to close inside it. A long (entered above the
// cloud) exits when the bid touches the cloud's upper edge; a
// short (entered below) exits when the ask touches the lower
// edge. Evaluated once per closed M1 bar, so a touch triggers
// the exit within a minute. This is the trade's main exit; the
// BE/chandelier stop is the profit-protection layer on top.
//==============================================================

bool InCloudTouch(int s, int tfIdx, int dir)
{
   double senA[1], senB[1];
   if(CopyBuffer(ich[s][tfIdx], 2, 1, 1, senA) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, 1, 1, senB) <= 0) return false;

   if(dir ==  1)
   {
      double bid = SymbolInfoDouble(syms[s], SYMBOL_BID);
      return bid <= MathMax(senA[0], senB[0]);
   }
   if(dir == -1)
   {
      double ask = SymbolInfoDouble(syms[s], SYMBOL_ASK);
      return ask >= MathMin(senA[0], senB[0]);
   }
   return false;
}

//==============================================================
// Tenkan-Sen Exit (NEW — for M30-bias trades): a CANDLE CLOSES
// BEYOND the tier TF's TENKAN SEN — not a mere touch. A long
// (entered above the tenkan) exits when the last closed tier-TF
// candle closes BELOW the tenkan; a short (entered below) exits
// when it closes ABOVE the tenkan. The tier TF is the HIGHEST
// timeframe of the trade's chain, so an M30-bias M5 tier exits
// on an M5 candle close beyond the M5 tenkan and an M30-bias M15
// tier on an M15 candle close beyond the M15 tenkan — never the
// cloud. Evaluated once per closed M1 bar, so a tier-TF close
// beyond the tenkan triggers the exit within a minute. The
// BE/chandelier stop is the profit-protection layer on top, as
// with the cloud exit.
//==============================================================

bool InTenkanClose(int s, int tfIdx, int dir)
{
   // Last closed bar of the tier TF
   MqlRates rt[];
   if(CopyRates(syms[s], tfs[tfIdx], 0, 2, rt) < 2) return false;
   ArraySetAsSeries(rt, true);

   double tenkan[1];
   if(CopyBuffer(ich[s][tfIdx], 0, 1, 1, tenkan) <= 0) return false;

   if(dir ==  1)
      return rt[1].close < tenkan[0];    // closed beyond (below) the tenkan
   if(dir == -1)
      return rt[1].close > tenkan[0];    // closed beyond (above) the tenkan
   return false;
}

//==============================================================
// Utility Functions
//==============================================================

string PCTime()
{
   MqlDateTime dt;
   TimeToStruct(TimeLocal(), dt);
   int h = dt.hour;
   string ampm = (h >= 12) ? "PM" : "AM";
   if(h == 0) h = 12;
   else if(h > 12) h -= 12;
   return IntegerToString(h) + ":" + StringFormat("%02d", dt.min) + " " + ampm;
}

bool SpreadOK(string sym)
{
   if(InpMaxSpreadPoints <= 0) return true;
   return SymbolInfoInteger(sym, SYMBOL_SPREAD) <= InpMaxSpreadPoints;
}

//==============================================================
// Risk Management — per-level risk as a fixed % of the ACTUAL
// equity at entry, in three equity tiers that DE-RISK as the
// account grows: full regime below InpRiskTier2At (M5/M15 1%,
// M30 5%, H1 10%, H4 20%), half regime between the tiers
// (0.5/0.5/2.5/5/10), and the tiny regime at InpRiskTier3At and
// above (0.1/0.1/0.2/1/2). Sizing measures the % against a
// reference distance of ATR(level TF) x InpRiskATRMult, the same
// ATR-based sizing philosophy as the H4 VPS build. More equity
// -> more risk money -> bigger lots at the same ATR distance;
// no multipliers on top. Falls back to InpFixedLots when the
// sizing data is unavailable, and every order is capped to the
// free margin so it fills fully.
//==============================================================

double LevelRiskPct(int lvl)
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   bool t3 = (eq >= InpRiskTier3At);
   bool t2 = (eq >= InpRiskTier2At);
   switch(lvl)
   {
      case 0:  return t3 ? InpRiskPctM5_T3  : t2 ? InpRiskPctM5_T2  : InpRiskPctM5;
      case 1:  return t3 ? InpRiskPctM15_T3 : t2 ? InpRiskPctM15_T2 : InpRiskPctM15;
      case 2:  return t3 ? InpRiskPctM30_T3 : t2 ? InpRiskPctM30_T2 : InpRiskPctM30;
      case 3:  return t3 ? InpRiskPctH1_T3  : t2 ? InpRiskPctH1_T2  : InpRiskPctH1;
      case 4:  return t3 ? InpRiskPctH4_T3  : t2 ? InpRiskPctH4_T2  : InpRiskPctH4;
   }
   return 0.0;
}

double RiskLots(int s, int lvl)
{
   double riskPct = LevelRiskPct(lvl);
   if(riskPct <= 0) return InpFixedLots;

   double a[1];
   if(CopyBuffer(atr[s][lvl], 0, 1, 1, a) <= 0 || a[0] <= 0) return InpFixedLots;
   double stopDist = a[0] * InpRiskATRMult;

   double tickValue = SymbolInfoDouble(syms[s], SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(syms[s], SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0) return InpFixedLots;

   double moneyPerLot = (stopDist / tickSize) * tickValue;
   if(moneyPerLot <= 0) return InpFixedLots;

   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * (riskPct / 100.0);
   double lots      = riskMoney / moneyPerLot;

   double lotStep = SymbolInfoDouble(syms[s], SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(syms[s], SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(syms[s], SYMBOL_VOLUME_MAX);
   if(lotStep > 0) lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lotMin, MathMin(lotMax, lots));

   return (lots > 0) ? lots : InpFixedLots;
}

// Scale a single order down to the free margin so it fills fully.
// lots never drops below the broker minimum.
void CapLotsToMargin(string sym, bool isBuy, double &lots)
{
   if(lots <= 0) return;
   double price = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK)
                        : SymbolInfoDouble(sym, SYMBOL_BID);
   double marginOne = 0.0;
   if(!OrderCalcMargin(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, sym, lots, price, marginOne))
      return;
   if(marginOne <= 0) return;
   double maxLots = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * lots / marginOne;
   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   if(lotStep > 0) maxLots = MathFloor(maxLots / lotStep) * lotStep;
   maxLots = MathMax(lotMin, maxLots);
   if(lots > maxLots) lots = maxLots;
}

//==============================================================
// Trading Functions
//==============================================================

// 'via' names the bias that authorised the entry ("H4", "H1" stand-in,
// "H1x" counter-H4 stand-in, "M30" last-resort breakout, "--" none) —
// logged so the bias paths are separable when reviewing the journal.
// An M30-authorised trade gets a "T" comment suffix and exits on the
// tier TF's tenkan sen instead of the cloud.
bool OpenLevel(int s, int lvl, int dir, double lots, string via)
{
   string sym = syms[s];
   bool tenkan = (via == "M30");
   string comment = tenkan ? LevelCommentT(lvl, dir) : LevelComment(lvl, dir);
   double price = (dir == 1) ? SymbolInfoDouble(sym, SYMBOL_ASK)
                             : SymbolInfoDouble(sym, SYMBOL_BID);

   // No entry stop loss in this build — the trade runs until the cloud
   // close (parent trades) or a tier-TF candle close beyond the tenkan
   // (M30-bias trades); the BE/chandelier layer protects it once in profit.
   bool ok = (dir == 1) ? trade.Buy(lots, sym, price, 0, 0, comment)
                        : trade.Sell(lots, sym, price, 0, 0, comment);
   if(ok)
   {
      state[s][lvl] = dir;
      tenkanExit[s][lvl] = tenkan;
      entryPrice[s][lvl] = price;   // BE + spike-lock trail references
      peakHigh[s][lvl]   = price;
      peakLow[s][lvl]    = price;
      beMoved[s][lvl]    = false;
      string action = (dir == 1) ? "Buy" : "Sell";
      string msg = PCTime() + " | " + action + " " + sym + " " + tfName[lvl + 1] +
                   " @ " + DoubleToString(lots, 2) + " (bottom-up, bias " + via + ")";
      Print(msg); SendNotification(msg);
   }
   return ok;
}

// Close all positions of the level; returns true only when none remain
// open, so a failed close (requote, halt) is retried instead of freeing
// the level for a fresh entry.
bool CloseLevelPositions(int s, int lvl)
{
   string sym = syms[s];
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      string comm = PositionGetString(POSITION_COMMENT);
      bool isTenkan = false;
      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC &&
         (MatchLevelComment(comm, lvl, 1, isTenkan) || MatchLevelComment(comm, lvl, -1, isTenkan)))
      {
         if(!trade.PositionClose(ticket))
            Print(PCTime() + " | " + sym + " " + tfName[lvl + 1] + " close failed, retcode " +
                  IntegerToString(trade.ResultRetcode()));
      }
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      string comm = PositionGetString(POSITION_COMMENT);
      bool isTenkan = false;
      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC &&
         (MatchLevelComment(comm, lvl, 1, isTenkan) || MatchLevelComment(comm, lvl, -1, isTenkan))) return false;
   }
   return true;
}

//==============================================================
// Profit Protection (VPS-style systems, per level):
//   * Break-even — once the trade is in profit by >= the ATR
//     threshold (InpBEProfitATR x ATR for M5/M15/M30, the tighter
//     InpBEProfitH1H4 x ATR for H1/H4), the stop moves to entry
//     plus InpBECoverPoints. One-shot per trade (beMoved).
//   * Chandelier trail — H1/H4 levels trail the stop behind the
//     peak once profitable by InpTrailActivateATR x ATR; the
//     lower levels arm it only on a spike (InpSpikeLockATR x ATR).
//     The reference is the highest high / lowest low of the level
//     TF, including the bar still forming; it only ever tightens
//     and never sits inside the broker minimum stop.
// ATR comes from the level's own TF, so H4/H1 protection is sized
// to those timeframes. No entry stop loss in this build.
//==============================================================

bool LevelTicket(int s, int lvl, ulong &ticket)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != syms[s]) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;
      string comm = PositionGetString(POSITION_COMMENT);
      bool isTenkan = false;
      if(MatchLevelComment(comm, lvl, 1, isTenkan) || MatchLevelComment(comm, lvl, -1, isTenkan)) return true;
   }
   return false;
}

void ManageLevelProtection(int s, int lvl)
{
   int dir = state[s][lvl];
   if(dir == 0) return;

   double a[1];
   if(CopyBuffer(atr[s][lvl], 0, 1, 1, a) <= 0 || a[0] <= 0) return;
   double atrVal = a[0];

   // The reference point is the extreme of the level-TF bar that is still
   // forming, so a peak is locked in before it retraces
   MqlRates tfx[];
   if(CopyRates(syms[s], tfs[lvl + 1], 0, 1, tfx) <= 0) return;
   ArraySetAsSeries(tfx, true);

   bool isLong = (dir == 1);
   if(isLong)
   {
      if(tfx[0].high > peakHigh[s][lvl]) peakHigh[s][lvl] = tfx[0].high;
   }
   else
   {
      if(tfx[0].low < peakLow[s][lvl]) peakLow[s][lvl] = tfx[0].low;
   }

   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);

   ulong ticket;
   if(!LevelTicket(s, lvl, ticket)) return;
   double slCur = PositionGetDouble(POSITION_SL);

   double bid = SymbolInfoDouble(syms[s], SYMBOL_BID);
   double ask = SymbolInfoDouble(syms[s], SYMBOL_ASK);

   // Break-even: tighter arming threshold on the long-running H1/H4 levels
   double beATR = (lvl >= 3) ? InpBEProfitH1H4 : InpBEProfitATR;
   if(!beMoved[s][lvl])
   {
      bool armed = isLong ? (bid >= entryPrice[s][lvl] + beATR * atrVal)
                          : (ask <= entryPrice[s][lvl] - beATR * atrVal);
      if(armed)
      {
         double slNew = isLong ? entryPrice[s][lvl] + InpBECoverPoints * point
                               : entryPrice[s][lvl] - InpBECoverPoints * point;
         slNew = NormalizeDouble(slNew, digits);

         bool ok = isLong ? (slNew > slCur + point && slNew < bid - minDist)
                          : (slNew < slCur - point && slNew > ask + minDist);
         if(ok)
         {
            if(!trade.PositionModify(ticket, slNew, 0))
               Print(PCTime() + " | " + syms[s] + " " + tfName[lvl + 1] + " BE SL modify failed, retcode " +
                     IntegerToString(trade.ResultRetcode()));
            else
               beMoved[s][lvl] = true;
         }
      }
   }

   // Chandelier trail behind the peak. H1/H4 levels get the full
   // chandelier: it arms once the trade is profitable by InpTrailActivateATR
   // x ATR so long-running higher-TF trades are always protected. The lower
   // levels keep the spike-gated trail (InpSpikeLockATR x ATR). Only ever
   // tightens, keeps out of the broker minimum stop distance, and skips
   // microscopic improvements (0.3x ATR).
   // Re-read the current stop first — the BE block above may have moved it.
   if(!LevelTicket(s, lvl, ticket)) return;
   slCur = PositionGetDouble(POSITION_SL);

   double armATR = (lvl >= 3) ? InpTrailActivateATR : InpSpikeLockATR;
   bool armed = isLong ? (bid >= entryPrice[s][lvl] + armATR * atrVal)
                       : (ask <= entryPrice[s][lvl] - armATR * atrVal);
   if(armed)
   {
      double slNew = isLong ? peakHigh[s][lvl] - InpTrailATR * atrVal
                            : peakLow[s][lvl] + InpTrailATR * atrVal;
      slNew = NormalizeDouble(slNew, digits);

      bool ok = isLong ? (slNew > slCur + point && slNew < bid - minDist &&
                          slNew - slCur >= 0.3 * atrVal)
                       : (slNew < slCur - point && slNew > ask + minDist &&
                          slCur - slNew >= 0.3 * atrVal);
      if(ok)
      {
         if(!trade.PositionModify(ticket, slNew, 0))
            Print(PCTime() + " | " + syms[s] + " " + tfName[lvl + 1] + " trail SL modify failed, retcode " +
                  IntegerToString(trade.ResultRetcode()));
      }
   }
}

//==============================================================
// Rejection Candle Exit: closes a trade when a VERY STRONG
// rejection forms against it on the tier TF (last closed bar).
// All four conditions must hold — a swing sweep plus a dominant
// wick plus a strong close-back on a candle whose body opposes
// the trade:
//   Bearish rejection (kills a LONG):
//     - bearish body (c1 < o1)
//     - takes out the swing high of the previous
//       InpRejSwingBars bars (h1 > highest high before it)
//     - upper wick >= InpRejWickPct of the candle's total range
//     - close in the bottom InpRejClosePct of the range
//       (closed strongly back from the sweep high)
//   Bullish rejection (kills a SHORT): mirrored.
// Returns 1 (bullish), -1 (bearish), 0 (none).
//==============================================================

int RejectionCandle(int s, int tfIdx)
{
   int need = 2 + InpRejSwingBars;
   MqlRates r[];
   if(CopyRates(syms[s], tfs[tfIdx], 0, need, r) < need) return 0;
   ArraySetAsSeries(r, true);

   double o1 = r[1].open, c1 = r[1].close, h1 = r[1].high, l1 = r[1].low;

   // Swing extreme of the InpRejSwingBars bars before the rejection candle
   double swingHi = r[2].high, swingLo = r[2].low;
   for(int i = 3; i < need; i++)
   {
      if(r[i].high > swingHi) swingHi = r[i].high;
      if(r[i].low  < swingLo) swingLo = r[i].low;
   }

   double range = h1 - l1;
   if(range <= 0) return 0;

   // Bearish rejection: sweeps the swing high and closes strongly back
   if(c1 < o1 && h1 > swingHi)
   {
      double upperWick = h1 - o1;               // bearish: high minus open
      double closeBack = c1 - l1;               // distance closed back from the low
      if(upperWick >= InpRejWickPct * range &&
         closeBack <= InpRejClosePct * range)
         return -1;
   }

   // Bullish rejection: sweeps the swing low and closes strongly back
   if(c1 > o1 && l1 < swingLo)
   {
      double lowerWick = o1 - l1;               // bullish: open minus low
      double closeBack = h1 - c1;               // distance closed back from the high
      if(lowerWick >= InpRejWickPct * range &&
         closeBack <= InpRejClosePct * range)
         return 1;
   }
   return 0;
}

// Close a level's positions with a notification; returns true only
// when nothing remains open, so a failed close is retried next bar.
bool ExitLevel(int s, int l, string reason)
{
   string side = (state[s][l] == 1) ? "Long" : "Short";
   string msg  = PCTime() + " | Close " + syms[s] + " " + side + " " +
                 tfName[l + 1] + " (" + reason + ")";
   Print(msg); SendNotification(msg);

   if(CloseLevelPositions(s, l))
   {
      state[s][l] = 0;
      msg = PCTime() + " | " + syms[s] + " " + tfName[l + 1] + " level closed";
      Print(msg); SendNotification(msg);
      return true;
   }
   Print(PCTime() + " | " + syms[s] + " " + tfName[l + 1] + " exit signal but positions still open — will retry");
   return false;
}

//==============================================================
// Main Loop
//==============================================================

void OnTick()
{
   // VPS perf: all logic runs only on closed M1 bars, which change at most
   // once per minute. Skip every intermediate tick entirely.
   int nowKey = (int)(TimeCurrent() / 60);
   if(nowKey == lastMinuteKey) return;
   lastMinuteKey = nowKey;

   bool synced = false;
   for(int s = 0; s < symsCount; s++)
   {
      // Per-symbol M1 bar gating — only act on a new closed M1 bar for this symbol
      MqlRates m1[];
      if(CopyRates(syms[s], PERIOD_M1, 0, 2, m1) < 2) continue;
      ArraySetAsSeries(m1, true);
      if(m1[1].time == lastM1bar[s]) continue;
      lastM1bar[s] = m1[1].time;

      // Sync position state once per tick on the first new M1 bar instead of
      // rebuilding it on every single tick.
      if(!synced) { SyncStateFromPositions(); synced = true; }

      // Exits and profit protection per level
      for(int l = 0; l < LEVELS; l++)
      {
         // Exit check: price touched the level TF's cloud edge (parent
         // trades) or, for M30-bias trades, a tier-TF candle closed
         // beyond the tenkan sen — the highest timeframe of the trade's
         // chain (M5 candle beyond the M5 tenkan for the M5 tier, M15
         // candle beyond the M15 tenkan for the M15 tier)
         if(state[s][l] != 0)
         {
            if(tenkanExit[s][l])
            {
               if(InTenkanClose(s, l + 1, state[s][l]))
                  ExitLevel(s, l, "tenkan close");
            }
            else
            {
               if(InCloudTouch(s, l + 1, state[s][l]))
                  ExitLevel(s, l, "kumo touch");
            }
         }

         // Rejection exit: a very strong rejection candle formed on
         // the tier TF against the trade (bearish kills a long,
         // bullish kills a short)
         if(InpRejectionExit && state[s][l] != 0)
         {
            int rj = RejectionCandle(s, l + 1);
            if(rj != 0 && rj == -state[s][l])
               ExitLevel(s, l, "rejection");
         }

         // Profit protection: BE + spike-lock chandelier trail
         if(state[s][l] != 0) ManageLevelProtection(s, l);
      }

      // Entry consolidation: when several tiers align at once, only the
      // LARGEST one opens (highest TF wins). Any smaller tier already
      // running on the symbol is closed first — e.g. M15 and M30 align
      // together: the running M15 trade closes and only M30 opens.
      int    topTier = -1;
      int    topDir  = 0;
      string topVia  = "--";
      if(SpreadOK(syms[s]))
      {
         for(int l = LEVELS - 1; l >= 0; l--)
         {
            if(state[s][l] != 0) continue;
            int st = ChainAligned(s, l + 1);
            if(st == 0) continue;
            if(InpCloudBiasEnabled && !LevelCloudBiasOK(s, l, st)) continue;

            // Directional bias: H4 as before, with the new H1 stand-in for
            // the lower tiers when H4 has no direction of its own.
            string via = "--";
            if(!EntryBiasOK(s, l, st, via)) continue;

            // H4 tier: D1 must carry the same bias (D1 in the cloud = no H4 trades)
            if(l == LEVELS - 1 && InpD1Filter && DailyAlign(s) != st) continue;

            topTier = l;
            topDir  = st;
            topVia  = via;
            break;
         }
      }

      if(topTier >= 0)
      {
         // Close any smaller (lower-tier) trades still running
         for(int l = 0; l < topTier; l++)
         {
            if(state[s][l] != 0)
            {
               string msg = PCTime() + " | Close " + syms[s] + " " + tfName[l + 1] +
                            " (superseded by " + tfName[topTier + 1] + ")";
               Print(msg); SendNotification(msg);

               if(CloseLevelPositions(s, l))
                  state[s][l] = 0;
               else
                  Print(PCTime() + " | " + syms[s] + " " + tfName[l + 1] + " superseded but positions still open — will retry");
            }
         }

         // Open only the largest tier
         double lots = RiskLots(s, topTier);
         CapLotsToMargin(syms[s], (topDir == 1), lots);

         if(!OpenLevel(s, topTier, topDir, lots, topVia))
            Print(PCTime() + " | " + syms[s] + " " + tfName[topTier + 1] +
                  " entry signal but order failed, retcode " + IntegerToString(trade.ResultRetcode()));
      }
   }
}
//This work is my worship unto GOD
