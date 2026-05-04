//+------------------------------------------------------------------+
//| Ichimoku M5-M1 Cloud EA                                          |
//| Entry: M5 and M1 close+chikou both above/below their cloud      |
//| Exit:  M1 close crosses M1 kijun against trade direction        |
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
#define MAX_SYMS 60

int      ich[MAX_SYMS];
int      ich5[MAX_SYMS];
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar = 0;
int      state[MAX_SYMS];   // 0=no position, 1=long, -1=short

int MAGIC_M1 = 20260501;

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
      ich[s]   = iIchimoku(syms[s], PERIOD_M1, Tenkan, Kijun, SenkouB);
      if(ich[s] == INVALID_HANDLE) return(INIT_FAILED);
      ich5[s]  = iIchimoku(syms[s], PERIOD_M5, Tenkan, Kijun, SenkouB);
      if(ich5[s] == INVALID_HANDLE) return(INIT_FAILED);
   }

   trade.SetDeviationInPoints(Slippage);
   SyncStateFromPositions();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   for(int s = 0; s < symsCount; s++)
   {
      IndicatorRelease(ich[s]);
      IndicatorRelease(ich5[s]);
   }
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

      string sym   = PositionGetString(POSITION_SYMBOL);
      int    magic = (int)PositionGetInteger(POSITION_MAGIC);
      int    type  = (int)PositionGetInteger(POSITION_TYPE);
      int    dir   = (type == POSITION_TYPE_BUY) ? 1 : -1;

      if(magic != MAGIC_M1) continue;

      for(int s = 0; s < symsCount; s++)
      {
         if(syms[s] == sym) { state[s] = dir; break; }
      }
   }
}

//==============================================================
// Entry Check: price and chikou both above/below cloud
//==============================================================

int CheckM5Align(int s)
{
   MqlRates rt[];
   if(CopyRates(syms[s], PERIOD_M5, 0, 120, rt) <= 0) return 0;
   ArraySetAsSeries(rt, true);

   int sh      = 1;
   int chShift = sh + 26;
   int chCloud = sh + 52;

   if(ArraySize(rt) <= chCloud) return 0;

   double senA[1], senB[1], chik[1], senA_ch[1], senB_ch[1];

   if(CopyBuffer(ich5[s], 2, sh + 26, 1, senA)    <= 0) return 0;
   if(CopyBuffer(ich5[s], 3, sh + 26, 1, senB)    <= 0) return 0;
   if(CopyBuffer(ich5[s], 4, chShift, 1, chik)    <= 0) return 0;
   if(CopyBuffer(ich5[s], 2, chCloud, 1, senA_ch) <= 0) return 0;
   if(CopyBuffer(ich5[s], 3, chCloud, 1, senB_ch) <= 0) return 0;

   double closeP = rt[sh].close;
   double cHi    = MathMax(senA[0], senB[0]);
   double cLo    = MathMin(senA[0], senB[0]);
   double cHiC   = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC   = MathMin(senA_ch[0], senB_ch[0]);

   if(closeP > cHi && chik[0] > cHiC) return  1;
   if(closeP < cLo && chik[0] < cLoC) return -1;
   return 0;
}

int CheckM1Entry(int s)
{
   MqlRates rt[];
   if(CopyRates(syms[s], PERIOD_M1, 0, 120, rt) <= 0) return 0;
   ArraySetAsSeries(rt, true);

   int sh      = 1;
   int chShift = sh + 26;   // chikou at last closed bar maps to offset sh+26 in buffer
   int chCloud = sh + 52;   // cloud at chikou's price position

   if(ArraySize(rt) <= chCloud) return 0;

   double senA[1], senB[1], chik[1], senA_ch[1], senB_ch[1];

   if(CopyBuffer(ich[s], 2, sh + 26, 1, senA)    <= 0) return 0;
   if(CopyBuffer(ich[s], 3, sh + 26, 1, senB)    <= 0) return 0;
   if(CopyBuffer(ich[s], 4, chShift, 1, chik)    <= 0) return 0;
   if(CopyBuffer(ich[s], 2, chCloud, 1, senA_ch) <= 0) return 0;
   if(CopyBuffer(ich[s], 3, chCloud, 1, senB_ch) <= 0) return 0;

   double closeP = rt[sh].close;
   double cHi    = MathMax(senA[0], senB[0]);
   double cLo    = MathMin(senA[0], senB[0]);
   double cHiC   = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC   = MathMin(senA_ch[0], senB_ch[0]);

   if(closeP > cHi && chik[0] > cHiC) return  1;
   if(closeP < cLo && chik[0] < cLoC) return -1;
   return 0;
}

//==============================================================
// Exit Check: price closed opposite side of kijun
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

void GetEquityRisk(int &count, double &lots)
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq <= 30)        { count = 1; lots = 0.10; }
   else if(eq <= 50)   { count = 2; lots = 0.10; }
   else if(eq <= 70)   { count = 3; lots = 0.10; }
   else if(eq <= 100)  { count = 4; lots = 0.10; }
   else if(eq <= 130)  { count = 5; lots = 0.10; }
   else if(eq <= 150)  { count = 7; lots = 0.10; }
   else if(eq <= 170)  { count = 9; lots = 0.10; }
   else if(eq <= 200)  { count = 5; lots = 0.20; }
   else if(eq <= 300)  { count = 4; lots = 0.30; }
   else if(eq <= 400)  { count = 5; lots = 0.30; }
   else if(eq <= 500)  { count = 6; lots = 0.30; }
   else if(eq <= 600)  { count = 7; lots = 0.30; }
   else if(eq <= 1000) { count = 4; lots = 0.50; }
   else if(eq <= 3000) { count = 3; lots = 0.30; }
   else if(eq <= 5000) { count = 3; lots = 0.20; }
   else if(eq <= 8000) { count = 3; lots = 0.10; }
   else                { count = 2; lots = 0.10; }
}

//==============================================================
// Trading Functions
//==============================================================

bool OpenPositions(string sym, bool isBuy)
{
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   int count; double lots;
   GetEquityRisk(count, lots);

   trade.SetExpertMagicNumber(MAGIC_M1);

   bool ok = true;
   for(int i = 0; i < count; i++)
   {
      if(isBuy) { if(!trade.Buy(lots,  sym, ask, 0, 0, "M1 Cloud")) ok = false; }
      else      { if(!trade.Sell(lots, sym, bid, 0, 0, "M1 Cloud")) ok = false; }
   }
   return ok;
}

void ClosePositions(string sym)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC_M1)
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
      // Exit check
      if(state[s] != 0 && CheckM1Exit(s, state[s]))
      {
         string side = (state[s] == 1) ? "Long" : "Short";
         string msg  = PCTime() + " | Close " + syms[s] + " " + side + " (M1 - Kijun crossed)";
         Print(msg); Alert(msg); SendNotification(msg);

         ClosePositions(syms[s]);
         state[s] = 0;
      }

      // Entry check
      if(state[s] == 0)
      {
         int m5 = CheckM5Align(s);
         int m1 = CheckM1Entry(s);
         int st = (m5 != 0 && m5 == m1) ? m1 : 0;
         if(st != 0)
         {
            bool   isBuy  = (st == 1);
            string action = isBuy ? "Buy" : "Sell";
            int msgCount; double msgLots;
            GetEquityRisk(msgCount, msgLots);
            string msg = PCTime() + " | " + action + " " + syms[s] +
                         " x" + IntegerToString(msgCount) +
                         " @ " + DoubleToString(msgLots, 2) + " (M5-M1)";
            Print(msg); Alert(msg); SendNotification(msg);

            if(OpenPositions(syms[s], isBuy))
               state[s] = st;
         }
      }
   }
}
//This work is my worship unto GOD
