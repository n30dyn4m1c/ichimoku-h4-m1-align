//+------------------------------------------------------------------+
//| Ichimoku Bottom-Up Stack EA — WINDOWS-LAPTOP + OVEREXTENSION      |
//| PROTECTION variant                                                |
//|                                                                  |
//| Fork of experimental-bottomup-stack-ea-very-profitable-windows-  |
//| laptop.mq5 (magic 20260850) adding a dedicated H4 PULLBACK GUARD: |
//| the strongest lower-TF signs that a stretched H4 move is about to |
//| pull back to the cloud. Fresh magic 20260851.                     |
//|                                                                  |
//| THE PROBLEM: the stack only enters WITH the H4 trend, so at the   |
//| peak of a stretched H4 move it buys exactly when the reversion    |
//| to the cloud is the dominant move. The plain 3-factor overexten-  |
//| sion filter (InpOverextDistATR/CandleATR/NoTouch) already blocks  |
//| H1/H4 tier entries — this variant extends protection to ALL       |
//| tiers and adds the strong reversal confirmations.                 |
//|                                                                  |
//| THE STRONG SIGNS (research summary):                             |
//|  * TURTLE SOUP — price sweeps the recent swing high/low (stops    |
//|    are run) and CLOSES back inside: the breakout failed and the   |
//|    trapped traders fuel the reversal. One of the strongest        |
//|    exhaustion triggers (Raschke/Hougaard; the repo used a turtle  |
//|    soup exit before 1d5ac0e replaced it with the rejection        |
//|    candle).                                                       |
//|  * REJECTION CANDLE — the repo's proven strong reversal candle    |
//|    (swing sweep + dominant wick + strong close-back), applied on  |
//|    the LOWER TFs.                                                 |
//|  * LOWER-TF PRECURSORS — H4 moves start and end on H1/M30 first:  |
//|    a rejection or turtle soup against the H4 trend on H1 or M30   |
//|    while H4 is stretched is the rollover beginning.               |
//|  * TENKAN-KIJUN CROSS on M30 against the H4 trend — ichimoku's    |
//|    classic first reversal signal on the timeframe below H4.       |
//|  * CHIKOU SPAN on H4 entering the price range — the H4 trend's    |
//|    own confirmation breaking down.                                |
//|  * EXTREME STRETCH — close >= InpOverextExtremeATR x ATR(H4) from |
//|    tenkan/kijun/cloud: reversion is near-certain by itself.       |
//|                                                                  |
//| HOW THE GUARD WORKS (H4PullbackGuard, default ON):                |
//|  * Tier 1 — EXTREME stretch alone (>= InpOverextExtremeATR,       |
//|    default 5 ATR) -> NO entries at all (any tier).                |
//|  * Tier 2 — normal stretch (H4Overextended) AND at least          |
//|    InpGuardMinConfirms (default 2) of 6 sub-signals firing        |
//|    TOGETHER, with H1/M30 bar signals required to print AT the     |
//|    H4 move's extreme (within InpGuardExtremeATR x ATR(H4)) ->     |
//|    NO entries at all.                                             |
//|  * Stretch without high-conviction confirmation -> previous       |
//|    behavior (only H1/H4 tier entries blocked; lower tiers trade). |
//|  * Guard only blocks ENTRIES. Open runners still exit on kumo     |
//|    touch / rejection candle / BE+trail — the pullback to the      |
//|    cloud is their normal exit point.                              |
//|                                                                  |
//| REVISION v2 (first backtest: guard blocked almost everything and  |
//| the removed trades were the profitable ones):                     |
//|  * FIXED BUG: the H4 chikou check was inverted — it compared the  |
//|    close 27 bars ago against the current high, which fires almost |
//|    constantly during trends, so the guard blocked ALL entries     |
//|    whenever H4 looked stretched. Now the mirror of CheckAlign:    |
//|    current close vs the price range 26 bars back.                 |
//|  * Any-1-of-4 OR-logic replaced by a SCORED confirmation (2 of 6  |
//|    sub-signals: rejection H1, rejection M30, turtle H1, turtle    |
//|    M30, M30 tenkan-kijun cross, H4 chikou).                       |
//|  * SPATIAL FILTER: H1/M30 rejection/turtle bars count only when   |
//|    they print AT the H4 move's extreme — a rejection at the       |
//|    bottom of a routine pullback is not an H4 top, one at the      |
//|    extreme is.                                                    |
//|  * Lookback reduced to 2 bars. The guard now fires only on        |
//|    high-conviction exhaustion setups, preserving the M5/M15/M30   |
//|    flow that the backtest showed is profitable during stretches.  |
//|                                                                  |
//| Everything else is identical to the windows-laptop build: one     |
//| position per symbol, disaster stop, re-entry cooldown, per-tick   |
//| kumo exits, alignment cache, ADX + overextension + D1 + H4 bias,  |
//| KUMO_CLOSE option, news blackout, rejection exit, BE +            |
//| chandelier, 3-tier risk regimes, consolidation, notifications.    |
//| Magic: 20260851                                                  |
//| Author: Neo Malesa                                               |
//+------------------------------------------------------------------+
#property strict
#property copyright "Neo Malesa — Windows-laptop + overextension protection build"
#property version   "1.01"

#include <Trade/Trade.mqh>

//--- Kumo exit mode: touch (aggressive) or tier-TF bar close (rides trends)
enum ENUM_KUMO_EXIT { KUMO_TOUCH = 0, KUMO_CLOSE = 1 };

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

input group  "Entry Filters"
input bool   InpCloudBiasEnabled = true;   // Require Span A vs Span B bias on the level TF + the TF below
input bool   InpH4Bias           = true;   // H4 is the bias — all tiers only trade in H4's direction (H4 flat = no trades)
input bool   InpD1Filter         = true;   // D1 filter for the H4 tier: H4 trades only in the D1's direction; D1 in the cloud = no H4 trades
input double InpOverextDistATR   = 3.0;    // H4 overextended when the close is >= this x ATR(H4) from tenkan, kijun or the cloud (0 = off)
input double InpOverextCandleATR = 2.5;    // H4 overextended when a recent H4 candle range is >= this x ATR(H4) (huge trending candles; 0 = off)
input int    InpOverextNoTouch   = 26;     // H4 overextended when NO H4 candle touched tenkan/kijun/cloud for this many bars (0 = off)

input group  "H4 Pullback Guard (overextension protection)"
input bool   InpOverextGuard        = true;  // Block ALL tier entries when stretched H4 shows strong pullback signs (high-conviction only)
input double InpOverextExtremeATR   = 5.0;   // H4 close >= this x ATR(H4) from tenkan/kijun/cloud = extreme stretch: block ALL entries, no confirmation needed (0 = off)
input int    InpGuardLookbackBars   = 2;     // Confirmation window (closed bars) on H1/M30 for the pullback signs
input int    InpGuardMinConfirms    = 2;     // Sub-signals that must fire TOGETHER to block (of 6: rejection H1, rejection M30, turtle H1, turtle M30, M30 TK cross, H4 chikou)
input double InpGuardExtremeATR     = 1.0;   // H1/M30 bar signals count only when they print within this x ATR(H4) of the H4 move's extreme (0 = anywhere)
input bool   InpGuardUseRejection   = true;  // Sub-signal: rejection candle on H1 or M30 against the H4 trend (sweep + wick + close-back)
input bool   InpGuardUseTurtle      = true;  // Sub-signal: turtle-soup stop hunt on H1 or M30 against the H4 trend (sweep the swing, close back inside)
input bool   InpGuardUseTKCross     = true;  // Sub-signal: fresh tenkan-kijun cross against the H4 trend on M30
input bool   InpGuardUseChikou      = true;  // Sub-signal: H4 chikou span has fallen back into the price range it overlaps
input int    InpMaxSpreadPoints  = 60;     // Max spread in points to allow entry (0 = no limit)
input int    InpReentryCooldownMin = 30;   // Per-level cooldown (min) after an exit before the same level may re-enter (0 = off)

input group  "Trend Strength Filter"
input bool   InpTrendADX       = true;    // Only enter on good trend conditions: H4 ADX must show a real trend
input int    InpADXPeriod      = 14;      // ADX period (H4)
input double InpTrendADXLevel  = 25.0;    // ADX(H4) must be >= this to enter (flat/choppy H4 = no entries)

input group  "Exit Management"
input ENUM_KUMO_EXIT InpKumoExit = KUMO_TOUCH;   // 0 = exit when price touches the cloud edge, 1 = exit when the tier TF bar closes inside the cloud

input group  "Stop Loss Policy"
input bool   InpUseInitialSL    = false;   // Attach a real entry SL at ATR x InpRiskATRMult (office-pc style; false = runner config)
input double InpDisasterStopATR = 4.0;     // Wide disaster stop at ATR x this (0 = off) — caps tail risk while runners run

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

input group  "News Filter (MT5 Economic Calendar)"
input bool   InpNewsFilterEnabled  = true;   // Flatten and stand aside around high-impact news
input int    InpNewsBlockBeforeMin = 60;     // Close positions / block entries this many minutes BEFORE the event
input int    InpNewsBlockAfterMin  = 5;      // Resume trading this many minutes AFTER the event
input bool   InpNewsIncludeMedium  = false;  // Also block on medium impact (orange); false = high (red) only
input string InpNewsCurrencies     = "";     // Extra currencies to watch, comma-separated (e.g. "USD,EUR")
input bool   InpSendPush           = true;   // Send push notifications for news events

//--- Constants and Global Variables ---
#define MAX_SYMS 60
#define LEVELS   5      // tradable levels: M5, M15, M30, H1, H4
#define TFS      6      // stack: M1, M5, M15, M30, H1, H4

#define NEWS_MAX_EVENTS  256
#define NEWS_REFRESH_SEC 900          // rebuild the event cache every 15 minutes
#define NEWS_LOOK_BACK   (6*3600)     // cache window behind now
#define NEWS_LOOK_AHEAD  (36*3600)    // cache window ahead of now

ENUM_TIMEFRAMES tfs[TFS] = { PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4 };
string          tfName[TFS] = { "M1", "M5", "M15", "M30", "H1", "H4" };

int      ich[MAX_SYMS][TFS];
int      ichD1[MAX_SYMS];           // D1 ichimoku handle — H4-tier bias filter
int      atr[MAX_SYMS][LEVELS];     // ATR(level TF) — BE and spike-lock trail sizing
int      adx[MAX_SYMS];             // ADX(H4) — trend strength filter
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar[MAX_SYMS];
int      state[MAX_SYMS][LEVELS];   // per level: 0 = flat, 1 = long, -1 = short
int      lastMinuteKey = -1;

double   entryPrice[MAX_SYMS][LEVELS];   // reference entry price per level (BE + trail arming)
double   peakHigh[MAX_SYMS][LEVELS];     // highest high since entry (long chandelier reference)
double   peakLow[MAX_SYMS][LEVELS];      // lowest low since entry (short chandelier reference)
bool     beMoved[MAX_SYMS][LEVELS];      // BE stop already moved to break even (one-shot)
datetime lastExitTime[MAX_SYMS][LEVELS];    // re-entry cooldown anchor per level
datetime lastExitAttempt[MAX_SYMS][LEVELS]; // per-tick exit retry throttle (seconds)

//--- News filter state (see the News Filter section below)
struct NewsEvent
{
   datetime time;
   string   currency;
   string   name;
};
NewsEvent newsCache[NEWS_MAX_EVENTS];
int       newsCount       = 0;
datetime  newsRefreshedAt = 0;
bool      newsWarned      = false;          // one-shot "calendar unavailable" warning
string    newsCcy[32];                      // every currency watched across all symbols
int       newsCcyCount    = 0;
string    symCcy[MAX_SYMS];                 // per-symbol currency watch list (","-wrapped)
datetime  newsBlockUntil[MAX_SYMS];         // entries blocked until this server time
datetime  newsAnnounced[MAX_SYMS];          // event time of the blackout already alerted on

int MAGIC = 20260851;   // fresh — overextension-protection build (20260848 = very-profitable snapshot, 20260849 = office-pc, 20260850 = windows-laptop)

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
      newsBlockUntil[s] = 0;
      newsAnnounced[s]  = 0;
      for(int l = 0; l < LEVELS; l++)
      {
         state[s][l] = 0;
         entryPrice[s][l] = 0.0;
         peakHigh[s][l]   = 0.0;
         peakLow[s][l]    = 0.0;
         beMoved[s][l]    = false;
         lastExitTime[s][l] = 0;
         lastExitAttempt[s][l] = 0;
      }

      for(int t = 0; t < TFS; t++)
      {
         ich[s][t] = iIchimoku(syms[s], tfs[t], Tenkan, Kijun, SenkouB);
         if(ich[s][t] == INVALID_HANDLE) return(INIT_FAILED);
      }

      ichD1[s] = iIchimoku(syms[s], PERIOD_D1, Tenkan, Kijun, SenkouB);
      if(ichD1[s] == INVALID_HANDLE) return(INIT_FAILED);

      adx[s] = iADX(syms[s], PERIOD_H4, InpADXPeriod);
      if(adx[s] == INVALID_HANDLE) return(INIT_FAILED);

      for(int l = 0; l < LEVELS; l++)
      {
         atr[s][l] = iATR(syms[s], tfs[l + 1], InpATRPeriod);
         if(atr[s][l] == INVALID_HANDLE) return(INIT_FAILED);
      }
   }

   BuildNewsCurrencies();

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
      if(adx[s] != INVALID_HANDLE) IndicatorRelease(adx[s]);
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

// Rebuild per-level state from the positions on the account so a restart
// mid-trade resumes the correct levels. The position comment carries the
// level (e.g. "Exp Buy M15"). Entry/peak/BE memory is rebuilt from the
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
            if(comm == LevelComment(l, 1) || comm == LevelComment(l, -1))
            {
               state[s][l] = dir;
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
         }
      }
   }
}

//==============================================================
// Alignment Check: price and chikou both above/below tenkan,
// kijun, and cloud on one timeframe. Returns 1 (bullish),
// -1 (bearish), 0 (none) — identical to the H4 VPS build.
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

   bool above = closeP > tenkan[0] && closeP > kijun[0] && closeP > cHi;
   bool below = closeP < tenkan[0] && closeP < kijun[0] && closeP < cLo;
   if(!above && !below) return 0;

   double tenkan_ch[1], kijun_ch[1], senA_ch[1], senB_ch[1];
   if(CopyBuffer(ich[s][tfIdx], 0, chShift, 1, tenkan_ch) <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 1, chShift, 1, kijun_ch)  <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 2, chShift, 1, senA_ch)   <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 3, chShift, 1, senB_ch)   <= 0) return 0;

   double chik = closeP;
   double cHiC = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC = MathMin(senA_ch[0], senB_ch[0]);

   if(above && chik > rt[chShift].high &&
      chik > tenkan_ch[0] && chik > kijun_ch[0] && chik > cHiC) return  1;

   if(below && chik < rt[chShift].low &&
      chik < tenkan_ch[0] && chik < kijun_ch[0] && chik < cLoC) return -1;

   return 0;
}

//==============================================================
// Chain Check (bottom-up): the full stack M1..topIdx must be
// aligned in the SAME direction for a level to open. Uses the
// per-bar alignment cache (computed once per symbol per M1 bar).
//==============================================================

int ChainAlignedCached(const int &al[], int topIdx)
{
   int dir = al[0];
   if(dir == 0) return 0;

   for(int t = 1; t <= topIdx; t++)
   {
      if(al[t] != dir) return 0;
   }
   return dir;
}

//==============================================================
// Daily Bias Filter (H4 tier): D1 is the bias for H4 trades.
// Same alignment semantics as CheckAlign but on D1 — D1 bullish
// (price + chikou above tenkan, kijun and cloud) allows only H4
// buys, D1 bearish only H4 sells. A D1 close INSIDE the cloud
// (or unreadable) returns 0 — no new H4 trades then.
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

   bool above = closeP > tenkan[0] && closeP > kijun[0] && closeP > cHi;
   bool below = closeP < tenkan[0] && closeP < kijun[0] && closeP < cLo;
   if(!above && !below) return 0;   // D1 close inside the cloud — no H4 trades

   double tenkan_ch[1], kijun_ch[1], senA_ch[1], senB_ch[1];
   if(CopyBuffer(ichD1[s], 0, chShift, 1, tenkan_ch) <= 0) return 0;
   if(CopyBuffer(ichD1[s], 1, chShift, 1, kijun_ch)  <= 0) return 0;
   if(CopyBuffer(ichD1[s], 2, chShift, 1, senA_ch)   <= 0) return 0;
   if(CopyBuffer(ichD1[s], 3, chShift, 1, senB_ch)   <= 0) return 0;

   double chik = closeP;
   double cHiC = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC = MathMin(senA_ch[0], senB_ch[0]);

   if(above && chik > rt[chShift].high &&
      chik > tenkan_ch[0] && chik > kijun_ch[0] && chik > cHiC) return  1;

   if(below && chik < rt[chShift].low &&
      chik < tenkan_ch[0] && chik < kijun_ch[0] && chik < cLoC) return -1;

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
// means only sells. If H4 has no alignment, no trades open.
// Uses the cached alignment array.
//==============================================================

bool H4BiasCached(const int &al[], int dir)
{
   int h4 = al[TFS - 1];
   if(h4 == 0) return false;        // H4 not aligned — no trades
   return h4 == dir;
}

//==============================================================
// Exit Check: cloud exit with two modes.
//   KUMO_TOUCH (aggressive): price TOUCHES the level TF's cloud
//     edge — a long exits when the bid touches the cloud's upper
//     edge, a short when the ask touches the lower edge. Fires
//     fast, but a trend pullback touching the cloud intra-bar
//     cuts the trade short.
//   KUMO_CLOSE (rides trends): the level TF bar must CLOSE inside
//     the cloud (or beyond it) — a pullback has to actually close
//     back into the kumo before the trade exits, letting good
//     trends run.
// TOUCH mode is evaluated on EVERY tick (desktop build — no 60 s
// exit lag); CLOSE mode is naturally per tier-TF bar.
//==============================================================

bool InCloudTouch(int s, int tfIdx, int dir)
{
   double senA[1], senB[1];
   if(CopyBuffer(ich[s][tfIdx], 2, 1, 1, senA) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, 1, 1, senB) <= 0) return false;

   if(InpKumoExit == KUMO_CLOSE)
   {
      // Ride mode: the tier TF's last closed bar must close inside
      // (or beyond) the cloud
      MqlRates rt[];
      if(CopyRates(syms[s], tfs[tfIdx], 1, 1, rt) <= 0) return false;
      double closeP = rt[0].close;
      if(dir ==  1) return closeP < MathMax(senA[0], senB[0]);
      if(dir == -1) return closeP > MathMin(senA[0], senB[0]);
      return false;
   }

   // Touch mode: current price touches the cloud edge
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
// H4 Overextension Filter — three H4-only measures. Any of them
// triggering blocks NEW H1 and H4 tier entries (no positions
// opened at the peak of a stretched move); the lower tiers
// (M5/M15/M30) may still trade:
//   1. DISTANCE: the last closed H4 close sits >=
//      InpOverextDistATR x ATR(H4) from tenkan, kijun or the
//      cloud edge — price far from every reference.
//   2. HUGE CANDLES: a recent H4 candle range is >=
//      InpOverextCandleATR x ATR(H4) — the trending candles are
//      enormous, the move is exhausting.
//   3. NO TOUCH: no H4 candle has touched tenkan, kijun or the
//      cloud within the last InpOverextNoTouch bars (>= 26) —
//      price has run away from all pullback references.
// Any sub-check with unreadable data is skipped (allows entry).
//==============================================================

bool H4Overextended(int s)
{
   double a2[1];

   // 1) Distance from tenkan, kijun and the cloud
   if(InpOverextDistATR > 0)
   {
      double d = 0.0;
      if(H4StretchDistanceATR(s, d) && d >= InpOverextDistATR) return true;
   }

   // 2) Huge trending candles: max range of the last 3 closed H4 bars
   if(InpOverextCandleATR > 0)
   {
      if(CopyBuffer(atr[s][LEVELS - 1], 0, 1, 1, a2) > 0 && a2[0] > 0)
      {
         MqlRates rc[];
         if(CopyRates(syms[s], tfs[TFS - 1], 1, 3, rc) == 3)
         {
            double maxRange = 0.0;
            for(int i = 0; i < 3; i++)
            {
               double rg = rc[i].high - rc[i].low;
               if(rg > maxRange) maxRange = rg;
            }
            if(maxRange >= InpOverextCandleATR * a2[0]) return true;
         }
      }
   }

   // 3) No touch of tenkan / kijun / cloud within InpOverextNoTouch bars
   if(InpOverextNoTouch > 0)
   {
      int win = 60;
      double tk[60], kj[60], sa[60], sb[60];
      if(CopyBuffer(ich[s][TFS - 1], 0, 1, win, tk) == win &&
         CopyBuffer(ich[s][TFS - 1], 1, 1, win, kj) == win &&
         CopyBuffer(ich[s][TFS - 1], 2, 1, win, sa) == win &&
         CopyBuffer(ich[s][TFS - 1], 3, 1, win, sb) == win)
      {
         MqlRates rt2[];
         if(CopyRates(syms[s], tfs[TFS - 1], 1, win, rt2) == win)
         {
            int sinceTen = win, sinceKj = win, sinceCloud = win;
            for(int i = 0; i < win; i++)
            {
               bool touchTen = rt2[i].low <= tk[i] && rt2[i].high >= tk[i];
               bool touchKj  = rt2[i].low <= kj[i] && rt2[i].high >= kj[i];
               double lo = MathMin(sa[i], sb[i]);
               double hi = MathMax(sa[i], sb[i]);
               bool touchCloud = rt2[i].low <= hi && rt2[i].high >= lo;
               if(sinceTen == win && touchTen)  sinceTen  = i + 1;
               if(sinceKj  == win && touchKj)   sinceKj   = i + 1;
               if(sinceCloud == win && touchCloud) sinceCloud = i + 1;
            }
            if(sinceTen  >= InpOverextNoTouch ||
               sinceKj   >= InpOverextNoTouch ||
               sinceCloud >= InpOverextNoTouch) return true;
         }
      }
   }

   return false;
}

//==============================================================
// Trend Strength Filter: only enter on good trend conditions.
// H4 ADX must show a genuine trend (>= InpTrendADXLevel) — a
// flat or choppy H4 means no entries, so the EA waits for the
// trend instead of trading every alignment. Unreadable ADX
// counts as blocking (conservative).
//==============================================================

bool H4TrendOK(int s)
{
   if(!InpTrendADX) return true;
   double d[1];
   if(CopyBuffer(adx[s], 0, 1, 1, d) <= 0 || d[0] <= 0) return false;
   return d[0] >= InpTrendADXLevel;
}

//==============================================================
// H4 Pullback Guard — the strongest signs that a stretched H4
// move is about to pull back to the cloud. When it fires, NO
// tier may open (not even M5/M15 dip-buys), because the coming
// reversion would hit any new position.
//
// Tier 1 — EXTREME STRETCH (no confirmation needed): the last
// closed H4 close sits >= InpOverextExtremeATR x ATR(H4) from
// tenkan, kijun AND the cloud edge. At that distance a reversion
// is near-certain by itself — it is not a trend, it is a rubber
// band.
//
// Tier 2 — STRETCH + CONFIRMATION: H4 is overextended (the 3-
// factor H4Overextended test) AND one of these fires against the
// H4 trend direction within the last InpGuardLookbackBars closed
// bars:
//   * REJECTION CANDLE on H1 or M30 — the repo's proven strong
//     reversal candle (swing sweep + dominant wick + strong
//     close-back). H4 moves end on the lower TFs first.
//   * TURTLE SOUP on H1 or M30 — price sweeps the recent swing
//     high/low (runs the stops) and CLOSES back inside: the
//     breakout failed and trapped breakout traders now fuel the
//     reversion. One of the strongest exhaustion triggers.
//   * FRESH TENKAN-KIJUN CROSS against the trend on M30 —
//     ichimoku's classic first reversal signal on the TF right
//     below H4.
//   * H4 CHIKOU entering the price range — the H4 trend's own
//     chikou confirmation breaking down.
//
// Any confirmation is enough (OR-logic); each can be disabled
// independently. Unreadable data fails OPEN (no block).
//==============================================================

// Worst-case distance of the last closed H4 close from tenkan, kijun
// and the cloud edge, in ATR(H4) multiples. Returns false when any
// input is unreadable. Shared by the 3-factor filter and the guard.
bool H4StretchDistanceATR(int s, double &distATR)
{
   distATR = -1.0;
   double a[1];
   if(CopyBuffer(atr[s][LEVELS - 1], 0, 1, 1, a) <= 0 || a[0] <= 0) return false;

   double tenkan[1], kijun[1], senA[1], senB[1];
   if(CopyBuffer(ich[s][TFS - 1], 0, 1, 1, tenkan) <= 0) return false;
   if(CopyBuffer(ich[s][TFS - 1], 1, 1, 1, kijun)  <= 0) return false;
   if(CopyBuffer(ich[s][TFS - 1], 2, 1, 1, senA)   <= 0) return false;
   if(CopyBuffer(ich[s][TFS - 1], 3, 1, 1, senB)   <= 0) return false;

   MqlRates rt[];
   if(CopyRates(syms[s], tfs[TFS - 1], 1, 1, rt) <= 0) return false;

   double closeP = rt[0].close;
   double cHi = MathMax(senA[0], senB[0]);
   double cLo = MathMin(senA[0], senB[0]);
   double dCloud = (closeP > cHi) ? (closeP - cHi)
                 : (closeP < cLo ? (cLo - closeP) : 0.0);
   double worst = MathMax(MathAbs(closeP - tenkan[0]),
                 MathMax(MathAbs(closeP - kijun[0]), dCloud));
   distATR = worst / a[0];
   return true;
}

// Did any of the last 'bars' closed bars on this TF print a strong
// rejection AGAINST 'dir' (the H4 trend direction)?
// Did a strong rejection candle AGAINST 'dir' print on this TF within the
// last 'bars' closed bars? Returns the bar shift (1 = last closed) or 0.
int RejectionInWindow(int s, int tfIdx, int dir, int bars)
{
   for(int sh = 1; sh <= bars; sh++)
   {
      int rj = RejectionCandleAt(s, tfIdx, sh);
      if(rj != 0 && rj == -dir) return sh;
   }
   return 0;
}

// Turtle soup against 'dir' on this TF within the last 'bars' closed
// bars: the bar sweeps the swing extreme of the previous
// InpRejSwingBars bars and CLOSES back inside — the breakout failed.
//   dir = +1 (H4 long):  high > swing high, close < swing high
//   dir = -1 (H4 short): low  < swing low,  close > swing low
// Returns the bar shift (1 = last closed) or 0.
int TurtleSoupInWindow(int s, int tfIdx, int dir, int bars)
{
   int need = bars + 1 + InpRejSwingBars;
   MqlRates r[];
   if(CopyRates(syms[s], tfs[tfIdx], 0, need, r) < need) return 0;
   ArraySetAsSeries(r, true);

   for(int sh = 1; sh <= bars; sh++)
   {
      double swingHi = r[sh + 1].high, swingLo = r[sh + 1].low;
      int lastSwing = sh + InpRejSwingBars;   // exactly InpRejSwingBars bars before the candidate
      for(int i = sh + 2; i <= lastSwing; i++)
      {
         if(r[i].high > swingHi) swingHi = r[i].high;
         if(r[i].low  < swingLo) swingLo = r[i].low;
      }

      if(dir ==  1 && r[sh].high > swingHi && r[sh].close < swingHi) return sh;
      if(dir == -1 && r[sh].low  < swingLo && r[sh].close > swingLo) return sh;
   }
   return 0;
}

// Fresh tenkan-kijun cross AGAINST 'dir' on this TF within the last
// 'bars' closed bars (tenkan crossing below kijun for a long trend =
// first ichimoku reversal signal on that TF).
bool TKCrossInWindow(int s, int tfIdx, int dir, int bars)
{
   double tk[], kj[];
   if(CopyBuffer(ich[s][tfIdx], 0, 1, bars + 2, tk) != bars + 2) return false;
   if(CopyBuffer(ich[s][tfIdx], 1, 1, bars + 2, kj) != bars + 2) return false;
   ArraySetAsSeries(tk, true);
   ArraySetAsSeries(kj, true);

   for(int sh = 1; sh <= bars; sh++)
   {
      if(dir ==  1 && tk[sh - 1] < kj[sh - 1] && tk[sh] >= kj[sh]) return true;
      if(dir == -1 && tk[sh - 1] > kj[sh - 1] && tk[sh] <= kj[sh]) return true;
   }
   return false;
}

// H4 chikou span has fallen back INTO the price range it overlaps.
// The chikou value drawn at position chShift (1 + Kijun) is the CURRENT
// close (rt[sh].close) — the mirror of CheckAlign's chikou-above-price
// test. For a long: chikou is no longer above the H4 high at that
// position; for a short: no longer below the H4 low.
bool H4ChikouEntered(int s, int dir)
{
   int sh = 1, chShift = sh + Kijun;
   MqlRates rt[];
   if(CopyRates(syms[s], tfs[TFS - 1], 0, chShift + 1, rt) <= 0) return false;
   ArraySetAsSeries(rt, true);
   if(ArraySize(rt) <= chShift) return false;

   double chik = rt[sh].close;              // the chikou value drawn at position chShift
   if(dir ==  1) return chik <= rt[chShift].high;
   if(dir == -1) return chik >= rt[chShift].low;
   return false;
}

// The H4 move's extreme: the highest high (long) / lowest low (short) of
// the last 3 closed H4 bars — the top of the stretched leg.
bool H4MoveExtreme(int s, int dir, double &extreme)
{
   MqlRates r[];
   if(CopyRates(syms[s], tfs[TFS - 1], 1, 3, r) != 3) return false;
   extreme = (dir == 1) ? r[0].high : r[0].low;
   for(int i = 1; i < 3; i++)
   {
      if(dir ==  1 && r[i].high > extreme) extreme = r[i].high;
      if(dir == -1 && r[i].low  < extreme) extreme = r[i].low;
   }
   return true;
}

// Spatial filter: did the confirmation bar (shift 'sh' on tfIdx) print AT
// the H4 extreme — within InpGuardExtremeATR x ATR(H4) of it? A rejection
// or turtle soup at the BOTTOM of a routine pullback is not an H4 top;
// one at the extreme itself is. Unreadable data fails open (counts).
bool AtH4Extreme(int s, int tfIdx, int sh, int dir)
{
   if(InpGuardExtremeATR <= 0) return true;   // filter off

   double extreme = 0.0;
   if(!H4MoveExtreme(s, dir, extreme)) return true;
   double a[1];
   if(CopyBuffer(atr[s][LEVELS - 1], 0, 1, 1, a) <= 0 || a[0] <= 0) return true;
   double dist = InpGuardExtremeATR * a[0];

   MqlRates r[];
   if(CopyRates(syms[s], tfs[tfIdx], sh, 1, r) <= 0) return true;
   double barExtreme = (dir == 1) ? r[0].high : r[0].low;

   if(dir ==  1) return barExtreme >= extreme - dist;
   return barExtreme <= extreme + dist;
}

// The guard itself. 'al' is the cached per-bar alignment array (al[TFS-1]
// = H4 direction), 'h4Stretched' the cached 3-factor overextension result.
//
// v2 (after the first backtest blocked almost everything): the guard now
// fires ONLY on high-conviction setups, so the M5/M15/M30 flow — which
// the backtest showed is profitable DURING stretches — is preserved:
//   * Tier 1 — EXTREME stretch (>= InpOverextExtremeATR, default 5 ATR)
//     alone blocks all tiers: reversion is near-certain.
//   * Tier 2 — normal stretch AND a MINIMUM NUMBER of sub-signals
//     (InpGuardMinConfirms, default 2 of 6) firing TOGETHER, with the
//     H1/M30 bar signals required to print AT the H4 move's extreme
//     (InpGuardExtremeATR, default within 1 ATR(H4) of it). A rejection
//     at the bottom of a routine pullback is not an H4 top; one at the
//     extreme is.
// The old any-1-of-4 OR-logic and the inverted chikou check (which fired
// almost constantly during trends) are gone.
bool H4PullbackGuard(int s, const int &al[], bool h4Stretched)
{
   if(!InpOverextGuard) return false;

   // Tier 1 — extreme stretch alone blocks everything
   if(InpOverextExtremeATR > 0)
   {
      double d = 0.0;
      if(H4StretchDistanceATR(s, d) && d >= InpOverextExtremeATR) return true;
   }

   // Tier 2 — stretch must be confirmed by several strong reversal signs
   if(!h4Stretched) return false;

   // The guard only makes sense while H4 still carries a direction
   int dir = al[TFS - 1];
   if(dir == 0) return false;

   int bars = (InpGuardLookbackBars > 0) ? InpGuardLookbackBars : 1;
   int score = 0;

   // H1 = tfs[4], M30 = tfs[3] — the TFs directly below H4, where an H4
   // move's rollover shows up first. Each sub-signal counts once; the
   // H1/M30 bar signals must print at the H4 extreme to count.
   if(InpGuardUseRejection)
   {
      int sh = RejectionInWindow(s, 4, dir, bars);
      if(sh > 0 && AtH4Extreme(s, 4, sh, dir)) score++;
      sh = RejectionInWindow(s, 3, dir, bars);
      if(sh > 0 && AtH4Extreme(s, 3, sh, dir)) score++;
   }

   if(InpGuardUseTurtle)
   {
      int sh = TurtleSoupInWindow(s, 4, dir, bars);
      if(sh > 0 && AtH4Extreme(s, 4, sh, dir)) score++;
      sh = TurtleSoupInWindow(s, 3, dir, bars);
      if(sh > 0 && AtH4Extreme(s, 3, sh, dir)) score++;
   }

   if(InpGuardUseTKCross && TKCrossInWindow(s, 3, dir, bars)) score++;
   if(InpGuardUseChikou && H4ChikouEntered(s, dir))          score++;

   return (score >= InpGuardMinConfirms);
}

//==============================================================
// News Filter — MT5 Economic Calendar (high-impact "red folder")
//==============================================================
// Events come from the terminal's built-in economic calendar (the same
// feed as the Calendar tab, supplied by MetaQuotes rather than the
// broker), so no WebRequest permission, no DLL and no external site are
// involved. CALENDAR_IMPORTANCE_HIGH is what Forex Factory paints as a
// red folder.
//
// Calendar times are trade-server time, which is what TimeTradeServer()
// returns, so the two compare directly — no broker GMT offset handling.
//
// Two limitations worth knowing: the calendar is empty in the Strategy
// Tester (the tester has no calendar access), so a backtest of this file
// trades as if no news existed; and the calendar needs a connected
// terminal. When the calendar can't be read the filter fails OPEN — it
// warns once and lets the EA keep trading, rather than silently freezing
// the account forever.

// Register a currency in the global watch list, once.
void NewsAddCcy(string ccy)
{
   StringTrimLeft(ccy);
   StringTrimRight(ccy);
   StringToUpper(ccy);
   if(StringLen(ccy) != 3) return;
   for(int i = 0; i < newsCcyCount; i++)
      if(newsCcy[i] == ccy) return;
   if(newsCcyCount < ArraySize(newsCcy)) newsCcy[newsCcyCount++] = ccy;
}

// Attach a currency to one symbol's watch list (and to the global one).
void SymAddCcy(int s, string ccy)
{
   StringTrimLeft(ccy);
   StringTrimRight(ccy);
   StringToUpper(ccy);
   if(StringLen(ccy) != 3) return;
   if(StringFind(symCcy[s], "," + ccy + ",") < 0) symCcy[s] += ccy + ",";
   NewsAddCcy(ccy);
}

// Which currencies each symbol reacts to: its own base and profit
// currency plus anything in InpNewsCurrencies. Metals and crypto carry a
// base the calendar has no events for (XAU, BTC) — harmless, they simply
// never match; GOLDm# still picks up USD through its profit currency.
void BuildNewsCurrencies()
{
   newsCcyCount = 0;

   string extra[];
   int extraCount = StringSplit(InpNewsCurrencies, ',', extra);

   for(int s = 0; s < symsCount; s++)
   {
      symCcy[s] = ",";
      SymAddCcy(s, SymbolInfoString(syms[s], SYMBOL_CURRENCY_BASE));
      SymAddCcy(s, SymbolInfoString(syms[s], SYMBOL_CURRENCY_PROFIT));
      for(int i = 0; i < extraCount; i++) SymAddCcy(s, extra[i]);
   }
}

// Rebuild the cache of qualifying events around now. Cheap enough to call
// on every M1 bar — it returns immediately until the refresh interval is up.
void RefreshNewsCache()
{
   datetime now = TimeTradeServer();
   if(newsRefreshedAt > 0 && now - newsRefreshedAt < NEWS_REFRESH_SEC) return;
   newsRefreshedAt = now;
   newsCount = 0;

   bool calendarOK = false;
   int  lastErr    = 0;

   for(int c = 0; c < newsCcyCount; c++)
   {
      MqlCalendarValue vals[];
      ResetLastError();
      int n = CalendarValueHistory(vals, now - NEWS_LOOK_BACK, now + NEWS_LOOK_AHEAD, NULL, newsCcy[c]);
      if(n <= 0)
      {
         int err = GetLastError();
         if(err == 0) calendarOK = true;   // no events for this currency is not a failure
         else         lastErr = err;
         continue;
      }
      calendarOK = true;

      for(int i = 0; i < n; i++)
      {
         if(newsCount >= NEWS_MAX_EVENTS) break;

         MqlCalendarEvent ev;
         if(!CalendarEventById(vals[i].event_id, ev)) continue;

         bool wanted = (ev.importance == CALENDAR_IMPORTANCE_HIGH) ||
                       (InpNewsIncludeMedium && ev.importance == CALENDAR_IMPORTANCE_MODERATE);
         if(!wanted) continue;

         newsCache[newsCount].time     = vals[i].time;
         newsCache[newsCount].currency = newsCcy[c];
         newsCache[newsCount].name     = ev.name;
         newsCount++;
      }
   }

   if(!calendarOK && !newsWarned)
   {
      newsWarned = true;
      string msg = PCTime() + " | News filter: MT5 calendar unavailable (err " +
                   IntegerToString(lastErr) + ") — trading WITHOUT the news blackout";
      Print(msg); Alert(msg);
      if(InpSendPush) SendNotification(msg);
   }
   if(calendarOK) newsWarned = false;
}

// Is this symbol inside a news blackout right now? Reports the end of the
// window — the latest one when several events overlap — and the event that
// opened it.
bool NewsBlackout(int s, datetime &until, string &evName, datetime &evTime)
{
   until  = 0;
   evName = "";
   evTime = 0;
   if(!InpNewsFilterEnabled) return false;

   RefreshNewsCache();

   datetime now = TimeTradeServer();
   for(int i = 0; i < newsCount; i++)
   {
      if(StringFind(symCcy[s], "," + newsCache[i].currency + ",") < 0) continue;

      datetime from = newsCache[i].time - InpNewsBlockBeforeMin * 60;
      datetime to   = newsCache[i].time + InpNewsBlockAfterMin  * 60;
      if(now < from || now > to) continue;

      if(to > until)
      {
         until  = to;
         evName = newsCache[i].name;
         evTime = newsCache[i].time;
      }
   }
   return (until > 0);
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

// One position per symbol, full stop. The snapshot only consolidated in
// one direction (close smaller tiers when a LARGER one opens); a running
// H4 with M1..H1 still aligned let the lower tiers pile on top of it.
bool SymbolFullyFlat(int s)
{
   for(int l = 0; l < LEVELS; l++)
      if(state[s][l] != 0) return false;
   return true;
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

// Real SL price for a level entry: the tighter of the policy inputs
// (initial SL at the sizing distance, or the wider disaster stop). Both
// only ever TIGHTEN afterwards via BE/chandelier. Returns 0.0 when no SL
// should be attached (disabled, data unavailable, or inside the broker
// minimum stop distance — a naked entry is preferable to a rejected one).
double EntrySLPrice(int s, int lvl, int dir, double price)
{
   double a[1];
   if(CopyBuffer(atr[s][lvl], 0, 1, 1, a) <= 0 || a[0] <= 0) return 0.0;

   double dist = (InpUseInitialSL) ? InpRiskATRMult * a[0]
                                   : InpDisasterStopATR * a[0];
   if(dist <= 0) return 0.0;

   double sl = (dir == 1) ? price - dist : price + dist;
   sl = NormalizeDouble(sl, (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS));

   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   double bid = SymbolInfoDouble(syms[s], SYMBOL_BID);
   double ask = SymbolInfoDouble(syms[s], SYMBOL_ASK);

   if(dir ==  1 && sl < bid - minDist) return sl;
   if(dir == -1 && sl > ask + minDist) return sl;
   return 0.0;
}

bool OpenLevel(int s, int lvl, int dir, double lots)
{
   string sym = syms[s];
   string comment = LevelComment(lvl, dir);
   double price = (dir == 1) ? SymbolInfoDouble(sym, SYMBOL_ASK)
                             : SymbolInfoDouble(sym, SYMBOL_BID);

   // No tight entry stop loss in the runner config — the trade runs until
   // the cloud exit; the BE/chandelier layer protects it once in profit.
   // The disaster stop (or optional initial SL) is attached when enabled.
   double sl = 0.0;
   if(InpUseInitialSL || InpDisasterStopATR > 0)
      sl = EntrySLPrice(s, lvl, dir, price);

   bool ok = (dir == 1) ? trade.Buy(lots, sym, price, sl, 0, comment)
                        : trade.Sell(lots, sym, price, sl, 0, comment);
   if(ok)
   {
      state[s][lvl] = dir;
      entryPrice[s][lvl] = price;   // BE + spike-lock trail references
      peakHigh[s][lvl]   = price;
      peakLow[s][lvl]    = price;
      beMoved[s][lvl]    = false;
      string action = (dir == 1) ? "Buy" : "Sell";
      string msg = PCTime() + " | " + action + " " + sym + " " + tfName[lvl + 1] +
                   " @ " + DoubleToString(lots, 2) + " (bottom-up)";
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

      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC &&
         (PositionGetString(POSITION_COMMENT) == LevelComment(lvl, 1) ||
          PositionGetString(POSITION_COMMENT) == LevelComment(lvl, -1)))
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
      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC &&
         (PositionGetString(POSITION_COMMENT) == LevelComment(lvl, 1) ||
          PositionGetString(POSITION_COMMENT) == LevelComment(lvl, -1))) return false;
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
// to those timeframes. The entry/disaster stop is replaced by BE
// and the trail once in profit.
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
      if(comm == LevelComment(lvl, 1) || comm == LevelComment(lvl, -1)) return true;
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
// 'sh' is the closed bar to test (1 = last closed). Returns
// 1 (bullish), -1 (bearish), 0 (none).
//==============================================================

int RejectionCandleAt(int s, int tfIdx, int sh)
{
   int need = sh + 1 + InpRejSwingBars;
   MqlRates r[];
   if(CopyRates(syms[s], tfs[tfIdx], 0, need, r) < need) return 0;
   ArraySetAsSeries(r, true);

   double o1 = r[sh].open, c1 = r[sh].close, h1 = r[sh].high, l1 = r[sh].low;

   // Swing extreme of the InpRejSwingBars bars before the rejection candle
   double swingHi = r[sh + 1].high, swingLo = r[sh + 1].low;
   for(int i = sh + 2; i < need; i++)
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
// On success the level's re-entry cooldown is armed.
bool ExitLevel(int s, int l, string reason)
{
   string side = (state[s][l] == 1) ? "Long" : "Short";
   string msg  = PCTime() + " | Close " + syms[s] + " " + side + " " +
                 tfName[l + 1] + " (" + reason + ")";
   Print(msg); SendNotification(msg);

   if(CloseLevelPositions(s, l))
   {
      state[s][l] = 0;
      lastExitTime[s][l] = TimeCurrent();
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
   // Per-tick cloud-touch exits: the touch is checked on EVERY tick so
   // an exit fires within milliseconds instead of up to 60 s late. Only
   // levels with an open position pay the (2 CopyBuffer) cost. CLOSE
   // mode is naturally bar-gated by the tier TF. Failed closes are
   // retried at most once every 5 seconds (no notification spam).
   for(int s = 0; s < symsCount; s++)
   {
      for(int l = 0; l < LEVELS; l++)
      {
         if(state[s][l] != 0 && TimeCurrent() >= lastExitAttempt[s][l] + 5 &&
            InCloudTouch(s, l + 1, state[s][l]))
         {
            lastExitAttempt[s][l] = TimeCurrent();
            ExitLevel(s, l, "kumo touch");
         }
      }
   }

   // Everything below runs once per closed M1 bar (VPS-style perf gate —
   // entries/protection don't need tick resolution).
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

      // News blackout: flatten ahead of a high-impact event and stay out
      // until the post-event window closes. Runs before every other check
      // so the news exit wins over the trail, BE and entry logic.
      datetime newsUntil = 0, newsTime = 0;
      string   newsName  = "";
      if(NewsBlackout(s, newsUntil, newsName, newsTime))
      {
         newsBlockUntil[s] = newsUntil;

         if(newsAnnounced[s] != newsTime)
         {
            newsAnnounced[s] = newsTime;
            string msg = PCTime() + " | News blackout " + syms[s] + ": " + newsName +
                         " at " + TimeToString(newsTime, TIME_MINUTES) +
                         " — flat until " + TimeToString(newsUntil, TIME_MINUTES) + " (server)";
            Print(msg); Alert(msg);
            if(InpSendPush) SendNotification(msg);
         }

         bool anyOpen = false;
         for(int l = 0; l < LEVELS; l++)
            if(state[s][l] != 0) { anyOpen = true; break; }

         if(anyOpen)
         {
            string msg = PCTime() + " | Close " + syms[s] + " all levels (news: " + newsName + ")";
            Print(msg); Alert(msg);
            if(InpSendPush) SendNotification(msg);

            bool allClosed = true;
            for(int l = 0; l < LEVELS; l++)
            {
               if(state[s][l] != 0)
               {
                  if(CloseLevelPositions(s, l)) state[s][l] = 0;
                  else                          allClosed = false;
               }
            }
            if(!allClosed)
               Print(PCTime() + " | " + syms[s] + " news close failed — will retry next bar");
         }

         // Flat and blocked: nothing left to manage this bar. A position that
         // refused to close falls through so the trail and BE keep guarding it.
         bool stillOpen = false;
         for(int l = 0; l < LEVELS; l++)
            if(state[s][l] != 0) { stillOpen = true; break; }
         if(!stillOpen) continue;
      }

      // Alignment cache: every CheckAlign result for this symbol, once per
      // M1 bar. The tier scan and the H4 bias gate read the cache instead
      // of recomputing the same TFs again and again.
      int al[TFS];
      for(int t = 0; t < TFS; t++) al[t] = CheckAlign(s, t);

      // Bar-based exits and profit protection per level
      for(int l = 0; l < LEVELS; l++)
      {
         // Rejection exit: a very strong rejection candle formed on
         // the tier TF against the trade (bearish kills a long,
         // bullish kills a short)
         if(InpRejectionExit && state[s][l] != 0)
         {
            int rj = RejectionCandleAt(s, l + 1, 1);
            if(rj != 0 && rj == -state[s][l])
               ExitLevel(s, l, "rejection");
         }

         // Profit protection: BE + spike-lock chandelier trail
         if(state[s][l] != 0) ManageLevelProtection(s, l);
      }

      // Entry scan. One position per symbol, full stop: the whole symbol
      // must be flat (a running H4 can no longer have H1/M30/M15/M5 pile
      // on top of it), the level must be out of its post-exit cooldown,
      // and every filter must pass. When several tiers align at once the
      // LARGEST one opens.
      int topTier = -1;
      int topDir  = 0;

      // H4 stretch state, computed once for this symbol/bar: the 3-factor
      // overextension (blocks H1/H4 tier entries) and the pullback guard
      // (blocks ALL tier entries when a strong reversal confirms).
      bool h4Stretched    = H4Overextended(s);
      bool pullbackGuard  = H4PullbackGuard(s, al, h4Stretched);

      if(SpreadOK(syms[s]) && H4TrendOK(s) && SymbolFullyFlat(s) &&
         TimeTradeServer() >= newsBlockUntil[s] && !pullbackGuard)
      {
         for(int l = LEVELS - 1; l >= 0; l--)
         {
            if(state[s][l] != 0) continue;
            if(InpReentryCooldownMin > 0 &&
               TimeCurrent() < lastExitTime[s][l] + InpReentryCooldownMin * 60) continue;

            int st = ChainAlignedCached(al, l + 1);
            if(st == 0) continue;
            if(InpCloudBiasEnabled && !LevelCloudBiasOK(s, l, st)) continue;
            if(InpH4Bias && !H4BiasCached(al, st)) continue;

            // H4 tier: D1 must carry the same bias (D1 in the cloud = no H4 trades)
            if(l == LEVELS - 1 && InpD1Filter && DailyAlign(s) != st) continue;

            // H1/H4 tiers: no entries while H4 is overextended — the
            // lower tiers (M5/M15/M30) may still trade
            if(l >= 3 && h4Stretched) continue;

            topTier = l;
            topDir  = st;
            break;
         }
      }

      if(topTier >= 0)
      {
         // Belt & braces: close any smaller (lower-tier) trades still
         // running. With SymbolFullyFlat this normally never triggers, but
         // it guards against a stale state after a manual/partial close.
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

         if(!OpenLevel(s, topTier, topDir, lots))
            Print(PCTime() + " | " + syms[s] + " " + tfName[topTier + 1] +
                  " entry signal but order failed, retcode " + IntegerToString(trade.ResultRetcode()));
      }
   }
}
//This work is my worship unto GOD
