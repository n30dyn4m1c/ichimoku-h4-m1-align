//+------------------------------------------------------------------+
//| Ichimoku Multi-Tier Alignment EA (MN→M1, H4→M1, H1→M1)         |
//| Trades H4-M1 tier only                                           |
//| Author: Neo Malesa                                               |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

//--- Input Parameters ---
input string Symbols      = "GOLDm#";
input int    Tenkan       = 9;
input int    Kijun        = 26;
input int    SenkouB      = 52;
//input double FullLots     = 0.20;  // Lot size per position (Full MN-M1)
//input int    FullCount    = 3;     // Number of positions (Full MN-M1)
input double H4Lots       = 0.10;  // Lot size per position (H4-M1)
input int    H4Count      = 3;     // Number of positions (H4-M1)
//input double RevLots      = 0.10;  // Lot size per position (Reversion-H4)
//input int    RevCount     = 3;     // Number of positions (Reversion-H4)
//input double H1Lots       = 0.10;  // Lot size per position (H1-M1)
//input int    H1Count      = 1;     // Number of positions (H1-M1)
//input double RevH1Lots    = 0.10;  // Lot size per position (Reversion-H1)
//input int    RevH1Count   = 1;     // Number of positions (Reversion-H1)
input int    Slippage     = 30;    // Max slippage in points

//--- Constants and Global Variables ---
#define MAX_SYMS 60
#define TF_COUNT 9
#define TIER_COUNT 3

ENUM_TIMEFRAMES TFs[TF_COUNT] = {
   PERIOD_MN1, PERIOD_W1, PERIOD_D1,
   PERIOD_H4, PERIOD_H1, PERIOD_M30,
   PERIOD_M15, PERIOD_M5, PERIOD_M1
};

// Exit TF index per tier: Full=M15(6), H4=M15(6), H1=M1(8)
int ExitTFIndex[TIER_COUNT] = {6, 6, 8};

// Positions per tier — populated from inputs in OnInit
int PositionsPerTier[TIER_COUNT];

// Magic numbers per tier
//int MAGIC_FULL   = 20260301;
int MAGIC_H4     = 20260302;
//int MAGIC_H1     = 20260303;
//int MAGIC_REV    = 20260304;
//int MAGIC_REV_H1 = 20260305;

int      ich[MAX_SYMS][TF_COUNT];
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar = 0;

// Track active state per symbol per tier
// 0=no position, 1=long, -1=short
int      tierState[MAX_SYMS][TIER_COUNT];

// Reversion-H4 trade state (triggered when H4-M1 exits due to M5 specifically reversing)
//bool     revWatchActive[MAX_SYMS];   // condition1: M5 broke opposite, watching for M15 confirmation
//int      revWatchDir[MAX_SYMS];      // direction of the reversal (-1 or 1)
//int      revState[MAX_SYMS];         // 0=none, 1=long reversion, -1=short reversion

//// Reversion-H1 trade state (triggered when H1-M1 exits due to M1 specifically reversing)
//bool     revH1WatchActive[MAX_SYMS]; // condition1: M1 broke opposite, watching for M5 confirmation
//int      revH1WatchDir[MAX_SYMS];    // direction of the reversal (-1 or 1)
//int      revH1State[MAX_SYMS];       // 0=none, 1=long reversion, -1=short reversion

CTrade   trade;

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
      for(int tier = 0; tier < TIER_COUNT; tier++)
         tierState[s][tier] = 0;

//      revWatchActive[s]   = false;
//      revWatchDir[s]      = 0;
//      revState[s]         = 0;

//      revH1WatchActive[s] = false;
//      revH1WatchDir[s]    = 0;
//      revH1State[s]       = 0;

      for(int t = 0; t < TF_COUNT; t++)
      {
         ich[s][t] = iIchimoku(syms[s], TFs[t], Tenkan, Kijun, SenkouB);
         if(ich[s][t] == INVALID_HANDLE) return(INIT_FAILED);
      }
   }

//   PositionsPerTier[0] = FullCount;
   PositionsPerTier[1] = H4Count;
//   PositionsPerTier[2] = H1Count;

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

      string sym   = PositionGetString(POSITION_SYMBOL);
      int    magic = (int)PositionGetInteger(POSITION_MAGIC);
      int    type  = (int)PositionGetInteger(POSITION_TYPE);
      int    dir   = (type == POSITION_TYPE_BUY) ? 1 : -1;

      int  tier    = -1;
//      bool isRev   = false;
//      bool isRevH1 = false;

//      if(magic == MAGIC_FULL)        tier    = 0;
//      else if(magic == MAGIC_H4)     tier    = 1;
      if(magic == MAGIC_H4)          tier    = 1;
//      else if(magic == MAGIC_REV)    isRev   = true;
//      else if(magic == MAGIC_H1)     tier    = 2;
//      else if(magic == MAGIC_REV_H1) isRevH1 = true;
      else continue;

      for(int s = 0; s < symsCount; s++)
      {
         if(syms[s] == sym)
         {
//            if(isRev)
//               revState[s] = dir;
//            else if(isRevH1)
//               revH1State[s] = dir;
//            else
               tierState[s][tier] = dir;
            break;
         }
      }
   }
}

//==============================================================
// Ichimoku Rule Check
//==============================================================

int CheckTF(string sym, ENUM_TIMEFRAMES tf, int h)
{
   MqlRates rt[];
   if(CopyRates(sym, tf, 0, 120, rt) <= 0) return 0;
   ArraySetAsSeries(rt, true);

   int sh         = 1;
   int priceCloud = sh + 26;
   int chShift    = sh + 26;
   int chCloud    = sh + 52;

   if(ArraySize(rt) <= chCloud) return 0;

   double ten[1], kij[1], senA[1], senB[1], chik[1];
   double ten_ch[1], kij_ch[1], senA_ch[1], senB_ch[1];

   if(CopyBuffer(h, 0, sh, 1, ten) <= 0) return 0;
   if(CopyBuffer(h, 1, sh, 1, kij) <= 0) return 0;
   if(CopyBuffer(h, 2, priceCloud, 1, senA) <= 0) return 0;
   if(CopyBuffer(h, 3, priceCloud, 1, senB) <= 0) return 0;

   if(CopyBuffer(h, 4, chShift, 1, chik) <= 0) return 0;
   if(CopyBuffer(h, 0, chShift, 1, ten_ch) <= 0) return 0;
   if(CopyBuffer(h, 1, chShift, 1, kij_ch) <= 0) return 0;
   if(CopyBuffer(h, 2, chCloud, 1, senA_ch) <= 0) return 0;
   if(CopyBuffer(h, 3, chCloud, 1, senB_ch) <= 0) return 0;

   double closeP   = rt[sh].close;
   double price_26 = rt[chShift].close;

   double cHi  = MathMax(senA[0], senB[0]);
   double cLo  = MathMin(senA[0], senB[0]);
   double cHiC = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC = MathMin(senA_ch[0], senB_ch[0]);

   bool priceAbove = (closeP > cHi && closeP > ten[0] && closeP > kij[0]);
   bool priceBelow = (closeP < cLo && closeP < ten[0] && closeP < kij[0]);

   bool chAbove = (chik[0] > cHiC && chik[0] > ten_ch[0] && chik[0] > kij_ch[0] && chik[0] > price_26);
   bool chBelow = (chik[0] < cLoC && chik[0] < ten_ch[0] && chik[0] < kij_ch[0] && chik[0] < price_26);

   if(priceAbove && chAbove) return 1;
   if(priceBelow && chBelow) return -1;

   return 0;
}

//==============================================================
// Alignment Check Functions
//==============================================================

int AlignRange(const int s, const int from, const int to)
{
   int state = 0;
   for(int t = from; t <= to; t++)
   {
      int st = CheckTF(syms[s], TFs[t], ich[s][t]);
      if(st == 0) return 0;
      if(t == from) state = st;
      else if(st != state) return 0;
   }
   return state;
}

// MN → M1 (indices 0-8, all 9 TFs)
//int AlignFull(const int s) { return AlignRange(s, 0, 8); }

// H4 → M1 (indices 3-8, 6 TFs)
int AlignH4(const int s)   { return AlignRange(s, 3, 8); }

// H1 → M1 (indices 4-8, 5 TFs)
//int AlignH1(const int s)   { return AlignRange(s, 4, 8); }

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
// Trading Functions
//==============================================================

int MagicForTier(const int tier)
{
//   if(tier == 0) return MAGIC_FULL;
   if(tier == 1) return MAGIC_H4;
//   return MAGIC_H1;
   return MAGIC_H4;
}

double LotsForTier(const int tier)
{
//   if(tier == 0) return FullLots;
   if(tier == 1) return H4Lots;
//   return H1Lots;
   return H4Lots;
}

string TierLabel(const int tier)
{
   if(tier == 0) return "Full MN-M1";
   if(tier == 1) return "H4-M1";
   return "H1-M1";
}

bool OpenPositions(string sym, bool isBuy, int tier)
{
   double ask   = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(sym, SYMBOL_BID);
   double lots  = LotsForTier(tier);
   int    count = PositionsPerTier[tier];
   string cmnt  = TierLabel(tier);

   trade.SetExpertMagicNumber(MagicForTier(tier));

   bool ok = true;
   for(int i = 0; i < count; i++)
   {
      if(isBuy)
      {
         if(!trade.Buy(lots, sym, ask, 0, 0, cmnt))
            ok = false;
      }
      else
      {
         if(!trade.Sell(lots, sym, bid, 0, 0, cmnt))
            ok = false;
      }
   }
   return ok;
}

void ClosePositions(string sym, int tier)
{
   int magic = MagicForTier(tier);

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

/*
bool OpenRevPositions(string sym, bool isBuy)
{
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);

   trade.SetExpertMagicNumber(MAGIC_REV);

   bool ok = true;
   for(int i = 0; i < RevCount; i++)
   {
      if(isBuy)
      {
         if(!trade.Buy(RevLots, sym, ask, 0, 0, "Reversion-H4"))
            ok = false;
      }
      else
      {
         if(!trade.Sell(RevLots, sym, bid, 0, 0, "Reversion-H4"))
            ok = false;
      }
   }
   return ok;
}

void CloseRevPositions(string sym)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC_REV)
      {
         trade.PositionClose(ticket);
      }
   }
}
*/

/*
bool OpenRevH1Positions(string sym, bool isBuy)
{
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);

   trade.SetExpertMagicNumber(MAGIC_REV_H1);

   bool ok = true;
   for(int i = 0; i < RevH1Count; i++)
   {
      if(isBuy)
      {
         if(!trade.Buy(RevH1Lots, sym, ask, 0, 0, "Reversion-H1"))
            ok = false;
      }
      else
      {
         if(!trade.Sell(RevH1Lots, sym, bid, 0, 0, "Reversion-H1"))
            ok = false;
      }
   }
   return ok;
}

void CloseRevH1Positions(string sym)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC_REV_H1)
      {
         trade.PositionClose(ticket);
      }
   }
}
*/

/*
// Called on every tick — checks M30 Kijun TP for active Reversion-H4 positions
void CheckRevTP(int s)
{
   if(revState[s] == 0) return;

   double kij[1];
   if(CopyBuffer(ich[s][5], 1, 1, 1, kij) <= 0) return;  // ich[s][5] = M30
   double kijun = kij[0];
   if(kijun <= 0) return;

   double bid = SymbolInfoDouble(syms[s], SYMBOL_BID);
   double ask = SymbolInfoDouble(syms[s], SYMBOL_ASK);

   bool tpHit = false;
   if(revState[s] == -1 && bid <= kijun) tpHit = true;  // short: price reached down to Kijun
   if(revState[s] ==  1 && ask >= kijun) tpHit = true;  // long: price reached up to Kijun

   if(tpHit)
   {
      string side = (revState[s] == 1) ? "Long" : "Short";
      string msg = PCTime() + " | Close " + syms[s] + " " + side + " (Reversion-H4 - M30 Kijun TP)";
      Print(msg); Alert(msg); SendNotification(msg);

      CloseRevPositions(syms[s]);
      revState[s]       = 0;
      revWatchActive[s] = false;
   }
}
*/

/*
// Called on every tick — checks M15 Kijun TP for active Reversion-H1 positions
void CheckRevH1TP(int s)
{
   if(revH1State[s] == 0) return;

   double kij[1];
   if(CopyBuffer(ich[s][6], 1, 1, 1, kij) <= 0) return;  // ich[s][6] = M15
   double kijun = kij[0];
   if(kijun <= 0) return;

   double bid = SymbolInfoDouble(syms[s], SYMBOL_BID);
   double ask = SymbolInfoDouble(syms[s], SYMBOL_ASK);

   bool tpHit = false;
   if(revH1State[s] == -1 && bid <= kijun) tpHit = true;
   if(revH1State[s] ==  1 && ask >= kijun) tpHit = true;

   if(tpHit)
   {
      string side = (revH1State[s] == 1) ? "Long" : "Short";
      string msg = PCTime() + " | Close " + syms[s] + " " + side + " (Reversion-H1 - M15 Kijun TP)";
      Print(msg); Alert(msg); SendNotification(msg);

      CloseRevH1Positions(syms[s]);
      revH1State[s]       = 0;
      revH1WatchActive[s] = false;
   }
}
*/

//==============================================================
// Main Loop
//==============================================================

void OnTick()
{
   // Per-tick: reversion TP checks (not gated on M1 bar close)
   for(int s = 0; s < symsCount; s++)
   {
//      CheckRevTP(s);
//      CheckRevH1TP(s);
   }

   // M1 bar gate — all remaining logic runs on M1 close only
   MqlRates m1[];
   if(CopyRates(_Symbol, PERIOD_M1, 0, 2, m1) <= 0) return;
   ArraySetAsSeries(m1, true);
   if(m1[1].time == lastM1bar) return;
   lastM1bar = m1[1].time;

   for(int s = 0; s < symsCount; s++)
   {
      // --- Exit checks (per tier, based on specific TF break) ---

      for(int tier = 0; tier < TIER_COUNT; tier++)
      {
         if(tierState[s][tier] == 0) continue;

         int exitIdx = ExitTFIndex[tier];
         int exitSt  = CheckTF(syms[s], TFs[exitIdx], ich[s][exitIdx]);

         if(exitSt != tierState[s][tier])
         {
            string side = (tierState[s][tier] == 1) ? "Long" : "Short";
            string msg = PCTime() + " | Close " + syms[s] + " " + side + " (" + TierLabel(tier) + " - " +
                         EnumToString(TFs[exitIdx]) + " broke)";
            Print(msg); Alert(msg); SendNotification(msg);

//            // H4 tier only: arm Reversion-H4 watch on any H4-M1 exit; M15 confirmation gates the entry
//            if(tier == 1 && revState[s] == 0)
//            {
//               revWatchDir[s]    = -tierState[s][tier];
//               revWatchActive[s] = true;
//            }

//            // H1 tier only: arm Reversion-H1 watch on any H1-M1 exit; M5 confirmation gates the entry
//            if(tier == 2 && revH1State[s] == 0)
//            {
//               revH1WatchDir[s]    = -tierState[s][tier];
//               revH1WatchActive[s] = true;
//            }

            ClosePositions(syms[s], tier);
            tierState[s][tier] = 0;
         }
      }

//      // --- Reversion-H4 M5 exit check ---
//
//      if(revState[s] != 0)
//      {
//         int m5St = CheckTF(syms[s], TFs[7], ich[s][7]);
//         if(m5St != revState[s])
//         {
//            string side = (revState[s] == 1) ? "Long" : "Short";
//            string msg = PCTime() + " | Close " + syms[s] + " " + side + " (Reversion-H4 - M5 reversed)";
//            Print(msg); Alert(msg); SendNotification(msg);
//
//            CloseRevPositions(syms[s]);
//            revState[s]       = 0;
//            revWatchActive[s] = false;
//         }
//      }

//      // --- Reversion-H1 M1 exit check ---
//
//      if(revH1State[s] != 0)
//      {
//         int m1St = CheckTF(syms[s], TFs[8], ich[s][8]);
//         if(m1St != revH1State[s])
//         {
//            string side = (revH1State[s] == 1) ? "Long" : "Short";
//            string msg = PCTime() + " | Close " + syms[s] + " " + side + " (Reversion-H1 - M1 broke)";
//            Print(msg); Alert(msg); SendNotification(msg);
//
//            CloseRevH1Positions(syms[s]);
//            revH1State[s]       = 0;
//            revH1WatchActive[s] = false;
//         }
//      }

//      // --- Reversion-H4 entry check (condition1: M5 broke, condition2: M15 confirms) ---
//
//      if(revWatchActive[s] && revState[s] == 0)
//      {
//         int m15St = CheckTF(syms[s], TFs[6], ich[s][6]);
//         if(m15St == revWatchDir[s])
//         {
//            bool   isBuy  = (revWatchDir[s] == 1);
//            string action = isBuy ? "Buy" : "Sell";
//            string msg = PCTime() + " | " + action + " " + syms[s] + " x" + IntegerToString(RevCount) +
//                         " @ " + DoubleToString(RevLots, 2) + " (Reversion-H4 - M15 confirmed)";
//            Print(msg); Alert(msg); SendNotification(msg);
//
//            if(OpenRevPositions(syms[s], isBuy))
//            {
//               revState[s]       = revWatchDir[s];
//               revWatchActive[s] = false;
//            }
//         }
//      }

//      // --- Reversion-H1 entry check (condition1: M1 broke, condition2: M5 confirms) ---
//
//      if(revH1WatchActive[s] && revH1State[s] == 0)
//      {
//         int m5St = CheckTF(syms[s], TFs[7], ich[s][7]);
//         if(m5St == revH1WatchDir[s])
//         {
//            bool   isBuy  = (revH1WatchDir[s] == 1);
//            string action = isBuy ? "Buy" : "Sell";
//            string msg = PCTime() + " | " + action + " " + syms[s] + " x" + IntegerToString(RevH1Count) +
//                         " @ " + DoubleToString(RevH1Lots, 2) + " (Reversion-H1 - M5 confirmed)";
//            Print(msg); Alert(msg); SendNotification(msg);
//
//            if(OpenRevH1Positions(syms[s], isBuy))
//            {
//               revH1State[s]       = revH1WatchDir[s];
//               revH1WatchActive[s] = false;
//            }
//         }
//      }

      // --- Entry checks (exclusive tiers) ---

//      // Tier 0: Full MN-M1
//      if(tierState[s][0] == 0)
//      {
//         int st = AlignFull(s);
//         if(st != 0)
//         {
//            bool isBuy = (st == 1);
//            string action = isBuy ? "Buy" : "Sell";
//            string msg = PCTime() + " | " + action + " " + syms[s] + " x" + IntegerToString(PositionsPerTier[0]) + " @ " + DoubleToString(LotsForTier(0), 2) + " (Full MN-M1)";
//            Print(msg); Alert(msg); SendNotification(msg);
//
//            if(OpenPositions(syms[s], isBuy, 0))
//               tierState[s][0] = st;
//         }
//      }

      // Tier 1: H4-M1 (only if Full not active and no reversion trade active)
      if(tierState[s][1] == 0 && tierState[s][0] == 0)
      {
         int st = AlignH4(s);
         if(st != 0)
         {
            bool isBuy = (st == 1);
            string action = isBuy ? "Buy" : "Sell";
            string msg = PCTime() + " | " + action + " " + syms[s] + " x" + IntegerToString(PositionsPerTier[1]) + " @ " + DoubleToString(LotsForTier(1), 2) + " (H4-M1)";
            Print(msg); Alert(msg); SendNotification(msg);

            if(OpenPositions(syms[s], isBuy, 1))
            {
               tierState[s][1]   = st;
//               revWatchActive[s] = false;  // cancel pending reversion watch if H4 re-enters
            }
         }
      }

//      // Tier 2: H1-M1 (only if H4 and Full not active)
//      if(tierState[s][2] == 0 && tierState[s][1] == 0 && tierState[s][0] == 0)
//      {
//         int st = AlignH1(s);
//         if(st != 0)
//         {
//            bool isBuy = (st == 1);
//            string action = isBuy ? "Buy" : "Sell";
//            string msg = PCTime() + " | " + action + " " + syms[s] + " x" + IntegerToString(PositionsPerTier[2]) + " @ " + DoubleToString(LotsForTier(2), 2) + " (H1-M1)";
//            Print(msg); Alert(msg); SendNotification(msg);
//
//            if(OpenPositions(syms[s], isBuy, 2))
//            {
//               tierState[s][2]     = st;
//               revH1WatchActive[s] = false;  // cancel pending H1 reversion watch if H1 re-enters
//            }
//         }
//      }
   }
}
//This work is my worship unto GOD
