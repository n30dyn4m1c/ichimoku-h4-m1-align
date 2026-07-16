//+------------------------------------------------------------------+
//| Ichimoku M1 Breakout EA                                          |
//| Entry: M1 price+chikou all above/below tenkan,kijun,cloud,       |
//|        close clear of the cloud by a minimum ATR distance        |
//| Exit:  M1 close crosses M1 kijun against trade direction,        |
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

input group  "Entry Quality"
input double InpMinBreakoutATR = 0.5;       // Min close distance beyond cloud, in ATR multiples (0 = off)

input group  "Risk Protection"
input bool   InpUseStopLoss       = true;   // Attach ATR-based stop loss to every entry
input int    InpATRPeriod         = 14;     // ATR period (M1)
input double InpATRMultiplier     = 2.0;    // SL distance = ATR * multiplier
input int    InpMaxSpreadPoints   = 60;     // Max spread in points to allow entry (0 = no limit)
input double InpHighEquityRiskPct = 1.0;    // % of equity risked per trade once equity > $8000

input group             "Equity Alert Settings"
input double            InpMinProfitTrigger  = 5.0;        // Min Profit over Baseline to trigger alert
input double            InpWithdrawProfitPct = 50.0;       // Percentage of the PROFIT to withdraw
input ENUM_DAY_OF_WEEK  InpCheckDay          = FRIDAY;     // Day of the week to check
input bool              InpResetBaseline     = false;      // Set to true to reset baseline to current equity
input bool              InpSendPush          = true;       // Send push notification

//--- Constants and Global Variables ---
#define MAX_SYMS  60

int      ich[MAX_SYMS];
int      atr[MAX_SYMS];
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar[MAX_SYMS];
datetime lastAlertBar = 0;
int      state[MAX_SYMS];   // 0=no position, 1=long, -1=short

int MAGIC = 20260716;

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

   for(int s = 0; s < symsCount; s++)
   {
      state[s] = 0;
      lastM1bar[s] = 0;
      ich[s] = iIchimoku(syms[s], PERIOD_M1, Tenkan, Kijun, SenkouB);
      if(ich[s] == INVALID_HANDLE) return(INIT_FAILED);

      atr[s] = INVALID_HANDLE;
      if(InpUseStopLoss || InpMinBreakoutATR > 0)
      {
         atr[s] = iATR(syms[s], PERIOD_M1, InpATRPeriod);
         if(atr[s] == INVALID_HANDLE) return(INIT_FAILED);
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
      IndicatorRelease(ich[s]);
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
}

//==============================================================
// ATR value of the last closed M1 bar. Returns false when the
// buffer isn't ready yet.
//==============================================================

bool GetATRValue(int s, double &val)
{
   val = 0.0;
   double a[1];
   if(CopyBuffer(atr[s], 0, 1, 1, a) <= 0 || a[0] <= 0) return false;
   val = a[0];
   return true;
}

//==============================================================
// Alignment Check: M1 price and chikou both above/below tenkan,
// kijun, and cloud, with the close clear of the cloud by at
// least InpMinBreakoutATR * ATR so marginal breakouts that just
// graze the cloud edge are skipped.
// Returns 1 (bullish), -1 (bearish), 0 (none)
//==============================================================

int CheckAlign(int s)
{
   int sh      = 1;              // last closed bar
   int chShift = sh + Kijun;     // chikou's chart position for bar sh (Kijun bars back)
   int chCloud = chShift + Kijun;// senkou buffer offset for the cloud at chikou's position

   MqlRates rt[];
   if(CopyRates(syms[s], PERIOD_M1, 0, chCloud + 1, rt) <= 0) return 0;
   ArraySetAsSeries(rt, true);

   if(ArraySize(rt) <= chCloud) return 0;

   double tenkan[1], kijun[1], senA[1], senB[1];
   double tenkan_ch[1], kijun_ch[1], senA_ch[1], senB_ch[1];

   // price bar sh: tenkan, kijun, cloud
   if(CopyBuffer(ich[s], 0, sh,         1, tenkan)    <= 0) return 0;
   if(CopyBuffer(ich[s], 1, sh,         1, kijun)     <= 0) return 0;
   if(CopyBuffer(ich[s], 2, sh + Kijun, 1, senA)      <= 0) return 0;
   if(CopyBuffer(ich[s], 3, sh + Kijun, 1, senB)      <= 0) return 0;
   // tenkan, kijun, cloud at chikou's chart position
   if(CopyBuffer(ich[s], 0, chShift,    1, tenkan_ch) <= 0) return 0;
   if(CopyBuffer(ich[s], 1, chShift,    1, kijun_ch)  <= 0) return 0;
   if(CopyBuffer(ich[s], 2, chCloud,    1, senA_ch)   <= 0) return 0;
   if(CopyBuffer(ich[s], 3, chCloud,    1, senB_ch)   <= 0) return 0;

   double closeP = rt[sh].close;
   // The chikou span for bar sh IS its close, plotted Kijun bars back.
   // Compare it against the candle and Ichimoku levels at that chart position.
   double chik   = closeP;
   double cHi    = MathMax(senA[0], senB[0]);
   double cLo    = MathMin(senA[0], senB[0]);
   double cHiC   = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC   = MathMin(senA_ch[0], senB_ch[0]);

   // Breakout-strength buffer: the close must clear the cloud by this much,
   // not merely sit on the other side of it. Skip the signal entirely when
   // the filter is on but ATR isn't available, rather than trade unfiltered.
   double buf = 0.0;
   if(InpMinBreakoutATR > 0)
   {
      double atrVal;
      if(!GetATRValue(s, atrVal)) return 0;
      buf = atrVal * InpMinBreakoutATR;
   }

   // bullish: price above tenkan, kijun, and decisively above the cloud;
   // chikou clear above price, tenkan, kijun, and cloud at its plotted position
   if(closeP > tenkan[0] && closeP > kijun[0] && closeP > cHi + buf &&
      chik > rt[chShift].high &&
      chik > tenkan_ch[0] && chik > kijun_ch[0] && chik > cHiC) return  1;

   // bearish: price below tenkan, kijun, and decisively below the cloud;
   // chikou clear below price, tenkan, kijun, and cloud at its plotted position
   if(closeP < tenkan[0] && closeP < kijun[0] && closeP < cLo - buf &&
      chik < rt[chShift].low &&
      chik < tenkan_ch[0] && chik < kijun_ch[0] && chik < cLoC) return -1;

   return 0;
}

//==============================================================
// Exit Check: M1 price closed on wrong side of M1 kijun
//==============================================================

bool CheckM1Exit(int s, int dir)
{
   double kij[1];
   if(CopyBuffer(ich[s], 1, 1, 1, kij) <= 0) return false;

   MqlRates rt[];
   if(CopyRates(syms[s], PERIOD_M1, 1, 1, rt) <= 0) return false;
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

// ATR(M1) * multiplier, widened to the broker's minimum stop distance if
// needed. Returns false when the ATR value is unavailable so the caller
// skips the entry instead of trading unprotected.
bool GetStopDistance(int s, double &dist)
{
   dist = 0.0;
   double atrVal;
   if(!GetATRValue(s, atrVal)) return false;

   dist = atrVal * InpATRMultiplier;
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

   trade.SetExpertMagicNumber(MAGIC);

   int filled = 0;
   for(int i = 0; i < count; i++)
   {
      double price = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK)
                           : SymbolInfoDouble(sym, SYMBOL_BID);
      double sl = InpUseStopLoss ? BuildStopLoss(s, isBuy, price, dist) : 0.0;

      bool ok = isBuy ? trade.Buy(lots,  sym, price, sl, 0, "Buy M1")
                      : trade.Sell(lots, sym, price, sl, 0, "Sell M1");
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
   SyncStateFromPositions();

   for(int s = 0; s < symsCount; s++)
   {
      // Per-symbol M1 bar gating — only act on a new closed M1 bar for this symbol
      MqlRates m1[];
      if(CopyRates(syms[s], PERIOD_M1, 0, 2, m1) < 2) continue;
      ArraySetAsSeries(m1, true);
      if(m1[1].time == lastM1bar[s]) continue;
      lastM1bar[s] = m1[1].time;

      // Equity alert: throttle to one check per new M1 bar
      // (CheckEquityAlert self-guards on day-of-week and last alert day)
      if(m1[1].time != lastAlertBar)
      {
         lastAlertBar = m1[1].time;
         CheckEquityAlert();
      }

      // Exit check: close all when M1 closes against direction across M1 kijun
      if(state[s] != 0 && CheckM1Exit(s, state[s]))
      {
         string side = (state[s] == 1) ? "Long" : "Short";
         string msg  = PCTime() + " | Close " + syms[s] + " " + side + " (M1 kijun crossed)";
         Print(msg); Alert(msg); SendNotification(msg);

         ClosePositions(syms[s]);
         state[s] = 0;
      }

      // Entry check: M1 must align, spread must be sane
      if(state[s] == 0 && SpreadOK(syms[s]))
      {
         int st = CheckAlign(s);
         if(st != 0)
         {
            bool   isBuy = (st == 1);
            double dist  = 0.0;
            if(InpUseStopLoss && !GetStopDistance(s, dist)) continue;   // ATR unavailable — skip entry

            int count; double lots;
            GetEquityRisk(syms[s], dist, count, lots);

            // Track state if any order filled — keeps exit logic and re-entry
            // guard correct even when only some of the orders go through.
            // Alert reports the actual fill count, not the requested count.
            int filled = OpenPositions(s, isBuy, dist, count, lots);
            if(filled > 0)
            {
               state[s] = st;
               string action = isBuy ? "Buy" : "Sell";
               string msg = PCTime() + " | " + action + " " + syms[s] +
                            " x" + IntegerToString(filled) +
                            " @ " + DoubleToString(lots, 2) + " (M1)";
               Print(msg); Alert(msg); SendNotification(msg);
            }
            else
               Print(PCTime() + " | " + syms[s] + " entry signal but no order filled");
         }
      }
   }
}
//This work is my worship unto GOD
