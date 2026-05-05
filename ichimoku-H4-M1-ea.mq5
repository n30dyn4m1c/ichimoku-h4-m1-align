//+------------------------------------------------------------------+
//| Ichimoku H4-M1 Alignment EA                                      |
//| Entry: H4→M1 price+chikou all above/below tenkan,kijun,cloud    |
//| Exit:  Half on M5 kijun cross, half on M15 kijun cross           |
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

//--- Constants and Global Variables ---
#define MAX_SYMS  60
#define TF_COUNT  6
#define IDX_M15   3   // index of M15 in tfs[] — used for exit check
#define IDX_M5    4   // index of M5 in tfs[] — used for exit check

#define TAG_M5    "H4-M1 Cloud M5"
#define TAG_M15   "H4-M1 Cloud M15"

ENUM_TIMEFRAMES tfs[TF_COUNT] = {
   PERIOD_H4, PERIOD_H1, PERIOD_M30, PERIOD_M15, PERIOD_M5, PERIOD_M1
};

int      ich[MAX_SYMS][TF_COUNT];
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar = 0;
int      stateM5[MAX_SYMS];   // 0=none, 1=long, -1=short — M5-exit batch
int      stateM15[MAX_SYMS];  // 0=none, 1=long, -1=short — M15-exit batch

int MAGIC = 20260501;

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
      stateM5[s]  = 0;
      stateM15[s] = 0;
      for(int t = 0; t < TF_COUNT; t++)
      {
         ich[s][t] = iIchimoku(syms[s], tfs[t], Tenkan, Kijun, SenkouB);
         if(ich[s][t] == INVALID_HANDLE) return(INIT_FAILED);
      }
   }

   trade.SetDeviationInPoints(Slippage);
   SyncStateFromPositions();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   for(int s = 0; s < symsCount; s++)
      for(int t = 0; t < TF_COUNT; t++)
         IndicatorRelease(ich[s][t]);
}

//==============================================================
// Position State Sync (recover after restart)
//==============================================================

void SyncStateFromPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      string sym     = PositionGetString(POSITION_SYMBOL);
      int    magic   = (int)PositionGetInteger(POSITION_MAGIC);
      int    type    = (int)PositionGetInteger(POSITION_TYPE);
      string comment = PositionGetString(POSITION_COMMENT);
      int    dir     = (type == POSITION_TYPE_BUY) ? 1 : -1;

      if(magic != MAGIC) continue;

      for(int s = 0; s < symsCount; s++)
      {
         if(syms[s] == sym)
         {
            if(comment == TAG_M5)       stateM5[s]  = dir;
            else if(comment == TAG_M15) stateM15[s] = dir;
            break;
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
   int chShift = sh + Kijun;     // chikou buffer offset for bar sh
   int chCloud = chShift + Kijun;// cloud buffer offset at chikou's chart position

   if(ArraySize(rt) <= chCloud) return 0;

   double tenkan[1], kijun[1], senA[1], senB[1], chik[1];
   double tenkan_ch[1], kijun_ch[1], senA_ch[1], senB_ch[1];

   // price bar sh: tenkan, kijun, cloud
   if(CopyBuffer(ich[s][tfIdx], 0, sh,         1, tenkan)    <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 1, sh,         1, kijun)     <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 2, sh + Kijun, 1, senA)      <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 3, sh + Kijun, 1, senB)      <= 0) return 0;
   // chikou value at bar sh
   if(CopyBuffer(ich[s][tfIdx], 4, chShift,    1, chik)      <= 0) return 0;
   // tenkan, kijun, cloud at chikou's chart position
   if(CopyBuffer(ich[s][tfIdx], 0, chShift,    1, tenkan_ch) <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 1, chShift,    1, kijun_ch)  <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 2, chCloud,    1, senA_ch)   <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 3, chCloud,    1, senB_ch)   <= 0) return 0;

   double closeP = rt[sh].close;
   double cHi    = MathMax(senA[0], senB[0]);
   double cLo    = MathMin(senA[0], senB[0]);
   double cHiC   = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC   = MathMin(senA_ch[0], senB_ch[0]);

   // bullish: price above tenkan, kijun, and cloud; chikou above all three at its position
   if(closeP > tenkan[0] && closeP > kijun[0] && closeP > cHi &&
      chik[0] > tenkan_ch[0] && chik[0] > kijun_ch[0] && chik[0] > cHiC) return  1;

   // bearish: price below tenkan, kijun, and cloud; chikou below all three at its position
   if(closeP < tenkan[0] && closeP < kijun[0] && closeP < cLo &&
      chik[0] < tenkan_ch[0] && chik[0] < kijun_ch[0] && chik[0] < cLoC) return -1;

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
// Exit Check: price closed on wrong side of kijun for the given TF
//==============================================================

bool CheckKijunExit(int s, int dir, int tfIdx, ENUM_TIMEFRAMES tf)
{
   double kij[1];
   if(CopyBuffer(ich[s][tfIdx], 1, 1, 1, kij) <= 0) return false;

   MqlRates rt[];
   if(CopyRates(syms[s], tf, 1, 1, rt) <= 0) return false;
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

void GetEquityRisk(int &count, double &lots)
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
   else                { count = 2;  lots = 0.10; }
}

//==============================================================
// Trading Functions
//==============================================================

int OpenPositions(string sym, bool isBuy, int &filledM5, int &filledM15)
{
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   int count; double lots;
   GetEquityRisk(count, lots);

   trade.SetExpertMagicNumber(MAGIC);

   int half = count / 2;
   filledM5  = 0;
   filledM15 = 0;

   for(int i = 0; i < half; i++)
   {
      bool ok = isBuy ? trade.Buy(lots,  sym, ask, 0, 0, TAG_M5)
                      : trade.Sell(lots, sym, bid, 0, 0, TAG_M5);
      if(ok) filledM5++;
   }
   for(int i = 0; i < half; i++)
   {
      bool ok = isBuy ? trade.Buy(lots,  sym, ask, 0, 0, TAG_M15)
                      : trade.Sell(lots, sym, bid, 0, 0, TAG_M15);
      if(ok) filledM15++;
   }
   return filledM5 + filledM15;
}

void ClosePositions(string sym, string tag)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC &&
         PositionGetString(POSITION_COMMENT) == tag)
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
   MqlRates m1[];
   if(CopyRates(_Symbol, PERIOD_M1, 0, 2, m1) <= 0) return;
   ArraySetAsSeries(m1, true);
   if(m1[1].time == lastM1bar) return;
   lastM1bar = m1[1].time;

   for(int s = 0; s < symsCount; s++)
   {
      // Exit check: M5 batch closes when M5 kijun crosses
      if(stateM5[s] != 0 && CheckKijunExit(s, stateM5[s], IDX_M5, PERIOD_M5))
      {
         string side = (stateM5[s] == 1) ? "Long" : "Short";
         string msg  = PCTime() + " | Close " + syms[s] + " " + side + " M5 half (M5 kijun crossed)";
         Print(msg); Alert(msg); SendNotification(msg);

         ClosePositions(syms[s], TAG_M5);
         stateM5[s] = 0;
      }

      // Exit check: M15 batch closes when M15 kijun crosses
      if(stateM15[s] != 0 && CheckKijunExit(s, stateM15[s], IDX_M15, PERIOD_M15))
      {
         string side = (stateM15[s] == 1) ? "Long" : "Short";
         string msg  = PCTime() + " | Close " + syms[s] + " " + side + " M15 half (M15 kijun crossed)";
         Print(msg); Alert(msg); SendNotification(msg);

         ClosePositions(syms[s], TAG_M15);
         stateM15[s] = 0;
      }

      // Entry check: all timeframes H4→M1 must align, and no batch open
      if(stateM5[s] == 0 && stateM15[s] == 0)
      {
         int st = CheckAllAlign(s);
         if(st != 0)
         {
            bool   isBuy  = (st == 1);
            string action = isBuy ? "Buy" : "Sell";
            int msgCount; double msgLots;
            GetEquityRisk(msgCount, msgLots);
            string msg = PCTime() + " | " + action + " " + syms[s] +
                         " x" + IntegerToString(msgCount) +
                         " @ " + DoubleToString(msgLots, 2) + " (H1-M1)";
            Print(msg); Alert(msg); SendNotification(msg);

            int fM5, fM15;
            OpenPositions(syms[s], isBuy, fM5, fM15);
            if(fM5  > 0) stateM5[s]  = st;
            if(fM15 > 0) stateM15[s] = st;
         }
      }
   }
}
//This work is my worship unto GOD
