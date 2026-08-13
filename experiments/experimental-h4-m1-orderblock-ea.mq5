//+------------------------------------------------------------------+
//| Experimental: H4-M1 Order Block EA (early entries)               |
//| Problem: the 6-TF alignment stack (H4→M1) only fires once every   |
//|        scale agrees. That is the LAST confirmation, so entries    |
//|        land well after the move has already extended and the      |
//|        ATR stop sits far behind price.                            |
//| Idea:  enter at the ORIGIN of the move instead of its end. An     |
//|        order block is the last opposite-colour candle before a    |
//|        displacement leg that breaks structure — the zone where    |
//|        the move was actually initiated. Wait only for the HIGHER  |
//|        timeframes (default H4+H1) to agree, then buy/sell the     |
//|        first retrace back into an unmitigated order block.        |
//| Entry: ORDER_BLOCK mode = higher-TF trend + price mitigating a    |
//|        fresh order block (optional close-side confirmation).      |
//|        ALIGNMENT mode = original 6-TF stack (baseline for A/B).   |
//| Exit:  same as the main H4-M1 EA — ATR chandelier trail, M15      |
//|        kijun cross fallback, protective stop, BE30 break-even.    |
//| Stop:  order-block entries can use the zone edge as the stop      |
//|        (much tighter than ATR x 3) instead of the ATR stop.       |
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

//--- Entry mode: order blocks (early), original alignment, or both
enum ENUM_OB_ENTRY_MODE { ENTRY_ALIGNMENT = 0, ENTRY_ORDERBLOCK = 1, ENTRY_BOTH = 2 };

//--- Stop placement for order-block entries
enum ENUM_OB_STOP_MODE { OB_STOP_ATR = 0, OB_STOP_ZONE = 1 };

input group  "Order Block Entry"
input ENUM_OB_ENTRY_MODE InpEntryMode      = ENTRY_ORDERBLOCK; // 0=alignment only, 1=order blocks only, 2=both
input ENUM_TIMEFRAMES    InpOBTimeframe    = PERIOD_H1;  // Timeframe the order blocks are mapped on
input int                InpOBTrendTFs     = 2;     // Top-N timeframes that must align (2 = H4+H1)
input int                InpOBScanBars     = 150;   // Bars of InpOBTimeframe scanned for order blocks
input int                InpOBImpulseBars  = 3;     // Bars after the block that must deliver the displacement
input double             InpOBImpulseATR   = 1.5;   // Displacement size from the block (x ATR of InpOBTimeframe)
input bool               InpOBRequireFVG   = true;  // Require a fair-value gap inside the displacement leg
input bool               InpOBUseBody      = false; // Zone = candle body only (false = full high/low range)
input int                InpOBMaxAgeBars   = 60;    // Ignore order blocks older than this many bars
input bool               InpOBFirstTouchOnly = true;// Only trade the first return into a zone
input double             InpOBEntryBufferATR = 0.15;// Arm the entry this far before the zone (x ATR)
input bool               InpOBUseConfirm   = true;  // Require a confirmation close on InpOBConfirmTF
input ENUM_TIMEFRAMES    InpOBConfirmTF    = PERIOD_M5; // Timeframe of the confirmation close

input group  "Order Block Stop"
input ENUM_OB_STOP_MODE  InpOBStopMode     = OB_STOP_ZONE; // 0=ATR stop (as main EA), 1=beyond the zone edge
input double             InpOBStopBufferATR = 0.5;  // Stop sits this far beyond the zone edge (x ATR)
input double             InpOBMaxStopATR    = 3.0;  // Skip the entry if the zone stop exceeds this x ATR(M15) (0 = off)

input group  "Risk Protection"
input bool   InpUseStopLoss       = true;   // Attach a stop loss to every entry
input int    InpATRPeriod         = 14;     // ATR period (M15)
input double InpATRMultiplier     = 3.0;    // ATR-mode SL distance = ATR * multiplier
input int    InpMaxSpreadPoints   = 60;     // Max spread in points to allow entry (0 = no limit)
input double InpHighEquityRiskPct = 1.0;    // % of equity risked per trade once equity > $8000
input int    InpReentryCooldownSec = 0;     // Min seconds after an exit before re-entering same symbol (0 = none)
input double InpMaxRiskPct         = 0.0;   // Cap total initial-stop risk per ladder as % of equity (0 = no cap)

//--- Trail mode: off, always on, or choppy-only (ADX regime filter)
enum ENUM_TRAIL_MODE { TRAIL_OFF = 0, TRAIL_ALWAYS = 1, TRAIL_CHOPPY = 2 };

input group  "Exit Management"
input ENUM_TRAIL_MODE InpTrailMode        = TRAIL_CHOPPY;  // 0=off, 1=always, 2=choppy-only (ADX)
input double          InpTrailATR         = 2.0;   // Trail distance = ATR(M15) * multiplier
input double          InpTrailActivateATR = 1.0;   // Arm the trail once profit >= ATR(M15) * multiplier
input int             InpADXPeriod        = 14;    // ADX period for choppy-market detection (M15)
input double          InpChopADXLevel     = 22.0;  // ADX below this = choppy -> trail on in auto mode

input group  "Break-Even (BE30) Management"
input bool   InpBE30Enabled        = true;   // Move SL to break even when profitable in time
input int    InpBE30Minutes        = 30;     // Profit window after entry (minutes)
input double InpBE30ActivateATR    = 0.5;    // Min profit to arm BE (x ATR M15)
input int    InpBE30CoverPoints    = 15;     // Points beyond break even (covers spread)

input group             "Equity Alert Settings"
input double            InpMinProfitTrigger  = 5.0;        // Min Profit over Baseline to trigger alert
input double            InpWithdrawProfitPct = 50.0;       // Percentage of the PROFIT to withdraw
input ENUM_DAY_OF_WEEK  InpCheckDay          = FRIDAY;     // Day of the week to check
input bool              InpResetBaseline     = false;      // Set to true to reset baseline to current equity
input bool              InpSendPush          = true;       // Send push notification

//--- Constants and Global Variables ---
#define MAX_SYMS  60
#define TF_COUNT  6
#define IDX_M15   3   // index of M15 in tfs[] — used for exit check
#define MAX_OB    8   // active order blocks tracked per symbol

#define GV_BASE_EQUITY    "EA_EquityAlert_Base_"    + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))
#define GV_LAST_ALERT_DAY "EA_EquityAlert_Day_"     + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))

ENUM_TIMEFRAMES tfs[TF_COUNT] = {
   PERIOD_H4, PERIOD_H1, PERIOD_M30, PERIOD_M15, PERIOD_M5, PERIOD_M1
};

//--- One order block: the origin candle of a displacement leg
struct OBZone
{
   datetime time;      // open time of the block candle
   double   hi;        // zone upper edge
   double   lo;        // zone lower edge
   int      dir;       // 1 = bullish block (demand), -1 = bearish block (supply)
   bool     touched;   // price has already returned into the zone at least once
};

int      ich[MAX_SYMS][TF_COUNT];
int      atr[MAX_SYMS];
int      adx[MAX_SYMS];    // ADX(M15) handle for choppy-market regime detection
int      atrOB[MAX_SYMS];  // ATR(InpOBTimeframe) handle for displacement/zone measurement
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar[MAX_SYMS];
datetime lastOBbar[MAX_SYMS];       // order blocks are re-mapped once per closed OB-TF bar
datetime lastEquityBar = 0;         // H4 bar gating for the equity alert
datetime noReentryUntil[MAX_SYMS];
int      lastMinuteKey = -1;
int      state[MAX_SYMS];   // 0=no position, 1=long, -1=short

OBZone   obs[MAX_SYMS][MAX_OB];     // live order blocks, newest first
int      obCount[MAX_SYMS];
datetime obTraded[MAX_SYMS];        // block already traded — never re-entered on the same zone

double   entryPrice[MAX_SYMS];  // reference entry price per symbol (trail arming)
double   trailHigh[MAX_SYMS];   // highest high since entry (long chandelier reference)
double   trailLow[MAX_SYMS];    // lowest low since entry (short chandelier reference)

datetime entryTime[MAX_SYMS];   // entry time per symbol (BE30 profit window)
bool     beMoved[MAX_SYMS];     // BE30 stop already moved to break even (one-shot)

int MAGIC = 20260901;   // fresh number — order block experiment, independent of every other EA

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

   if(InpOBScanBars <= InpOBImpulseBars + 2) return(INIT_FAILED);

   for(int s = 0; s < symsCount; s++)
   {
      state[s] = 0;
      lastM1bar[s] = 0;
      lastOBbar[s] = 0;
      noReentryUntil[s] = 0;
      entryTime[s] = 0;
      beMoved[s] = false;
      obCount[s] = 0;
      obTraded[s] = 0;
      for(int t = 0; t < TF_COUNT; t++)
      {
         ich[s][t] = iIchimoku(syms[s], tfs[t], Tenkan, Kijun, SenkouB);
         if(ich[s][t] == INVALID_HANDLE) return(INIT_FAILED);
      }

      // ATR(M15) is needed for the stop, the trail, BE30, and the zone-stop
      // sanity cap, so it is always created here (not only when the ATR stop
      // mode is selected).
      atr[s] = iATR(syms[s], PERIOD_M15, InpATRPeriod);
      if(atr[s] == INVALID_HANDLE) return(INIT_FAILED);

      atrOB[s] = iATR(syms[s], InpOBTimeframe, InpATRPeriod);
      if(atrOB[s] == INVALID_HANDLE) return(INIT_FAILED);

      adx[s] = INVALID_HANDLE;
      if(InpTrailMode == TRAIL_CHOPPY)
      {
         adx[s] = iADX(syms[s], PERIOD_M15, InpADXPeriod);
         if(adx[s] == INVALID_HANDLE) return(INIT_FAILED);
      }
   }

   trade.SetDeviationInPoints(Slippage);
   trade.SetExpertMagicNumber(MAGIC);
   SyncStateFromPositions();
   InitEquityAlert();
   return(INIT_SUCCEEDED);
}

//==============================================================
// Equity Alert: weekly profit-withdrawal reminder
//==============================================================

void InitEquityAlert()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(!GlobalVariableCheck(GV_BASE_EQUITY) || InpResetBaseline)
   {
      GlobalVariableSet(GV_BASE_EQUITY, currentEquity);
   }
   if(!GlobalVariableCheck(GV_LAST_ALERT_DAY))
   {
      GlobalVariableSet(GV_LAST_ALERT_DAY, 0);
   }
}

void CheckEquityAlert()
{
   MqlDateTime dt;
   TimeCurrent(dt);

   if(dt.day_of_week != InpCheckDay) return;
   if((int)GlobalVariableGet(GV_LAST_ALERT_DAY) == dt.day) return;

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double baseEquity    = GlobalVariableGet(GV_BASE_EQUITY);
   double profit        = currentEquity - baseEquity;

   if(profit >= InpMinProfitTrigger)
   {
      double withdrawAmount = profit * (InpWithdrawProfitPct / 100.0);
      string msg = StringFormat("Profit: %.2f. Suggest withdrawing: %.2f", profit, withdrawAmount);

      Alert(msg);
      if(InpSendPush) SendNotification(msg);

      GlobalVariableSet(GV_LAST_ALERT_DAY, (double)dt.day);
      GlobalVariablesFlush();
   }
}

void OnDeinit(const int reason)
{
   for(int s = 0; s < symsCount; s++)
   {
      for(int t = 0; t < TF_COUNT; t++)
         if(ich[s][t] != INVALID_HANDLE) IndicatorRelease(ich[s][t]);
      if(atr[s]   != INVALID_HANDLE) IndicatorRelease(atr[s]);
      if(atrOB[s] != INVALID_HANDLE) IndicatorRelease(atrOB[s]);
      if(adx[s]   != INVALID_HANDLE) IndicatorRelease(adx[s]);
   }
}

//==============================================================
// Position State Sync (recover after restart)
//==============================================================

void SyncStateFromPositions()
{
   // Rebuild from scratch so positions closed by SL or manually free the
   // symbol for re-entry instead of leaving stale state behind.
   int prevState[MAX_SYMS];
   bool hasPos[MAX_SYMS];
   for(int s = 0; s < symsCount; s++) { prevState[s] = state[s]; state[s] = 0; hasPos[s] = false; }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      string sym   = PositionGetString(POSITION_SYMBOL);
      int    magic = (int)PositionGetInteger(POSITION_MAGIC);
      int    type  = (int)PositionGetInteger(POSITION_TYPE);
      int    dir   = (type == POSITION_TYPE_BUY) ? 1 : -1;

      if(magic != MAGIC) continue;

      for(int s = 0; s < symsCount; s++)
      {
         if(syms[s] == sym)
         {
            state[s] = dir;
            hasPos[s] = true;
             // EA (re)started mid-trade — rebuild the trail from the open price
             // and let it accumulate fresh extremes from here.
             if(entryPrice[s] == 0.0)
             {
                entryPrice[s] = PositionGetDouble(POSITION_PRICE_OPEN);
                trailHigh[s]  = entryPrice[s];
                trailLow[s]   = entryPrice[s];
             }
             // Restart mid-trade: restart the BE30 clock from the earliest
             // open position so the profit window keeps real entry semantics.
             if(entryTime[s] == 0)
                entryTime[s] = (datetime)PositionGetInteger(POSITION_TIME);
             break;
         }
      }
   }

   // Symbols with no open position get their trail memory cleared
   for(int s = 0; s < symsCount; s++)
   {
      if(!hasPos[s])
      {
         entryPrice[s] = 0.0;
         trailHigh[s]  = 0.0;
         trailLow[s]   = 0.0;
         entryTime[s]  = 0;
         beMoved[s]    = false;
      }
   }

   // A position that vanished since the last sync (SL hit, manual close) frees
   // the symbol; arm the optional re-entry cooldown so it can't flip instantly.
   for(int s = 0; s < symsCount; s++)
   {
      if(prevState[s] != 0 && state[s] == 0)
         noReentryUntil[s] = TimeCurrent() + InpReentryCooldownSec;
   }
}

//==============================================================
// Alignment Check: price and chikou both above/below tenkan,
// kijun, and cloud. Returns 1 (bullish), -1 (bearish), 0 (none)
//==============================================================

int CheckAlign(int s, int tfIdx)
{
   ENUM_TIMEFRAMES tf = tfs[tfIdx];

   int sh      = 1;              // last closed bar
   int chShift = sh + Kijun;     // chikou's chart position for bar sh (Kijun bars back)
   // MT5's iIchimoku Senkou buffers are pre-shifted: the value at shift p
   // is the cloud as drawn at chart position p — no extra offset needed.

   MqlRates rt[];
   if(CopyRates(syms[s], tf, 0, chShift + 1, rt) <= 0) return 0;
   ArraySetAsSeries(rt, true);

   if(ArraySize(rt) <= chShift) return 0;

   // price bar sh: tenkan, kijun, cloud (cloud read at sh = drawn at sh)
   double tenkan[1], kijun[1], senA[1], senB[1];
   if(CopyBuffer(ich[s][tfIdx], 0, sh,    1, tenkan)    <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 1, sh,    1, kijun)     <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 2, sh,    1, senA)      <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 3, sh,    1, senB)      <= 0) return 0;

   double closeP = rt[sh].close;
   double cHi    = MathMax(senA[0], senB[0]);
   double cLo    = MathMin(senA[0], senB[0]);

   // Short-circuit: most bars aren't aligned, so skip the chikou-side buffers
   // unless the close is already clearly on one side of tenkan/kijun/cloud.
   bool above = closeP > tenkan[0] && closeP > kijun[0] && closeP > cHi;
   bool below = closeP < tenkan[0] && closeP < kijun[0] && closeP < cLo;
   if(!above && !below) return 0;

   // tenkan, kijun, cloud at chikou's chart position (cloud read at
   // chShift = drawn at chikou's plotted bar)
   double tenkan_ch[1], kijun_ch[1], senA_ch[1], senB_ch[1];
   if(CopyBuffer(ich[s][tfIdx], 0, chShift,    1, tenkan_ch) <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 1, chShift,    1, kijun_ch)  <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 2, chShift,    1, senA_ch)   <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 3, chShift,    1, senB_ch)   <= 0) return 0;

   // The chikou span for bar sh IS its close, plotted Kijun bars back.
   // Compare it against the candle and Ichimoku levels at that chart position.
   double chik   = closeP;
   double cHiC   = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC   = MathMin(senA_ch[0], senB_ch[0]);

   // bullish: price above tenkan, kijun, and cloud; chikou clear above price,
   // tenkan, kijun, and cloud at its plotted position
   if(above && chik > rt[chShift].high &&
      chik > tenkan_ch[0] && chik > kijun_ch[0] && chik > cHiC) return  1;

   // bearish: price below tenkan, kijun, and cloud; chikou clear below price,
   // tenkan, kijun, and cloud at its plotted position
   if(below && chik < rt[chShift].low &&
      chik < tenkan_ch[0] && chik < kijun_ch[0] && chik < cLoC) return -1;

   return 0;
}

//==============================================================
// Entry Check: all timeframes (H4→M1) aligned same direction
//==============================================================

int CheckAllAlign(int s)
{
   int dir = CheckAlign(s, 0);
   if(dir == 0) return 0;

   for(int t = 1; t < TF_COUNT; t++)
   {
      if(CheckAlign(s, t) != dir) return 0;
   }
   return dir;
}

//==============================================================
// Higher-timeframe trend gate for order-block entries: only the
// top InpOBTrendTFs timeframes (default 2 -> H4 + H1) must agree.
// This is what makes the entry early — the lower timeframes are
// still retracing when the order block is filled, by design.
//==============================================================

int TrendDir(int s)
{
   int n = InpOBTrendTFs;
   if(n < 1) n = 1;
   if(n > TF_COUNT) n = TF_COUNT;

   int dir = CheckAlign(s, 0);
   if(dir == 0) return 0;

   for(int t = 1; t < n; t++)
      if(CheckAlign(s, t) != dir) return 0;

   return dir;
}

//==============================================================
// Order Block Mapping
//
// A bullish (demand) order block is the last DOWN candle before a
// displacement leg that (a) travels at least InpOBImpulseATR x ATR
// away from the block, (b) closes above the block's high (a break
// of structure — proof the move was initiated there), and
// optionally (c) leaves a fair-value gap inside the leg.
// Bearish (supply) blocks are the mirror image.
//
// The whole list is rebuilt from bar data on every closed OB-TF
// bar rather than maintained incrementally, so the EA recovers the
// exact same zones after a restart, a reattach, or a data refresh.
//==============================================================

bool ZonesOverlap(const OBZone &z, double hi, double lo, int dir)
{
   if(z.dir != dir) return false;
   return (lo <= z.hi && hi >= z.lo);
}

void ScanOrderBlocks(int s)
{
   obCount[s] = 0;

   int need = InpOBScanBars + InpOBImpulseBars + 3;
   MqlRates r[];
   if(CopyRates(syms[s], InpOBTimeframe, 0, need, r) < need) return;
   ArraySetAsSeries(r, true);

   double a[];
   ArraySetAsSeries(a, true);
   if(CopyBuffer(atrOB[s], 0, 0, need, a) < need) return;

   int maxAge = (InpOBMaxAgeBars > 0 && InpOBMaxAgeBars < InpOBScanBars)
                ? InpOBMaxAgeBars : InpOBScanBars;

   // Walk from the newest usable candidate backwards, so the list ends up
   // newest-first and the freshest zone is the one entries prefer.
   for(int i = 1 + InpOBImpulseBars; i <= maxAge && obCount[s] < MAX_OB; i++)
   {
      if(a[i] <= 0) continue;

      // Last opposite-colour candle: a down candle seeds a bullish block,
      // an up candle seeds a bearish block. Dojis seed nothing.
      int dir = 0;
      if(r[i].close < r[i].open)      dir =  1;
      else if(r[i].close > r[i].open) dir = -1;
      else continue;

      // --- Displacement leg: the bars immediately after the block ---
      double ext   = (dir == 1) ? r[i].high : r[i].low;
      bool   bos   = false;   // break of structure through the block
      bool   fvg   = false;   // fair-value gap inside the leg

      for(int j = i - 1; j >= i - InpOBImpulseBars; j--)
      {
         if(dir == 1)
         {
            if(r[j].high > ext)          ext = r[j].high;
            if(r[j].close > r[i].high)   bos = true;
            // three-candle imbalance: this bar's low is above the high two
            // bars earlier, leaving unfilled space behind the move
            if(j <= i - 2 && r[j].low > r[j + 2].high) fvg = true;
         }
         else
         {
            if(r[j].low < ext)           ext = r[j].low;
            if(r[j].close < r[i].low)    bos = true;
            if(j <= i - 2 && r[j].high < r[j + 2].low) fvg = true;
         }
      }

      if(!bos) continue;
      if(InpOBRequireFVG && !fvg) continue;

      double travel = (dir == 1) ? (ext - r[i].low) : (r[i].high - ext);
      if(travel < InpOBImpulseATR * a[i]) continue;

      // --- The zone itself ---
      double zHi = InpOBUseBody ? MathMax(r[i].open, r[i].close) : r[i].high;
      double zLo = InpOBUseBody ? MathMin(r[i].open, r[i].close) : r[i].low;
      if(zHi <= zLo) continue;

      // --- Mitigation and invalidation ---
      // Scanned from the end of the displacement leg: the bars inside the leg
      // start on top of the block, so counting them would mark every fresh
      // zone as already touched.
      bool dead = false, touched = false;
      for(int j = i - InpOBImpulseBars - 1; j >= 1; j--)
      {
         if(dir == 1)
         {
            if(r[j].close < zLo) { dead = true; break; }   // closed through it — the zone failed
            if(r[j].low <= zHi)  touched = true;           // price has already returned into it
         }
         else
         {
            if(r[j].close > zHi) { dead = true; break; }
            if(r[j].high >= zLo) touched = true;
         }
      }

      if(dead) continue;
      if(InpOBFirstTouchOnly && touched) continue;

      // Keep only distinct zones: a nested older block in the same direction
      // is the same level of interest, already represented by the newer one.
      bool dup = false;
      for(int k = 0; k < obCount[s]; k++)
         if(ZonesOverlap(obs[s][k], zHi, zLo, dir)) { dup = true; break; }
      if(dup) continue;

      obs[s][obCount[s]].time    = r[i].time;
      obs[s][obCount[s]].hi      = zHi;
      obs[s][obCount[s]].lo      = zLo;
      obs[s][obCount[s]].dir     = dir;
      obs[s][obCount[s]].touched = touched;
      obCount[s]++;
   }
}

//==============================================================
// Order Block Entry: price has retraced into an unmitigated zone
// in the trend direction. Returns the zone edges so the stop can
// be placed just beyond it.
//==============================================================

bool FindEntryOB(int s, int dir, double &zHi, double &zLo, datetime &zTime)
{
   if(obCount[s] <= 0) return false;

   double a[1];
   if(CopyBuffer(atrOB[s], 0, 1, 1, a) <= 0 || a[0] <= 0) return false;
   double buf = InpOBEntryBufferATR * a[0];

   double bid = SymbolInfoDouble(syms[s], SYMBOL_BID);
   double ask = SymbolInfoDouble(syms[s], SYMBOL_ASK);

   for(int k = 0; k < obCount[s]; k++)
   {
      if(obs[s][k].dir != dir) continue;
      if(obs[s][k].time == obTraded[s]) continue;   // this zone already had its trade

      if(dir == 1)
      {
         // Long: price has dropped to the top edge (plus the arming buffer)
         // but has not broken below the zone.
         if(bid <= obs[s][k].hi + buf && bid > obs[s][k].lo)
         {
            zHi = obs[s][k].hi; zLo = obs[s][k].lo; zTime = obs[s][k].time;
            return true;
         }
      }
      else
      {
         if(ask >= obs[s][k].lo - buf && ask < obs[s][k].hi)
         {
            zHi = obs[s][k].hi; zLo = obs[s][k].lo; zTime = obs[s][k].time;
            return true;
         }
      }
   }
   return false;
}

// Confirmation: the last closed InpOBConfirmTF bar rejected the zone in the
// trend direction — it traded into the zone and closed back out of it, in
// the trend's favour. Keeps the EA from buying straight into a zone that is
// being sliced through.
bool ConfirmOB(int s, int dir, double zHi, double zLo)
{
   MqlRates c[];
   if(CopyRates(syms[s], InpOBConfirmTF, 1, 1, c) <= 0) return false;

   if(dir == 1)
      return (c[0].close > c[0].open && c[0].low <= zHi && c[0].close > zLo);

   return (c[0].close < c[0].open && c[0].high >= zLo && c[0].close < zHi);
}

//==============================================================
// Exit Check: M15 price closed on wrong side of M15 kijun
//==============================================================

bool CheckM15Exit(int s, int dir)
{
   double kij[1];
   if(CopyBuffer(ich[s][IDX_M15], 1, 1, 1, kij) <= 0) return false;

   MqlRates rt[];
   if(CopyRates(syms[s], PERIOD_M15, 1, 1, rt) <= 0) return false;
   double closeP = rt[0].close;

   if(dir ==  1 && closeP < kij[0]) return true;
   if(dir == -1 && closeP > kij[0]) return true;
   return false;
}

//==============================================================
// Choppy-market detection: ADX(M15) below InpChopADXLevel means no
// trend, so the trail is allowed. An unready/unknown ADX value is
// treated as choppy (trail on) to match the always-on default.
//==============================================================

bool IsChoppy(int s)
{
   double d[1];
   if(CopyBuffer(adx[s], 0, 1, 1, d) <= 0 || d[0] <= 0) return true;
   return d[0] < InpChopADXLevel;
}

//==============================================================
// Exit Trail: ATR chandelier stop once the trade is in profit.
// The reference point is the extreme (high/low) of the M15 bar
// that is still forming, so a peak is locked in before it
// retraces. Re-evaluated on every new M1 bar; only ever
// tightens and never sits inside the broker minimum stop.
//==============================================================

void ManageTrail(int s)
{
   if(state[s] == 0 || InpTrailMode == TRAIL_OFF || !InpUseStopLoss) return;
   if(InpTrailMode == TRAIL_CHOPPY && !IsChoppy(s)) return;

   double atrVal;
   if(atr[s] == INVALID_HANDLE) return;
   double a[1];
   if(CopyBuffer(atr[s], 0, 1, 1, a) <= 0 || a[0] <= 0) return;
   atrVal = a[0];

   MqlRates m15[];
   if(CopyRates(syms[s], PERIOD_M15, 0, 1, m15) <= 0) return;
   ArraySetAsSeries(m15, true);

   bool isLong = (state[s] == 1);
   if(isLong)
   {
      if(m15[0].high > trailHigh[s]) trailHigh[s] = m15[0].high;
   }
   else
   {
      if(m15[0].low < trailLow[s]) trailLow[s] = m15[0].low;
   }

   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);

   // Not profitable enough yet to arm the trail
   if(isLong && SymbolInfoDouble(syms[s], SYMBOL_BID) < entryPrice[s] + InpTrailActivateATR * atrVal) return;
   if(!isLong && SymbolInfoDouble(syms[s], SYMBOL_ASK) > entryPrice[s] - InpTrailActivateATR * atrVal) return;

   double price = isLong ? SymbolInfoDouble(syms[s], SYMBOL_BID)
                         : SymbolInfoDouble(syms[s], SYMBOL_ASK);
   double slNew = isLong ? trailHigh[s] - InpTrailATR * atrVal
                         : trailLow[s] + InpTrailATR * atrVal;
   slNew = NormalizeDouble(slNew, digits);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != syms[s]) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;

      double slCur = PositionGetDouble(POSITION_SL);

      // Only ever tighten, keep out of the broker's minimum stop distance,
      // and skip microscopic improvements (0.3x ATR) to cut request volume.
      if(isLong && slNew > slCur + point && slNew < price - minDist &&
         slNew - slCur >= 0.3 * atrVal)
      {
         if(!trade.PositionModify(ticket, slNew, 0))
            Print(PCTime() + " | " + syms[s] + " trail SL modify failed, retcode " + IntegerToString(trade.ResultRetcode()));
      }
      if(!isLong && slNew < slCur - point && slNew > price + minDist &&
         slCur - slNew >= 0.3 * atrVal)
      {
         if(!trade.PositionModify(ticket, slNew, 0))
            Print(PCTime() + " | " + syms[s] + " trail SL modify failed, retcode " + IntegerToString(trade.ResultRetcode()));
      }
   }
}

//==============================================================
// Break-Even Management (BE30): if the trade reaches a profitable
// position within InpBE30Minutes of entry, the stop loss moves up
// to break even plus a few points to cover the spread. One-shot
// per trade (beMoved); the chandelier trail may tighten further
// afterwards but never lowers the stop back down.
//==============================================================

double AvgOpenPrice(int s)
{
   double sum = 0.0, vol = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != syms[s]) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;
      sum += PositionGetDouble(POSITION_PRICE_OPEN) * PositionGetDouble(POSITION_VOLUME);
      vol += PositionGetDouble(POSITION_VOLUME);
   }
   return (vol > 0) ? sum / vol : 0.0;
}

void ManageBE(int s)
{
   if(state[s] == 0 || !InpBE30Enabled) return;
   if(entryTime[s] == 0 || beMoved[s]) return;

   // The profit window: once InpBE30Minutes have passed without the trade
   // turning profitable, the stop stays where it is for this trade.
   if(TimeCurrent() - entryTime[s] > InpBE30Minutes * 60) return;

   double avg = AvgOpenPrice(s);
   if(avg <= 0) return;

   if(atr[s] == INVALID_HANDLE) return;
   double a[1];
   if(CopyBuffer(atr[s], 0, 1, 1, a) <= 0 || a[0] <= 0) return;
   double atrVal = a[0];

   bool   isLong = (state[s] == 1);
   double bid    = SymbolInfoDouble(syms[s], SYMBOL_BID);
   double ask    = SymbolInfoDouble(syms[s], SYMBOL_ASK);

   // Not yet profitable enough to arm the break-even move
   if(isLong && bid < avg + InpBE30ActivateATR * atrVal) return;
   if(!isLong && ask > avg - InpBE30ActivateATR * atrVal) return;

   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);

   // Break even plus a few points to cover the spread
   double slNew = isLong ? avg + InpBE30CoverPoints * point
                         : avg - InpBE30CoverPoints * point;
   slNew = NormalizeDouble(slNew, digits);

   double price = isLong ? bid : ask;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != syms[s]) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;

      double slCur = PositionGetDouble(POSITION_SL);

      // Only ever tighten, and keep out of the broker's minimum stop distance
      if(isLong && slNew > slCur + point && slNew < price - minDist)
      {
         if(!trade.PositionModify(ticket, slNew, 0))
            Print(PCTime() + " | " + syms[s] + " BE SL modify failed, retcode " + IntegerToString(trade.ResultRetcode()));
         else
            beMoved[s] = true;
      }
      if(!isLong && slNew < slCur - point && slNew > price + minDist)
      {
         if(!trade.PositionModify(ticket, slNew, 0))
            Print(PCTime() + " | " + syms[s] + " BE SL modify failed, retcode " + IntegerToString(trade.ResultRetcode()));
         else
            beMoved[s] = true;
      }
   }
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

//==============================================================
// Risk Management
//==============================================================

// Lot size that risks InpHighEquityRiskPct% of equity, split evenly across
// 'count' concurrent orders, if the stop loss is hit on all of them.
double RiskBasedLots(string sym, double eq, double stopDist, int count)
{
   double fallback = 0.10;
   if(stopDist <= 0 || count <= 0) return fallback;

   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0) return fallback;

   double moneyPerLot = (stopDist / tickSize) * tickValue;
   if(moneyPerLot <= 0) return fallback;

   double riskMoney = eq * (InpHighEquityRiskPct / 100.0) / count;
   double lots      = riskMoney / moneyPerLot;

   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   if(lotStep > 0) lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lotMin, MathMin(lotMax, lots));

   return (lots > 0) ? lots : fallback;
}

void GetEquityRisk(string sym, double stopDist, int &count, double &lots)
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq <= 30)        { count = 4;  lots = 0.10; }
   else if(eq <= 50)   { count = 4;  lots = 0.10; }
   else if(eq <= 70)   { count = 8;  lots = 0.10; }
   else if(eq <= 100)  { count = 8;  lots = 0.10; }
   else if(eq <= 130)  { count = 12;  lots = 0.10; }
   else if(eq <= 150)  { count = 16;  lots = 0.10; }
   else if(eq <= 170)  { count = 20; lots = 0.10; }
   else if(eq <= 200)  { count = 12;  lots = 0.20; }
   else if(eq <= 300)  { count = 8;  lots = 0.30; }
   else if(eq <= 400)  { count = 12;  lots = 0.30; }
   else if(eq <= 500)  { count = 12;  lots = 0.30; }
   else if(eq <= 600)  { count = 16;  lots = 0.30; }
   else if(eq <= 1000) { count = 8;  lots = 0.50; }
   else if(eq <= 3000) { count = 8;  lots = 0.30; }
   else if(eq <= 5000) { count = 8;  lots = 0.20; }
   else if(eq <= 8000) { count = 8;  lots = 0.10; }
   else                { count = 4;  lots = RiskBasedLots(sym, eq, stopDist, count); }
}

// Scale the ladder down so the initial stop on all orders risks at most
// InpMaxRiskPct% of equity. count never drops below 1.
void CapToRisk(string sym, double dist, int &count, double &lots)
{
   if(count <= 0 || lots <= 0 || dist <= 0 || InpMaxRiskPct <= 0) return;
   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0) return;

   double lossPerOrder = (dist / tickSize) * tickValue * lots;
   if(lossPerOrder <= 0) return;

   double budget = AccountInfoDouble(ACCOUNT_EQUITY) * (InpMaxRiskPct / 100.0);
   int maxByRisk = (int)MathFloor(budget / lossPerOrder);
   if(maxByRisk < 1) maxByRisk = 1;
   if(count > maxByRisk) count = maxByRisk;
}

// Scale the ladder down to the free margin so the orders fill fully
// instead of silently breaking mid-way. count never drops below 1.
void CapToMargin(string sym, bool isBuy, int &count, double &lots)
{
   if(count <= 0 || lots <= 0) return;
   double price = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK)
                        : SymbolInfoDouble(sym, SYMBOL_BID);
   double marginOne = 0.0;
   if(!OrderCalcMargin(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, sym, lots, price, marginOne))
      return;
   if(marginOne <= 0) return;
   int maxByMargin = (int)MathFloor(AccountInfoDouble(ACCOUNT_MARGIN_FREE) / marginOne);
   if(maxByMargin < 1) maxByMargin = 1;
   if(count > maxByMargin) count = maxByMargin;
}

//==============================================================
// Trading Functions
//==============================================================

bool SpreadOK(string sym)
{
   if(InpMaxSpreadPoints <= 0) return true;
   return SymbolInfoInteger(sym, SYMBOL_SPREAD) <= InpMaxSpreadPoints;
}

// ATR(M15) * multiplier, widened to the broker's minimum stop distance if
// needed. Returns false when the ATR value is unavailable so the caller
// skips the entry instead of trading unprotected.
bool GetStopDistance(int s, double &dist)
{
   dist = 0.0;
   double a[1];
   if(CopyBuffer(atr[s], 0, 1, 1, a) <= 0 || a[0] <= 0) return false;

   dist = a[0] * InpATRMultiplier;
   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   if(dist < minDist) dist = minDist;
   return true;
}

// Stop just beyond the far edge of the order block: below the zone low for a
// long, above the zone high for a short. This is the real payoff of entering
// at the origin — the invalidation level is close, so the same money risk
// buys a much bigger position or a much larger R multiple.
// Returns false (skip the entry) when the zone stop would be wider than
// InpOBMaxStopATR x ATR(M15) — that means price is already deep through the
// zone and the setup is no longer an early entry.
bool GetOBStopDistance(int s, int dir, double zHi, double zLo, double &dist)
{
   dist = 0.0;
   double a[1];
   if(CopyBuffer(atrOB[s], 0, 1, 1, a) <= 0 || a[0] <= 0) return false;
   double buf = InpOBStopBufferATR * a[0];

   double price = (dir == 1) ? SymbolInfoDouble(syms[s], SYMBOL_ASK)
                             : SymbolInfoDouble(syms[s], SYMBOL_BID);

   dist = (dir == 1) ? price - (zLo - buf) : (zHi + buf) - price;
   if(dist <= 0) return false;

   if(InpOBMaxStopATR > 0)
   {
      double m[1];
      if(CopyBuffer(atr[s], 0, 1, 1, m) <= 0 || m[0] <= 0) return false;
      if(dist > InpOBMaxStopATR * m[0]) return false;
   }

   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   if(dist < minDist) dist = minDist;
   return true;
}

double BuildStopLoss(int s, bool isBuy, double price, double dist)
{
   int digits = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);
   return NormalizeDouble(isBuy ? price - dist : price + dist, digits);
}

int OpenPositions(int s, bool isBuy, double dist, int count, double lots, string tag, double &firstFill)
{
   string sym = syms[s];

   int filled = 0;
   firstFill = 0.0;
   for(int i = 0; i < count; i++)
   {
      double price = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK)
                           : SymbolInfoDouble(sym, SYMBOL_BID);
      double sl = InpUseStopLoss ? BuildStopLoss(s, isBuy, price, dist) : 0.0;

      bool ok = isBuy ? trade.Buy(lots,  sym, price, sl, 0, "Buy "  + tag)
                      : trade.Sell(lots, sym, price, sl, 0, "Sell " + tag);
      if(!ok) break;   // out of margin or rejected — don't hammer the server
      if(firstFill == 0.0) firstFill = price;
      filled++;
   }
   return filled;
}

// Close all positions for the symbol; returns true only when none remain
// open, so a failed close (requote, halt) is retried instead of freeing
// the symbol for a fresh entry.
bool ClosePositions(string sym)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC)
      {
         if(!trade.PositionClose(ticket))
            Print(PCTime() + " | " + sym + " close failed, retcode " + IntegerToString(trade.ResultRetcode()));
      }
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC) return false;
   }
   return true;
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

   // Equity alert: fire only on a new H4 bar (CheckEquityAlert self-guards on day-of-week)
   MqlRates h4eq[];
   if(symsCount > 0 && CopyRates(syms[0], PERIOD_H4, 0, 1, h4eq) > 0 && h4eq[0].time != lastEquityBar)
   {
      lastEquityBar = h4eq[0].time;
      CheckEquityAlert();
   }

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

      // Re-map the order blocks once per closed OB-timeframe bar
      if(InpEntryMode != ENTRY_ALIGNMENT)
      {
         MqlRates ob[];
         if(CopyRates(syms[s], InpOBTimeframe, 0, 2, ob) >= 2)
         {
            ArraySetAsSeries(ob, true);
            if(ob[1].time != lastOBbar[s])
            {
               lastOBbar[s] = ob[1].time;
               ScanOrderBlocks(s);
            }
         }
      }

      // Exit check: close all when M15 closes against direction across M15 kijun
      if(state[s] != 0 && CheckM15Exit(s, state[s]))
      {
         string side = (state[s] == 1) ? "Long" : "Short";
         string msg  = PCTime() + " | Close " + syms[s] + " " + side + " (M15 kijun crossed)";
         Print(msg); Alert(msg); SendNotification(msg);

         if(ClosePositions(syms[s]))
         {
            state[s] = 0;
            noReentryUntil[s] = TimeCurrent() + InpReentryCooldownSec;
         }
         else
            Print(PCTime() + " | " + syms[s] + " exit signal but positions still open — will retry");
      }

      // Chandelier trail: tighten stops behind the peak on each new M1 bar
      if(state[s] != 0) ManageTrail(s);

      // BE30: move the stop to break even + cover if profitable in time
      if(state[s] != 0) ManageBE(s);

      // Entry check: order block first (it fires earlier), full alignment second
      if(state[s] == 0 && TimeCurrent() >= noReentryUntil[s] && SpreadOK(syms[s]))
      {
         int      st     = 0;
         bool     fromOB = false;
         double   zHi    = 0.0, zLo = 0.0;
         datetime zTime  = 0;

         if(InpEntryMode != ENTRY_ALIGNMENT)
         {
            int tdir = TrendDir(s);
            if(tdir != 0 && FindEntryOB(s, tdir, zHi, zLo, zTime))
            {
               if(!InpOBUseConfirm || ConfirmOB(s, tdir, zHi, zLo))
               {
                  st     = tdir;
                  fromOB = true;
               }
            }
         }

         if(st == 0 && InpEntryMode != ENTRY_ORDERBLOCK)
            st = CheckAllAlign(s);

         if(st != 0)
         {
            bool   isBuy = (st == 1);
            double dist  = 0.0;
            if(InpUseStopLoss)
            {
               if(fromOB && InpOBStopMode == OB_STOP_ZONE)
               {
                  // Zone stop unavailable or already too wide — the setup is
                  // no longer early, so skip it rather than widen the risk.
                  if(!GetOBStopDistance(s, st, zHi, zLo, dist)) continue;
               }
               else if(!GetStopDistance(s, dist)) continue;
            }

            int count; double lots;
            GetEquityRisk(syms[s], dist, count, lots);
            CapToRisk(syms[s], dist, count, lots);
            CapToMargin(syms[s], isBuy, count, lots);

            // Track state if any order filled — keeps exit logic and re-entry
            // guard correct even when only some of the orders go through.
            // Alert reports the actual fill count, not the requested count.
            string tag = fromOB ? "OB" : "H4-M1";
            double firstFill = 0.0;
            int filled = OpenPositions(s, isBuy, dist, count, lots, tag, firstFill);
            if(filled > 0)
            {
               state[s] = st;
               entryPrice[s] = firstFill;   // chandelier trail reference
               trailHigh[s]  = firstFill;
               trailLow[s]   = firstFill;
               entryTime[s]  = TimeCurrent();   // start the BE30 profit window
               beMoved[s]    = false;
               if(fromOB) obTraded[s] = zTime; // one trade per order block

               string action = isBuy ? "Buy" : "Sell";
               string src    = fromOB
                  ? "OB " + DoubleToString(zLo, (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS)) +
                    "-"   + DoubleToString(zHi, (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS))
                  : "H4-M1 align";
               string msg = PCTime() + " | " + action + " " + syms[s] +
                            " x" + IntegerToString(filled) +
                            " @ " + DoubleToString(lots, 2) + " (" + src + ")";
               Print(msg); Alert(msg); SendNotification(msg);
            }
            else
               Print(PCTime() + " | " + syms[s] + " entry signal but no order filled");
         }
      }
   }
}
//This work is my worship unto GOD
