//+------------------------------------------------------------------+
//| Ichimoku H4-M1 Alignment EA — VPS build                          |
//| Entry: H4→M1 price+chikou all above/below tenkan,kijun,cloud    |
//| Exit:  M15 close crosses M15 kijun against trade direction,      |
//|        or ATR-based protective stop loss                         |
//| VPS:   no popup alerts, no weekly equity check, per-bar cached   |
//|        alignment and tick-gated work — trimmed for low CPU/RAM   |
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

input group  "VPS Build"
input int    InpMagic     = 20260801;  // Magic number (use 20260501 to adopt the non-VPS EA's positions)
input bool   InpSendPush  = true;      // Push notification on entry/exit (no popup alerts in this build)
input bool   InpLogTrades = true;      // Print entry/exit lines to the Experts log

//--- Constants and Global Variables ---
#define MAX_SYMS  60
#define TF_COUNT  6
#define IDX_EXIT  3            // index of M15 in tfs[] — used for exit check
#define TF_EXIT   PERIOD_M15   // exit timeframe (must match tfs[IDX_EXIT])

ENUM_TIMEFRAMES tfs[TF_COUNT] = {
   PERIOD_H4, PERIOD_H1, PERIOD_M30, PERIOD_M15, PERIOD_M5, PERIOD_M1
};

int      ich[MAX_SYMS][TF_COUNT];
int      atr[MAX_SYMS];
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar[MAX_SYMS];
int      state[MAX_SYMS];   // 0=no position, 1=long, -1=short

// Per-timeframe alignment cache: an Ichimoku reading taken on closed bars only
// changes when that timeframe prints a new bar, so the result is stored against
// the bar it was computed from and reused until that bar changes.
datetime alignBar[MAX_SYMS][TF_COUNT];
int      alignDir[MAX_SYMS][TF_COUNT];

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
      for(int t = 0; t < TF_COUNT; t++)
      {
         ich[s][t] = iIchimoku(syms[s], tfs[t], Tenkan, Kijun, SenkouB);
         if(ich[s][t] == INVALID_HANDLE) return(INIT_FAILED);
         alignBar[s][t] = 0;
         alignDir[s][t] = 0;
      }

      atr[s] = INVALID_HANDLE;
      if(InpUseStopLoss)
      {
         atr[s] = iATR(syms[s], PERIOD_M15, InpATRPeriod);
         if(atr[s] == INVALID_HANDLE) return(INIT_FAILED);
      }
   }

   trade.SetDeviationInPoints(Slippage);
   trade.SetExpertMagicNumber((ulong)InpMagic);
   SyncStateFromPositions();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   for(int s = 0; s < symsCount; s++)
   {
      for(int t = 0; t < TF_COUNT; t++)
         IndicatorRelease(ich[s][t]);
      if(atr[s] != INVALID_HANDLE) IndicatorRelease(atr[s]);
   }
}

//==============================================================
// Notification (log + optional push, never a blocking popup)
//==============================================================

void Notify(string msg)
{
   if(InpLogTrades) Print(msg);
   if(InpSendPush)  SendNotification(msg);
}

//==============================================================
// Position State Sync (recover after restart)
//==============================================================

void SyncStateFromPositions()
{
   // Rebuild from scratch so positions closed by SL or manually free the
   // symbol for re-entry instead of leaving stale state behind.
   for(int s = 0; s < symsCount; s++) state[s] = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      string sym  = PositionGetString(POSITION_SYMBOL);
      int    type = (int)PositionGetInteger(POSITION_TYPE);
      int    dir  = (type == POSITION_TYPE_BUY) ? 1 : -1;

      for(int s = 0; s < symsCount; s++)
      {
         if(syms[s] == sym) { state[s] = dir; break; }
      }
   }
}

//==============================================================
// Alignment Check: price and chikou both above/below tenkan,
// kijun, and cloud. Returns 1 (bullish), -1 (bearish), 0 (none)
//==============================================================

// Reads the alignment for one timeframe. Returns false when the indicator or
// price data isn't ready yet, so the caller skips caching and retries later.
bool ComputeAlign(int s, int tfIdx, int &dir)
{
   dir = 0;

   ENUM_TIMEFRAMES tf = tfs[tfIdx];
   int sh      = 1;              // last closed bar
   int chShift = sh + Kijun;     // chikou's chart position for bar sh (Kijun bars back)
   int chCloud = chShift + Kijun;// senkou buffer offset for the cloud at chikou's position

   if(Bars(syms[s], tf) <= chCloud) return false;

   double tenkan[1], kijun[1], senA[1], senB[1];
   double tenkan_ch[1], kijun_ch[1], senA_ch[1], senB_ch[1];

   // price bar sh: tenkan, kijun, cloud
   if(CopyBuffer(ich[s][tfIdx], 0, sh,         1, tenkan)    <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 1, sh,         1, kijun)     <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 2, sh + Kijun, 1, senA)      <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, sh + Kijun, 1, senB)      <= 0) return false;
   // tenkan, kijun, cloud at chikou's chart position
   if(CopyBuffer(ich[s][tfIdx], 0, chShift,    1, tenkan_ch) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 1, chShift,    1, kijun_ch)  <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 2, chCloud,    1, senA_ch)   <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, chCloud,    1, senB_ch)   <= 0) return false;

   // Single-value price reads instead of copying a full MqlRates window —
   // only three price points are ever used here.
   double closeP = iClose(syms[s], tf, sh);
   double chHigh = iHigh(syms[s], tf, chShift);
   double chLow  = iLow(syms[s], tf, chShift);
   if(closeP <= 0 || chHigh <= 0 || chLow <= 0) return false;

   // The chikou span for bar sh IS its close, plotted Kijun bars back.
   // Compare it against the candle and Ichimoku levels at that chart position.
   double chik = closeP;
   double cHi  = MathMax(senA[0], senB[0]);
   double cLo  = MathMin(senA[0], senB[0]);
   double cHiC = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC = MathMin(senA_ch[0], senB_ch[0]);

   // bullish: price above tenkan, kijun, and cloud; chikou clear above price,
   // tenkan, kijun, and cloud at its plotted position
   if(closeP > tenkan[0] && closeP > kijun[0] && closeP > cHi &&
      chik > chHigh &&
      chik > tenkan_ch[0] && chik > kijun_ch[0] && chik > cHiC) dir = 1;

   // bearish: price below tenkan, kijun, and cloud; chikou clear below price,
   // tenkan, kijun, and cloud at its plotted position
   else if(closeP < tenkan[0] && closeP < kijun[0] && closeP < cLo &&
           chik < chLow &&
           chik < tenkan_ch[0] && chik < kijun_ch[0] && chik < cLoC) dir = -1;

   return true;
}

int CheckAlign(int s, int tfIdx)
{
   datetime bt = iTime(syms[s], tfs[tfIdx], 1);
   if(bt == 0) return 0;

   // Cache hit: this timeframe hasn't closed a new bar since the last read.
   // Without this, every M1 bar re-derives an H4 reading that only changes
   // once every 240 M1 bars.
   if(bt == alignBar[s][tfIdx]) return alignDir[s][tfIdx];

   int dir;
   if(!ComputeAlign(s, tfIdx, dir)) return 0;   // data not ready — don't cache

   alignBar[s][tfIdx] = bt;
   alignDir[s][tfIdx] = dir;
   return dir;
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
// Exit Check: M15 price closed on wrong side of M15 kijun
//==============================================================

bool CheckExit(int s, int dir)
{
   double kij[1];
   if(CopyBuffer(ich[s][IDX_EXIT], 1, 1, 1, kij) <= 0) return false;

   double closeP = iClose(syms[s], TF_EXIT, 1);
   if(closeP <= 0) return false;

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

      bool ok = isBuy ? trade.Buy(lots,  sym, price, sl, 0, "Buy H4-M1")
                      : trade.Sell(lots, sym, price, sl, 0, "Sell H4-M1");
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
         (int)PositionGetInteger(POSITION_MAGIC) == InpMagic)
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
   // Cheap gate first: on ticks with no newly closed M1 bar anywhere the EA
   // does nothing beyond one iTime() per symbol — no position scan, no
   // indicator reads. Everything below runs at most once per M1 bar.
   bool synced = false;

   for(int s = 0; s < symsCount; s++)
   {
      datetime bt = iTime(syms[s], PERIOD_M1, 1);
      if(bt == 0 || bt == lastM1bar[s]) continue;
      lastM1bar[s] = bt;

      // Rebuild state from live positions once per acting pass, not per tick,
      // so a stop-loss or manual close is still picked up before we act.
      if(!synced) { SyncStateFromPositions(); synced = true; }

      // Exit check: close all when M15 closes against direction across M15 kijun
      if(state[s] != 0 && CheckExit(s, state[s]))
      {
         string side = (state[s] == 1) ? "Long" : "Short";
         Notify(PCTime() + " | Close " + syms[s] + " " + side + " (M15 kijun crossed)");

         ClosePositions(syms[s]);
         state[s] = 0;
      }

      // Entry check: all timeframes H4→M1 must align, spread must be sane
      if(state[s] == 0 && SpreadOK(syms[s]))
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
            // The message reports the actual fill count, not the requested count.
            int filled = OpenPositions(s, isBuy, dist, count, lots);
            if(filled > 0)
            {
               state[s] = st;
               string action = isBuy ? "Buy" : "Sell";
               Notify(PCTime() + " | " + action + " " + syms[s] +
                      " x" + IntegerToString(filled) +
                      " @ " + DoubleToString(lots, 2) + " (H4-M1)");
            }
            else if(InpLogTrades)
               Print(PCTime() + " | " + syms[s] + " entry signal but no order filled");
         }
      }
   }
}
//This work is my worship unto GOD
