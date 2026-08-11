//+------------------------------------------------------------------+
//| Ichimoku H4-M1 Alignment EA (BE15)                               |
//| Entry: H4→M1 price+chikou all above/below tenkan,kijun,cloud    |
//| Exit:  ATR chandelier trailing stop once profitable (locks in    |
//|        the peak), M15 close crosses M15 kijun as final fallback, |
//|        or ATR-based protective stop loss                         |
//| Experiment: once the trade has been in profit continuously for   |
//|        InpBE15Minutes, the stop loss moves up to break even +    |
//|        a few points to cover the spread (BE15)                   |
//| Time theory: optional kihon suchi filter — a breakout is skipped |
//|        when the H4/H1/M30/M15 move count (bars since the last    |
//|        Kijun touch) equals a kihon suchi number up to 51 exactly |
//|        (9/17/26/33/42/51). Nested: H4 is checked first, then H1, |
//|        then M30, then M15 — each must be clear (not on a cycle)  |
//|        before the next is checked; all clear => trade proceeds   |
//|        change is due                                              |
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

//--- Trail mode: off, always on, or choppy-only (ADX regime filter)
enum ENUM_TRAIL_MODE { TRAIL_OFF = 0, TRAIL_ALWAYS = 1, TRAIL_CHOPPY = 2 };

input group  "Exit Management"
input ENUM_TRAIL_MODE InpTrailMode        = TRAIL_CHOPPY;  // 0=off, 1=always, 2=choppy-only (ADX)
input double          InpTrailATR         = 2.0;   // Trail distance = ATR(M15) * multiplier
input double          InpTrailActivateATR = 1.0;   // Arm the trail once profit >= ATR(M15) * multiplier
input int             InpADXPeriod        = 14;    // ADX period for choppy-market detection (M15)
input double          InpChopADXLevel     = 22.0;  // ADX below this = choppy -> trail on in auto mode

input group  "Break-Even (BE15) Management"
input bool   InpBE15Enabled        = true;   // Move SL to break even after time in profit
input int    InpBE15Minutes        = 15;     // Consecutive minutes in profit required
input double InpBE15ActivateATR    = 0.5;    // Min profit to count as "in profit" (x ATR M15)
input int    InpBE15CoverPoints    = 15;     // Points beyond break even (covers spread)

input group  "Time Theory (Kihon Suchi)"
input bool   InpUseTimeFilter  = true;    // Skip entry when a TF move count equals a kihon suchi number
input string InpTimeCycles     = "9,17,26,33,42,51,65,76,83,97,101,129,172,200,226,257,676"; // Ichimoku kihon suchi cycles: bars since last Kijun touch
input bool   InpTimeFilterH4   = true;    // Check H4 first (exact match, up to cycle 51)
input bool   InpTimeFilterH1   = true;    // Check H1 next, only if H4 is clear
input bool   InpTimeFilterM30  = true;    // Check M30 next, only if H1 is clear
input bool   InpTimeFilterM15  = true;    // Check M15 last, only if M30 is clear

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
#define KIHON_MAX_CYCLE 51   // cycle cap on every timeframe: older moves are never "mature"

ENUM_TIMEFRAMES tfs[TF_COUNT] = {
   PERIOD_H4, PERIOD_H1, PERIOD_M30, PERIOD_M15, PERIOD_M5, PERIOD_M1
};

int      ich[MAX_SYMS][TF_COUNT];
int      atr[MAX_SYMS];
int      adx[MAX_SYMS];   // ADX(M15) handle for choppy-market regime detection
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar[MAX_SYMS];
datetime noReentryUntil[MAX_SYMS];
datetime lastH4bar = 0;
int      state[MAX_SYMS];   // 0=no position, 1=long, -1=short

double   entryPrice[MAX_SYMS];  // reference entry price per symbol (trail arming)
double   trailHigh[MAX_SYMS];   // highest high since entry (long chandelier reference)
double   trailLow[MAX_SYMS];    // lowest low since entry (short chandelier reference)

datetime beProfitStart[MAX_SYMS];  // when the current continuous profit streak began (BE15)
bool     beMoved[MAX_SYMS];        // BE15 stop already moved to break even (one-shot)

int  g_cycles[];        // parsed kihon suchi cycle list (9,17,26,...,676 by default)
int  g_cycleCount = 0;  // number of parsed cycles

int MAGIC = 20260812;   // distinct from the other H4-M1 builds so both can run on one account

#define GV_BASE_EQUITY    "EA_EquityAlert_Base_"    + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))
#define GV_LAST_ALERT_DAY "EA_EquityAlert_Day_"     + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))

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
      beProfitStart[s] = 0;
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

      adx[s] = INVALID_HANDLE;
      if(InpTrailMode == TRAIL_CHOPPY)
      {
         adx[s] = iADX(syms[s], PERIOD_M15, InpADXPeriod);
         if(adx[s] == INVALID_HANDLE) return(INIT_FAILED);
      }
   }

   trade.SetDeviationInPoints(Slippage);
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
         IndicatorRelease(ich[s][t]);
      if(atr[s] != INVALID_HANDLE) IndicatorRelease(atr[s]);
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
             // Restart mid-trade: the BE15 profit streak starts fresh from here —
             // how long the trade was already in profit can't be recovered.
             beProfitStart[s] = 0;
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
         beProfitStart[s] = 0;
         beMoved[s]       = false;
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
   int chCloud = chShift + Kijun;// senkou buffer offset for the cloud at chikou's position

   MqlRates rt[];
   if(CopyRates(syms[s], tf, 0, chCloud + 1, rt) <= 0) return 0;
   ArraySetAsSeries(rt, true);

   if(ArraySize(rt) <= chCloud) return 0;

   // price bar sh: tenkan, kijun, cloud
   double tenkan[1], kijun[1], senA[1], senB[1];
   if(CopyBuffer(ich[s][tfIdx], 0, sh,         1, tenkan)    <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 1, sh,         1, kijun)     <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 2, sh + Kijun, 1, senA)      <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 3, sh + Kijun, 1, senB)      <= 0) return 0;

   double closeP = rt[sh].close;
   double cHi    = MathMax(senA[0], senB[0]);
   double cLo    = MathMin(senA[0], senB[0]);

   // Short-circuit: most bars aren't aligned, so skip the chikou-side buffers
   // unless the close is already clearly on one side of tenkan/kijun/cloud.
   bool above = closeP > tenkan[0] && closeP > kijun[0] && closeP > cHi;
   bool below = closeP < tenkan[0] && closeP < kijun[0] && closeP < cLo;
   if(!above && !below) return 0;

   // tenkan, kijun, cloud at chikou's chart position
   double tenkan_ch[1], kijun_ch[1], senA_ch[1], senB_ch[1];
   if(CopyBuffer(ich[s][tfIdx], 0, chShift,    1, tenkan_ch) <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 1, chShift,    1, kijun_ch)  <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 2, chCloud,    1, senA_ch)   <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 3, chCloud,    1, senB_ch)   <= 0) return 0;

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
// suchi number up to 51 the move is mature and the breakout is low
// probability; between cycles there is room for the move to continue
// to the next number — the continuation case. The cascade below
// checks H4 first, then H1, then M30, then M15 — each must be clear
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
// KIHON_MAX_CYCLE (51).
bool InTimeWindow(int count, int maxCycle)
{
   for(int i = 0; i < g_cycleCount; i++)
   {
      if(g_cycles[i] > maxCycle) continue;
      if(count == g_cycles[i]) return true;
   }
   return false;
}

// Consecutive closed bars on timeframe tfIdx whose whole range stayed on
// the move's side of the Kijun (above it for a long, below for a short).
// Stops at the first touch or side violation — the count is the age of
// the current move in bars on that timeframe. Lookback is bounded by
// maxCycle so shallow history suffices (51 bars on any timeframe).
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
   return count;
}

// Nested kihon suchi cascade: H4 -> H1 -> M30 -> M15. Each timeframe
// must be clear (count not exactly on a cycle) before the next is
// checked; a mature count anywhere in the chain blocks the breakout.
// Returns true when the entry was skipped.
bool TimeFilterBlocks(int s, int st)
{
   if(!InpUseTimeFilter) return false;

   if(InpTimeFilterH4)
   {
      int c4 = CountNoTouchTF(s, 0, st, KIHON_MAX_CYCLE);
      if(InTimeWindow(c4, KIHON_MAX_CYCLE))
      {
         Print(PCTime() + " | " + syms[s] + " skip entry: H4 time cycle mature (count " + IntegerToString(c4) + ")");
         return true;
      }
      if(InpTimeFilterH1)
      {
         int c1 = CountNoTouchTF(s, 1, st, KIHON_MAX_CYCLE);
         if(InTimeWindow(c1, KIHON_MAX_CYCLE))
         {
            Print(PCTime() + " | " + syms[s] + " skip entry: H1 time cycle mature (count " + IntegerToString(c1) + ")");
            return true;
         }
         if(InpTimeFilterM30)
         {
            int c30 = CountNoTouchTF(s, 2, st, KIHON_MAX_CYCLE);
            if(InTimeWindow(c30, KIHON_MAX_CYCLE))
            {
               Print(PCTime() + " | " + syms[s] + " skip entry: M30 time cycle mature (count " + IntegerToString(c30) + ")");
               return true;
            }
            if(InpTimeFilterM15)
            {
               int c15 = CountNoTouchTF(s, IDX_M15, st, KIHON_MAX_CYCLE);
               if(InTimeWindow(c15, KIHON_MAX_CYCLE))
               {
                  Print(PCTime() + " | " + syms[s] + " skip entry: M15 time cycle mature (count " + IntegerToString(c15) + ")");
                  return true;
               }
            }
         }
      }
   }
   return false;
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

      // Only ever tighten, and keep out of the broker's minimum stop distance
      if(isLong && slNew > slCur + point && slNew < price - minDist)
         trade.PositionModify(ticket, slNew, 0);
      if(!isLong && slNew < slCur - point && slNew > price + minDist)
         trade.PositionModify(ticket, slNew, 0);
   }
}

//==============================================================
// Break-Even Management (BE15): once the trade has been in profit
// continuously for InpBE15Minutes, the stop loss moves up to
// break even plus a few points to cover the spread. Any dip back
// to break even resets the profit streak. One-shot per trade
// (beMoved); the chandelier trail may tighten further afterwards
// but never lowers the stop back down.
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
   if(state[s] == 0 || !InpBE15Enabled) return;
   if(beMoved[s]) return;

   double avg = AvgOpenPrice(s);
   if(avg <= 0) return;

   double a[1];
   if(CopyBuffer(atr[s], 0, 1, 1, a) <= 0 || a[0] <= 0) return;
   double atrVal = a[0];

   bool   isLong = (state[s] == 1);
   double bid    = SymbolInfoDouble(syms[s], SYMBOL_BID);
   double ask    = SymbolInfoDouble(syms[s], SYMBOL_ASK);

   // Profitable enough to count toward the streak?
   bool inProfit = (isLong && bid >= avg + InpBE15ActivateATR * atrVal) ||
                   (!isLong && ask <= avg - InpBE15ActivateATR * atrVal);

   if(inProfit)
   {
      // Start (or continue) the profit-streak timer; it is reset by any
      // dip back to break even, so only *continuous* profit time counts.
      if(beProfitStart[s] == 0) beProfitStart[s] = TimeCurrent();

      // Streak target reached — move the stop to break even + cover
      if(TimeCurrent() - beProfitStart[s] < InpBE15Minutes * 60) return;
   }
   else
   {
      beProfitStart[s] = 0;   // streak broken — start over if it turns profitable again
      return;
   }

   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);

   // Break even plus a few points to cover the spread
   double slNew = isLong ? avg + InpBE15CoverPoints * point
                         : avg - InpBE15CoverPoints * point;
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
         trade.PositionModify(ticket, slNew, 0);
         beMoved[s] = true;
      }
      if(!isLong && slNew < slCur - point && slNew > price + minDist)
      {
         trade.PositionModify(ticket, slNew, 0);
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

   trade.SetExpertMagicNumber(MAGIC);

   int filled = 0;
   firstFill = 0.0;
   for(int i = 0; i < count; i++)
   {
      double price = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK)
                           : SymbolInfoDouble(sym, SYMBOL_BID);
      double sl = InpUseStopLoss ? BuildStopLoss(s, isBuy, price, dist) : 0.0;

      bool ok = isBuy ? trade.Buy(lots,  sym, price, sl, 0, "Buy H4-M1")
                      : trade.Sell(lots, sym, price, sl, 0, "Sell H4-M1");
      if(!ok) break;   // out of margin or rejected — don't hammer the server
      if(firstFill == 0.0) firstFill = price;
      filled++;
   }
   return filled;
}

void ClosePositions(string sym)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC)
      {
         trade.PositionClose(ticket);
      }
   }
}

//==============================================================
// Main Loop
//==============================================================

void OnTick()
{
   // Equity alert: fire only on a new H4 bar (CheckEquityAlert self-guards on day-of-week)
   MqlRates h4[];
   if(symsCount > 0 && CopyRates(syms[0], PERIOD_H4, 0, 1, h4) > 0 && h4[0].time != lastH4bar)
   {
      lastH4bar = h4[0].time;
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

      // Exit check: close all when M15 closes against direction across M15 kijun
      if(state[s] != 0 && CheckM15Exit(s, state[s]))
      {
         string side = (state[s] == 1) ? "Long" : "Short";
         string msg  = PCTime() + " | Close " + syms[s] + " " + side + " (M15 kijun crossed)";
         Print(msg); Alert(msg); SendNotification(msg);

         ClosePositions(syms[s]);
         state[s] = 0;
         noReentryUntil[s] = TimeCurrent() + InpReentryCooldownSec;
      }

      // Chandelier trail: tighten stops behind the peak on each new M1 bar
      if(state[s] != 0) ManageTrail(s);

      // BE15: move the stop to break even + cover after time in profit
      if(state[s] != 0) ManageBE(s);

      // Entry check: all timeframes H4→M1 must align, spread must be sane
      if(state[s] == 0 && TimeCurrent() >= noReentryUntil[s] && SpreadOK(syms[s]))
      {
         int st = CheckAllAlign(s);
         if(st != 0)
         {
            // Time theory: nested kihon suchi cascade — H4 must be
            // clear (count not exactly on a cycle) before H1 is
            // checked, then M30, then M15. A mature count anywhere in
            // the chain blocks the entry.
            if(TimeFilterBlocks(s, st)) continue;

            bool   isBuy = (st == 1);
            double dist  = 0.0;
            if(InpUseStopLoss && !GetStopDistance(s, dist)) continue;   // ATR unavailable — skip entry

            int count; double lots;
            GetEquityRisk(syms[s], dist, count, lots);

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
               beProfitStart[s] = 0;   // BE15 profit streak starts fresh
               beMoved[s]       = false;
               string action = isBuy ? "Buy" : "Sell";
               string msg = PCTime() + " | " + action + " " + syms[s] +
                            " x" + IntegerToString(filled) +
                            " @ " + DoubleToString(lots, 2) + " (H4-M1)";
               Print(msg); Alert(msg); SendNotification(msg);
            }
            else
               Print(PCTime() + " | " + syms[s] + " entry signal but no order filled");
         }
      }
   }
}
//This work is my worship unto GOD
