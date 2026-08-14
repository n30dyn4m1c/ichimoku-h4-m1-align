//+------------------------------------------------------------------+
//| Ichimoku Bottom-Up Stack EA (EXPERIMENT)                          |
//| Entry: same per-TF alignment as the H4 VPS build (price + chikou  |
//|        above/below tenkan, kijun and cloud), but checked BOTTOM-UP|
//|        instead of top-down:                                       |
//|          Level M5 : M1 + M5 aligned              -> open trade    |
//|          Level M15: M1 + M5 + M15 aligned        -> open trade    |
//|          Level M30: M1 + M5 + M15 + M30 aligned  -> open trade    |
//|          Level H1 : M1 ... H1 aligned            -> open trade    |
//|          Level H4 : M1 ... H4 aligned            -> open trade    |
//|        M1 alone never trades — it is only the start of the stack. |
//|        A level can only open when every lower TF still holds the  |
//|        trade's direction (full chain M1->level). The cloud bias   |
//|        gate (Span A vs Span B) applies to the level TF and the TF |
//|        directly below it.                                         |
//| Exit:  the level's own TF bar closes back inside its cloud.       |
//|        Long  -> close below the cloud's upper edge (inside/under) |
//|        Short -> close above the cloud's lower edge (inside/over)  |
//|        No initial stop loss, no trail, no break-even, no time     |
//|        cap — the trade runs until the cloud close.                |
//| Risk:  single position per level per symbol; levels run           |
//|        concurrently (up to 5 per symbol); each level re-enters    |
//|        independently whenever its chain re-aligns.                |
//| Magic: 20260848 — fresh, distinct from the live VPS builds        |
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

input group  "Position Sizing"
input double InpLots = 0.10;        // Fixed lots per level position

input group  "Entry Filters"
input bool   InpCloudBiasEnabled = true;   // Require Span A vs Span B bias on the level TF + the TF below
input int    InpMaxSpreadPoints  = 60;     // Max spread in points to allow entry (0 = no limit)

//--- Constants and Global Variables ---
#define MAX_SYMS 60
#define LEVELS   5      // tradable levels: M5, M15, M30, H1, H4
#define TFS      6      // stack: M1, M5, M15, M30, H1, H4

ENUM_TIMEFRAMES tfs[TFS] = { PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4 };
string          tfName[TFS] = { "M1", "M5", "M15", "M30", "H1", "H4" };

int      ich[MAX_SYMS][TFS];
string   syms[MAX_SYMS];
int      symsCount = 0;
datetime lastM1bar[MAX_SYMS];
int      state[MAX_SYMS][LEVELS];   // per level: 0 = flat, 1 = long, -1 = short
int      lastMinuteKey = -1;

int MAGIC = 20260848;   // fresh — bottom-up stack experiment (20260846/47 are the live VPS builds)

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

   for(int s = 0; s < symsCount; s++)
   {
      lastM1bar[s] = 0;
      for(int l = 0; l < LEVELS; l++) state[s][l] = 0;

      for(int t = 0; t < TFS; t++)
      {
         ich[s][t] = iIchimoku(syms[s], tfs[t], Tenkan, Kijun, SenkouB);
         if(ich[s][t] == INVALID_HANDLE) return(INIT_FAILED);
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
      for(int t = 0; t < TFS; t++)
         if(ich[s][t] != INVALID_HANDLE) IndicatorRelease(ich[s][t]);
}

//==============================================================
// Position State Sync (recover after restart)
//==============================================================

string LevelComment(int lvl, int dir)
{
   return (dir == 1 ? "Exp Buy " : "Exp Sell ") + tfName[lvl + 1];
}

// Rebuild per-level state from the positions on the account so a restart
// mid-trade resumes the correct levels. The position comment carries the
// level (e.g. "Exp Buy M15").
void SyncStateFromPositions()
{
   for(int s = 0; s < symsCount; s++)
      for(int l = 0; l < LEVELS; l++) state[s][l] = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      string sym   = PositionGetString(POSITION_SYMBOL);
      int    magic = (int)PositionGetInteger(POSITION_MAGIC);
      int    type  = (int)PositionGetInteger(POSITION_TYPE);
      string comm  = PositionGetString(POSITION_COMMENT);

      if(magic != MAGIC) continue;

      int dir = (type == POSITION_TYPE_BUY) ? 1 : -1;

      for(int s = 0; s < symsCount; s++)
      {
         if(syms[s] != sym) continue;
         for(int l = 0; l < LEVELS; l++)
         {
            if(comm == LevelComment(l, 1) || comm == LevelComment(l, -1))
               state[s][l] = dir;
         }
      }
   }
}

//==============================================================
// Alignment Check: price and chikou both above/below tenkan,
// kijun, and cloud on one timeframe. Returns 1 (bullish),
// -1 (bearish), 0 (none) — identical to the H4 VPS build.
//==============================================================

int CheckAlign(int s, int tfIdx)
{
   ENUM_TIMEFRAMES tf = tfs[tfIdx];

   int sh      = 1;              // last closed bar
   int chShift = sh + Kijun;     // chikou's chart position for bar sh (Kijun bars back)

   MqlRates rt[];
   if(CopyRates(syms[s], tf, 0, chShift + 1, rt) <= 0) return 0;
   ArraySetAsSeries(rt, true);

   if(ArraySize(rt) <= chShift) return 0;

   double tenkan[1], kijun[1], senA[1], senB[1];
   if(CopyBuffer(ich[s][tfIdx], 0, sh, 1, tenkan) <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 1, sh, 1, kijun)  <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 2, sh, 1, senA)   <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 3, sh, 1, senB)   <= 0) return 0;

   double closeP = rt[sh].close;
   double cHi    = MathMax(senA[0], senB[0]);
   double cLo    = MathMin(senA[0], senB[0]);

   bool above = closeP > tenkan[0] && closeP > kijun[0] && closeP > cHi;
   bool below = closeP < tenkan[0] && closeP < kijun[0] && closeP < cLo;
   if(!above && !below) return 0;

   double tenkan_ch[1], kijun_ch[1], senA_ch[1], senB_ch[1];
   if(CopyBuffer(ich[s][tfIdx], 0, chShift, 1, tenkan_ch) <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 1, chShift, 1, kijun_ch)  <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 2, chShift, 1, senA_ch)   <= 0) return 0;
   if(CopyBuffer(ich[s][tfIdx], 3, chShift, 1, senB_ch)   <= 0) return 0;

   double chik = closeP;
   double cHiC = MathMax(senA_ch[0], senB_ch[0]);
   double cLoC = MathMin(senA_ch[0], senB_ch[0]);

   if(above && chik > rt[chShift].high &&
      chik > tenkan_ch[0] && chik > kijun_ch[0] && chik > cHiC) return  1;

   if(below && chik < rt[chShift].low &&
      chik < tenkan_ch[0] && chik < kijun_ch[0] && chik < cLoC) return -1;

   return 0;
}

//==============================================================
// Chain Check (bottom-up): the full stack M1..topIdx must be
// aligned in the SAME direction for a level to open.
//==============================================================

int ChainAligned(int s, int topIdx)
{
   int dir = CheckAlign(s, 0);
   if(dir == 0) return 0;

   for(int t = 1; t <= topIdx; t++)
   {
      if(CheckAlign(s, t) != dir) return 0;
   }
   return dir;
}

//==============================================================
// Cloud Bias Filter: the cloud must carry the trade's bias
// (Span A above Span B for a long, below for a short) at both
// the last closed bar and the far end of the future-cloud
// window. Unreadable values count as blocking.
//==============================================================

bool CloudBiasOK(int s, int tfIdx, int dir)
{
   double aNow[1], bNow[1], aFar[1], bFar[1];
   if(CopyBuffer(ich[s][tfIdx], 2, 1,         1, aNow) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, 1,         1, bNow) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 2, 1 - Kijun, 1, aFar) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, 1 - Kijun, 1, bFar) <= 0) return false;

   if(dir == 1) return aNow[0] > bNow[0] && aFar[0] > bFar[0];
   return aNow[0] < bNow[0] && aFar[0] < bFar[0];
}

// The bias must hold on the level TF and the TF directly below it
// (level lvl opens on TF lvl+1, so the pair is TF lvl and TF lvl+1).
bool LevelCloudBiasOK(int s, int lvl, int dir)
{
   if(!CloudBiasOK(s, lvl + 1, dir)) return false;
   if(!CloudBiasOK(s, lvl, dir))     return false;
   return true;
}

//==============================================================
// Exit Check: the level TF's last closed bar closes back inside
// its cloud (or beyond it — a long that closes below the cloud,
// a short that closes above it). This is the only exit: no SL,
// no trail, no break-even.
//==============================================================

bool InCloudClose(int s, int tfIdx, int dir)
{
   double senA[1], senB[1];
   if(CopyBuffer(ich[s][tfIdx], 2, 1, 1, senA) <= 0) return false;
   if(CopyBuffer(ich[s][tfIdx], 3, 1, 1, senB) <= 0) return false;

   MqlRates rt[];
   if(CopyRates(syms[s], tfs[tfIdx], 1, 1, rt) <= 0) return false;
   double closeP = rt[0].close;

   if(dir ==  1) return closeP < MathMax(senA[0], senB[0]);
   if(dir == -1) return closeP > MathMin(senA[0], senB[0]);
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

bool SpreadOK(string sym)
{
   if(InpMaxSpreadPoints <= 0) return true;
   return SymbolInfoInteger(sym, SYMBOL_SPREAD) <= InpMaxSpreadPoints;
}

//==============================================================
// Trading Functions
//==============================================================

bool OpenLevel(int s, int lvl, int dir)
{
   string sym = syms[s];
   string comment = LevelComment(lvl, dir);
   bool ok = (dir == 1) ? trade.Buy(InpLots, sym, SymbolInfoDouble(sym, SYMBOL_ASK), 0, 0, comment)
                        : trade.Sell(InpLots, sym, SymbolInfoDouble(sym, SYMBOL_BID), 0, 0, comment);
   if(ok)
   {
      state[s][lvl] = dir;
      string action = (dir == 1) ? "Buy" : "Sell";
      string msg = PCTime() + " | " + action + " " + sym + " " + tfName[lvl + 1] +
                   " @ " + DoubleToString(InpLots, 2) + " (bottom-up)";
      Print(msg); SendNotification(msg);
   }
   return ok;
}

// Close all positions of the level; returns true only when none remain
// open, so a failed close (requote, halt) is retried instead of freeing
// the level for a fresh entry.
bool CloseLevelPositions(int s, int lvl)
{
   string sym = syms[s];
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC &&
         (PositionGetString(POSITION_COMMENT) == LevelComment(lvl, 1) ||
          PositionGetString(POSITION_COMMENT) == LevelComment(lvl, -1)))
      {
         if(!trade.PositionClose(ticket))
            Print(PCTime() + " | " + sym + " " + tfName[lvl + 1] + " close failed, retcode " +
                  IntegerToString(trade.ResultRetcode()));
      }
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) == sym &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC &&
         (PositionGetString(POSITION_COMMENT) == LevelComment(lvl, 1) ||
          PositionGetString(POSITION_COMMENT) == LevelComment(lvl, -1))) return false;
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

      for(int l = 0; l < LEVELS; l++)
      {
         // Exit check: the level's own TF closed a bar back inside its cloud
         if(state[s][l] != 0 && InCloudClose(s, l + 1, state[s][l]))
         {
            string side = (state[s][l] == 1) ? "Long" : "Short";
            string msg  = PCTime() + " | Close " + syms[s] + " " + side + " " +
                          tfName[l + 1] + " (cloud close)";
            Print(msg); SendNotification(msg);

            if(CloseLevelPositions(s, l))
            {
               state[s][l] = 0;
               msg = PCTime() + " | " + syms[s] + " " + tfName[l + 1] + " level closed";
               Print(msg); SendNotification(msg);
            }
            else
               Print(PCTime() + " | " + syms[s] + " " + tfName[l + 1] + " exit signal but positions still open — will retry");
         }

         // Entry check: the level is flat and the full chain M1..level TF
         // aligns in one direction (plus spread and cloud bias gates)
         if(state[s][l] == 0 && SpreadOK(syms[s]))
         {
            int st = ChainAligned(s, l + 1);
            if(st != 0)
            {
               if(InpCloudBiasEnabled && !LevelCloudBiasOK(s, l, st)) continue;

               if(!OpenLevel(s, l, st))
                  Print(PCTime() + " | " + syms[s] + " " + tfName[l + 1] +
                        " entry signal but order failed, retcode " + IntegerToString(trade.ResultRetcode()));
            }
         }
      }
   }
}
//This work is my worship unto GOD
