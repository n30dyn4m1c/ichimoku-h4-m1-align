//+------------------------------------------------------------------+
//| Ichimoku H1-M1 Alignment EA (BE30) — VPS build                   |
//| Entry: H1→M1 price+chikou all above/below tenkan,kijun,cloud    |
//| Exit:  ATR chandelier trailing stop once profitable (locks in    |
//|        the peak), M5 close crosses M5 kijun as final fallback,   |
//|        or ATR-based protective stop loss                         |
//| Experiment: if price reaches a profitable position within        |
//|        InpBE30Minutes of entry, the stop loss moves up to        |
//|        break even + a few points to cover the spread (BE30)      |
//| Time theory: optional kihon suchi filter — a breakout is skipped |
//|        when the H1/M30/M15/M5 move count (bars since the last    |
//|        Kijun touch) equals a kihon suchi number up to 100 exactly |
//|        (9/17/26/33/42/51/65/76/83/97). Nested: H1 is checked first, then M30,|
//|        then M15, then M5 — each must be clear (not on a cycle)   |
//|        before the next is checked; all clear => trade proceeds   |
//| VPS: no Alert popups or equity alerts; all logic runs only on    |
//|        closed M1 bars (once per minute) to cut CPU usage         |
//| Risk:   ladder optionally capped by InpMaxRiskPct (0 = off) and  |
//|        by free margin; exits are verified so failed closes retry |
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

input group  "Risk Protection"
input bool   InpUseStopLoss       = true;   // Attach ATR-based stop loss to every entry
input int    InpATRPeriod         = 14;     // ATR period (M15)
input double InpATRMultiplier     = 3.0;    // SL distance = ATR * multiplier
input int    InpMaxSpreadPoints   = 60;     // Max spread in points to allow entry (0 = no limit)
input double InpHighEquityRiskPct = 1.0;    // % of equity risked per trade once equity > $8000
input int    InpReentryCooldownSec = 0;     // Min seconds after an exit before re-entering same symbol (0 = none)
input double InpMaxRiskPct         = 0.0;   // Cap total initial-stop risk per ladder as % of equity (0 = no cap)

//--- Trail mode: off, always on, or choppy-only (ADX regime filter)
enum ENUM_TRAIL_MODE { TRAIL_OFF = 0, TRAIL_ALWAYS = 1, TRAIL_CHOPPY = 2 };

input group  "Exit Management"
input ENUM_TRAIL_MODE InpTrailMode        = TRAIL_CHOPPY;  // 0=off, 1=always, 2=choppy-only (ADX)
input double          InpTrailATR         = 2.0;   // Trail distance = ATR(M5) * multiplier
input double          InpTrailActivateATR = 1.0;   // Arm the trail once profit >= ATR(M5) * multiplier
input int             InpADXPeriod        = 14;    // ADX period for choppy-market detection (M5)
input double          InpChopADXLevel     = 22.0;  // ADX below this = choppy -> trail on in auto mode

input group  "Break-Even (BE30) Management"
input bool   InpBE30Enabled        = true;   // Move SL to break even when profitable in time
input int    InpBE30Minutes        = 30;     // Profit window after entry (minutes)
input double InpBE30ActivateATR    = 0.5;    // Min profit to arm BE (x ATR M15)
input int    InpBE30CoverPoints    = 15;     // Points beyond break even (covers spread)

input group  "Time Theory (Kihon Suchi)"
input bool   InpUseTimeFilter  = false;   // Skip entry when a TF move count equals a kihon suchi number (off by default)
input string InpTimeCycles     = "9,17,26,33,42,51,65,76,83,97,101,129,172,200,226,257,676"; // Ichimoku kihon suchi cycles: bars since last Kijun touch (touch candle = bar 1, present candle included)
input bool   InpTimeFilterH1   = true;    // Check H1 first (exact match, up to cycle 100)
input bool   InpTimeFilterM30  = true;    // Check M30 next, only if H1 is clear
input bool   InpTimeFilterM15  = true;    // Check M15 next, only if M30 is clear
input bool   InpTimeFilterM5   = true;    // Check M5 last, only if M15 is clear

//--- Constants and Global Variables ---
#define MAX_SYMS  60
#define TF_COUNT  5
#define IDX_M5    3   // index of M5 in tfs[] — used for exit check
#define KIHON_MAX_CYCLE 100   // cycle cap on every timeframe: older moves are never "mature"

ENUM_TIMEFRAMES tfs[TF_COUNT] = {
   PERIOD_H1, PERIOD_M30, PERIOD_M15, PERIOD_M5, PERIOD_M1
};

int      ich[MAX_SYMS][TF_COUNT];
int      atr[MAX_SYMS];
int      atrExit[MAX_SYMS];   // ATR(M5) handle for the chandelier trail
int      adx[MAX_SYMS];   // ADX(M5) handle for choppy-market regime detection
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar[MAX_SYMS];
datetime noReentryUntil[MAX_SYMS];
int      lastSkipKey[MAX_SYMS];   // dedup time-filter skip logs (tfIdx * 10000 + count)
int      lastMinuteKey = -1;
int      state[MAX_SYMS];   // 0=no position, 1=long, -1=short

double   entryPrice[MAX_SYMS];  // reference entry price per symbol (trail arming)
double   trailHigh[MAX_SYMS];   // highest high since entry (long chandelier reference)
double   trailLow[MAX_SYMS];    // lowest low since entry (short chandelier reference)

datetime entryTime[MAX_SYMS];   // entry time per symbol (BE30 profit window)
bool     beMoved[MAX_SYMS];     // BE30 stop already moved to break even (one-shot)

int  g_cycles[];        // parsed kihon suchi cycle list (9,17,26,...,676 by default)
int  g_cycleCount = 0;  // number of parsed cycles

int MAGIC = 20260814;   // distinct from the other H1-M1 builds so both can run on one account

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

   ParseCycles(InpTimeCycles);
   if(InpUseTimeFilter && g_cycleCount <= 0) return(INIT_FAILED);

   for(int s = 0; s < symsCount; s++)
   {
      state[s] = 0;
      lastM1bar[s] = 0;
      noReentryUntil[s] = 0;
      lastSkipKey[s] = -1;
      entryTime[s] = 0;
      beMoved[s] = false;
      for(int t = 0; t < TF_COUNT; t++)
      {
         ich[s][t] = iIchimoku(syms[s], tfs[t], Tenkan, Kijun, SenkouB);
         if(ich[s][t] == INVALID_HANDLE) return(INIT_FAILED);
      }

      atr[s] = INVALID_HANDLE;
      if(InpUseStopLoss)
      {
         atr[s] = iATR(syms[s], PERIOD_M15, InpATRPeriod);
         if(atr[s] == INVALID_HANDLE) return(INIT_FAILED);
      }

      atrExit[s] = INVALID_HANDLE;
      if(InpTrailMode != TRAIL_OFF)
      {
         atrExit[s] = iATR(syms[s], PERIOD_M5, InpATRPeriod);
         if(atrExit[s] == INVALID_HANDLE) return(INIT_FAILED);
      }

      adx[s] = INVALID_HANDLE;
      if(InpTrailMode == TRAIL_CHOPPY)
      {
         adx[s] = iADX(syms[s], PERIOD_M5, InpADXPeriod);
         if(adx[s] == INVALID_HANDLE) return(INIT_FAILED);
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
      for(int t = 0; t < TF_COUNT; t++)
         if(ich[s][t] != INVALID_HANDLE) IndicatorRelease(ich[s][t]);
      if(atr[s] != INVALID_HANDLE) IndicatorRelease(atr[s]);
      if(atrExit[s] != INVALID_HANDLE) IndicatorRelease(atrExit[s]);
      if(adx[s] != INVALID_HANDLE) IndicatorRelease(adx[s]);
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
// Entry Check: all timeframes (H1→M1) aligned same direction
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
// Ichimoku Time Theory (Kihon Suchi)
//==============================================================
// The kihon suchi basic numbers (9 / 17 / 26 / 33 / 42 / 51 / 65 /
// 76 / 83 / 97 / 101 / 129 / 172 / 200 / 226 / 257 / 676) are bar
// counts at which a move tends
// to mature and change direction. The count used
// here is "bars since the last Kijun touch" (the breakaway), the same
// convention as the H1-M1 reversion EA. At an aligned breakout the
// count measures how many candles the current move has already
// printed on that timeframe. If the count EXACTLY equals a kihon
// suchi number up to 100 the move is mature and the breakout is low
// probability; between cycles there is room for the move to continue
// to the next number — the continuation case. The cascade below
// checks H1 first, then M30, then M15, then M5 — each must be clear
// before the next is consulted.

// Parse the kihon suchi cycle list into g_cycles[].
void ParseCycles(string list)
{
   string parts[];
   int n = StringSplit(list, ',', parts);
   ArrayResize(g_cycles, 0);
   g_cycleCount = 0;
   for(int i = 0; i < n; i++)
   {
      string p = parts[i];
      StringTrimLeft(p);
      StringTrimRight(p);
      int v = (int)StringToInteger(p);
      if(v > 0)
      {
         ArrayResize(g_cycles, g_cycleCount + 1);
         g_cycles[g_cycleCount++] = v;
      }
   }
}

// True when the count exactly equals a cycle <= maxCycle (mature move).
// Cycles beyond maxCycle are ignored — all timeframes cap at
// KIHON_MAX_CYCLE (100).
bool InTimeWindow(int count, int maxCycle)
{
   for(int i = 0; i < g_cycleCount; i++)
   {
      if(g_cycles[i] > maxCycle) continue;
      if(count == g_cycles[i]) return true;
   }
   return false;
}

// Closed bars on timeframe tfIdx whose whole range stayed on the move's
// side of the Kijun (above it for a long, below for a short), counted
// from the first clear candle up to the present candle. Stops at the
// first touch or side violation — the count is the age of the current
// move in bars on that timeframe, with the touching candle as candle 1.
// Lookback is bounded by maxCycle so shallow history suffices (100 bars
// on any timeframe).
int CountNoTouchTF(int s, int tfIdx, int dir, int maxCycle)
{
   int want = maxCycle + 10;
   double kij[];
   MqlRates rt[];
   if(CopyBuffer(ich[s][tfIdx], 1, 1, want, kij) <= 0) return 0;
   if(CopyRates(syms[s], tfs[tfIdx], 1, want, rt) <= 0) return 0;
   ArraySetAsSeries(kij, true);
   ArraySetAsSeries(rt, true);

   int n = MathMin(ArraySize(kij), ArraySize(rt));
   int count = 0;
   for(int i = 0; i < n; i++)
   {
      double k = kij[i];
      if(dir == 1)
      {
         if(rt[i].low <= k) break;    // touched the Kijun or slipped under it
      }
      else
      {
         if(rt[i].high >= k) break;   // touched the Kijun or slipped above it
      }
      count++;
   }
   // +2: candle 1 is the touching candle (the breakaway candle that
   // starts the move); the count then runs through the clear candles
   // up to the present forming candle.
   return count + 2;
}

// One skip line per (timeframe, count) episode instead of one per minute.
void LogTimeSkip(int s, int tfIdx, int count, string tfName)
{
   int key = tfIdx * 10000 + count;
   if(lastSkipKey[s] == key) return;
   lastSkipKey[s] = key;
   Print(PCTime() + " | " + syms[s] + " skip entry: " + tfName + " time cycle mature (count " + IntegerToString(count) + ")");
}

// Nested kihon suchi cascade: H1 -> M30 -> M15 -> M5. Each timeframe
// must be clear (count not exactly on a cycle) before the next is
// checked; a mature count anywhere in the chain blocks the breakout.
// Each timeframe's check is gated by its own input flag.
// Returns true when the entry was skipped.
bool TimeFilterBlocks(int s, int st)
{
   if(!InpUseTimeFilter) return false;

   if(InpTimeFilterH1)
   {
      int c1 = CountNoTouchTF(s, 0, st, KIHON_MAX_CYCLE);
      if(InTimeWindow(c1, KIHON_MAX_CYCLE))
      {
         LogTimeSkip(s, 0, c1, "H1");
         return true;
      }
   }
   if(InpTimeFilterM30)
   {
      int c30 = CountNoTouchTF(s, 1, st, KIHON_MAX_CYCLE);
      if(InTimeWindow(c30, KIHON_MAX_CYCLE))
      {
         LogTimeSkip(s, 1, c30, "M30");
         return true;
      }
   }
   if(InpTimeFilterM15)
   {
      int c15 = CountNoTouchTF(s, 2, st, KIHON_MAX_CYCLE);
      if(InTimeWindow(c15, KIHON_MAX_CYCLE))
      {
         LogTimeSkip(s, 2, c15, "M15");
         return true;
      }
   }
   if(InpTimeFilterM5)
   {
      int c5 = CountNoTouchTF(s, IDX_M5, st, KIHON_MAX_CYCLE);
      if(InTimeWindow(c5, KIHON_MAX_CYCLE))
      {
         LogTimeSkip(s, IDX_M5, c5, "M5");
         return true;
      }
   }
   return false;
}

//==============================================================
// Exit Check: M5 price closed on wrong side of M5 kijun
//==============================================================

bool CheckM5Exit(int s, int dir)
{
   double kij[1];
   if(CopyBuffer(ich[s][IDX_M5], 1, 1, 1, kij) <= 0) return false;

   MqlRates rt[];
   if(CopyRates(syms[s], PERIOD_M5, 1, 1, rt) <= 0) return false;
   double closeP = rt[0].close;

   if(dir ==  1 && closeP < kij[0]) return true;
   if(dir == -1 && closeP > kij[0]) return true;
   return false;
}

//==============================================================
// Choppy-market detection: ADX(M5) below InpChopADXLevel means no
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
// The reference point is the extreme (high/low) of the M5 bar
// that is still forming, so a peak is locked in before it
// retraces. Re-evaluated on every new M1 bar; only ever
// tightens and never sits inside the broker minimum stop.
//==============================================================

void ManageTrail(int s)
{
   if(state[s] == 0 || InpTrailMode == TRAIL_OFF || !InpUseStopLoss) return;
   if(InpTrailMode == TRAIL_CHOPPY && !IsChoppy(s)) return;

   double atrVal;
   if(atrExit[s] == INVALID_HANDLE) return;
   double a[1];
   if(CopyBuffer(atrExit[s], 0, 1, 1, a) <= 0 || a[0] <= 0) return;
   atrVal = a[0];

   MqlRates m5[];
   if(CopyRates(syms[s], PERIOD_M5, 0, 1, m5) <= 0) return;
   ArraySetAsSeries(m5, true);

   bool isLong = (state[s] == 1);
   if(isLong)
   {
      if(m5[0].high > trailHigh[s]) trailHigh[s] = m5[0].high;
   }
   else
   {
      if(m5[0].low < trailLow[s]) trailLow[s] = m5[0].low;
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
// 'count' concurrent orders, if the ATR stop loss is hit on all of them.
// Falls back to a conservative fixed lot when the stop distance or the
// symbol's tick value/size aren't available (e.g. InpUseStopLoss = false).
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
   if(eq <= 30)        { count = 2;  lots = 0.10; }
   else if(eq <= 50)   { count = 2;  lots = 0.10; }
   else if(eq <= 70)   { count = 4;  lots = 0.10; }
   else if(eq <= 100)  { count = 4;  lots = 0.10; }
   else if(eq <= 130)  { count = 6;  lots = 0.10; }
   else if(eq <= 150)  { count = 8;  lots = 0.10; }
   else if(eq <= 170)  { count = 10; lots = 0.10; }
   else if(eq <= 200)  { count = 6;  lots = 0.20; }
   else if(eq <= 300)  { count = 4;  lots = 0.30; }
   else if(eq <= 400)  { count = 6;  lots = 0.30; }
   else if(eq <= 500)  { count = 6;  lots = 0.30; }
   else if(eq <= 600)  { count = 8;  lots = 0.30; }
   else if(eq <= 1000) { count = 4;  lots = 0.50; }
   else if(eq <= 3000) { count = 4;  lots = 0.30; }
   else if(eq <= 5000) { count = 4;  lots = 0.20; }
   else if(eq <= 8000) { count = 4;  lots = 0.10; }
   else                { count = 2;  lots = RiskBasedLots(sym, eq, stopDist, count); }
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

double BuildStopLoss(int s, bool isBuy, double price, double dist)
{
   int digits = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);
   return NormalizeDouble(isBuy ? price - dist : price + dist, digits);
}

int OpenPositions(int s, bool isBuy, double dist, int count, double lots, double &firstFill)
{
   string sym = syms[s];

   int filled = 0;
   firstFill = 0.0;
   for(int i = 0; i < count; i++)
   {
      double price = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK)
                           : SymbolInfoDouble(sym, SYMBOL_BID);
      double sl = InpUseStopLoss ? BuildStopLoss(s, isBuy, price, dist) : 0.0;

      bool ok = isBuy ? trade.Buy(lots,  sym, price, sl, 0, "Buy H1-M1")
                      : trade.Sell(lots, sym, price, sl, 0, "Sell H1-M1");
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

      // Exit check: close all when M5 closes against direction across M5 kijun
      if(state[s] != 0 && CheckM5Exit(s, state[s]))
      {
         string side = (state[s] == 1) ? "Long" : "Short";
         string msg  = PCTime() + " | Close " + syms[s] + " " + side + " (M5 kijun crossed)";
         Print(msg); SendNotification(msg);

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

      // Entry check: all timeframes H1→M1 must align, spread must be sane
      if(state[s] == 0 && TimeCurrent() >= noReentryUntil[s] && SpreadOK(syms[s]))
      {
         int st = CheckAllAlign(s);
         if(st != 0)
         {
            // Time theory: nested kihon suchi cascade — H1 must be
            // clear (count not exactly on a cycle) before M30 is
            // checked, then M15, then M5. A mature count anywhere in
            // the chain blocks the entry.
            if(TimeFilterBlocks(s, st)) continue;

            bool   isBuy = (st == 1);
            double dist  = 0.0;
            if(InpUseStopLoss && !GetStopDistance(s, dist)) continue;   // ATR unavailable — skip entry

            int count; double lots;
            GetEquityRisk(syms[s], dist, count, lots);
            CapToRisk(syms[s], dist, count, lots);
            CapToMargin(syms[s], isBuy, count, lots);

            // Track state if any order filled — keeps exit logic and re-entry
            // guard correct even when only some of the orders go through.
            // Alert reports the actual fill count, not the requested count.
            double firstFill = 0.0;
            int filled = OpenPositions(s, isBuy, dist, count, lots, firstFill);
            if(filled > 0)
            {
               state[s] = st;
               entryPrice[s] = firstFill;   // chandelier trail reference
               trailHigh[s]  = firstFill;
               trailLow[s]   = firstFill;
               entryTime[s]  = TimeCurrent();   // start the BE30 profit window
               beMoved[s]    = false;
               string action = isBuy ? "Buy" : "Sell";
               string msg = PCTime() + " | " + action + " " + syms[s] +
                            " x" + IntegerToString(filled) +
                            " @ " + DoubleToString(lots, 2) + " (H1-M1)";
               Print(msg); SendNotification(msg);
            }
            else
               Print(PCTime() + " | " + syms[s] + " entry signal but no order filled");
         }
      }
   }
}
//This work is my worship unto GOD
