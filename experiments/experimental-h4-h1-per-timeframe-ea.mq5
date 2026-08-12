//+------------------------------------------------------------------+
//| Ichimoku Per-Timeframe Breakout EA (experimental)                |
//| Entry: price+chikou all above/below tenkan,kijun,cloud on the    |
//|        selected timeframe(s) — H4 and/or H1, each monitored      |
//|        independently (no cross-TF confirmation)                  |
//| Exit:  close crosses back over that timeframe's tenkan           |
//|        (conversion line) against trade direction, or ATR-based   |
//|        protective stop loss                                      |
//| Aggressive profit locking: SL moves to break even once           |
//|        profitable, then an ATR chandelier trail tightens         |
//|        behind the peak (locks in the spike)                      |
//| Choppy filter: entries skipped when ADX of that timeframe is     |
//|        below InpChopADXLevel (no trend -> breakout won't follow) |
//| Options: InpUseH4 / InpUseH1 enable each timeframe; when both    |
//|        are on, each monitors itself and can fire its own trades  |
//|        on the same symbol at the same time                       |
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

input group  "Timeframe Options"
input bool   InpUseH4 = true;   // Trade the H4 breakout (exit at H4 tenkan)
input bool   InpUseH1 = true;   // Trade the H1 breakout (exit at H1 tenkan)

input group  "Risk Protection"
input bool   InpUseStopLoss       = true;   // Attach ATR-based stop loss to every entry
input int    InpATRPeriod         = 14;     // ATR period (read on each timeframe)
input double InpATRMultiplier     = 3.0;    // SL distance = ATR * multiplier
input int    InpMaxSpreadPoints   = 60;     // Max spread in points to allow entry (0 = no limit)
input double InpHighEquityRiskPct = 1.0;    // % of equity risked per trade once equity > $8000

input group  "Choppy Filter"
input bool   InpChopFilterEnabled = true;   // Skip entries when the market is choppy
input int    InpChopADXPeriod     = 14;     // ADX period (same on both timeframes)
input double InpChopADXLevel      = 22.0;   // ADX below this = choppy -> no entry

input group  "Aggressive Profit Locking"
input bool   InpTrailEnabled     = true;   // Chandelier trail behind the peak
input double InpTrailATR         = 1.0;    // Trail distance = ATR * multiplier (1.0 = tight)
input double InpTrailActivateATR = 0.5;    // Arm the trail once profit >= ATR * multiplier
input bool   InpBEEnabled        = true;   // Move SL to break even once profitable
input double InpBEActivateATR    = 0.3;    // Min profit to arm BE (x ATR)
input int    InpBECoverPoints    = 10;     // Points beyond break even (covers spread)

input group             "Equity Alert Settings"
input double            InpMinProfitTrigger  = 5.0;        // Min Profit over Baseline to trigger alert
input double            InpWithdrawProfitPct = 50.0;       // Percentage of the PROFIT to withdraw
input ENUM_DAY_OF_WEEK  InpCheckDay          = FRIDAY;     // Day of the week to check
input bool              InpResetBaseline     = false;      // Set to true to reset baseline to current equity
input bool              InpSendPush          = true;       // Send push notification

//--- Constants and Global Variables ---
#define MAX_SYMS  60
#define TF_COUNT  2

ENUM_TIMEFRAMES tfs[TF_COUNT] = {
   PERIOD_H4, PERIOD_H1
};

int      ich[MAX_SYMS][TF_COUNT];
int      atr[MAX_SYMS][TF_COUNT];
int      adx[MAX_SYMS][TF_COUNT];   // ADX per TF for choppy-market entry gating
string   syms[MAX_SYMS];
int      symsCount = 0;
bool     useTF[TF_COUNT];               // enabled per InpUseH4 / InpUseH1
datetime lastBar[MAX_SYMS][TF_COUNT];   // per-symbol per-TF bar gating
int      state[MAX_SYMS][TF_COUNT];     // 0=no position, 1=long, -1=short

double   entryPrice[MAX_SYMS][TF_COUNT];  // reference entry price per TF (trail/BE arming)
double   trailHigh[MAX_SYMS][TF_COUNT];   // highest high since entry (long chandelier reference)
double   trailLow[MAX_SYMS][TF_COUNT];    // lowest low since entry (short chandelier reference)
bool     beMoved[MAX_SYMS][TF_COUNT];     // BE stop already moved to break even (one-shot)

int MAGIC_H4 = 20260826;
int MAGIC_H1 = 20260827;

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

string TFName(int tfIdx)
{
   return (tfIdx == 0) ? "H4" : "H1";
}

int OnInit()
{
   symsCount = ParseSymbols(Symbols);
   if(symsCount <= 0) return(INIT_FAILED);

   useTF[0] = InpUseH4;
   useTF[1] = InpUseH1;
   if(!useTF[0] && !useTF[1]) return(INIT_FAILED);

   for(int s = 0; s < symsCount; s++)
   {
      for(int t = 0; t < TF_COUNT; t++)
      {
         state[s][t] = 0;
         lastBar[s][t] = 0;
         ich[s][t] = iIchimoku(syms[s], tfs[t], Tenkan, Kijun, SenkouB);
         if(ich[s][t] == INVALID_HANDLE) return(INIT_FAILED);

         atr[s][t] = INVALID_HANDLE;
         if(InpUseStopLoss)
         {
            atr[s][t] = iATR(syms[s], tfs[t], InpATRPeriod);
            if(atr[s][t] == INVALID_HANDLE) return(INIT_FAILED);
         }

         adx[s][t] = INVALID_HANDLE;
         if(InpChopFilterEnabled)
         {
            adx[s][t] = iADX(syms[s], tfs[t], InpChopADXPeriod);
            if(adx[s][t] == INVALID_HANDLE) return(INIT_FAILED);
         }
      }
   }

   trade.SetDeviationInPoints(Slippage);
   SyncStateFromPositions();
   InitEquityAlert();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   for(int s = 0; s < symsCount; s++)
   {
      for(int t = 0; t < TF_COUNT; t++)
      {
         if(ich[s][t] != INVALID_HANDLE) IndicatorRelease(ich[s][t]);
         if(atr[s][t] != INVALID_HANDLE) IndicatorRelease(atr[s][t]);
         if(adx[s][t] != INVALID_HANDLE) IndicatorRelease(adx[s][t]);
      }
   }
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

//==============================================================
// Position State Sync (recover after restart)
//==============================================================

int TFIdxFromMagic(int magic)
{
   if(magic == MAGIC_H4) return 0;
   if(magic == MAGIC_H1) return 1;
   return -1;
}

void SyncStateFromPositions()
{
   // Rebuild from scratch so positions closed by SL or manually free the
   // symbol for re-entry instead of leaving stale state behind.
   for(int s = 0; s < symsCount; s++)
   {
      for(int t = 0; t < TF_COUNT; t++)
         state[s][t] = 0;
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      string sym   = PositionGetString(POSITION_SYMBOL);
      int    magic = (int)PositionGetInteger(POSITION_MAGIC);
      int    type  = (int)PositionGetInteger(POSITION_TYPE);
      int    dir   = (type == POSITION_TYPE_BUY) ? 1 : -1;

      int t = TFIdxFromMagic(magic);
      if(t < 0) continue;

      for(int s = 0; s < symsCount; s++)
      {
         if(syms[s] == sym)
         {
            state[s][t] = dir;
            // EA (re)started mid-trade — rebuild the trail from the open
            // price and let it accumulate fresh extremes from here.
            if(entryPrice[s][t] == 0.0)
            {
               entryPrice[s][t] = PositionGetDouble(POSITION_PRICE_OPEN);
               trailHigh[s][t]  = entryPrice[s][t];
               trailLow[s][t]   = entryPrice[s][t];
            }
            break;
         }
      }
   }

   // Symbols/TFs with no open position get their trail memory cleared
   for(int s = 0; s < symsCount; s++)
   {
      for(int t = 0; t < TF_COUNT; t++)
      {
         if(state[s][t] == 0)
         {
            entryPrice[s][t] = 0.0;
            trailHigh[s][t]  = 0.0;
            trailLow[s][t]   = 0.0;
            beMoved[s][t]    = false;
         }
      }
   }
}

//==============================================================
// Alignment Check: price and chikou both above/below tenkan,
// kijun, and cloud. Returns 1 (bullish), -1 (bearish), 0 (none)
//==============================================================

int CheckAlign(int s, int tfIdx)
{
   ENUM_TIMEFRAMES tf = tfs[tfIdx];

   MqlRates rt[];
   if(CopyRates(syms[s], tf, 0, 120, rt) <= 0) return 0;
   ArraySetAsSeries(rt, true);

   int sh      = 1;              // last closed bar
   int chShift = sh + Kijun;     // chikou's chart position for bar sh (Kijun bars back)
   int chCloud = chShift + Kijun;// senkou buffer offset for the cloud at chikou's position

   if(ArraySize(rt) <= chCloud) return 0;

   double tenkan[1], kijun[1], senA[1], senB[1];
   double tenkan_ch[1], kijun_ch[1], senA_ch[1], senB_ch[1];

   // price bar sh: tenkan, kijun, cloud
   if(CopyBuffer(ich[s][tfIdx], 0, sh,         1, tenkan)    <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 1, sh,         1, kijun)     <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 2, sh + Kijun, 1, senA)      <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 3, sh + Kijun, 1, senB)      <= 0) return 0;
   // tenkan, kijun, cloud at chikou's chart position
   if(CopyBuffer(ich[s][tfIdx], 0, chShift,    1, tenkan_ch) <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 1, chShift,    1, kijun_ch)  <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 2, chCloud,    1, senA_ch)   <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 3, chCloud,    1, senB_ch)   <= 0) return 0;

   double closeP = rt[sh].close;
   // The chikou span for bar sh IS its close, plotted Kijun bars back.
   // Compare it against the candle and Ichimoku levels at that chart position.
   double chik   = closeP;
   double cHi    = MathMax(senA[0], senB[0]);
   double cLo    = MathMin(senA[0], senB[0]);
   double cHiC   = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC   = MathMin(senA_ch[0], senB_ch[0]);

   // bullish: price above tenkan, kijun, and cloud; chikou clear above price,
   // tenkan, kijun, and cloud at its plotted position
   if(closeP > tenkan[0] && closeP > kijun[0] && closeP > cHi &&
      chik > rt[chShift].high &&
      chik > tenkan_ch[0] && chik > kijun_ch[0] && chik > cHiC) return  1;

   // bearish: price below tenkan, kijun, and cloud; chikou clear below price,
   // tenkan, kijun, and cloud at its plotted position
   if(closeP < tenkan[0] && closeP < kijun[0] && closeP < cLo &&
      chik < rt[chShift].low &&
      chik < tenkan_ch[0] && chik < kijun_ch[0] && chik < cLoC) return -1;

   return 0;
}

//==============================================================
// Entry Check: this timeframe's price+chikou breakout
//==============================================================

int CheckAllAlign(int s, int tfIdx)
{
   return CheckAlign(s, tfIdx);
}

//==============================================================
// Exit Check: close on the wrong side of that timeframe's tenkan
// (conversion line) closes the trade
//==============================================================

bool CheckTenkanExit(int s, int tfIdx, int dir)
{
   double ten[1];
   if(CopyBuffer(ich[s][tfIdx], 0, 1, 1, ten) <= 0) return false;

   MqlRates rt[];
   if(CopyRates(syms[s], tfs[tfIdx], 1, 1, rt) <= 0) return false;
   double closeP = rt[0].close;

   if(dir ==  1 && closeP < ten[0]) return true;
   if(dir == -1 && closeP > ten[0]) return true;
   return false;
}

//==============================================================
// Aggressive Profit Locking
//==============================================================

// Volume-weighted average open price of all this TF's positions on the
// symbol (the ladder opens several orders at slightly different prices).
double AvgOpenPrice(int s, int tfIdx)
{
   double sum = 0.0, vol = 0.0;
   int magic = MagicForTF(tfIdx);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != syms[s]) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != magic) continue;
      sum += PositionGetDouble(POSITION_PRICE_OPEN) * PositionGetDouble(POSITION_VOLUME);
      vol += PositionGetDouble(POSITION_VOLUME);
   }
   return (vol > 0) ? sum / vol : 0.0;
}

// Break-even lock: as soon as the trade is profitable by InpBEActivateATR
// x ATR, the stop moves up to break even + a few points to cover the
// spread. One-shot per trade (beMoved); the chandelier trail may tighten
// further afterwards but never lowers the stop back down.
void ManageBE(int s, int tfIdx)
{
   if(state[s][tfIdx] == 0 || !InpBEEnabled) return;
   if(entryPrice[s][tfIdx] <= 0 || beMoved[s][tfIdx]) return;

   double avg = AvgOpenPrice(s, tfIdx);
   if(avg <= 0) return;

   if(atr[s][tfIdx] == INVALID_HANDLE) return;
   double a[1];
   if(CopyBuffer(atr[s][tfIdx], 0, 1, 1, a) <= 0 || a[0] <= 0) return;
   double atrVal = a[0];

   bool   isLong = (state[s][tfIdx] == 1);
   double bid    = SymbolInfoDouble(syms[s], SYMBOL_BID);
   double ask    = SymbolInfoDouble(syms[s], SYMBOL_ASK);

   // Not yet profitable enough to arm the break-even move
   if(isLong && bid < avg + InpBEActivateATR * atrVal) return;
   if(!isLong && ask > avg - InpBEActivateATR * atrVal) return;

   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);

   // Break even plus a few points to cover the spread
   double slNew = isLong ? avg + InpBECoverPoints * point
                         : avg - InpBECoverPoints * point;
   slNew = NormalizeDouble(slNew, digits);

   double price = isLong ? bid : ask;
   int magic = MagicForTF(tfIdx);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != syms[s]) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != magic) continue;

      double slCur = PositionGetDouble(POSITION_SL);

      // Only ever tighten, and keep out of the broker's minimum stop distance
      if(isLong && slNew > slCur + point && slNew < price - minDist)
      {
         if(!trade.PositionModify(ticket, slNew, 0))
            Print(PCTime() + " | " + syms[s] + " BE SL modify failed, retcode " + IntegerToString(trade.ResultRetcode()));
         else
            beMoved[s][tfIdx] = true;
      }
      if(!isLong && slNew < slCur - point && slNew > price + minDist)
      {
         if(!trade.PositionModify(ticket, slNew, 0))
            Print(PCTime() + " | " + syms[s] + " BE SL modify failed, retcode " + IntegerToString(trade.ResultRetcode()));
         else
            beMoved[s][tfIdx] = true;
      }
   }
}

// ATR chandelier trail: once the trade is in profit by InpTrailActivateATR
// x ATR, the stop follows the peak of the forming bar of this timeframe at
// InpTrailATR x ATR distance — a breakout spike is locked in before it
// retraces. Re-evaluated on every new bar of this timeframe; only ever
// tightens and never sits inside the broker minimum stop.
void ManageTrail(int s, int tfIdx)
{
   if(state[s][tfIdx] == 0 || !InpTrailEnabled || !InpUseStopLoss) return;

   if(atr[s][tfIdx] == INVALID_HANDLE) return;
   double a[1];
   if(CopyBuffer(atr[s][tfIdx], 0, 1, 1, a) <= 0 || a[0] <= 0) return;
   double atrVal = a[0];

   MqlRates rt[];
   if(CopyRates(syms[s], tfs[tfIdx], 0, 1, rt) <= 0) return;
   ArraySetAsSeries(rt, true);

   bool isLong = (state[s][tfIdx] == 1);
   if(isLong)
   {
      if(rt[0].high > trailHigh[s][tfIdx]) trailHigh[s][tfIdx] = rt[0].high;
   }
   else
   {
      if(rt[0].low < trailLow[s][tfIdx]) trailLow[s][tfIdx] = rt[0].low;
   }

   double point   = SymbolInfoDouble(syms[s], SYMBOL_POINT);
   double minDist = SymbolInfoInteger(syms[s], SYMBOL_TRADE_STOPS_LEVEL) * point;
   int    digits  = (int)SymbolInfoInteger(syms[s], SYMBOL_DIGITS);

   // Not profitable enough yet to arm the trail
   if(isLong && SymbolInfoDouble(syms[s], SYMBOL_BID) < entryPrice[s][tfIdx] + InpTrailActivateATR * atrVal) return;
   if(!isLong && SymbolInfoDouble(syms[s], SYMBOL_ASK) > entryPrice[s][tfIdx] - InpTrailActivateATR * atrVal) return;

   double price = isLong ? SymbolInfoDouble(syms[s], SYMBOL_BID)
                         : SymbolInfoDouble(syms[s], SYMBOL_ASK);
   double slNew = isLong ? trailHigh[s][tfIdx] - InpTrailATR * atrVal
                         : trailLow[s][tfIdx] + InpTrailATR * atrVal;
   slNew = NormalizeDouble(slNew, digits);

   int magic = MagicForTF(tfIdx);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != syms[s]) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != magic) continue;

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

// Choppy-market detection: ADX of this timeframe below InpChopADXLevel
// means no trend, so entries are skipped (breakouts don't follow through).
// An unready/unknown ADX value is treated as choppy to stay conservative.
bool IsChoppy(int s, int tfIdx)
{
   double d[1];
   if(CopyBuffer(adx[s][tfIdx], 0, 1, 1, d) <= 0 || d[0] <= 0) return true;
   return d[0] < InpChopADXLevel;
}

// ATR(tf) * multiplier, widened to the broker's minimum stop distance if
// needed. Returns false when the ATR value is unavailable so the caller
// skips the entry instead of trading unprotected.
bool GetStopDistance(int s, int tfIdx, double &dist)
{
   dist = 0.0;
   double a[1];
   if(CopyBuffer(atr[s][tfIdx], 0, 1, 1, a) <= 0 || a[0] <= 0) return false;

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

int MagicForTF(int tfIdx)
{
   return (tfIdx == 0) ? MAGIC_H4 : MAGIC_H1;
}

int OpenPositions(int s, int tfIdx, bool isBuy, double &firstFill)
{
   string sym = syms[s];

   double dist = 0.0;
   if(InpUseStopLoss && !GetStopDistance(s, tfIdx, dist)) return 0;   // ATR unavailable — skip entry

   int count; double lots;
   GetEquityRisk(sym, dist, count, lots);

   trade.SetExpertMagicNumber(MagicForTF(tfIdx));

   int filled = 0;
   firstFill = 0.0;
   for(int i = 0; i < count; i++)
   {
      double price = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK)
                           : SymbolInfoDouble(sym, SYMBOL_BID);
      double sl = InpUseStopLoss ? BuildStopLoss(s, isBuy, price, dist) : 0.0;

      string tag = isBuy ? "Buy " + TFName(tfIdx) : "Sell " + TFName(tfIdx);
      bool ok = isBuy ? trade.Buy(lots,  sym, price, sl, 0, tag)
                      : trade.Sell(lots, sym, price, sl, 0, tag);
      if(!ok) break;   // out of margin or rejected — don't hammer the server
      if(firstFill == 0.0) firstFill = price;
      filled++;
   }
   return filled;
}

void ClosePositions(string sym, int tfIdx)
{
   int magic = MagicForTF(tfIdx);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == magic)
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
      for(int t = 0; t < TF_COUNT; t++)
      {
         if(!useTF[t]) continue;
         ENUM_TIMEFRAMES tf = tfs[t];

         // Per-symbol per-TF bar gating — only act on a new closed bar of
         // this timeframe (entry and exit both read the closed bar)
         MqlRates rt[];
         if(CopyRates(syms[s], tf, 0, 2, rt) < 2) continue;
         ArraySetAsSeries(rt, true);
         if(rt[1].time == lastBar[s][t]) continue;
         lastBar[s][t] = rt[1].time;

         // Equity alert: check on the first symbol's new bar
         // (CheckEquityAlert self-guards on day-of-week)
         if(s == 0) CheckEquityAlert();

         // Exit check: close all when the close crosses back under the
         // tenkan (long) / back over it (short)
         if(state[s][t] != 0 && CheckTenkanExit(s, t, state[s][t]))
         {
            string side = (state[s][t] == 1) ? "Long" : "Short";
            string msg  = PCTime() + " | Close " + syms[s] + " " + side +
                          " (" + TFName(t) + " tenkan crossed)";
            Print(msg); Alert(msg); SendNotification(msg);

            ClosePositions(syms[s], t);
            state[s][t] = 0;
         }

         // Aggressive profit locking: lock break-even, then trail the peak
         if(state[s][t] != 0)
         {
            ManageBE(s, t);
            ManageTrail(s, t);
         }

         // Entry check: this timeframe's price+chikou breakout, trending
         // market, spread must be sane
         if(state[s][t] == 0 &&
            (!InpChopFilterEnabled || !IsChoppy(s, t)) &&
            SpreadOK(syms[s]))
         {
            int st = CheckAllAlign(s, t);
            if(st != 0)
            {
               bool   isBuy  = (st == 1);
               string action = isBuy ? "Buy" : "Sell";
               double msgDist = 0.0;
               if(InpUseStopLoss) GetStopDistance(s, t, msgDist);
               int msgCount; double msgLots;
               GetEquityRisk(syms[s], msgDist, msgCount, msgLots);
               string msg = PCTime() + " | " + action + " " + syms[s] +
                            " x" + IntegerToString(msgCount) +
                            " @ " + DoubleToString(msgLots, 2) + " (" + TFName(t) + ")";
               Print(msg); Alert(msg); SendNotification(msg);

               // Track state if any order filled — keeps exit logic and re-entry
               // guard correct even when only some of the orders go through.
               double firstFill = 0.0;
               if(OpenPositions(s, t, isBuy, firstFill) > 0)
               {
                  state[s][t] = st;
                  entryPrice[s][t] = firstFill;   // trail/BE reference
                  trailHigh[s][t]  = firstFill;
                  trailLow[s][t]   = firstFill;
                  beMoved[s][t]    = false;
               }
            }
         }
      }
   }
}
//This work is my worship unto GOD
