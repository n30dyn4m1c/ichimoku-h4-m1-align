//+------------------------------------------------------------------+
//| Ichimoku H1-M1 Alignment EA                                      |
//| Entry: H1→M1 price+chikou all above/below tenkan,kijun,cloud    |
//| Exit:  M5 close crosses M5 kijun against trade direction,        |
//|        or ATR-based protective stop loss                         |
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

//--- Constants and Global Variables ---
#define MAX_SYMS  60
#define TF_COUNT  5
#define IDX_M5    3   // index of M5 in tfs[] — used for exit check

ENUM_TIMEFRAMES tfs[TF_COUNT] = {
   PERIOD_H1, PERIOD_M30, PERIOD_M15, PERIOD_M5, PERIOD_M1
};

int      ich[MAX_SYMS][TF_COUNT];
int      atr[MAX_SYMS];
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar[MAX_SYMS];
datetime noReentryUntil[MAX_SYMS];
int      state[MAX_SYMS];   // 0=no position, 1=long, -1=short
int      lastMinuteKey = -1;

int MAGIC = 20260502;

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

   for(int s = 0; s < symsCount; s++)
   {
      state[s] = 0;
      lastM1bar[s] = 0;
      noReentryUntil[s] = 0;
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
   for(int s = 0; s < symsCount; s++) prevState[s] = state[s];
   for(int s = 0; s < symsCount; s++) state[s] = 0;

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
         if(syms[s] == sym) { state[s] = dir; break; }
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

   double tenkan[1], kijun[1], senA[1], senB[1];

   // price bar sh: tenkan, kijun, cloud
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

int OpenPositions(int s, bool isBuy, double dist, int count, double lots)
{
   string sym = syms[s];

   int filled = 0;
   for(int i = 0; i < count; i++)
   {
      double price = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK)
                           : SymbolInfoDouble(sym, SYMBOL_BID);
      double sl = InpUseStopLoss ? BuildStopLoss(s, isBuy, price, dist) : 0.0;

      bool ok = isBuy ? trade.Buy(lots,  sym, price, sl, 0, "Buy H1-M1")
                      : trade.Sell(lots, sym, price, sl, 0, "Sell H1-M1");
      if(!ok) break;   // out of margin or rejected — don't hammer the server
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

         ClosePositions(syms[s]);
         state[s] = 0;
         noReentryUntil[s] = TimeCurrent() + InpReentryCooldownSec;
      }

      // Entry check: all timeframes H1→M1 must align, spread must be sane
      if(state[s] == 0 && TimeCurrent() >= noReentryUntil[s] && SpreadOK(syms[s]))
      {
         int st = CheckAllAlign(s);
         if(st != 0)
         {
            bool   isBuy = (st == 1);
            double dist  = 0.0;
            if(InpUseStopLoss && !GetStopDistance(s, dist)) continue;   // ATR unavailable — skip entry

            int count; double lots;
            GetEquityRisk(syms[s], dist, count, lots);

            // Track state if any order filled — keeps exit logic and re-entry
            // guard correct even when only some of the orders go through.
            int filled = OpenPositions(s, isBuy, dist, count, lots);
            if(filled > 0)
            {
               state[s] = st;
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
